import SwiftUI

struct CloudStatusToolbar: ToolbarContent {
  var status: String
  var action: () -> Void

  var body: some ToolbarContent {
    ToolbarItem(placement: .automatic) {
      Button(action: action) {
        Image(systemName: status == "iCloud sync is on" ? "checkmark.icloud" : "icloud")
          .foregroundStyle(status == "iCloud sync is on" ? Color.miseOlive : Color.secondary)
      }
      .help("Open Settings and view iCloud sync status")
      .accessibilityLabel("Settings and iCloud sync status: \(status)")
    }
  }
}
