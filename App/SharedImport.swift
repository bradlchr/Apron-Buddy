import Foundation

struct SharedImportPayload: Codable, Identifiable {
  var id: UUID = UUID()
  var text: String = ""
  var sourceURL: String = ""
  var fileURL: String = ""
  var title: String = ""
}

enum SharedImportQueue {
  static let appGroup = "group.app.bitrig.christopherbradley.newproject.shared"

  private static var queueURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
      .appending(path: "IncomingImports.json")
  }

  static func takeNextPending() -> SharedImportPayload? {
    guard let url = queueURL,
          let data = try? Data(contentsOf: url),
          let imports = try? JSONDecoder().decode([SharedImportPayload].self, from: data),
          let next = imports.first else { return nil }
    let remaining = Array(imports.dropFirst())
    if remaining.isEmpty {
      try? FileManager.default.removeItem(at: url)
    } else if let updated = try? JSONEncoder().encode(remaining) {
      try? updated.write(to: url, options: .atomic)
    }
    return next
  }
}
