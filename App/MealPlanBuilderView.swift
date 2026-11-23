import SwiftData
import SwiftUI

struct MealPlanBuilderView: View {
  @KitchenPalette private var palette
  private enum Stage {
    case preferences
    case review
  }

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
  @State private var stage = Stage.preferences
  @State private var startDate = Calendar.current.startOfDay(for: .now)
  @State private var dayCount = 7
  @State private var mealsPerDay = 1
  @State private var peopleEating = 4
  @State private var plansLeftovers = false
  @State private var planTitle = ""
  @State private var occasion = ""
  @State private var constraints = ""
  @State private var calorieTargetText = ""
  @State private var usesCalendar = false
  @State private var usesAppleIntelligence = MealPlanSuggestionService.isAIAvailable
  @State private var draftSlots: [MealPlanDraftSlot] = []
  @State private var usedAppleIntelligence = false
  @State private var isGenerating = false
  @State private var isImportPresented = false
  @State private var isShowingError = false
  @State private var errorMessage = ""

  private var dailyCalorieTarget: Int {
    Int(calorieTargetText.filter(\.isNumber)) ?? 0
  }

  private var mealTypes: [PlannedMeal] {
    switch mealsPerDay {
    case 1: [.dinner]
    case 2: [.lunch, .dinner]
    default: [.breakfast, .lunch, .dinner]
    }
  }

