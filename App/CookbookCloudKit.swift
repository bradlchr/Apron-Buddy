import CloudKit
import CoreTransferable
import Foundation
import SwiftData

extension SharedRecipeSnapshot {
  init(_ recipe: Recipe) {
    id = recipe.id
    name = recipe.name
    summary = recipe.summary
    userNotes = recipe.userNotes
    category = recipe.category
    servings = recipe.servings
    caloriesPerServing = recipe.caloriesPerServing
    prepMinutes = recipe.prepMinutes
    cookMinutes = recipe.cookMinutes
    difficulty = recipe.difficulty
    sourceURL = recipe.sourceURL
    sourceName = recipe.sourceName
    ingredientsJSON = recipe.ingredientsJSON
    stepsJSON = recipe.stepsJSON
    goodForJSON = recipe.goodForJSON
    rating = recipe.rating
    isFavorite = recipe.isFavorite
    createdAt = recipe.createdAt
    photoData = recipe.photoData
  }
}

extension SharedRecipeSnapshot: Transferable {
  static var transferRepresentation: some TransferRepresentation {
    CKShareTransferRepresentation { snapshot in
      .prepareShare(
        container: CloudKitCookbookStore.container,
        allowedSharingOptions: CKAllowedSharingOptions(
          allowedParticipantPermissionOptions: .any,
          allowedParticipantAccessOptions: .specifiedRecipientsOnly
        )
      ) {
        try await CloudKitCookbookStore.shared.prepareRecipeShare(for: snapshot)
      }
    }
  }
}

struct CookbookShareSnapshot: Codable, Hashable, Identifiable, Sendable, Transferable {
  var id: UUID
  var name: String
  var detail: String
  var recipes: [SharedRecipeSnapshot]

  init(cookbook: Cookbook, recipes: [Recipe]) {
    id = cookbook.id
    name = cookbook.name
    detail = cookbook.detail
    self.recipes = recipes.map(SharedRecipeSnapshot.init)
  }

  init(id: UUID, name: String, detail: String, recipes: [SharedRecipeSnapshot]) {
    self.id = id
    self.name = name
    self.detail = detail
    self.recipes = recipes
  }

  static var transferRepresentation: some TransferRepresentation {
    CKShareTransferRepresentation { snapshot in
      .prepareShare(
        container: CloudKitCookbookStore.container,
        allowedSharingOptions: CKAllowedSharingOptions(
          allowedParticipantPermissionOptions: .any,
          allowedParticipantAccessOptions: .specifiedRecipientsOnly
        )
      ) {
        try await CloudKitCookbookStore.shared.prepareShare(for: snapshot)
      }
    }
  }
}

enum CloudKitCookbookError: LocalizedError {
  case missingSharedCookbook
  case missingSharedRecipe(String)
  case missingShare

  var errorDescription: String? {
    switch self {
    case .missingSharedCookbook: "The shared cookbook is no longer available."
    case .missingSharedRecipe(let name): "Apron Buddy couldn’t load “\(name)”. Try again when you’re online."
    case .missingShare: "CloudKit didn’t return the cookbook share. Try again."
    }
  }
}

final class CloudKitCookbookStore: @unchecked Sendable {
  static let containerIdentifier = "iCloud.app.bitrig.christopherbradley.newproject"
  static let container = CKContainer(identifier: containerIdentifier)
  static let shared = CloudKitCookbookStore()

  private init() { }

  private var privateDatabase: CKDatabase { Self.container.privateCloudDatabase }
  private var sharedDatabase: CKDatabase { Self.container.sharedCloudDatabase }

  func accountStatusMessage() async -> String {
    await withCheckedContinuation { continuation in
      Self.container.accountStatus { status, error in
        let message = switch status {
        case .available: "iCloud sync is on"
        case .noAccount: "Sign in to iCloud to sync"
        case .restricted: "iCloud access is restricted"
        case .temporarilyUnavailable: "iCloud is temporarily unavailable"
        case .couldNotDetermine: error.map { Self.message(for: $0) } ?? "iCloud status is unavailable"
        @unknown default: error.map { Self.message(for: $0) } ?? "iCloud status is unavailable"
        }
        continuation.resume(returning: message)
      }
    }
  }

