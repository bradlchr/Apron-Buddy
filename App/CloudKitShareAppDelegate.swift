import CloudKit
import Foundation

#if os(iOS)
import UIKit

final class CloudKitShareAppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
    NotificationCenter.default.post(name: .miseCloudKitShareAccepted, object: metadata)
  }
}
#elseif os(macOS)
import AppKit

final class CloudKitShareAppDelegate: NSObject, NSApplicationDelegate {
  func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
    NotificationCenter.default.post(name: .miseCloudKitShareAccepted, object: metadata)
  }
}
#endif
