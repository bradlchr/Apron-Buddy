import Foundation
import SwiftData

@Model
final class Cookbook {
  var id: UUID = UUID()
  var name: String = ""
  var detail: String = ""
  var createdAt: Date = Date()
  var isCloudShared: Bool = false
  var isSharedCopy: Bool = false
  var canEditSharedCopy: Bool = false
  var cloudZoneName: String = ""
  var cloudOwnerName: String = ""

  init(name: String, detail: String = "") {
    self.id = UUID()
    self.name = name
    self.detail = detail
    self.createdAt = Date()
  }
}