  var body: some View {
    NavigationStack {
      Group {
        if stage == .preferences {
          preferencesForm
        } else {
          reviewForm
        }
      }
      .background(palette.paper)
      .navigationTitle(stage == .preferences ? "Plan meals" : "Review your plan")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(stage == .review ? "Back" : "Cancel") {
            if stage == .review {
              stage = .preferences
            } else {
              dismiss()
            }
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          if stage == .preferences {
            Button {
              Task { await generateSuggestions() }
            } label: {
              if isGenerating {
                ProgressView()
              } else {
                Text("Suggest")
              }
            }
            .disabled(isGenerating)
          } else {
            Button("Create plan", action: createPlan)
              .fontWeight(.semibold)
              .disabled(draftSlots.isEmpty)
          }
        }
      }
      .alert("Meal plan", isPresented: $isShowingError) {
        Button("OK", role: .cancel) { }
      } message: {
        Text(errorMessage)
      }
      .sheet(isPresented: $isImportPresented) {
        ImportRecipeView(importItem: nil)
          .frame(minWidth: 360, minHeight: 520)
      }
    }
    .frame(minWidth: 380, minHeight: 560)
  }

  private var preferencesForm: some View {
    Form {
      Section("Schedule") {
        TextField("Plan name (optional)", text: $planTitle)
        DatePicker("Start date", selection: $startDate, displayedComponents: .date)
        Stepper("Days · \(dayCount)", value: $dayCount, in: 1...14)
        Picker("Meals per day", selection: $mealsPerDay) {
          Text("Dinner only").tag(1)
          Text("Lunch and dinner").tag(2)
          Text("Breakfast, lunch, and dinner").tag(3)
        }
        Stepper("People eating · \(peopleEating)", value: $peopleEating, in: 1...24)
        Toggle("Plan for leftovers", isOn: $plansLeftovers)
        if plansLeftovers {
          Text("Apron Buddy cooks extra portions and schedules them for the same meal on a later day. The grocery list counts the larger batch once.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("Occasion and preferences") {
        TextField("Special occasion (optional)", text: $occasion)
        TextField("Dietary needs or other constraints", text: $constraints, axis: .vertical)
          .lineLimit(2...4)
        TextField("Daily calorie target (optional)", text: $calorieTargetText)
#if os(iOS)
          .keyboardType(.numberPad)
#endif
        if dailyCalorieTarget > 0 {
          Text("Apron Buddy can compare the target with recipes that have calorie information. Recipes without nutrition data can’t be counted.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("Optional helpers") {
        Toggle("Consider my calendar", isOn: $usesCalendar)
        Text("When enabled, Apron Buddy checks dinner-time events on this device. Event titles aren’t saved with the plan.")
          .font(.caption)
          .foregroundStyle(.secondary)

        if MealPlanSuggestionService.isAIAvailable {
          Toggle("Use Apple Intelligence", isOn: $usesAppleIntelligence)
          Text("Apple Intelligence selects from your saved recipes on this device. Apron Buddy never asks it to invent a recipe.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Label("Apple Intelligence isn’t available right now. Apron Buddy will match recipes using your preferences and cooking times.", systemImage: "sparkles")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section {
        Button {
          Task { await generateSuggestions() }
        } label: {
          if isGenerating {
            HStack {
              ProgressView()
              Text("Checking your preferences…")
            }
            .frame(maxWidth: .infinity)
          } else {
            Label("Suggest meals", systemImage: "sparkles")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(palette.accent)
        .disabled(isGenerating)
      }
    }
    .scrollContentBackground(.hidden)
  }

  private var reviewForm: some View {
    Form {
      Section {
        Label(usedAppleIntelligence ? "Suggested with Apple Intelligence" : "Suggested from your recipes", systemImage: "sparkles")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.accent)
        Text("Review each meal and change any recipe before creating the plan.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      ForEach(reviewDates, id: \.self) { date in
        Section(date.formatted(date: .complete, time: .omitted)) {
          Toggle("Plan this day", isOn: dayIsPlannedBinding(for: date))
            .font(.subheadline.weight(.medium))

          ForEach($draftSlots) { $slot in
            if Calendar.current.isDate(slot.date, inSameDayAs: date) {
              VStack(alignment: .leading, spacing: 9) {
                Label(slot.meal.title, systemImage: slot.meal.symbol)
                  .font(.subheadline.weight(.semibold))

                if !slot.note.isEmpty {
                  Label(slot.note, systemImage: slot.note == "Dinner invitation found" ? "person.2" : "clock")
                    .font(.caption)
                    .foregroundStyle(palette.accent)
                }

                Toggle("Include this meal", isOn: Binding(
                  get: { !slot.isSkipped },
                  set: { isIncluded in
                    slot.isSkipped = !isIncluded
                    updateDraftLeftovers()
                  }
                ))
                .font(.caption)

                if !slot.isSkipped {
                  Picker("Recipe", selection: Binding(
                    get: { slot.recipeID },
                    set: { value in
                      slot.recipeID = value
                      slot.suggestedRecipeID = value
                      updateDraftLeftovers()
                    }
                  )) {
                    Text("Choose a recipe").tag(UUID?.none)
                    ForEach(recipes) { recipe in
                      Text(recipe.name).tag(Optional(recipe.id))
                    }
                  }
                  .pickerStyle(.menu)
                  .disabled(slot.isLeftovers)
                  if slot.isLeftovers {
                    Text("This meal uses the extra portions cooked earlier in the plan.")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
              }
              .padding(.vertical, 5)
            }
          }
        }
      }

      if dailyCalorieTarget > 0 {
        Section("Daily calorie check") {
          ForEach(reviewDates, id: \.self) { date in
            HStack {
              Text(date.formatted(date: .abbreviated, time: .omitted))
              Spacer()
              Text(calorieSummary(for: date))
                .foregroundStyle(.secondary)
            }
          }
          Text("Target: \(dailyCalorieTarget.formatted()) calories per person. Totals include planned recipes only; meals without nutrition information or meals skipped for calendar events aren’t counted.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("Need more recipes?") {
        if let onlineSearchURL {
          Link(destination: onlineSearchURL) {
            Label("Search online for highly rated recipes", systemImage: "safari")
          }
        }
        Button("Import a recipe link into Apron Buddy", systemImage: "arrow.down.document") {
          isImportPresented = true
        }
        Text("After importing, tap Suggest again to use the new recipe in this plan.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Button("Suggest again", systemImage: "sparkles") {
          Task { await regenerateSuggestions() }
        }
      }
    }
    .scrollContentBackground(.hidden)
  }

  private var onlineSearchURL: URL? {
    var components = URLComponents(string: "https://www.google.com/search")
    let mealText = mealTypes.map(\.title).joined(separator: " ")
    let query = ["highly rated", mealText, occasion, constraints, "recipes"]
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: " ")
    components?.queryItems = [URLQueryItem(name: "q", value: query)]
    return components?.url
  }

  private var reviewDates: [Date] {
    Array(Set(draftSlots.map { Calendar.current.startOfDay(for: $0.date) })).sorted()
  }

  private func dayIsPlannedBinding(for date: Date) -> Binding<Bool> {
    Binding(
      get: {
        draftSlots.contains { Calendar.current.isDate($0.date, inSameDayAs: date) && !$0.isSkipped }
      },
      set: { isPlanned in
        for index in draftSlots.indices where Calendar.current.isDate(draftSlots[index].date, inSameDayAs: date) {
          draftSlots[index].isSkipped = !isPlanned
        }
        updateDraftLeftovers()
      }
    )
  }

  private func calorieSummary(for date: Date) -> String {
    let daySlots = draftSlots.filter { Calendar.current.isDate($0.date, inSameDayAs: date) && !$0.isSkipped }
    guard !daySlots.isEmpty else { return "No planned meals" }
    var total = 0
    for slot in daySlots {
      guard let recipeID = slot.recipeID,
            let recipe = recipes.first(where: { $0.id == recipeID }),
            recipe.caloriesPerServing > 0 else { return "Incomplete" }
      total += recipe.caloriesPerServing
    }
    return "\(total.formatted()) kcal"
  }

  @MainActor
  private func generateSuggestions() async {
    isGenerating = true
    defer { isGenerating = false }

    do {
      let calendarContexts: [CalendarDinnerContext]
      if usesCalendar {
        calendarContexts = try await MealPlannerSystemServices.shared.dinnerContexts(starting: startDate, dayCount: dayCount)
      } else {
        calendarContexts = []
      }

      let calendar = Calendar.current
      let firstDay = calendar.startOfDay(for: startDate)
      var proposedSlots: [MealPlanDraftSlot] = []
      for dayOffset in 0..<dayCount {
        guard let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDay) else { continue }
        for meal in mealTypes {
          var slot = MealPlanDraftSlot(date: date, meal: meal, recipeID: nil, servings: peopleEating)
          if meal == .dinner,
             let context = calendarContexts.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            slot.note = context.kind == .open ? "" : context.message
            slot.isSkipped = context.kind == .dinnerInvitation
          }
          proposedSlots.append(slot)
        }
      }

      let result = await MealPlanSuggestionService.suggest(
        slots: proposedSlots,
        recipes: recipes,
        occasion: occasion,
        constraints: constraints,
        dailyCalorieTarget: dailyCalorieTarget,
        mealsPerDay: mealsPerDay,
        peopleEating: peopleEating,
        plansLeftovers: plansLeftovers,
        useAI: usesAppleIntelligence
      )
      draftSlots = result.slots
      usedAppleIntelligence = result.usedAI
      stage = .review
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
    }
  }

  @MainActor
  private func regenerateSuggestions() async {
    let preservedCalendarNotes = Dictionary(grouping: draftSlots, by: { Calendar.current.startOfDay(for: $0.date) })
    await generateSuggestions()
    guard !draftSlots.isEmpty else { return }
    for index in draftSlots.indices where draftSlots[index].meal == .dinner {
      guard let original = preservedCalendarNotes[Calendar.current.startOfDay(for: draftSlots[index].date)]?.first(where: { $0.meal == .dinner }) else { continue }
      if original.isSkipped {
        draftSlots[index].isSkipped = true
        draftSlots[index].note = original.note
        draftSlots[index].recipeID = nil
        draftSlots[index].suggestedRecipeID = nil
      }
    }
    updateDraftLeftovers()
  }

  private func createPlan() {
    updateDraftLeftovers()
    let slots = draftSlots.map(\.savedSlot)
    let firstDate = Calendar.current.startOfDay(for: startDate)
    let lastDate = Calendar.current.date(byAdding: .day, value: max(0, dayCount - 1), to: firstDate) ?? firstDate
    let defaultTitle = "Meals · \(firstDate.formatted(date: .abbreviated, time: .omitted))–\(lastDate.formatted(date: .abbreviated, time: .omitted))"
    let plan = MealPlan(
      title: planTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultTitle : planTitle.trimmingCharacters(in: .whitespacesAndNewlines),
      startDate: firstDate,
      slots: slots,
      occasion: occasion.trimmingCharacters(in: .whitespacesAndNewlines),
      constraints: constraints.trimmingCharacters(in: .whitespacesAndNewlines),
      dailyCalorieTarget: dailyCalorieTarget,
      peopleEating: peopleEating,
      plansLeftovers: plansLeftovers,
      usesCalendar: usesCalendar
    )
    modelContext.insert(plan)
    do {
      try modelContext.save()
      dismiss()
    } catch {
      errorMessage = "Apron Buddy couldn’t save this meal plan. Try again."
      isShowingError = true
    }
  }

  private func updateDraftLeftovers() {
    MealPlanSuggestionService.updateForLeftovers(
      &draftSlots,
      peopleEating: peopleEating,
      plansLeftovers: plansLeftovers
    )
  }
}