  private static func message(for error: Error) -> String {
    let value = error as NSError
    if value.domain == NSCocoaErrorDomain && value.code == 134400 {
      return "Sign in to iCloud to sync"
    }
    if value.domain == CKError.errorDomain, let code = CKError.Code(rawValue: value.code) {
      switch code {
      case .notAuthenticated: return "Sign in to iCloud to sync"
      case .networkUnavailable, .networkFailure: return "iCloud is temporarily unavailable"
      default: return "iCloud sync needs attention"
      }
    }
    return "iCloud sync needs attention"
  }

  func prepareShare(for snapshot: CookbookShareSnapshot) async throws -> CKShare {
    guard let share = try await save(snapshot, in: privateDatabase, makeShare: true, createZone: true) else {
      throw CloudKitCookbookError.missingShare
    }
    return share
  }

  func prepareRecipeShare(for snapshot: SharedRecipeSnapshot) async throws -> CKShare {
    guard let share = try await saveRecipe(
      snapshot,
      in: privateDatabase,
      makeShare: true,
      createZone: true
    ) else {
      throw CloudKitCookbookError.missingShare
    }
    return share
  }

  func inviteRecipe(_ snapshot: SharedRecipeSnapshot, emailAddress: String?, phoneNumber: String?) async throws -> URL {
    let share = try await prepareRecipeShare(for: snapshot)
    let participant: CKShare.Participant
    if let phoneNumber {
      participant = try await Self.container.shareParticipant(forPhoneNumber: phoneNumber)
    } else if let emailAddress {
      participant = try await Self.container.shareParticipant(forEmailAddress: emailAddress)
    } else {
      throw CloudKitCookbookError.missingShare
    }
    participant.permission = .readOnly
    if !share.participants.contains(where: { $0.isEqual(participant) }) {
      share.addParticipant(participant)
    }
    let savedShare = try await privateDatabase.save(share) as? CKShare ?? share
    guard let url = savedShare.url else { throw CloudKitCookbookError.missingShare }
    return url
  }

  func synchronizeRecipe(_ snapshot: SharedRecipeSnapshot, recipe: Recipe) async throws {
    if recipe.isSharedRecipeCopy {
      guard recipe.canEditSharedRecipe else { return }
      _ = try await saveRecipe(
        snapshot,
        in: sharedDatabase,
        makeShare: false,
        createZone: false,
        zoneID: CKRecordZone.ID(zoneName: recipe.sharedRecipeZoneName, ownerName: recipe.sharedRecipeOwnerName)
      )
    } else if recipe.isCloudSharedRecipe {
      _ = try await saveRecipe(snapshot, in: privateDatabase, makeShare: true, createZone: true)
    }
  }

  func deleteRecipeShare(id: UUID) async throws {
    try await privateDatabase.deleteRecordZone(withID: Self.recipeZoneID(for: id))
  }

  func fetchSharedRecipe(metadata: CKShare.Metadata) async throws -> (SharedRecipeSnapshot, CKShare) {
    let share = try await accept(metadata)
    guard let rootID = metadata.hierarchicalRootRecordID else {
      throw CloudKitCookbookError.missingSharedRecipe("shared recipe")
    }
    let root = try await sharedDatabase.record(for: rootID)
    return (try snapshot(from: root), share)
  }

  func synchronize(
    _ snapshot: CookbookShareSnapshot,
    isSharedCopy: Bool,
    zoneName: String = "",
    ownerName: String = ""
  ) async throws {
    let database = isSharedCopy ? sharedDatabase : privateDatabase
    let sharedZone = isSharedCopy
      ? CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
      : nil
    _ = try await save(
      snapshot,
      in: database,
      makeShare: !isSharedCopy,
      createZone: !isSharedCopy,
      zoneID: sharedZone
    )
  }

  func fetchSharedCookbook(metadata: CKShare.Metadata) async throws -> (CookbookShareSnapshot, CKShare) {
    let share = try await accept(metadata)
    guard let rootID = metadata.hierarchicalRootRecordID else {
      throw CloudKitCookbookError.missingSharedCookbook
    }
    let root = try await sharedDatabase.record(for: rootID)
    return (try await snapshot(from: root, in: sharedDatabase), share)
  }

