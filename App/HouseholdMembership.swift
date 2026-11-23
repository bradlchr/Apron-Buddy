import CloudKit
import CoreTransferable
import Foundation

struct HouseholdMembership: Codable, Equatable, Identifiable, Sendable, Transferable {
  static let zonePrefix = "apron-buddy-household-"
  var zoneName: String
  var ownerName: String
  var isOwner: Bool

  var id: String { zoneName }
  var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName) }

  static func matches(_ metadata: CKShare.Metadata) -> Bool {
    metadata.share.recordID.zoneID.zoneName.hasPrefix(zonePrefix)
  }

  static var transferRepresentation: some TransferRepresentation {
    CKShareTransferRepresentation { membership in
      .prepareShare(
        container: CloudKitCookbookStore.container,
        allowedSharingOptions: CKAllowedSharingOptions(
          allowedParticipantPermissionOptions: .readWrite,
          allowedParticipantAccessOptions: .specifiedRecipientsOnly
        )
      ) {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: membership.zoneID)
        guard let share = try await CloudKitCookbookStore.container.privateCloudDatabase.record(for: id) as? CKShare else {
          throw CloudKitCookbookError.missingShare
        }
        return share
      }
    }
  }
}
