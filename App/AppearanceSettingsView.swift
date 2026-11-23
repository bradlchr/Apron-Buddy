import SwiftUI
#if os(iOS)
import UIKit
#endif

struct AppearanceSettingsView: View {
  @KitchenPalette private var palette
  @AppStorage(KitchenTheme.preferenceKey) private var theme: KitchenTheme = .forest
  @Environment(\.colorScheme) private var colorScheme
  #if os(iOS)
  @State private var icon: KitchenTheme = .forest
  @State private var isChangingIcon = false
  @State private var iconError = false
  #endif

  var body: some View {
    Form {
      Section("Kitchen theme") {
        Picker("Theme", selection: $theme) {
          ForEach(KitchenTheme.allCases) { color in
            Text(color.title).tag(color)
          }
        }

        HStack {
          Text("Apron Buddy").font(.headline)
          Spacer()
          Circle().fill(theme.accent(for: colorScheme)).frame(width: 24, height: 24)
        }
        .padding(12)
        .background(theme.paper(for: colorScheme), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
      }
      .listRowBackground(palette.surface)

      #if os(iOS)
      if UIApplication.shared.supportsAlternateIcons {
        Section("Home Screen icon") {
          HStack(spacing: 12) {
            Image((icon.appIconName ?? "IconForest") + "Preview")
              .resizable()
              .frame(width: 46, height: 46)
              .clipShape(RoundedRectangle(cornerRadius: 11))
              .accessibilityHidden(true)
            Text(icon.title).font(.subheadline)
          }
          Picker("App icon", selection: Binding(get: { icon }, set: changeIcon)) {
            ForEach(KitchenTheme.allCases) { color in
              Text(color.title).tag(color)
            }
          }
          .disabled(isChangingIcon)
        }
        .listRowBackground(palette.surface)
      }
      #endif
    }
    .scrollContentBackground(.hidden)
    .background(palette.paper)
    .tint(palette.accent)
    .navigationTitle("Appearance")
    .tint(theme.accent(for: colorScheme))
    #if os(iOS)
    .onAppear {
      icon = KitchenTheme.allCases.first { $0.appIconName == UIApplication.shared.alternateIconName } ?? .forest
    }
    .alert("Couldn’t change the app icon", isPresented: $iconError) {
      Button("OK", role: .cancel) {}
    }
    #endif
  }

  #if os(iOS)
  private func changeIcon(_ color: KitchenTheme) {
    guard !isChangingIcon else { return }
    isChangingIcon = true
    Task {
      defer { isChangingIcon = false }
      do {
        try await UIApplication.shared.setAlternateIconName(color.appIconName)
        icon = color
      } catch {
        iconError = true
      }
    }
  }
  #endif
}
