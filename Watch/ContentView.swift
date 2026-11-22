import SwiftUI
import WatchConnectivity

struct ContentView: View {
  @StateObject private var session = WatchCookingSession()
  @State private var stepIndex = 0
  @State private var timerEnd: Date?
  @State private var isNextStepVisible = false

  private var currentStep: String {
    guard session.steps.indices.contains(stepIndex) else { return "Start a recipe on your iPhone to see the cooking steps here." }
    return session.steps[stepIndex]
  }

  private var currentTimer: Int {
    guard session.timers.indices.contains(stepIndex) else { return 0 }
    return session.timers[stepIndex]
  }

  var body: some View {
    GeometryReader { viewport in
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 5) {
            Image(systemName: "fork.knife")
              .foregroundStyle(Color(red: 0.62, green: 0.74, blue: 0.48))
              .accessibilityHidden(true)
            Text("APRON BUDDY")
              .font(.caption.weight(.bold))
              .tracking(1.1)
          }
          .foregroundStyle(.secondary)

          if session.steps.isEmpty {
            Text("Your kitchen, at a glance")
              .font(.title3.weight(.semibold))
              Text("Start cooking on your iPhone and Apron Buddy will bring the current recipe to your watch.")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            Text(session.recipeName)
              .font(.headline.weight(.semibold))
              .lineLimit(2)
              .accessibilityAddTraits(.isHeader)
            Text("STEP \(stepIndex + 1) OF \(session.steps.count) · SERVES \(session.servings)")
              .font(.caption.weight(.bold))
              .foregroundStyle(.secondary)
            ProgressView(value: Double(stepIndex + 1), total: Double(session.steps.count))
              .tint(Color(red: 0.62, green: 0.74, blue: 0.48))
              .accessibilityHidden(true)
            Text(currentStep.components(separatedBy: "\n").first ?? "")
              .font(.subheadline.weight(.semibold))
              .padding(.top, 3)
              .accessibilityAddTraits(.isHeader)
            Text(currentStep.components(separatedBy: "\n").dropFirst().joined(separator: "\n"))
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)

            if currentTimer > 0 {
              Button {
                timerEnd = Date().addingTimeInterval(TimeInterval(currentTimer * 60))
              } label: {
                HStack {
                  Image(systemName: "timer")
                  if let timerEnd {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                      let remaining = max(0, Int(timerEnd.timeIntervalSince(context.date)))
                      Text(remaining == 0 ? "Done" : remaining.formattedWatchTime)
                    }
                  } else {
                    Text("Start \(currentTimer)m timer")
                  }
                }
                .font(.caption.weight(.semibold))
              }
              .tint(Color(red: 0.62, green: 0.74, blue: 0.48))
              .accessibilityLabel(timerEnd == nil ? "Start \(currentTimer) minute timer" : "Step timer")
              .accessibilityHint(timerEnd == nil ? "Starts a timer for this step." : "Shows the remaining time for this step.")
            }

            HStack(spacing: 8) {
              Button {
                stepIndex = max(0, stepIndex - 1)
                timerEnd = nil
              } label: {
                Image(systemName: "chevron.left")
                  .frame(maxWidth: .infinity)
              }
              .disabled(stepIndex == 0)
              .accessibilityLabel("Previous step")
              Button {
                if stepIndex + 1 < session.steps.count {
                  stepIndex += 1
                  timerEnd = nil
                }
              } label: {
                Image(systemName: "chevron.right")
                  .frame(maxWidth: .infinity)
              }
              .disabled(stepIndex + 1 >= session.steps.count)
              .accessibilityLabel("Next step")
              .accessibilityHint("Double-tap with the watch gesture to move to the next step when this button is visible.")
              .background {
                GeometryReader { buttonGeometry in
                  Color.clear.preference(
                    key: WatchNextStepFramePreferenceKey.self,
                    value: buttonGeometry.frame(in: .named("watchCookingScroll"))
                  )
                }
              }
              .handGestureShortcut(
                .primaryAction,
                isEnabled: isNextStepVisible && stepIndex + 1 < session.steps.count
              )
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.29, green: 0.38, blue: 0.25))
          }
        }
        .padding(.vertical, 8)
      }
      .coordinateSpace(name: "watchCookingScroll")
      .onPreferenceChange(WatchNextStepFramePreferenceKey.self) { frame in
        let visibleBounds = CGRect(origin: .zero, size: viewport.size)
        isNextStepVisible = !frame.isNull
          && visibleBounds.contains(CGPoint(x: frame.midX, y: frame.midY))
      }
    }
    .onChange(of: session.recipeName) { _, _ in
      stepIndex = 0
      timerEnd = nil
      isNextStepVisible = false
    }
  }
}

private struct WatchNextStepFramePreferenceKey: PreferenceKey {
  static var defaultValue: CGRect = .null

  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    value = nextValue()
  }
}

private final class WatchCookingSession: NSObject, ObservableObject, WCSessionDelegate {
  @Published var recipeName = ""
  @Published var servings = 2
  @Published var steps: [String] = []
  @Published var timers: [Int] = []

  override init() {
    super.init()
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
    receive(WCSession.default.receivedApplicationContext)
  }

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    DispatchQueue.main.async { self.receive(applicationContext) }
  }

  #if os(iOS)
  func sessionDidBecomeInactive(_ session: WCSession) { }
  func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  #endif

  private func receive(_ context: [String: Any]) {
    guard let name = context["recipeName"] as? String,
          let steps = context["steps"] as? [String] else { return }
    recipeName = name
    self.steps = steps
    servings = context["servings"] as? Int ?? 2
    timers = context["timers"] as? [Int] ?? []
  }
}

private extension Int {
  var formattedWatchTime: String {
    "\(self / 60):\(String(format: "%02d", self % 60))"
  }
}
