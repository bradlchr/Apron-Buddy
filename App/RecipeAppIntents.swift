import AppIntents
import CloudKit
import Contacts
import Foundation

enum SiriIntegrationPreference {
  static let key = "apronBuddy.siriIntegrationEnabled"

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: key) as? Bool ?? true
  }
}

struct RecipeIntentEntity: AppEntity, Identifiable, Sendable {
  var id: String
  @Property(title: "Name")
  var name: String

  init(id: String, name: String) {
    self.id = id
    self.name = name
  }

  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Recipe")
  static var defaultQuery = RecipeIntentEntityQuery()
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct RecipeIntentEntityQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [RecipeIntentEntity] {
    guard SiriIntegrationPreference.isEnabled else { return [] }
    let wanted = Set(identifiers)
    return SharedKitchenSnapshotStore.load().recipes
      .filter { wanted.contains($0.id.uuidString) }
      .map { RecipeIntentEntity(id: $0.id.uuidString, name: $0.name) }
  }

  func suggestedEntities() async throws -> [RecipeIntentEntity] {
    guard SiriIntegrationPreference.isEnabled else { return [] }
    return Array(SharedKitchenSnapshotStore.load().recipes.prefix(20))
      .map { RecipeIntentEntity(id: $0.id.uuidString, name: $0.name) }
  }

  func entities(matching string: String) async throws -> [RecipeIntentEntity] {
    guard SiriIntegrationPreference.isEnabled else { return [] }
    let query = IntentFuzzyMatcher.normalized(string)
    guard !query.isEmpty else { return try await suggestedEntities() }
    return SharedKitchenSnapshotStore.load().recipes
      .compactMap { recipe -> (RecipeIntentEntity, Double)? in
        let score = IntentFuzzyMatcher.score(query, against: recipe.name)
        guard score >= 0.42 else { return nil }
        return (RecipeIntentEntity(id: recipe.id.uuidString, name: recipe.name), score)
      }
      .sorted { $0.1 > $1.1 }
      .prefix(12)
      .map(\.0)
  }
}

struct ContactRecipientEntity: AppEntity, Identifiable, Sendable {
  var id: String
  @Property(title: "Name")
  var displayName: String
  @Property(title: "Email address")
  var emailAddress: String?
  @Property(title: "Phone number")
  var phoneNumber: String?

  init(id: String, displayName: String, emailAddress: String?, phoneNumber: String?) {
    self.id = id
    self.displayName = displayName
    self.emailAddress = emailAddress
    self.phoneNumber = phoneNumber
  }

  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Contact")
  static var defaultQuery = ContactRecipientEntityQuery()
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(displayName)") }
}

struct ContactRecipientEntityQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [ContactRecipientEntity] {
    guard SiriIntegrationPreference.isEnabled else { return [] }
    let wanted = Set(identifiers)
    return try await contacts().filter { wanted.contains($0.id) }
  }

  func suggestedEntities() async throws -> [ContactRecipientEntity] {
    guard SiriIntegrationPreference.isEnabled else { return [] }
    return Array(try await contacts().prefix(12))
  }

  func entities(matching string: String) async throws -> [ContactRecipientEntity] {
    guard SiriIntegrationPreference.isEnabled else { return [] }
    let query = IntentFuzzyMatcher.normalized(string)
    guard !query.isEmpty else { return try await suggestedEntities() }
    return try await contacts()
      .compactMap { contact -> (ContactRecipientEntity, Double)? in
        let score = IntentFuzzyMatcher.score(query, against: contact.displayName)
        guard score >= 0.42 else { return nil }
        return (contact, score)
      }
      .sorted { $0.1 > $1.1 }
      .prefix(8)
      .map(\.0)
  }

  private func contacts() async throws -> [ContactRecipientEntity] {
    guard SiriIntegrationPreference.isEnabled else { return [] }
    let store = CNContactStore()
    let status = CNContactStore.authorizationStatus(for: .contacts)
    if status == .notDetermined {
      _ = try await store.requestAccess(for: .contacts)
    }
    guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return [] }

    let keys: [CNKeyDescriptor] = [
      CNContactIdentifierKey as CNKeyDescriptor,
      CNContactGivenNameKey as CNKeyDescriptor,
      CNContactFamilyNameKey as CNKeyDescriptor,
      CNContactNicknameKey as CNKeyDescriptor,
      CNContactEmailAddressesKey as CNKeyDescriptor,
      CNContactPhoneNumbersKey as CNKeyDescriptor
    ]
    let request = CNContactFetchRequest(keysToFetch: keys)
    var results: [ContactRecipientEntity] = []
    try store.enumerateContacts(with: request) { contact, _ in
      let email = contact.emailAddresses.first?.value as String?
      let phone = contact.phoneNumbers.first?.value.stringValue
      guard let stableAddress = email?.lowercased() ?? phone?.filter(\.isNumber), !stableAddress.isEmpty else { return }
      let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
      let displayName = name.isEmpty ? (contact.nickname.isEmpty ? "Contact" : contact.nickname) : name
      results.append(ContactRecipientEntity(
        id: stableAddress,
        displayName: displayName,
        emailAddress: email,
        phoneNumber: phone
      ))
    }
    return results.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
  }
}

struct OpenRecipeIntent: AppIntent {
  static var title: LocalizedStringResource = "Open a recipe"
  static var description = IntentDescription("Find and open one of your saved recipes by name.")
  static var supportedModes: IntentModes { .foreground(.immediate) }

  @Parameter(title: "Recipe") var recipe: RecipeIntentEntity

