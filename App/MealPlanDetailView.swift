import EventKit
import SwiftData
import SwiftUI

struct MealPlanDetailView: View {
  @KitchenPalette private var palette
  @Environment(\.modelContext) private var modelContext
  @State private var isShowingGroceries = false

  var plan: MealPlan
  var recipes: [Recipe]
  var showGroceriesOnAppear = false

  private var dayGroups: [(date: Date, slots: [MealPlanSlot])] {
    Dictionary(grouping: plan.slots, by: { Calendar.current.startOfDay(for: $0.date) })
      .map { (date: $0.key, slots: $0.value.sorted { $0.meal.rawValue < $1.meal.rawValue }) }
      .sorted { $0.date < $1.date }
  }

  var body: some View {
    List {
      if !plan.occasion.isEmpty || !plan.constraints.isEmpty || plan.dailyCalorieTarget > 0 || plan.peopleEating > 0 {
        Section("Plan preferences") {
          Label("For \(plan.peopleEating) people", systemImage: "person.2")
          if plan.plansLeftovers {
            Text("Larger batches are scheduled to cover a later meal.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if !plan.occasion.isEmpty { Label(plan.occasion, systemImage: "sparkles") }
          if !plan.constraints.isEmpty { Label(plan.constraints, systemImage: "leaf") }
          if plan.dailyCalorieTarget > 0 {
            Label("\(plan.dailyCalorieTarget.formatted()) calories per day", systemImage: "flame")
            Text("Calorie totals depend on nutrition information entered for each recipe.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      ForEach(dayGroups, id: \.date) { group in
        Section(group.date.formatted(date: .complete, time: .omitted)) {
          ForEach(group.slots) { slot in
            MealPlanSlotRow(slot: slot, recipe: recipes.first { $0.id == slot.recipeID }, peopleEating: plan.peopleEating)
          }
          if plan.dailyCalorieTarget > 0 {
            Text(calorieSummary(for: group.slots))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      Section("Grocery list") {
        if plan.groceryItems.isEmpty {
          Text("Build a grouped list from the ingredients in your planned recipes.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Button("Generate grocery list", systemImage: "cart") {
            plan.groceryItems = GroceryListBuilder.build(slots: plan.slots, recipes: recipes)
            try? modelContext.save()
            isShowingGroceries = true
          }
          .buttonStyle(.borderedProminent)
          .tint(palette.strongAccent)
          Button("Open grocery list", systemImage: "list.bullet") { isShowingGroceries = true }
        } else {
          Label("\(plan.groceryItems.count) items saved in Apron Buddy", systemImage: "checklist")
          Button("Open grocery list", systemImage: "cart") { isShowingGroceries = true }
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(palette.paper)
    .navigationTitle(plan.title)
    .sheet(isPresented: $isShowingGroceries) {
      GroceryListView(plan: plan)
    }
    .onAppear {
      if showGroceriesOnAppear { isShowingGroceries = true }
    }
  }

  private func calorieSummary(for slots: [MealPlanSlot]) -> String {
    let planned = slots.filter { !$0.isSkipped }
    guard !planned.isEmpty else { return "No meals planned" }
    var total = 0
    for slot in planned {
      guard let recipe = recipes.first(where: { $0.id == slot.recipeID }), recipe.caloriesPerServing > 0 else {
        return "Calories unavailable for some recipes"
      }
      total += recipe.caloriesPerServing
    }
    return "\(total.formatted()) calories from planned recipes"
  }
}

private struct MealPlanSlotRow: View {
  @KitchenPalette private var palette
  var slot: MealPlanSlot
  var recipe: Recipe?
  var peopleEating: Int

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: slot.meal.symbol)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.accent)
        .frame(width: 36, height: 36)
        .background(palette.softAccent, in: Circle())
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(slot.meal.title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        if slot.isSkipped {
          Text(slot.note.isEmpty ? "No meal planned" : slot.note)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.ink)
        } else {
          Text(recipe?.name ?? "Recipe unavailable")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.ink)
          if let recipe {
            Text(slot.isLeftovers
              ? "Leftovers · serves \(slot.servings)"
              : slot.servings > peopleEating
                ? "Serves \(peopleEating) now · makes \(slot.servings) total · \(recipe.prepMinutes + recipe.cookMinutes) min"
                : "Serves \(slot.servings) · \(recipe.prepMinutes + recipe.cookMinutes) min")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 3)
    .accessibilityElement(children: .combine)
  }
}

private struct GroceryGroup: Identifiable {
  var category: String
  var items: [GroceryListItem]
  var id: String { category }
}

private struct GroceryListView: View {
  @KitchenPalette private var palette
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.householdLibrary) private var householdLibrary
  @State private var newItem = ""
  @State private var reminderLists: [ReminderListOption] = []
  @State private var isSelectingReminderList = false
  @State private var isShowingError = false
  @State private var errorMessage = ""
  var plan: MealPlan

  private var groups: [GroceryGroup] {
    Dictionary(grouping: plan.groceryItems, by: \.category)
      .map { GroceryGroup(category: $0.key, items: $0.value.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) }
      .sorted { $0.category.localizedStandardCompare($1.category) == .orderedAscending }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack {
            TextField("Add a grocery item", text: $newItem)
              .onSubmit(addItem)
            Button("Add", systemImage: "plus", action: addItem)
              .labelStyle(.iconOnly)
              .buttonStyle(.borderless)
              .disabled(newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
        .listRowBackground(palette.surface)

        if groups.isEmpty {
          ContentUnavailableView("No groceries to show", systemImage: "cart", description: Text("Add at least one recipe to this plan, then generate the grocery list again."))
        } else {
          ForEach(groups) { group in
            Section(group.category) {
              ForEach(group.items) { item in
                Button { toggle(item) } label: {
                  HStack(spacing: 11) {
                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                      .foregroundStyle(item.isChecked ? palette.accent : Color.secondary)
                      .accessibilityHidden(true)
                    Text(item.displayText)
                      .foregroundStyle(item.isChecked ? Color.secondary : palette.ink)
                      .strikethrough(item.isChecked)
                    Spacer(minLength: 0)
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.displayText)
                .accessibilityValue(item.isChecked ? "Checked" : "Not checked")
                .accessibilityHint("Double-tap to change the checked state.")
                .swipeActions {
                  Button("Remove", systemImage: "trash", role: .destructive) {
                    let items = plan.groceryItems.filter { $0.id != item.id }
                    save(items)
                  }
                }
              }
            }
          }
        }

        Section("Keep your list") {
          Label("Saved in Apron Buddy", systemImage: "checkmark.circle.fill")
            .foregroundStyle(palette.accent)
          if !plan.reminderListName.isEmpty {
            Label("Also added to \(plan.reminderListName)", systemImage: "checkmark")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Button(plan.reminderListName.isEmpty ? "Add to Reminders…" : "Add to another Reminders list…", systemImage: "list.bullet") {
            Task { await loadReminderLists() }
          }
          .disabled(plan.groceryItems.allSatisfy(\.isChecked))
        }
      }
      .scrollContentBackground(.hidden)
      .background(palette.paper)
      .navigationTitle("Groceries")
      .tint(palette.accent)
      .onAppear {
        guard householdLibrary?.isActive != true else { return }
        let normalized = GroceryListBuilder.normalized(plan.groceryItems)
        if normalized != plan.groceryItems {
          plan.groceryItems = normalized
          try? modelContext.save()
        }
      }
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(isPresented: $isSelectingReminderList) {
        ReminderListPickerView(lists: reminderLists) { selectedList in
          Task { await export(to: selectedList) }
        }
      }
      .alert("Grocery list", isPresented: $isShowingError) {
        Button("OK", role: .cancel) { }
      } message: {
        Text(errorMessage)
      }
    }
    .frame(minWidth: 360, minHeight: 460)
  }

  private func toggle(_ item: GroceryListItem) {
    var items = plan.groceryItems
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
    items[index].isChecked.toggle()
    save(items)
  }

  private func addItem() {
    let name = IngredientNormalization.tidy(newItem)
    guard !name.isEmpty else { return }
    let items = plan.groceryItems + [.init(name: name, amount: 0, unit: "", category: "Other")]
    if save(items) { newItem = "" }
  }

  @discardableResult
  private func save(_ items: [GroceryListItem]) -> Bool {
    let previous = plan.groceryItems
    plan.groceryItems = items
    do {
      try modelContext.save()
      if householdLibrary?.isActive == true {
        Task { await householdLibrary?.synchronize() }
      }
      return true
    } catch {
      plan.groceryItems = previous
      errorMessage = error.localizedDescription
      isShowingError = true
      return false
    }
  }

  @MainActor
  private func loadReminderLists() async {
    do {
      reminderLists = try await MealPlannerSystemServices.shared.reminderLists()
      guard !reminderLists.isEmpty else {
        errorMessage = "No editable Reminders lists were found. Create or enable a list in Reminders and try again."
        isShowingError = true
        return
      }
      isSelectingReminderList = true
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
    }
  }

  @MainActor
  private func export(to list: ReminderListOption) async {
    do {
      try await MealPlannerSystemServices.shared.add(plan.groceryItems, to: list.id)
      plan.reminderListID = list.id
      plan.reminderListName = list.title
      try modelContext.save()
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
    }
  }
}

private struct ReminderListPickerView: View {
  @Environment(\.dismiss) private var dismiss
  var lists: [ReminderListOption]
  var onSelect: (ReminderListOption) -> Void

  var body: some View {
    NavigationStack {
      List {
        if lists.allSatisfy({ !$0.isEditable }) {
          Section {
            Text("These lists are read-only. Create or enable an editable list in Reminders to add groceries.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        ForEach(lists) { list in
          Button {
            onSelect(list)
            dismiss()
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Label(list.title, systemImage: "list.bullet")
                if !list.isEditable {
                  Text("Read-only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              Spacer()
              Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(!list.isEditable)
        }
      }
      .navigationTitle("Choose a Reminders list")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .frame(minWidth: 340, minHeight: 320)
  }
}