  func refreshSharedCookbook(zoneName: String, ownerName: String, cookbookID: UUID) async throws -> CookbookShareSnapshot {
    let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)
    let root = try await sharedDatabase.record(for: rootID)
    return try await snapshot(from: root, in: sharedDatabase)
  }

  private func accept(_ metadata: CKShare.Metadata) async throws -> CKShare {
    try await withCheckedThrowingContinuation { continuation in
      Self.container.accept(metadata) { share, error in
        if let share {
          continuation.resume(returning: share)
        } else if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(throwing: CloudKitCookbookError.missingShare)
        }
      }
    }
  }

  private func save(
    _ snapshot: CookbookShareSnapshot,
    in database: CKDatabase,
    makeShare: Bool,
    createZone: Bool,
    zoneID suppliedZoneID: CKRecordZone.ID? = nil
  ) async throws -> CKShare? {
    let zoneID = suppliedZoneID ?? Self.zoneID(for: snapshot.id)
    if createZone {
      let existingZones = try? await database.recordZones(for: [zoneID])
      if let zoneResult = existingZones?[zoneID], case .success = zoneResult {
        // This cookbook's custom zone already exists.
      } else {
        _ = try await database.save(CKRecordZone(zoneID: zoneID))
      }
    }

    let rootID = CKRecord.ID(recordName: Self.rootRecordName, zoneID: zoneID)
    let root: CKRecord
    if let current = try? await database.record(for: rootID) {
      root = current
    } else {
      root = CKRecord(recordType: "MiseCookbook", recordID: rootID)
    }
    let oldIDs = root["recipeIDs"] as? [String] ?? []
    root["cookbookID"] = snapshot.id.uuidString as CKRecordValue
    root["name"] = snapshot.name as CKRecordValue
    root["detail"] = snapshot.detail as CKRecordValue
    root["recipeIDs"] = snapshot.recipes.map { $0.id.uuidString } as NSArray

    var recipeRecords: [CKRecord] = []
    var temporaryPhotos: [URL] = []
    for recipe in snapshot.recipes {
      let recordID = CKRecord.ID(recordName: recipe.id.uuidString, zoneID: zoneID)
      let record: CKRecord
      if let current = try? await database.record(for: recordID) {
        record = current
      } else {
        record = CKRecord(recordType: "MiseRecipe", recordID: recordID)
      }
      record.parent = CKRecord.Reference(recordID: rootID, action: .none)
      record["name"] = recipe.name as CKRecordValue
      record["summary"] = recipe.summary as CKRecordValue
      record["userNotes"] = recipe.userNotes as CKRecordValue
      record["category"] = recipe.category as CKRecordValue
      record["servings"] = NSNumber(value: recipe.servings)
      record["caloriesPerServing"] = NSNumber(value: recipe.caloriesPerServing)
      record["prepMinutes"] = NSNumber(value: recipe.prepMinutes)
      record["cookMinutes"] = NSNumber(value: recipe.cookMinutes)
      record["difficulty"] = recipe.difficulty as CKRecordValue
      record["sourceURL"] = recipe.sourceURL as CKRecordValue
      record["sourceName"] = recipe.sourceName as CKRecordValue
      record["ingredientsJSON"] = recipe.ingredientsJSON as CKRecordValue
      record["stepsJSON"] = recipe.stepsJSON as CKRecordValue
      record["goodForJSON"] = recipe.goodForJSON as CKRecordValue
      record["rating"] = NSNumber(value: recipe.rating)
      record["isFavorite"] = NSNumber(value: recipe.isFavorite)
      record["createdAt"] = recipe.createdAt as CKRecordValue

      if let photoData = recipe.photoData, photoData.count <= 8_000_000 {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MiseSharePhotos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let photoURL = directory.appending(path: "\(recipe.id.uuidString).jpg")
        try photoData.write(to: photoURL, options: .atomic)
        temporaryPhotos.append(photoURL)
        record["photo"] = CKAsset(fileURL: photoURL)
      } else {
        record["photo"] = nil
      }
      recipeRecords.append(record)
    }
    defer { temporaryPhotos.forEach { try? FileManager.default.removeItem(at: $0) } }

    var share: CKShare?
    if makeShare {
      let shareID = CKRecord.ID(recordName: Self.shareRecordName, zoneID: zoneID)
      if let existing = try? await database.record(for: shareID) as? CKShare {
        share = existing
      } else {
        share = CKShare(rootRecord: root, shareID: shareID)
      }
      share?[CKShare.SystemFieldKey.title] = snapshot.name as CKRecordValue
      share?.publicPermission = .none
    }

    let currentIDs = Set(snapshot.recipes.map { $0.id.uuidString })
    let deletions = oldIDs.filter { !currentIDs.contains($0) }.map {
      CKRecord.ID(recordName: $0, zoneID: zoneID)
    }
    let records = [root] + recipeRecords + (share.map { [$0] } ?? [])
    let result = try await database.modifyRecords(
      saving: records,
      deleting: deletions,
      savePolicy: .changedKeys,
      atomically: true
    )
    for saved in result.saveResults.values {
      if case .failure(let error) = saved { throw error }
    }
    guard makeShare else { return nil }
    let savedShareID = CKRecord.ID(recordName: Self.shareRecordName, zoneID: zoneID)
    guard let savedShare = result.saveResults[savedShareID] else { throw CloudKitCookbookError.missingShare }
    switch savedShare {
    case .success(let record): return record as? CKShare ?? share
    case .failure(let error): throw error
    }
  }

  private func saveRecipe(
    _ snapshot: SharedRecipeSnapshot,
    in database: CKDatabase,
    makeShare: Bool,
    createZone: Bool,
    zoneID suppliedZoneID: CKRecordZone.ID? = nil
  ) async throws -> CKShare? {
    let zoneID = suppliedZoneID ?? Self.recipeZoneID(for: snapshot.id)
    if createZone {
      let existingZones = try? await database.recordZones(for: [zoneID])
      if let result = existingZones?[zoneID], case .success = result {
        // The standalone recipe's private zone is already present.
      } else {
        _ = try await database.save(CKRecordZone(zoneID: zoneID))
      }
    }

    let rootID = CKRecord.ID(recordName: Self.recipeRootRecordName, zoneID: zoneID)
    let root = (try? await database.record(for: rootID)) ?? CKRecord(recordType: "MiseSharedRecipe", recordID: rootID)
    root["recipeID"] = snapshot.id.uuidString as CKRecordValue
    root["name"] = snapshot.name as CKRecordValue
    root["summary"] = snapshot.summary as CKRecordValue
    root["userNotes"] = snapshot.userNotes as CKRecordValue
    root["category"] = snapshot.category as CKRecordValue
    root["servings"] = NSNumber(value: snapshot.servings)
    root["caloriesPerServing"] = NSNumber(value: snapshot.caloriesPerServing)
    root["prepMinutes"] = NSNumber(value: snapshot.prepMinutes)
    root["cookMinutes"] = NSNumber(value: snapshot.cookMinutes)
    root["difficulty"] = snapshot.difficulty as CKRecordValue
    root["sourceURL"] = snapshot.sourceURL as CKRecordValue
    root["sourceName"] = snapshot.sourceName as CKRecordValue
    root["ingredientsJSON"] = snapshot.ingredientsJSON as CKRecordValue
    root["stepsJSON"] = snapshot.stepsJSON as CKRecordValue
    root["goodForJSON"] = snapshot.goodForJSON as CKRecordValue
    root["rating"] = NSNumber(value: snapshot.rating)
    root["isFavorite"] = NSNumber(value: snapshot.isFavorite)
    root["createdAt"] = snapshot.createdAt as CKRecordValue

    var photoURL: URL?
    if let photoData = snapshot.photoData, photoData.count <= 8_000_000 {
      let directory = FileManager.default.temporaryDirectory.appending(path: "ApronBuddySharePhotos", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appending(path: "\(snapshot.id.uuidString).jpg")
      try photoData.write(to: url, options: .atomic)
      photoURL = url
      root["photo"] = CKAsset(fileURL: url)
    } else {
      root["photo"] = nil
    }
    defer { if let photoURL { try? FileManager.default.removeItem(at: photoURL) } }

    var share: CKShare?
    if makeShare {
      let shareID = CKRecord.ID(recordName: Self.recipeShareRecordName, zoneID: zoneID)
      if let existing = try? await database.record(for: shareID) as? CKShare {
        share = existing
      } else {
        share = CKShare(rootRecord: root, shareID: shareID)
      }
      share?[CKShare.SystemFieldKey.title] = snapshot.name as CKRecordValue
      share?.publicPermission = .none
    }

    let records = [root] + (share.map { [$0] } ?? [])
    let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys, atomically: true)
    for saved in result.saveResults.values {
      if case .failure(let error) = saved { throw error }
    }
    guard makeShare else { return nil }
    let shareID = CKRecord.ID(recordName: Self.recipeShareRecordName, zoneID: zoneID)
    guard let result = result.saveResults[shareID] else { throw CloudKitCookbookError.missingShare }
    switch result {
    case .success(let record): return record as? CKShare ?? share
    case .failure(let error): throw error
    }
  }

  private func snapshot(from root: CKRecord) throws -> SharedRecipeSnapshot {
    guard let idString = root["recipeID"] as? String, let id = UUID(uuidString: idString) else {
      throw CloudKitCookbookError.missingSharedRecipe("shared recipe")
    }
    let photoData: Data?
    if let asset = root["photo"] as? CKAsset, let url = asset.fileURL {
      photoData = try? Data(contentsOf: url)
    } else {
      photoData = nil
    }
    return SharedRecipeSnapshot(
      id: id,
      name: root["name"] as? String ?? "Shared recipe",
      summary: root["summary"] as? String ?? "",
      userNotes: root["userNotes"] as? String ?? "",
      category: root["category"] as? String ?? "Dinner",
      servings: (root["servings"] as? NSNumber)?.intValue ?? 4,
      caloriesPerServing: (root["caloriesPerServing"] as? NSNumber)?.intValue ?? 0,
      prepMinutes: (root["prepMinutes"] as? NSNumber)?.intValue ?? 0,
      cookMinutes: (root["cookMinutes"] as? NSNumber)?.intValue ?? 0,
      difficulty: root["difficulty"] as? String ?? "Easy",
      sourceURL: root["sourceURL"] as? String ?? "",
      sourceName: root["sourceName"] as? String ?? "",
      ingredientsJSON: root["ingredientsJSON"] as? String ?? "[]",
      stepsJSON: root["stepsJSON"] as? String ?? "[]",
      goodForJSON: root["goodForJSON"] as? String ?? "[]",
      rating: (root["rating"] as? NSNumber)?.intValue ?? 0,
      isFavorite: (root["isFavorite"] as? NSNumber)?.boolValue ?? false,
      createdAt: root["createdAt"] as? Date ?? .now,
      photoData: photoData
    )
  }

  private func snapshot(from root: CKRecord, in database: CKDatabase) async throws -> CookbookShareSnapshot {
    guard let idString = root["cookbookID"] as? String, let id = UUID(uuidString: idString) else {
      throw CloudKitCookbookError.missingSharedCookbook
    }
    let recipeIDs = root["recipeIDs"] as? [String] ?? []
    var recipes: [SharedRecipeSnapshot] = []
    for recipeIDString in recipeIDs {
      let recordID = CKRecord.ID(recordName: recipeIDString, zoneID: root.recordID.zoneID)
      guard let record = try? await database.record(for: recordID) else {
        throw CloudKitCookbookError.missingSharedRecipe(recipeIDString)
      }
      guard let recipeID = UUID(uuidString: recipeIDString) else { continue }
      let photoData: Data?
      if let photo = record["photo"] as? CKAsset, let url = photo.fileURL {
        photoData = try? Data(contentsOf: url)
      } else {
        photoData = nil
      }
      let name = record["name"] as? String ?? "Untitled recipe"
      let summary = record["summary"] as? String ?? ""
      let userNotes = record["userNotes"] as? String ?? ""
      let category = record["category"] as? String ?? "Dinner"
      let servings = (record["servings"] as? NSNumber)?.intValue ?? 4
      let caloriesPerServing = (record["caloriesPerServing"] as? NSNumber)?.intValue ?? 0
      let prepMinutes = (record["prepMinutes"] as? NSNumber)?.intValue ?? 0
      let cookMinutes = (record["cookMinutes"] as? NSNumber)?.intValue ?? 0
      let difficulty = record["difficulty"] as? String ?? "Easy"
      let sourceURL = record["sourceURL"] as? String ?? ""
      let sourceName = record["sourceName"] as? String ?? ""
      let ingredientsJSON = record["ingredientsJSON"] as? String ?? "[]"
      let stepsJSON = record["stepsJSON"] as? String ?? "[]"
      let goodForJSON = record["goodForJSON"] as? String ?? "[]"
      let rating = (record["rating"] as? NSNumber)?.intValue ?? 0
      let isFavorite = (record["isFavorite"] as? NSNumber)?.boolValue ?? false
      let createdAt = record["createdAt"] as? Date ?? .now
      let recipeSnapshot = SharedRecipeSnapshot(
        id: recipeID,
        name: name,
        summary: summary,
        userNotes: userNotes,
        category: category,
        servings: servings,
        caloriesPerServing: caloriesPerServing,
        prepMinutes: prepMinutes,
        cookMinutes: cookMinutes,
        difficulty: difficulty,
        sourceURL: sourceURL,
        sourceName: sourceName,
        ingredientsJSON: ingredientsJSON,
        stepsJSON: stepsJSON,
        goodForJSON: goodForJSON,
        rating: rating,
        isFavorite: isFavorite,
        createdAt: createdAt,
        photoData: photoData
      )
      recipes.append(recipeSnapshot)
    }
    return CookbookShareSnapshot(
      id: id,
      name: root["name"] as? String ?? "Shared cookbook",
      detail: root["detail"] as? String ?? "",
      recipes: recipes
    )
  }

  static func snapshot(cookbook: Cookbook, recipes: [Recipe]) -> CookbookShareSnapshot {
    CookbookShareSnapshot(cookbook: cookbook, recipes: recipes.filter { $0.cookbookIDs.contains(cookbook.id) })
  }

  static func zoneID(for cookbookID: UUID) -> CKRecordZone.ID {
    CKRecordZone.ID(zoneName: "mise-cookbook-\(cookbookID.uuidString)", ownerName: CKCurrentUserDefaultName)
  }

  static func recipeZoneID(for recipeID: UUID) -> CKRecordZone.ID {
    CKRecordZone.ID(zoneName: "mise-recipe-\(recipeID.uuidString)", ownerName: CKCurrentUserDefaultName)
  }

  static let rootRecordName = "cookbook-root"
  static let shareRecordName = "cookbook-share"
  static let recipeRootRecordName = "recipe-root"
  static let recipeShareRecordName = "recipe-share"
}

