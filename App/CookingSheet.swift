#if os(iOS)
import SwiftUI
import UIKit

struct CookingSheet: View {
  @KitchenPalette private var palette
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var confirmsEnding = false
  @State private var showsIngredients = false
  @State private var showsCompletionError = false

  var cooking: CookingSessionStore
  var fallbackIngredients: [String] = []
  var recordCompletion: (UUID) throws -> Void

  var body: some View {
    if let session = cooking.session {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          HStack(alignment: .top) {
            Text(session.recipeName)
              .font(.headline)
              .foregroundStyle(palette.ink)
              .accessibilityAddTraits(.isHeader)
              .padding(.vertical, 12)
            Spacer()
            Button("Ingredients", systemImage: "list.bullet") { showsIngredients = true }
              .labelStyle(.iconOnly)
              .buttonStyle(.glass)
              .frame(minWidth: 44, minHeight: 44)
              .popover(isPresented: $showsIngredients) {
                CookingIngredientsPeek(ingredients: session.ingredientMeasurements ?? fallbackIngredients)
                  .presentationCompactAdaptation(.popover)
              }
            Button("Minimize cooking", systemImage: "chevron.down") { dismiss() }
              .labelStyle(.iconOnly)
              .buttonStyle(.glass)
              .frame(minWidth: 44, minHeight: 44)
            Menu("Cooking options", systemImage: "ellipsis") {
              Button("End cooking", role: .destructive) { confirmsEnding = true }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .frame(minWidth: 44, minHeight: 44)
          }

          ProgressView(value: Double(session.stepIndex + 1), total: Double(session.steps.count))
            .tint(palette.accent)
            .accessibilityHidden(true)

          Text("Step \(session.stepIndex + 1) of \(session.steps.count) · Serves \(session.servings)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)

          Text(session.stepTitle)
            .font(.system(.largeTitle, design: .serif, weight: .semibold))
            .foregroundStyle(palette.ink)
            .accessibilityAddTraits(.isHeader)

          CookingInstructionText(instruction: session.step.measuredInstructions ?? session.step.instructions) { seconds in
            Task { await cooking.startTimer(seconds: seconds) }
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          if session.step.defaultTimerSeconds > 0 || session.timers[session.stepIndex] != nil || cooking.timerMessage != nil {
            stepTimer(for: session)
          }

          if let message = cooking.activityMessage {
            Text(message)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
        .padding(24)
        .frame(maxWidth: 650)
        .frame(maxWidth: .infinity)
      }
      .id(session.stepIndex)
      .background(palette.paper)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        stepControls(for: session)
          .padding(.horizontal, 24)
          .padding(.vertical, 12)
          .frame(maxWidth: 650)
          .frame(maxWidth: .infinity)
          .background(palette.surface)
      }
      .confirmationDialog("End this cooking session?", isPresented: $confirmsEnding, titleVisibility: .visible) {
        Button("End cooking", role: .destructive, action: finish)
      }
      .alert("Couldn’t save the last cooked date", isPresented: $showsCompletionError) {
        Button("OK", role: .cancel) { }
      }
    }
  }

  private func stepTimer(for session: CookingSession) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) {
          timerStatus(for: session)
          Spacer(minLength: 0)
          timerControl(for: session)
        }
        VStack(alignment: .leading, spacing: 12) {
          timerStatus(for: session)
          timerControl(for: session)
        }
      }
      if let message = cooking.timerMessage {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      if cooking.needsTimerPermission, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
        Link("Open Settings", destination: settingsURL)
          .font(.subheadline.weight(.semibold))
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
  }

  private func timerStatus(for session: CookingSession) -> some View {
    Label {
      VStack(alignment: .leading, spacing: 3) {
        Text("Step timer")
          .font(.subheadline.weight(.semibold))
        if let timer = session.timers[session.stepIndex] {
          TimelineView(.periodic(from: .now, by: 1)) { context in
            if context.date < timer.endsAt {
              Text(timerInterval: timer.startedAt...timer.endsAt, countsDown: true, showsHours: true)
                .monospacedDigit()
            } else {
              Text("Timer finished")
            }
          }
          .font(.subheadline)
          .foregroundStyle(.secondary)
        } else {
          Text(Duration.seconds(session.step.defaultTimerSeconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    } icon: {
      Image(systemName: "timer")
        .font(.title2)
        .foregroundStyle(palette.accent)
    }
  }

  private func timerControl(for session: CookingSession) -> some View {
    Group {
      if session.timers[session.stepIndex] != nil {
        Button("Stop timer", action: cooking.stopTimer)
      } else {
        Button("Start timer") {
          Task { await cooking.startTimer() }
        }
        .disabled(cooking.isStartingTimer)
      }
    }
    .buttonStyle(.bordered)
    .tint(palette.accent)
    .controlSize(.large)
  }

  private func stepControls(for session: CookingSession) -> some View {
    let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
    let isLastStep = session.stepIndex + 1 == session.steps.count
    return layout {
      Button {
        move(by: -1, in: session)
      } label: {
        Label("Previous", systemImage: "arrow.left")
          .frame(maxWidth: .infinity, minHeight: 36)
      }
      .buttonStyle(.bordered)
      .disabled(session.stepIndex == 0)

      Button {
        if isLastStep {
          do {
            try recordCompletion(session.recipeID)
            finish()
          } catch {
            showsCompletionError = true
          }
        } else {
          move(by: 1, in: session)
        }
      } label: {
        Label(isLastStep ? "Finish" : "Next step", systemImage: isLastStep ? "checkmark" : "arrow.right")
          .frame(maxWidth: .infinity, minHeight: 36)
      }
      .buttonStyle(.borderedProminent)
      .tint(palette.strongAccent)
    }
    .controlSize(.large)
    .tint(palette.accent)
  }

  private func move(by offset: Int, in session: CookingSession) {
    Task { await cooking.move(by: offset, sessionID: session.id, from: session.stepIndex) }
  }

  private func finish() {
    dismiss()
    cooking.finish()
  }
}
#endif
