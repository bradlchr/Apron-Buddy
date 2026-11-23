import CloudKit
import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor @Observable
final class HouseholdLibraryManager {
  private static let membershipKey = "apronBuddy.householdMembership"
  private static let activeKey = "apronBuddy.householdActive"

  private(set) var membership: HouseholdMembership?
  private(set) var container: ModelContainer?
  private(set) var isActive = false
  private(set) var isBusy = false
  private(set) var isSyncing = false
  private(set) var errorMessage: String?

  @ObservationIgnored var personalContext: ModelContext?
  @ObservationIgnored private var sync: HouseholdLibrarySync?

  var activeID: String? { isActive ? membership?.id : nil }

  func restore() {
    guard membership == nil,
          let saved = UserDefaults.standard.data(forKey: Self.membershipKey),
          let membership = try? JSONDecoder().decode(HouseholdMembership.self, from: saved) else { return }
    do {
      try configure(membership, active: UserDefaults.standard.bool(forKey: Self.activeKey))
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func create(copying personalContext: ModelContext?) async -> Bool {
    guard membership == nil, !isBusy else { return false }
    isBusy = true
    defer { isBusy = false }

    do {
      let entries = try personalContext.map { try HouseholdLocalLibrary(context: $0).snapshot(ownedOnly: true) } ?? []
      let membership = HouseholdMembership(zoneName: HouseholdMembership.zonePrefix + UUID().uuidString, ownerName: CKCurrentUserDefaultName, isOwner: true)
      let db = CloudKitCookbookStore.container.privateCloudDatabase
      _ = try await db.save(CKRecordZone(zoneID: membership.zoneID))
      let share = CKShare(recordZoneID: membership.zoneID)
      share[CKShare.SystemFieldKey.title] = "Apron Buddy Household" as CKRecordValue
      share.publicPermission = .none
      _ = try await db.save(share)
      try configure(membership, active: false)
      if let container, !entries.isEmpty {
        var library = try HouseholdLocalLibrary(context: container.mainContext)
        library.apply(entries, deleting: [])
        try container.mainContext.save()
      }
      errorMessage = nil
      switchLibrary(active: true)
      await synchronize()
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func accept(_ metadata: CKShare.Metadata) async {
    guard HouseholdMembership.matches(metadata), !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    do {
      let zone = metadata.share.recordID.zoneID
      if metadata.participantStatus != .accepted {
        _ = try await CloudKitCookbookStore.container.accept(metadata)
      }
      let isOwner = metadata.participantRole == .owner
      let membership = HouseholdMembership(zoneName: zone.zoneName, ownerName: isOwner ? CKCurrentUserDefaultName : zone.ownerName, isOwner: isOwner)
      try configure(membership, active: true)
      errorMessage = nil
      await synchronize()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func recordError(_ error: Error) { errorMessage = error.localizedDescription }

  func switchLibrary(active: Bool) {
    guard !active || container != nil else { return }
    isActive = active
    UserDefaults.standard.set(active, forKey: Self.activeKey)
  }

  func synchronize() async {
    guard !isSyncing, let sync, let container else { return }
    isSyncing = true
    defer { isSyncing = false }
    do {
      try await sync.synchronize(in: container.mainContext)
      errorMessage = nil
    } catch {
      if !Task.isCancelled { errorMessage = error.localizedDescription }
    }
  }

  private func configure(_ membership: HouseholdMembership, active: Bool) throws {
    let schema = Schema([Recipe.self, Cookbook.self, MealPlan.self])
    let configuration = ModelConfiguration(membership.id, schema: schema, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let sync = try HouseholdLibrarySync(membership: membership)
    UserDefaults.standard.set(try JSONEncoder().encode(membership), forKey: Self.membershipKey)
    self.membership = membership
    self.container = container
    self.sync = sync
    switchLibrary(active: active)
  }
}

extension EnvironmentValues {
  @Entry var householdLibrary: HouseholdLibraryManager? = nil
}