@MainActor
enum SharedRecipeImporter {
  static func accept(_ metadata: CKShare.Metadata, in context: ModelContext) async throws {
    let (snapshot, share) = try await CloudKitCookbookStore.shared.fetchSharedRecipe(metadata: metadata)
    let rootID = metadata.hierarchicalRootRecordID
    let existing = ((try? context.fetch(FetchDescriptor<Recipe>())) ?? []).first { $0.id == snapshot.id }
    let recipe = existing ?? Recipe(
      name: snapshot.name,
      summary: snapshot.summary,
      category: snapshot.category,
      servings: snapshot.servings,
      prepMinutes: snapshot.prepMinutes,
      cookMinutes: snapshot.cookMinutes,
      difficulty: snapshot.difficulty,
      ingredients: [],
      steps: []
    )
    if existing == nil { context.insert(recipe) }
    apply(snapshot, to: recipe)
    recipe.isSharedRecipeCopy = true
    recipe.canEditSharedRecipe = share.currentUserParticipant?.permission == .readWrite
    recipe.sharedRecipeZoneName = rootID?.zoneID.zoneName ?? ""
    recipe.sharedRecipeOwnerName = rootID?.zoneID.ownerName ?? ""
    try context.save()
  }

  private static func apply(_ snapshot: SharedRecipeSnapshot, to recipe: Recipe) {
    recipe.id = snapshot.id
    recipe.name = snapshot.name
    recipe.summary = snapshot.summary
    recipe.userNotes = snapshot.userNotes
    recipe.category = snapshot.category
    recipe.servings = snapshot.servings
    recipe.caloriesPerServing = snapshot.caloriesPerServing
    recipe.prepMinutes = snapshot.prepMinutes
    recipe.cookMinutes = snapshot.cookMinutes
    recipe.difficulty = snapshot.difficulty
    recipe.sourceURL = snapshot.sourceURL
    recipe.sourceName = snapshot.sourceName
    recipe.ingredientsJSON = snapshot.ingredientsJSON
    recipe.stepsJSON = snapshot.stepsJSON
    recipe.goodForJSON = snapshot.goodForJSON
    recipe.rating = snapshot.rating
    recipe.isFavorite = snapshot.isFavorite
    recipe.createdAt = snapshot.createdAt
    recipe.photoData = snapshot.photoData
  }
}

