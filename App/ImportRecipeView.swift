import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ImportRecipeView: View {
  @KitchenPalette private var palette
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Query(sort: \Cookbook.createdAt, order: .forward) private var cookbooks: [Cookbook]
  @State private var link = ""
  @State private var sourceText = ""
  @State private var manualPasteText = ""
  @State private var sourceURL = ""
  @State private var sourceName = ""
  @State private var isReading = false
  @State private var isShowingFilePicker = false
  @State private var isShowingBatchFilesPicker = false
  @State private var isShowingFolderPicker = false
  @State private var isScannerPresented = false
  @State private var isCameraPresented = false
  @State private var isPastingText = false
  @State private var isShowingError = false
  @State private var alertTitle = "Couldn’t import recipe"
  @State private var errorMessage = ""
  @State private var batchProgress = ""
  @State private var batchFiles: [URL] = []
  @State private var batchIndex = 0
  @State private var batchImportedCount = 0
  @State private var batchFailedCount = 0
  @State private var batchFolderURL: URL?
  @State private var batchFolderAccessing = false
  @State private var dismissAfterBatchAlert = false
  @State private var importedDraft: ImportedRecipeDraft?
  @State private var wasAIExtracted = true
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var photoData: Data?
  @State private var selectedCookbookID: UUID?
  var importItem: SharedImportPayload?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Bring a recipe in")
        .font(.system(.largeTitle, design: .serif, weight: .semibold))
              .foregroundStyle(palette.ink)
            Text("Apron Buddy reads a link or document, then uses on-device AI to turn it into a recipe you can edit.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          if let importedDraft {
            draftEditor(importedDraft)
          } else {
            sourcePicker
          }
        }
        .padding(24)
        .frame(maxWidth: 680, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .background(palette.paper)
      .navigationTitle(importedDraft == nil ? "Import recipe" : "Review recipe")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        if importedDraft != nil {
          ToolbarItem(placement: .confirmationAction) {
            Button(saveButtonTitle) { saveRecipe() }
              .fontWeight(.semibold)
              .disabled(importedDraft?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
          }
        }
      }
      .fileImporter(
        isPresented: $isShowingFilePicker,
        allowedContentTypes: [.pdf, .plainText, .text, .image, .html, .url],
        allowsMultipleSelection: false
      ) { result in
        switch result {
        case .success(let urls):
          guard let url = urls.first else { return }
          Task { await importFile(at: url) }
        case .failure(let error):
          presentError(error.localizedDescription)
        }
      }
      .fileImporter(
        isPresented: $isShowingBatchFilesPicker,
        allowedContentTypes: [.pdf, .plainText, .text, .image, .html, .url],
        allowsMultipleSelection: true
      ) { result in
        switch result {
        case .success(let urls):
          guard !urls.isEmpty else { return }
          Task { await importBatchFiles(urls) }
        case .failure(let error):
          presentError(error.localizedDescription)
        }
      }
#if os(iOS)
      .sheet(isPresented: $isScannerPresented) {
        RecipeDocumentScanner(
          onScan: { pages in
            isScannerPresented = false
            Task { await importScannedPages(pages) }
          },
          onCancel: { isScannerPresented = false }
        )
        .ignoresSafeArea()
      }
      .sheet(isPresented: $isCameraPresented) {
        CameraPhotoCaptureView { data in
          selectedPhoto = nil
          photoData = data
          isCameraPresented = false
        } onCancel: {
          isCameraPresented = false
        }
        .ignoresSafeArea()
      }
#endif
      .fileImporter(
        isPresented: $isShowingFolderPicker,
        allowedContentTypes: [.folder],
        allowsMultipleSelection: false
      ) { result in
        switch result {
        case .success(let urls):
          guard let url = urls.first else { return }
          Task { await importFolder(at: url) }
        case .failure(let error):
          presentError(error.localizedDescription)
        }
      }
      .alert(alertTitle, isPresented: $isShowingError) {
        if isBatchImportActive && !dismissAfterBatchAlert {
          Button("Retry this file") {
            Task { await importCurrentBatchFile() }
          }
          Button("Skip this file", role: .destructive) {
            skipCurrentBatchFile()
          }
          Button("Cancel batch", role: .cancel) {
            cancelBatchImport()
          }
        } else {
          Button(dismissAfterBatchAlert ? "Done" : "OK", role: .cancel) {
            if dismissAfterBatchAlert { dismiss() }
          }
        }
      } message: {
        Text(errorMessage)
      }
      .task {
        await readIncomingShare()
      }
      .onDisappear {
        stopBatchFolderAccess()
      }
    }
  }

  private var isBatchImportActive: Bool {
    !batchFiles.isEmpty
  }

  private var saveButtonTitle: String {
    guard isBatchImportActive else { return "Save" }
    return batchIndex + 1 == batchFiles.count ? "Save & Finish" : "Save & Next"
  }

  private var sourcePicker: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 10) {
        Label("Website link", systemImage: "link")
          .font(.headline)
          .foregroundStyle(palette.ink)
        HStack(spacing: 10) {
          TextField("Paste a recipe URL", text: $link)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Recipe website address")
            .accessibilityHint("Paste or type a link to the recipe.")
#if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
#endif
          Button {
            Task { await importLink() }
          } label: {
            if isReading { ProgressView().controlSize(.small) }
            else { Image(systemName: "arrow.right") }
          }
          .buttonStyle(.borderedProminent)
          .tint(palette.accent)
          .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isReading)
          .accessibilityLabel("Read recipe link")
          .accessibilityHint("Reads the recipe at this address.")
          .frame(minWidth: 44, minHeight: 44)
        }
      }

      HStack(spacing: 12) {
        Rectangle().fill(palette.ink.opacity(0.12)).frame(height: 1)
        Text("OR")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
        Rectangle().fill(palette.ink.opacity(0.12)).frame(height: 1)
      }

      Button {
        isPastingText = false
        isShowingFilePicker = true
      } label: {
        HStack(spacing: 14) {
          Image(systemName: "document.viewfinder")
            .font(.title2)
            .foregroundStyle(palette.accent)
            .frame(width: 50, height: 50)
            .background(palette.softAccent, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 3) {
            Text("Choose a document")
              .font(.headline)
              .foregroundStyle(palette.ink)
            Text("PDF, text, or a recipe image")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
        .padding(15)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens the document picker to select a recipe source.")

#if os(iOS)
      Button {
        isPastingText = false
        guard RecipeDocumentScanner.isSupported else {
          presentError("Camera scanning isn’t available on this device. Choose a document or add a recipe photo instead.")
          return
        }
        isScannerPresented = true
      } label: {
        Label("Scan recipe pages with camera", systemImage: "document.viewfinder")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(palette.accent)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(14)
          .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
      }
      .buttonStyle(.plain)
#endif

      Button {
        isPastingText = false
        isShowingFolderPicker = true
      } label: {
        Label(isReading && !batchProgress.isEmpty ? "Importing recipes…" : "Import a folder of recipes", systemImage: "folder.badge.plus")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(palette.accent)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(14)
          .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
      }
      .buttonStyle(.plain)
      .disabled(isReading)

      Button {
        isPastingText = false
        isShowingBatchFilesPicker = true
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          Label("Select multiple recipe files…", systemImage: "doc.on.doc")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.accent)
          Text("Choose files directly from Google Drive, iCloud Drive, or another Files location.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
      }
      .buttonStyle(.plain)
      .disabled(isReading)

      if isReading {
        HStack(spacing: 10) {
          ProgressView()
          Text(batchProgress.isEmpty ? "Reading recipe…" : batchProgress)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(palette.softAccent.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
      } else if !batchProgress.isEmpty {
        Text(batchProgress)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      cookbookPicker
      finishedDishPhotoSection

      if isPastingText {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Paste recipe text")
              .font(.headline)
              .foregroundStyle(palette.ink)
            Spacer()
            Button("Hide") { isPastingText = false }
              .font(.subheadline)
          }
          TextEditor(text: $manualPasteText)
            .frame(minHeight: 130)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(alignment: .topLeading) {
              if manualPasteText.isEmpty {
                Text("Ingredients, method, or the full recipe…")
                  .font(.body)
                  .foregroundStyle(.tertiary)
                  .padding(.horizontal, 13)
                  .padding(.vertical, 16)
                  .allowsHitTesting(false)
                  .accessibilityHidden(true)
              }
            }
          Button {
            Task { await extractRecipe(from: manualPasteText, url: "") }
          } label: {
            Label("Read pasted recipe", systemImage: "sparkles")
              .frame(maxWidth: .infinity)
              .frame(height: 48)
          }
          .buttonStyle(.borderedProminent)
          .tint(palette.accent)
          .disabled(manualPasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isReading)
        }
      } else {
        Button {
          batchProgress = ""
          isPastingText = true
        } label: {
          Label("Paste recipe text instead…", systemImage: "text.alignleft")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.accent)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func draftEditor(_ initialDraft: ImportedRecipeDraft) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 8) {
        Image(systemName: wasAIExtracted ? "sparkles" : "doc.text")
          .foregroundStyle(palette.accent)
        Text(wasAIExtracted ? "AI draft · review before saving" : "Recipe draft · review before saving")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.accent)
      }
      .padding(.horizontal, 13)
      .padding(.vertical, 9)
      .background(palette.softAccent.opacity(0.7), in: Capsule())

      if isBatchImportActive {
        Text("Batch import · " + String(batchIndex + 1) + " of " + String(batchFiles.count) + " · " + sourceName)
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
      }

      TextField("Recipe name", text: binding(for: \.name))
        .font(.title2.weight(.semibold))
        .textFieldStyle(.roundedBorder)
      TextField("Short description", text: binding(for: \.summary), axis: .vertical)
        .lineLimit(2...4)
        .textFieldStyle(.roundedBorder)
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: 10) {
            TextField("Category", text: binding(for: \.category))
            Stepper("Serves \(initialDraft.servings)", value: binding(for: \.servings), in: 1...24)
          }
        } else {
          HStack {
            TextField("Category", text: binding(for: \.category))
            Stepper("Serves \(initialDraft.servings)", value: binding(for: \.servings), in: 1...24)
              .fixedSize()
          }
        }
      }
      .textFieldStyle(.roundedBorder)
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: 10) {
            Stepper("Prep time · \(initialDraft.prepMinutes) min", value: binding(for: \.prepMinutes), in: 0...600, step: 5)
            Stepper("Cook time · \(initialDraft.cookMinutes) min", value: binding(for: \.cookMinutes), in: 0...1200, step: 5)
          }
        } else {
          HStack(spacing: 12) {
            Stepper("Prep \(initialDraft.prepMinutes)m", value: binding(for: \.prepMinutes), in: 0...600, step: 5)
            Stepper("Cook \(initialDraft.cookMinutes)m", value: binding(for: \.cookMinutes), in: 0...1200, step: 5)
          }
        }
      }
      .font(.subheadline)
      TextField("Calories per serving (optional)", value: binding(for: \.caloriesPerServing), format: .number)
        .textFieldStyle(.roundedBorder)

      cookbookPicker
      finishedDishPhotoSection

      VStack(alignment: .leading, spacing: 9) {
        Text("GOOD FOR")
          .font(.caption.weight(.bold))
          .tracking(1)
          .foregroundStyle(.secondary)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
          ForEach(RecipeGoodFor.allCases) { occasion in
            Toggle(occasion.title, isOn: goodForBinding(occasion))
              .toggleStyle(.button)
              .tint(palette.accent)
              .font(.caption.weight(.medium))
              .frame(minHeight: 44)
          }
        }
      }
      .padding(14)
      .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))

      if !initialDraft.ingredients.isEmpty {
        VStack(alignment: .leading, spacing: 9) {
          Text("INGREDIENTS")
            .font(.caption.weight(.bold))
            .tracking(1)
            .foregroundStyle(.secondary)
          ForEach(RecipeIngredientSection.group(initialDraft.ingredients)) { section in
            if !section.title.isEmpty {
              Text(section.title).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            }
            ForEach(section.ingredients) { ingredient in
              HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                  .font(.system(size: 5))
                  .foregroundStyle(palette.accent)
                  .accessibilityHidden(true)
                Text(IngredientFormatterForImport.format(ingredient))
                  .font(.subheadline)
              }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
      }

      if !initialDraft.steps.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          Text("METHOD · \(initialDraft.steps.count) STEPS")
            .font(.caption.weight(.bold))
            .tracking(1)
            .foregroundStyle(.secondary)
          ForEach(initialDraft.steps) { step in
            VStack(alignment: .leading, spacing: 6) {
              Text(step.title)
                .font(.subheadline.weight(.semibold))
              Text(step.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
              StepTimerDurationPicker(duration: timerBinding(for: step))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
          }
        }
      }
    }
  }

  private var finishedDishPhotoSection: some View {
    VStack(alignment: .leading, spacing: 11) {
      Text("Finished dish photo")
        .font(.headline)
        .foregroundStyle(palette.ink)

      if let photoData, let image = PlatformImage.data(photoData) {
        GeometryReader { geometry in
          image
            .resizable()
            .scaledToFill()
            .frame(width: geometry.size.width, height: 170)
            .clipped()
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("Finished dish photo")
      } else {
        Label("Add a photo of the finished dish", systemImage: "photo")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
      }

      HStack(spacing: 14) {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
          Label(photoData == nil ? "Choose photo" : "Change photo", systemImage: "photo")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.accent)
        }
#if os(iOS)
        Button {
          guard CameraPhotoCaptureView.isAvailable else {
            presentError("This device doesn’t have an available camera. Choose a photo from your library instead.")
            return
          }
          isCameraPresented = true
        } label: {
          Label(photoData == nil ? "Take photo" : "Retake photo", systemImage: "camera")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.accent)
        }
        .buttonStyle(.plain)
#endif
      }

      if photoData != nil {
        Button("Remove photo", systemImage: "trash", role: .destructive) {
          photoData = nil
          selectedPhoto = nil
        }
        .font(.caption)
      }
    }
    .padding(14)
    .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
    .onChange(of: selectedPhoto) { _, item in
      guard let item else { return }
      Task { photoData = try? await item.loadTransferable(type: Data.self) }
    }
  }

  private func binding<Value>(for keyPath: WritableKeyPath<ImportedRecipeDraft, Value>) -> Binding<Value> {
    Binding(
      get: { importedDraft![keyPath: keyPath] },
      set: { importedDraft![keyPath: keyPath] = $0 }
    )
  }

  private func timerBinding(for step: RecipeStep) -> Binding<Int> {
    Binding(
      get: { importedDraft?.steps.first(where: { $0.id == step.id })?.timerMinutes ?? step.timerMinutes },
      set: { value in
        guard let index = importedDraft?.steps.firstIndex(where: { $0.id == step.id }) else { return }
        importedDraft?.steps[index].timerMinutes = value
      }
    )
  }

  private func goodForBinding(_ value: RecipeGoodFor) -> Binding<Bool> {
    Binding(
      get: { importedDraft?.goodFor.contains(value) == true },
      set: { isSelected in
        guard var draft = importedDraft else { return }
        if isSelected, !draft.goodFor.contains(value) {
          draft.goodFor.append(value)
        } else if !isSelected {
          draft.goodFor.removeAll { $0 == value }
        }
        importedDraft = draft
      }
    )
  }

  @ViewBuilder
  private var cookbookPicker: some View {
    if cookbooks.isEmpty {
      Label("You can add this to a cookbook later.", systemImage: "books.vertical")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else {
      Picker("Save to cookbook", selection: $selectedCookbookID) {
        Text("No cookbook").tag(UUID?.none)
        ForEach(cookbooks) { cookbook in
          Text(cookbook.name).tag(Optional(cookbook.id))
        }
      }
      .pickerStyle(.menu)
      .tint(palette.accent)
    }
  }

  private func readIncomingShare() async {
    guard let importItem else { return }
    isPastingText = false
    if !importItem.text.isEmpty { sourceText = importItem.text }
    if !importItem.sourceURL.isEmpty {
      sourceURL = importItem.sourceURL
      link = importItem.sourceURL
      sourceName = importItem.title
    }
    if !importItem.fileURL.isEmpty, let url = URL(string: importItem.fileURL) {
      await importFile(at: url)
    } else if !link.isEmpty {
      await importLink()
    } else if !sourceText.isEmpty {
      await extractRecipe(from: sourceText, url: sourceURL)
    }
  }

  private func importLink() async {
    isPastingText = false
    batchProgress = ""
    guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
          ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
      presentError("Enter a full web address beginning with https://.")
      return
    }
    isReading = true
    defer { isReading = false }
    do {
      let text = try await RecipeSourceReader.text(from: url)
      sourceURL = url.absoluteString
      sourceName = url.host ?? "Website"
      sourceText = text
      try await createDraft(from: text, sourceURL: url.absoluteString)
    } catch {
      presentError(error.localizedDescription)
    }
  }

  private func importFile(at url: URL) async {
    isPastingText = false
    batchProgress = isBatchImportActive
      ? "Reading " + String(batchIndex + 1) + " of " + String(batchFiles.count) + "…"
      : ""
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    isReading = true
    defer { isReading = false }
    sourceName = url.lastPathComponent
    if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
      photoData = RecipeSourceReader.compressedImageData(from: url, maxPixelSize: 1400)
    }
    do {
      let text = try await RecipeSourceReader.text(from: url)
      sourceText = text
      try await createDraft(from: text, sourceURL: "")
    } catch {
      alertTitle = "Couldn’t read " + url.lastPathComponent
      presentError(error.localizedDescription)
    }
  }

  private func importScannedPages(_ pages: [Data]) async {
    isPastingText = false
    batchProgress = ""
    guard !pages.isEmpty else {
      presentError("No pages were captured. Try scanning the recipe again.")
      return
    }
    isReading = true
    defer { isReading = false }
    sourceName = "Camera scan"
    photoData = pages.first
    do {
      let text = try RecipeSourceReader.text(fromImagePages: pages)
      sourceText = text
      try await createDraft(from: text, sourceURL: "")
    } catch {
      presentError(error.localizedDescription)
    }
  }

  private func importFolder(at folderURL: URL) async {
    isPastingText = false
    let access = folderURL.startAccessingSecurityScopedResource()

    guard let enumerator = FileManager.default.enumerator(
      at: folderURL,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else {
      if access { folderURL.stopAccessingSecurityScopedResource() }
      presentError("Apron Buddy couldn’t open that folder.")
      return
    }
    let supportedExtensions: Set<String> = ["pdf", "txt", "text", "html", "htm", "jpg", "jpeg", "png", "heic"]
    let files = enumerator.compactMap { $0 as? URL }
      .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
      .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    guard !files.isEmpty else {
      if access { folderURL.stopAccessingSecurityScopedResource() }
      presentError("No supported recipe files were found. Choose a folder with PDFs, text, HTML, or image files.")
      return
    }

    if access {
      batchFolderURL = folderURL
      batchFolderAccessing = true
    }
    await importBatchFiles(files)
  }

  private func importBatchFiles(_ selectedFiles: [URL]) async {
    let supportedExtensions: Set<String> = ["pdf", "txt", "text", "html", "htm", "jpg", "jpeg", "png", "heic"]
    let files = selectedFiles
      .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
      .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    guard !files.isEmpty else {
      presentError("No supported recipe files were selected. Choose PDFs, text, HTML, or image files.")
      return
    }

    isPastingText = false
    batchFiles = files
    batchIndex = 0
    batchImportedCount = 0
    batchFailedCount = 0
    dismissAfterBatchAlert = false
    await importCurrentBatchFile()
  }

  private func importCurrentBatchFile() async {
    guard isBatchImportActive, batchFiles.indices.contains(batchIndex) else { return }
    importedDraft = nil
    sourceText = ""
    sourceURL = ""
    sourceName = ""
    photoData = nil
    selectedPhoto = nil
    await importFile(at: batchFiles[batchIndex])
  }

  private func skipCurrentBatchFile() {
    guard isBatchImportActive else { return }
    batchFailedCount += 1
    batchIndex += 1
    importedDraft = nil
    photoData = nil
    selectedPhoto = nil
    if batchIndex < batchFiles.count {
      Task { await importCurrentBatchFile() }
    } else {
      finishBatchImport()
    }
  }

  private func moveToNextBatchFile() {
    batchIndex += 1
    importedDraft = nil
    sourceText = ""
    sourceURL = ""
    sourceName = ""
    photoData = nil
    selectedPhoto = nil
    if batchIndex < batchFiles.count {
      Task { await importCurrentBatchFile() }
    } else {
      finishBatchImport()
    }
  }

  private func finishBatchImport() {
    let savedText = "Saved \(batchImportedCount) \(batchImportedCount == 1 ? "recipe" : "recipes")."
    let skippedText = batchFailedCount == 0
      ? ""
      : " Skipped \(batchFailedCount) \(batchFailedCount == 1 ? "file" : "files")."
    let summary = savedText + skippedText
    alertTitle = batchFailedCount == 0 ? "Batch import complete" : "Batch import finished"
    batchProgress = summary
    batchFiles = []
    batchIndex = 0
    dismissAfterBatchAlert = true
    stopBatchFolderAccess()
    presentError(summary)
  }

  private func cancelBatchImport() {
    batchFiles = []
    batchIndex = 0
    batchProgress = ""
    dismissAfterBatchAlert = false
    stopBatchFolderAccess()
  }

  private func stopBatchFolderAccess() {
    if batchFolderAccessing, let batchFolderURL {
      batchFolderURL.stopAccessingSecurityScopedResource()
    }
    batchFolderURL = nil
    batchFolderAccessing = false
  }

  private func extractRecipe(from text: String, url: String) async {
    isReading = true
    defer { isReading = false }
    do {
      try await createDraft(from: text, sourceURL: url)
    } catch {
      presentError(error.localizedDescription)
    }
  }

  private func createDraft(from text: String, sourceURL: String) async throws {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { throw RecipeImportError.noTextFound }
    let source = String(cleaned.prefix(18_000))
    do {
      importedDraft = try await OnDeviceRecipeAI.extract(from: source)
      wasAIExtracted = true
    } catch {
      importedDraft = SimpleRecipeParser.extract(from: source, suggestedName: sourceName)
      wasAIExtracted = false
    }
    self.sourceURL = sourceURL
  }

  private func saveRecipe() {
    guard let importedDraft else { return }
    let recipe = Recipe(
      name: importedDraft.name.trimmingCharacters(in: .whitespacesAndNewlines),
      summary: importedDraft.summary,
      category: importedDraft.category.isEmpty ? "Dinner" : importedDraft.category,
      servings: importedDraft.servings,
      caloriesPerServing: importedDraft.caloriesPerServing,
      prepMinutes: importedDraft.prepMinutes,
      cookMinutes: importedDraft.cookMinutes,
      ingredients: importedDraft.ingredients,
      steps: importedDraft.steps,
      sourceURL: sourceURL,
      sourceName: sourceName,
      photoData: photoData,
      cookbookIDs: selectedCookbookID.map { [$0] } ?? [],
      goodFor: importedDraft.goodFor
    )
    modelContext.insert(recipe)
    do {
      try modelContext.save()
    } catch {
      modelContext.delete(recipe)
      presentError(error.localizedDescription)
      return
    }
    if isBatchImportActive {
      batchImportedCount += 1
      moveToNextBatchFile()
    } else {
      dismiss()
    }
  }

  private func presentError(_ message: String) {
    errorMessage = message
    isShowingError = true
  }
}

private enum IngredientFormatterForImport {
  static func format(_ ingredient: RecipeIngredient) -> String {
    let ingredient = IngredientNormalization.clean(ingredient)
    let measurement = ingredient.amount > 0
      ? [KitchenQuantity.format(ingredient.amount), KitchenQuantity.unitLabel(ingredient.unit, amount: ingredient.amount)]
      : []
    return (measurement + [ingredient.name, ingredient.note]).filter { !$0.isEmpty }.joined(separator: " ")
  }
}

enum PlatformImage {
  #if canImport(UIKit)
  static func data(_ data: Data) -> Image? {
    guard let image = UIImage(data: data) else { return nil }
    return Image(uiImage: image)
  }
  #elseif canImport(AppKit)
  static func data(_ data: Data) -> Image? {
    guard let image = NSImage(data: data) else { return nil }
    return Image(nsImage: image)
  }
  #else
  static func data(_ data: Data) -> Image? { nil }
  #endif
}
