import SwiftUI

struct CookingIngredientsPeek: View {
  @KitchenPalette private var palette
  var ingredients: [String]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text("Ingredients").font(.headline).accessibilityAddTraits(.isHeader)
        if ingredients.isEmpty {
          Text("No ingredients saved").foregroundStyle(.secondary)
        }
        ForEach(ingredients.indices, id: \.self) { index in
          Text(ingredients[index])
            .font(ingredients[index].hasSuffix(":") ? .subheadline.weight(.semibold) : .body)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
    }
    .background(palette.surface)
    .foregroundStyle(palette.ink)
    .frame(idealWidth: 290, idealHeight: 260)
  }
}
