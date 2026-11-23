import CloudKit
import Foundation

#if os(iOS)
import UIKit

@MainActor
final class CloudKitShareAppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
    CloudKitShareArrival.receive(metadata)
  }
}
#elseif os(macOS)
import AppKit

@MainActor
final class CloudKitShareAppDelegate: NSObject, NSApplicationDelegate {
  func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
    CloudKitShareArrival.receive(metadata)
  }
}
#endif

@MainActor
enum CloudKitShareArrival {
  private static var pendingHousehold: CKShare.Metadata?

  static func receive(_ metadata: CKShare.Metadata) {
    if HouseholdMembership.matches(metadata) { pendingHousehold = metadata }
    NotificationCenter.default.post(name: .miseCloudKitShareAccepted, object: metadata)
  }

  static func takePendingHousehold() -> CKShare.Metadata? {
    defer { pendingHousehold = nil }
    return pendingHousehold
  }
}
