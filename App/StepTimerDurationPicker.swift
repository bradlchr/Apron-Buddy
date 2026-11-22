import SwiftUI

struct StepTimerDurationPicker: View {
  @Binding var duration: Int

  private var hours: Int { max(0, duration) / 60 }
  private var minutes: Int { max(0, duration) % 60 }
  private var hourOptions: [Int] {
    let standard = Array(0...24)
    return hours > 24 ? standard + [hours] : standard
  }

  var body: some View {
    LabeledContent("Timer") {
      HStack(spacing: 4) {
        Picker("Hours", selection: Binding(get: { hours }, set: { setDuration(hours: $0, minutes: minutes) })) {
          ForEach(hourOptions, id: \.self) { value in
            Text("\(value) hr").tag(value)
          }
        }
        Picker("Minutes", selection: Binding(get: { minutes }, set: { setDuration(hours: hours, minutes: $0) })) {
          ForEach(0..<60, id: \.self) { value in
            Text("\(value) min").tag(value)
          }
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
    }
  }

  private func setDuration(hours: Int, minutes: Int) {
    let wholeHours = hours * 60
    duration = wholeHours + min(minutes, Int.max - wholeHours)
  }
}
