import CloudKit
import CryptoKit
import Foundation
import SwiftData

@MainActor
final class HouseholdLibrarySync {
  private struct Checkpoint: Codable {
    var fingerprints: [String: String] = [:]
    var changeToken: Data?
  }

  private struct Row {
    var entry: HouseholdLibraryEntry
    var payload: Data
    var fingerprint: String
  }

  private let membership: HouseholdMembership
  private let checkpointURL: URL
  private var checkpoint: Checkpoint

  private var database: CKDatabase {
    let container = CloudKitCookbookStore.container
    return membership.isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
  }

  init(membership: HouseholdMembership) throws {
    self.membership = membership
    let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let folder = base.appending(path: "HouseholdSync", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    checkpointURL = folder.appending(path: membership.id + ".json")
    if FileManager.default.fileExists(atPath: checkpointURL.path) {
      checkpoint = try JSONDecoder().decode(Checkpoint.self, from: Data(contentsOf: checkpointURL))
    } else {
      checkpoint = Checkpoint()
    }
  }

  func synchronize(in context: ModelContext) async throws {
    if context.hasChanges { try context.save() }
    do {
      try await push(in: context)
    } catch {
      try? await pull(in: context)
      throw error
    }
    try await pull(in: context)
  }

  private func push(in context: ModelContext) async throws {
    let local = try rows(in: context)
    let changed = local.values.filter { checkpoint.fingerprints[$0.entry.key] != $0.fingerprint }
      .sorted { $0.entry.order < $1.entry.order }
    let deleted = Set(checkpoint.fingerprints.keys).subtracting(local.keys)
    let alreadyGone = try await save(changed)
    let didDelete = try await remove(deleted)

    if !alreadyGone.isEmpty {
      var library = try HouseholdLocalLibrary(context: context)
      library.apply([], deleting: alreadyGone)
      try context.save()
    }
    for row in changed where !alreadyGone.contains(row.entry.key) {
      checkpoint.fingerprints[row.entry.key] = row.fingerprint
    }
    for key in didDelete.union(alreadyGone) { checkpoint.fingerprints[key] = nil }
    if !changed.isEmpty || !deleted.isEmpty { try persist() }
  }

  private func save(_ rows: [Row]) async throws -> Set<String> {
    var alreadyGone: Set<String> = []
    for offset in stride(from: 0, to: rows.count, by: 75) {
      try Task.checkCancellation()
      let batch = rows[offset..<min(offset + 75, rows.count)]
      let ids = batch.map { recordID($0.entry.key) }
      let current = try await database.records(for: ids, desiredKeys: [])
      var records: [CKRecord] = []
      var attachments: [URL] = []
      defer { attachments.forEach { try? FileManager.default.removeItem(at: $0) } }

      for row in batch {
        let id = recordID(row.entry.key)
        let record: CKRecord
        do {
          guard let result = current[id] else { throw CocoaError(.fileReadUnknown) }
          record = try result.get()
        } catch let error as CKError where error.code == .unknownItem {
          if checkpoint.fingerprints[row.entry.key] != nil {
            alreadyGone.insert(row.entry.key)
            continue
          }
          record = CKRecord(recordType: row.entry.recordType, recordID: id)
        }
        record["payloadJSON"] = String(decoding: row.payload, as: UTF8.self) as CKRecordValue
        if case .recipe = row.entry {
          if let photo = row.entry.photo {
            let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".jpg")
            try photo.write(to: url, options: .atomic)
            attachments.append(url)
            record["photo"] = CKAsset(fileURL: url)
          } else {
            record["photo"] = nil
          }
        }
        if case .grocery(let grocery) = row.entry {
          record["checked"] = NSNumber(value: grocery.item.isChecked)
          record["mealPlan"] = CKRecord.Reference(recordID: recordID("plan.\(grocery.planID)"), action: .deleteSelf)
        }
        records.append(record)
      }

      guard !records.isEmpty else { continue }
      let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys, atomically: false)
      for record in records {
        guard let saved = result.saveResults[record.recordID] else { throw CocoaError(.fileWriteUnknown) }
        _ = try saved.get()
      }
    }
    return alreadyGone
  }

  private func remove(_ keys: Set<String>) async throws -> Set<String> {
    let ids = keys.map(recordID)
    for offset in stride(from: 0, to: ids.count, by: 100) {
      try Task.checkCancellation()
      let batch = Array(ids[offset..<min(offset + 100, ids.count)])
      let results = try await database.modifyRecords(saving: [], deleting: batch, atomically: false)
      for id in batch {
        guard let result = results.deleteResults[id] else { throw CocoaError(.fileWriteUnknown) }
        do { try result.get() } catch let error as CKError where error.code == .unknownItem { continue }
      }
    }
    return keys
  }

  private func pull(in context: ModelContext) async throws {
    let token = try checkpoint.changeToken.flatMap {
      try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
    }
    do {
      try await pull(since: token, in: context)
    } catch let error as CKError where error.code == .changeTokenExpired {
      try await pull(since: nil, in: context)
    }
  }

  private func pull(since token: CKServerChangeToken?, in context: ModelContext) async throws {
    var nextToken = token
    var entries: [String: Row] = [:]
    var deletions: Set<String> = []
    var more: Bool
    repeat {
      try Task.checkCancellation()
      let page = try await database.recordZoneChanges(inZoneWith: membership.zoneID, since: nextToken)
      for result in page.modificationResultsByID.values {
        let record = try result.get().record
        guard let payload = record["payloadJSON"] as? String else { continue }
        var entry = try JSONDecoder().decode(HouseholdLibraryEntry.self, from: Data(payload.utf8))
        guard entry.key == record.recordID.recordName else { continue }
        if let asset = record["photo"] as? CKAsset, let url = asset.fileURL {
          entry = entry.replacingPhoto(try Data(contentsOf: url))
        }
        entries[entry.key] = try makeRow(entry)
        deletions.remove(entry.key)
      }
      for deletion in page.deletions {
        let key = deletion.recordID.recordName
        entries[key] = nil
        deletions.insert(key)
      }
      nextToken = page.changeToken
      more = page.moreComing
    } while more

    if token == nil {
      deletions.formUnion(Set(checkpoint.fingerprints.keys).subtracting(entries.keys))
    }
    let local = try rows(in: context)
    let updates = entries.values.filter { row in
      let key = row.entry.key
      return local[key]?.fingerprint == checkpoint.fingerprints[key]
    }
    if !updates.isEmpty || !deletions.isEmpty {
      var library = try HouseholdLocalLibrary(context: context)
      library.apply(updates.map(\.entry), deleting: deletions)
      try context.save()
    }
    for update in updates { checkpoint.fingerprints[update.entry.key] = update.fingerprint }
    for key in deletions { checkpoint.fingerprints[key] = nil }
    if let nextToken {
      checkpoint.changeToken = try NSKeyedArchiver.archivedData(withRootObject: nextToken, requiringSecureCoding: true)
    }
    try persist()
  }

  private func rows(in context: ModelContext) throws -> [String: Row] {
    let library = try HouseholdLocalLibrary(context: context)
    return try Dictionary(library.snapshot().map { ($0.key, try makeRow($0)) }, uniquingKeysWith: { first, _ in first })
  }

  private func makeRow(_ entry: HouseholdLibraryEntry) throws -> Row {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let body = try encoder.encode(entry.replacingPhoto(nil))
    var hash = SHA256()
    hash.update(data: body)
    if let photo = entry.photo { hash.update(data: photo) }
    return Row(entry: entry, payload: body, fingerprint: hash.finalize().map { String(format: "%02x", $0) }.joined())
  }

  private func persist() throws {
    try JSONEncoder().encode(checkpoint).write(to: checkpointURL, options: .atomic)
  }

  private func recordID(_ name: String) -> CKRecord.ID {
    CKRecord.ID(recordName: name, zoneID: membership.zoneID)
  }
}
