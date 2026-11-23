import SwiftUI

struct HouseholdLibrarySettings: View {
  @KitchenPalette private var palette
  @Environment(\.dismiss) private var dismiss
  @Environment(\.householdLibrary) private var library
  @State private var confirmsCreation = false

  var body: some View {
    Form {
      if let library {
        Section("Current library") {
          if library.isActive {
            Label("Household library", systemImage: "house")
            Button("Open personal library", systemImage: "person") {
              library.switchLibrary(active: false)
              dismiss()
            }
          } else {
            Label("Personal library", systemImage: "person")
            if library.membership != nil {
              Button("Open household library", systemImage: "house") {
                library.switchLibrary(active: true)
                dismiss()
              }
            }
          }
        }
        .listRowBackground(palette.surface)

        Section {
          if let membership = library.membership {
            if membership.isOwner {
              ShareLink(item: membership, preview: SharePreview("Apron Buddy Household")) {
                Label("Invite someone", systemImage: "person.badge.plus")
              }
            }
            if library.isSyncing {
              ProgressView("Syncing household…")
            } else {
              Button("Sync now", systemImage: "arrow.clockwise") {
                Task { await library.synchronize() }
              }
            }
          } else {
            Button("Create household", systemImage: "house.badge.plus") { confirmsCreation = true }
              .disabled(library.isBusy)
            if library.isBusy { ProgressView("Creating household…") }
          }
          if let error = library.errorMessage {
            Text(error)
              .font(.footnote)
              .foregroundStyle(palette.warning)
          }
        } header: {
          Text("Household sharing")
        } footer: {
          Text("Members share one recipe library, cookbooks, meal plans, and grocery lists. Edits and deletions apply to every member. Your personal library stays separate.")
        }
        .listRowBackground(palette.surface)
      }
    }
    .scrollContentBackground(.hidden)
    .background(palette.paper)
    .tint(palette.accent)
    .navigationTitle("Household")
    .confirmationDialog("Create a household library?", isPresented: $confirmsCreation, titleVisibility: .visible) {
      Button("Start with a copy of my library") { create(copy: true) }
      Button("Start with an empty library") { create(copy: false) }
    } message: {
      Text("You can invite someone after creating the library. Copies exclude recipes and cookbooks shared with you by someone else.")
    }
  }

  private func create(copy: Bool) {
    guard let library else { return }
    Task {
      if await library.create(copying: copy ? library.personalContext : nil) {
        dismiss()
      }
    }
  }
}
