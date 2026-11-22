import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private var payload = SharePayload()
  private var host: UIHostingController<ShareImportForm>?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    showForm()
    receiveSharedItems()
  }

  private func showForm() {
    let form = ShareImportForm(payload: payload) { [weak self] in
      self?.saveAndFinish()
    } onCancel: { [weak self] in
      self?.extensionContext?.cancelRequest(withError: CancellationError())
    }
    let host = UIHostingController(rootView: form)
    self.host = host
    addChild(host)
    view.addSubview(host.view)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      host.view.topAnchor.constraint(equalTo: view.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
    host.didMove(toParent: self)
  }

  private func receiveSharedItems() {
    let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
    let providers = items.flatMap { $0.attachments ?? [] }
    guard !providers.isEmpty else { return }
    receive(providers: providers, index: 0)
  }

  private func receive(providers: [NSItemProvider], index: Int) {
    guard index < providers.count else {
      DispatchQueue.main.async { self.host?.update(self.payload) }
      return
    }
    let provider = providers[index]
    let typeIDs = [UTType.url.identifier, UTType.fileURL.identifier, UTType.pdf.identifier, UTType.image.identifier, UTType.plainText.identifier]
    guard let typeID = typeIDs.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
      receive(providers: providers, index: index + 1)
      return
    }
    provider.loadItem(forTypeIdentifier: typeID, options: nil) { [weak self] item, _ in
      guard let self else { return }
      if let url = item as? URL {
        if url.isFileURL {
          self.payload.fileURL = self.copyToSharedContainer(url)?.absoluteString ?? ""
          self.payload.title = url.lastPathComponent
        } else {
          self.payload.sourceURL = url.absoluteString
          self.payload.title = url.host ?? "Shared website"
        }
      } else if let url = item as? NSURL {
        let value = url as URL
        if value.isFileURL {
          self.payload.fileURL = self.copyToSharedContainer(value)?.absoluteString ?? ""
          self.payload.title = value.lastPathComponent
        } else {
          self.payload.sourceURL = value.absoluteString
          self.payload.title = value.host ?? "Shared website"
        }
      } else if let text = item as? String {
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
          self.payload.sourceURL = url.absoluteString
          self.payload.title = url.host ?? "Shared website"
        } else if self.payload.text.isEmpty {
          self.payload.text = text
          self.payload.title = "Shared recipe text"
        }
      } else if let data = item as? Data {
        if typeID == UTType.plainText.identifier, let text = String(data: data, encoding: .utf8) {
          self.payload.text = text
          self.payload.title = "Shared recipe text"
        } else {
          let ext = UTType(typeID)?.preferredFilenameExtension ?? "dat"
          self.payload.fileURL = self.writeToSharedContainer(data, name: "Shared recipe.\(ext)")?.absoluteString ?? ""
          self.payload.title = "Shared recipe.\(ext)"
        }
      }
      self.receive(providers: providers, index: index + 1)
    }
  }

  private func copyToSharedContainer(_ url: URL) -> URL? {
    guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharePayload.appGroup) else { return nil }
    let imports = group.appending(path: "Imports", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
    let destination = imports.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
    guard (try? FileManager.default.copyItem(at: url, to: destination)) != nil else { return nil }
    return destination
  }

  private func writeToSharedContainer(_ data: Data, name: String) -> URL? {
    guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharePayload.appGroup) else { return nil }
    let imports = group.appending(path: "Imports", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
    let destination = imports.appending(path: "\(UUID().uuidString)-\(name)")
    do {
      try data.write(to: destination, options: .atomic)
      return destination
    } catch {
      return nil
    }
  }

  private func saveAndFinish() {
    guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharePayload.appGroup) else {
      extensionContext?.cancelRequest(withError: CocoaError(.fileNoSuchFile))
      return
    }
    let queueURL = group.appending(path: "IncomingImports.json")
    var queue = (try? Data(contentsOf: queueURL)).flatMap { try? JSONDecoder().decode([SharePayload].self, from: $0) } ?? []
    queue.append(payload)
    do {
      try JSONEncoder().encode(queue).write(to: queueURL, options: .atomic)
      extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    } catch {
      extensionContext?.cancelRequest(withError: error)
    }
  }
}

private struct SharePayload: Codable, Identifiable {
  static let appGroup = "group.app.bitrig.christopherbradley.newproject.shared"
  var id = UUID()
  var text = ""
  var sourceURL = ""
  var fileURL = ""
  var title = "Shared recipe"
}

private struct ShareImportForm: View {
  @State private var payload: SharePayload
  var onImport: () -> Void
  var onCancel: () -> Void

  init(payload: SharePayload, onImport: @escaping () -> Void, onCancel: @escaping () -> Void) {
    _payload = State(initialValue: payload)
    self.onImport = onImport
    self.onCancel = onCancel
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Image(systemName: "fork.knife")
            .foregroundStyle(Color(red: 0.29, green: 0.38, blue: 0.25))
            .accessibilityHidden(true)
          Text("Apron Buddy")
            .font(.headline)
            .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.14))
          Spacer()
          Button("Cancel", action: onCancel)
            .font(.subheadline)
            .frame(minWidth: 44, minHeight: 44)
        }
        Image(systemName: "document.viewfinder")
          .font(.system(size: 38, weight: .light))
          .foregroundStyle(Color(red: 0.29, green: 0.38, blue: 0.25))
          .accessibilityHidden(true)
        Text("Save to your kitchen")
          .font(.system(.largeTitle, design: .serif, weight: .semibold))
          .foregroundStyle(Color(red: 0.16, green: 0.18, blue: 0.14))
          .accessibilityAddTraits(.isHeader)
        Text(payload.title)
          .font(.headline)
          .fixedSize(horizontal: false, vertical: true)
        if !payload.sourceURL.isEmpty {
          Text(payload.sourceURL)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
        Text("Apron Buddy will read this link or document and prepare an editable recipe when you open the app.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Button(action: onImport) {
          Text("Add to Apron Buddy")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(Color(red: 0.29, green: 0.38, blue: 0.25), in: RoundedRectangle(cornerRadius: 15))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Adds this item to Apron Buddy’s import queue and closes the share sheet.")
      }
      .padding(24)
    }
    .background(Color(red: 0.96, green: 0.95, blue: 0.91))
  }
}

private extension UIHostingController where Content == ShareImportForm {
  func update(_ payload: SharePayload) {
    rootView = ShareImportForm(payload: payload, onImport: rootView.onImport, onCancel: rootView.onCancel)
  }
}
