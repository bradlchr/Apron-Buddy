import SwiftUI

struct CloudStatusToolbar: ToolbarContent {
  var status: String
  var action: () -> Void

  var body: some ToolbarContent {
    ToolbarItem(placement: .automatic) {
      Button(action: action) {
        Label("Settings", systemImage: "gearshape")
          .labelStyle(.iconOnly)
      }
      .help("Open Apron Buddy settings")
      .accessibilityValue(status)
    }
  }
}