  func perform() async throws -> some IntentResult & OpensIntent {
    guard SiriIntegrationPreference.isEnabled else {
      throw RecipeIntentError.siriIntegrationDisabled
    }
    guard let id = UUID(uuidString: recipe.id),
          let url = URL(string: "apronbuddy://recipe/\(id.uuidString)") else {
      throw RecipeIntentError.recipeUnavailable
    }
    return .result(opensIntent: OpenURLIntent(url))
  }
}

struct ShareRecipeIntent: AppIntent {
  static var title: LocalizedStringResource = "Share a recipe"
  static var description = IntentDescription("Share a saved recipe with a contact using a private iCloud share.")
  static var supportedModes: IntentModes { .foreground(.immediate) }

  @Parameter(title: "Recipe") var recipe: RecipeIntentEntity
  @Parameter(title: "Recipient") var recipient: ContactRecipientEntity

  func perform() async throws -> some IntentResult & OpensIntent {
    guard SiriIntegrationPreference.isEnabled else {
      throw RecipeIntentError.siriIntegrationDisabled
    }
    guard let id = UUID(uuidString: recipe.id),
          let snapshot = SharedKitchenSnapshotStore.load().recipes.first(where: { $0.id == id }) else {
      throw RecipeIntentError.recipeUnavailable
    }
    try await requestConfirmation()
    let shareURL = try await CloudKitCookbookStore.shared.inviteRecipe(
      snapshot,
      emailAddress: recipient.emailAddress,
      phoneNumber: recipient.phoneNumber
    )
    let messageBody = "I shared \(recipe.name) with you in Apron Buddy: \(shareURL.absoluteString)"
    guard let messageURL = invitationMessageURL(body: messageBody) else {
      throw RecipeIntentError.recipientUnavailable
    }
    return .result(opensIntent: OpenURLIntent(messageURL))
  }

  private func invitationMessageURL(body: String) -> URL? {
    var components = URLComponents()
    if let phoneNumber = recipient.phoneNumber {
      components.scheme = "sms"
      components.path = phoneNumber
      components.queryItems = [URLQueryItem(name: "body", value: body)]
    } else if let emailAddress = recipient.emailAddress {
      components.scheme = "mailto"
      components.path = emailAddress
      components.queryItems = [
        URLQueryItem(name: "subject", value: "A recipe from Apron Buddy"),
        URLQueryItem(name: "body", value: body)
      ]
    } else {
      return nil
    }
    return components.url
  }
}

struct ApronBuddyShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
        intent: OpenRecipeIntent(),
        phrases: [
          "Open \(\.$recipe) in \(.applicationName)",
          "Find \(\.$recipe) in \(.applicationName)"
        ],
        shortTitle: "Open recipe",
        systemImageName: "fork.knife"
    )
    AppShortcut(
        intent: ShareRecipeIntent(),
        phrases: [
          "Share \(\.$recipe) in \(.applicationName)",
          "Send a recipe to \(\.$recipient) with \(.applicationName)"
        ],
        shortTitle: "Share recipe",
        systemImageName: "square.and.arrow.up"
    )
  }
}

enum RecipeIntentError: Error, CustomLocalizedStringResourceConvertible {
  case siriIntegrationDisabled
  case recipeUnavailable
  case recipientUnavailable

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .siriIntegrationDisabled:
      "Siri recipe access is turned off. Enable Siri & Shortcuts in Apron Buddy Settings to use this action."
    case .recipeUnavailable:
      "That recipe isn't available in Apron Buddy yet."
    case .recipientUnavailable:
      "That contact doesn't have an email address or phone number to receive a share invitation."
    }
  }
}

private enum IntentFuzzyMatcher {
  static func normalized(_ value: String) -> String {
    let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    let words = folded.split { !$0.isLetter && !$0.isNumber }
      .map(String.init)
      .filter { !["my", "the", "a", "an", "recipe", "please", "open", "show", "find", "send", "share"].contains($0) }
    return words.joined(separator: " ")
  }

  static func score(_ query: String, against candidate: String) -> Double {
    let normalizedCandidate = normalized(candidate)
    if normalizedCandidate == query { return 1 }
    if normalizedCandidate.contains(query) || query.contains(normalizedCandidate) { return 0.94 }
    let queryWords = query.split(separator: " ").map(String.init)
    let candidateWords = normalizedCandidate.split(separator: " ").map(String.init)
    guard !queryWords.isEmpty, !candidateWords.isEmpty else { return 0 }
    let matched = queryWords.map { word in
      candidateWords.map { wordScore(word, $0) }.max() ?? 0
    }
    let average = matched.reduce(0, +) / Double(matched.count)
    let coverage = Double(matched.filter { $0 >= 0.62 }.count) / Double(queryWords.count)
    return average * 0.65 + coverage * 0.35
  }

  private static func wordScore(_ left: String, _ right: String) -> Double {
    if left == right { return 1 }
    if left.count >= 3 && (left.contains(right) || right.contains(left)) { return 0.88 }
    let a = Array(left)
    let b = Array(right)
    var row = Array(0...b.count)
    for (i, leftCharacter) in a.enumerated() {
      var next = [i + 1] + Array(repeating: 0, count: b.count)
      for (j, rightCharacter) in b.enumerated() {
        next[j + 1] = min(
          next[j] + 1,
          row[j + 1] + 1,
          row[j] + (leftCharacter == rightCharacter ? 0 : 1)
        )
      }
      row = next
    }
    return 1 - Double(row[b.count]) / Double(max(max(a.count, b.count), 1))
  }
}
