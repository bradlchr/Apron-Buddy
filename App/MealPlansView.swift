import SwiftData
import SwiftUI

struct MealPlansView: View {
  @Query(sort: \MealPlan.startDate, order: .reverse) private var plans: [MealPlan]
  @State private var isCreatingPlan = false
  @State private var navigationPath: [UUID] = []

  var recipes: [Recipe]
  var searchText: String
  var openPlanID: UUID? = nil
  var openGroceries = false
  var wrapsNavigationStack = true
  var cloudSyncStatus: String? = nil
  var onCloudSyncAction: (() -> Void)? = nil

  private var visiblePlans: [MealPlan] {
    guard !searchText.isEmpty else { return plans }
    return plans.filter { plan in
      plan.title.localizedCaseInsensitiveContains(searchText)
        || plan.occasion.localizedCaseInsensitiveContains(searchText)
        || plan.constraints.localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    Group {
      if wrapsNavigationStack {
        NavigationStack(path: $navigationPath) { content }
      } else {
        content
      }
    }
  }

  private var content: some View {
      Group {
        if plans.isEmpty {
          ContentUnavailableView {
            Label("Plan meals for the week", systemImage: "calendar")
          } description: {
            Text("Use your recipes, your schedule, and the ingredients you already have in Apron Buddy to plan meals.")
          } actions: {
            Button("Create a meal plan", systemImage: "plus") { isCreatingPlan = true }
              .buttonStyle(.borderedProminent)
              .tint(Color.miseOlive)
          }
        } else if visiblePlans.isEmpty {
          ContentUnavailableView("No matching meal plans", systemImage: "magnifyingglass", description: Text("Try another search."))
        } else {
          List {
            ForEach(visiblePlans) { plan in
              NavigationLink(value: plan.id) {
                MealPlanRow(plan: plan)
              }
              .listRowBackground(Color.miseSurface)
            }
          }
          .scrollContentBackground(.hidden)
          .background(Color.misePaper)
        }
      }
      .background(Color.misePaper)
      .navigationTitle("Meal plans")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("New meal plan", systemImage: "plus") { isCreatingPlan = true }
            .labelStyle(.iconOnly)
            .accessibilityLabel("Create a meal plan")
        }
        if let cloudSyncStatus, let onCloudSyncAction {
          CloudStatusToolbar(status: cloudSyncStatus, action: onCloudSyncAction)
        }
      }
      .sheet(isPresented: $isCreatingPlan) {
        MealPlanBuilderView()
      }
      .navigationDestination(for: UUID.self) { planID in
        if let plan = plans.first(where: { $0.id == planID }) {
          MealPlanDetailView(plan: plan, recipes: recipes, showGroceriesOnAppear: openGroceries && planID == openPlanID)
        } else {
          ContentUnavailableView("Meal plan unavailable", systemImage: "calendar.badge.exclamationmark")
        }
      }
      .onAppear(perform: openRequestedPlan)
      .onChange(of: openPlanID) { _, _ in openRequestedPlan() }
  }

  private func openRequestedPlan() {
    guard let openPlanID, plans.contains(where: { $0.id == openPlanID }) else { return }
    navigationPath = [openPlanID]
  }
}

private struct MealPlanRow: View {
  var plan: MealPlan

  private var lastDate: Date {
    plan.slots.map(\.date).max() ?? plan.startDate
  }

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: "calendar")
        .font(.title3.weight(.medium))
        .foregroundStyle(Color.miseOlive)
        .frame(width: 48, height: 52)
        .background(Color.miseSage, in: RoundedRectangle(cornerRadius: 13))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(plan.title)
          .font(.headline)
          .foregroundStyle(Color.miseInk)
        Text("\(plan.startDate.formatted(date: .abbreviated, time: .omitted)) – \(lastDate.formatted(date: .abbreviated, time: .omitted))")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Text("\(plan.slots.filter { !$0.isSkipped }.count) meals · \(plan.peopleEating) people")
          .font(.caption)
          .foregroundStyle(Color.miseOlive)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 5)
  }
}