@MainActor
enum SharedCookbookImporter {
  static func accept(_ metadata: CKShare.Metadata, in context: ModelContext) async throws {
    let (snapshot, share) = try await CloudKitCookbookStore.shared.fetchSharedCookbook(metadata: metadata)
    guard let rootID = metadata.hierarchicalRootRecordID else {
      throw CloudKitCookbookError.missingSharedCookbook
    }
    apply(snapshot, in: context, sharedCopy: true, canEdit: share.currentUserParticipant?.permission == .readWrite, zoneName: rootID.zoneID.zoneName, ownerName: rootID.zoneID.ownerName)
  }

  static func refresh(_ cookbook: Cookbook, recipes: [Recipe], in context: ModelContext) async throws {
    guard cookbook.isSharedCopy else {
      try await CloudKitCookbookStore.shared.synchronize(
        CloudKitCookbookStore.snapshot(cookbook: cookbook, recipes: recipes),
        isSharedCopy: false
      )
      return
    }
    guard cookbook.canEditSharedCopy else {
      let snapshot = try await CloudKitCookbookStore.shared.refreshSharedCookbook(
        zoneName: cookbook.cloudZoneName,
        ownerName: cookbook.cloudOwnerName,
        cookbookID: cookbook.id
      )
      apply(snapshot, in: context, sharedCopy: true, canEdit: false, zoneName: cookbook.cloudZoneName, ownerName: cookbook.cloudOwnerName)
      return
    }
    try await CloudKitCookbookStore.shared.synchronize(
      CloudKitCookbookStore.snapshot(cookbook: cookbook, recipes: recipes),
      isSharedCopy: true,
      zoneName: cookbook.cloudZoneName,
      ownerName: cookbook.cloudOwnerName
    )
  }

