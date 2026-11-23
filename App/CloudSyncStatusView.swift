import AppIntents
import SwiftUI

struct CloudSyncStatusView: View {
  @KitchenPalette private var palette
  @Environment(\.dismiss) private var dismiss
  @AppStorage(SiriIntegrationPreference.key) private var siriIntegrationEnabled = true

  var status: String
  var onRefresh: () -> Void
  var showsDoneButton = true

  private var isAvailable: Bool {
    status == "iCloud sync is on"
  }

  private var hasNoAccount: Bool {
    status == "Sign in to iCloud to sync"
  }

  private var iCloudDescription: String {
    if isAvailable {
      return "Recipes and cookbooks sync through your private iCloud account. Shared cookbooks and recipes use Apple’s CloudKit sharing controls."
    }
    if hasNoAccount {
      return "Your recipes stay on this device. Sign in to iCloud in Settings to sync recipes and cookbooks across your devices."
    }
    return "Apron Buddy couldn’t confirm your iCloud connection. Check your connection and try again."
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          NavigationLink {
            AppearanceSettingsView()
          } label: {
            Label("Appearance", systemImage: "paintpalette")
          }
          NavigationLink {
            HouseholdLibrarySettings()
          } label: {
            Label("Household", systemImage: "house")
          }
          NavigationLink {
            TipJarView()
          } label: {
            Label("Chef’s Tip Jar", systemImage: "heart")
          }
        }
        .listRowBackground(palette.surface)

        Section("iCloud") {
          Label(status, systemImage: isAvailable ? "checkmark.icloud" : "icloud.slash")
            .font(.headline)
            .foregroundStyle(isAvailable ? palette.accent : Color.primary)

          Text(iCloudDescription)
            .foregroundStyle(.secondary)

          Button("Check iCloud again", systemImage: "arrow.clockwise", action: onRefresh)
        }
        .listRowBackground(palette.surface)

        Section {
          Toggle("Enable Siri & Shortcuts", isOn: $siriIntegrationEnabled)
            .accessibilityHint("Allow Siri and Shortcuts to find, open, and share recipes from Apron Buddy.")

          Text("Turn on this switch, then try one of the phrases below. Siri can match approximate or partly remembered recipe names. Turn this off to stop recipe lookups and shortcut actions. Shortcuts you already saved may remain visible, but won’t access recipes or run until you turn this back on.")
            .foregroundStyle(.secondary)
        } header: {
          Text("Siri & Shortcuts")
        }
        .listRowBackground(palette.surface)

        Section("Try saying") {
          VStack(alignment: .leading, spacing: 4) {
            Text("Open a recipe")
              .font(.subheadline.weight(.semibold))
            Text("“Siri, open my chicken enchiladas in Apron Buddy.”")
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)

          VStack(alignment: .leading, spacing: 4) {
            Text("Share a recipe")
              .font(.subheadline.weight(.semibold))
            Text("“Siri, share my chicken enchiladas in Apron Buddy.”\n“Siri, send a recipe to Mom with Apron Buddy.”")
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)

          Text("Siri can match a partial or remembered name, then asks you to confirm the recipe and person. Apron Buddy opens a Messages or Mail draft with a private iCloud share link. Review the draft and tap Send to share it.")
            .foregroundStyle(.secondary)
        }
        .listRowBackground(palette.surface)
      }
      .foregroundStyle(palette.ink)
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .background(palette.paper)
      .tint(palette.accent)
      #if os(macOS)
      .navigationTitle("Apron Buddy Settings")
      #else
      .navigationTitle("Settings")
      #endif
      .toolbar {
        if showsDoneButton {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
          }
        }
      }
    }
    #if os(macOS)
    .frame(minWidth: 360, minHeight: 460)
    #endif
    .onChange(of: siriIntegrationEnabled) { _, _ in
      ApronBuddyShortcuts.updateAppShortcutParameters()
    }
  }
}

@MainActor
struct AppSettingsRootView: View {
  @State private var cloudStatus = "Checking iCloud…"

  var body: some View {
    CloudSyncStatusView(status: cloudStatus, onRefresh: refresh, showsDoneButton: false)
      .task { await updateCloudStatus() }
  }

  private func refresh() {
    Task { await updateCloudStatus() }
  }

  private func updateCloudStatus() async {
    cloudStatus = await CloudKitCookbookStore.shared.accountStatusMessage()
  }
}