  static func apply(
    _ snapshot: CookbookShareSnapshot,
    in context: ModelContext,
    sharedCopy: Bool,
    canEdit: Bool,
    zoneName: String,
    ownerName: String
  ) {
    let localCookbooks = (try? context.fetch(FetchDescriptor<Cookbook>())) ?? []
    let cookbook = localCookbooks.first { $0.id == snapshot.id }
    let target = cookbook ?? Cookbook(name: snapshot.name, detail: snapshot.detail)
    if cookbook == nil { context.insert(target) }
    target.id = snapshot.id
    target.name = snapshot.name
    target.detail = snapshot.detail
    target.isCloudShared = true
    target.isSharedCopy = sharedCopy
    target.canEditSharedCopy = canEdit
    target.cloudZoneName = zoneName
    target.cloudOwnerName = ownerName

    let incomingIDs = Set(snapshot.recipes.map(\.id))
    let localRecipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
    for recipe in localRecipes where recipe.cookbookIDs.contains(snapshot.id) && !incomingIDs.contains(recipe.id) {
      recipe.remove(from: snapshot.id)
    }
    for shared in snapshot.recipes {
        let existing = localRecipes.first { $0.id == shared.id }
        let recipe = existing ?? Recipe(
          name: shared.name,
          summary: shared.summary,
          category: shared.category,
          servings: shared.servings,
          prepMinutes: shared.prepMinutes,
          cookMinutes: shared.cookMinutes,
          difficulty: shared.difficulty,
          ingredients: [],
          steps: []
        )
        if existing == nil { context.insert(recipe) }
        recipe.id = shared.id
        recipe.name = shared.name
        recipe.summary = shared.summary
        recipe.userNotes = shared.userNotes
        recipe.category = shared.category
        recipe.servings = shared.servings
        recipe.caloriesPerServing = shared.caloriesPerServing
        recipe.prepMinutes = shared.prepMinutes
        recipe.cookMinutes = shared.cookMinutes
        recipe.difficulty = shared.difficulty
        recipe.sourceURL = shared.sourceURL
        recipe.sourceName = shared.sourceName
        recipe.ingredientsJSON = shared.ingredientsJSON
        recipe.stepsJSON = shared.stepsJSON
        recipe.goodForJSON = shared.goodForJSON
        recipe.rating = shared.rating
        recipe.isFavorite = shared.isFavorite
        recipe.createdAt = shared.createdAt
        recipe.photoData = shared.photoData
        recipe.add(to: snapshot.id)
    }
    try? context.save()
  }
}

extension Notification.Name {
  static let miseCloudKitShareAccepted = Notification.Name("MiseCloudKitShareAccepted")
}
