import SwiftUI

enum KitchenTheme: String, CaseIterable, Identifiable {
  static let preferenceKey = "apronBuddy.kitchenTheme"

  case forest
  case terracotta
  case denim
  case linen
  case midnight

  var id: Self { self }

  var title: String {
    switch self {
    case .forest: "Forest Green"
    case .terracotta: "Terracotta"
    case .denim: "Navy Denim"
    case .linen: "Cream Linen"
    case .midnight: "Midnight Black"
    }
  }

  func accent(for scheme: ColorScheme) -> Color {
    switch (self, scheme) {
    case (.forest, .light): Color("AccentColor")
    case (.forest, _): Color.miseOlive
    case (.terracotta, .light): Color(red: 0.60, green: 0.27, blue: 0.19)
    case (.terracotta, _): Color(red: 0.94, green: 0.61, blue: 0.48)
    case (.denim, .light): Color(red: 0.22, green: 0.34, blue: 0.54)
    case (.denim, _): Color(red: 0.63, green: 0.73, blue: 0.91)
    case (.linen, .light): Color(red: 0.48, green: 0.35, blue: 0.22)
    case (.linen, _): Color(red: 0.86, green: 0.73, blue: 0.56)
    case (.midnight, .light): Color(red: 0.30, green: 0.30, blue: 0.35)
    case (.midnight, _): Color(red: 0.72, green: 0.73, blue: 0.82)
    }
  }

  func paper(for scheme: ColorScheme) -> Color {
    switch (self, scheme) {
    case (.forest, _): Color.misePaper
    case (.terracotta, .light): Color(red: 0.98, green: 0.93, blue: 0.89)
    case (.terracotta, _): Color(red: 0.17, green: 0.12, blue: 0.11)
    case (.denim, .light): Color(red: 0.92, green: 0.95, blue: 0.98)
    case (.denim, _): Color(red: 0.10, green: 0.13, blue: 0.20)
    case (.linen, .light): Color(red: 0.98, green: 0.96, blue: 0.91)
    case (.linen, _): Color(red: 0.16, green: 0.14, blue: 0.11)
    case (.midnight, .light): Color(red: 0.93, green: 0.94, blue: 0.96)
    case (.midnight, _): Color(red: 0.10, green: 0.10, blue: 0.13)
    }
  }

  var appIconName: String? {
    switch self {
    case .forest: nil
    case .terracotta: "IconTerracotta"
    case .denim: "IconDenim"
    case .linen: "IconLinen"
    case .midnight: "IconMidnight"
    }
  }
}

struct KitchenThemeColors {
  var theme: KitchenTheme
  var scheme: ColorScheme

  var paper: Color { theme.paper(for: scheme) }
  var accent: Color { theme.accent(for: scheme) }
  var strongAccent: Color { theme.accent(for: .light) }
  var ink: Color { Color.miseInk }
  var softAccent: Color { theme == .forest ? Color.miseSage : accent.opacity(scheme == .dark ? 0.21 : 0.15) }
  var warning: Color { Color.miseCoral }

  var surface: Color {
    switch (theme, scheme) {
    case (.forest, _): Color.miseSurface
    case (.terracotta, .light): Color(red: 1, green: 0.97, blue: 0.94)
    case (.terracotta, _): Color(red: 0.23, green: 0.16, blue: 0.14)
    case (.denim, .light): Color(red: 0.97, green: 0.98, blue: 1)
    case (.denim, _): Color(red: 0.15, green: 0.19, blue: 0.26)
    case (.linen, .light): Color(red: 1, green: 0.985, blue: 0.95)
    case (.linen, _): Color(red: 0.22, green: 0.20, blue: 0.16)
    case (.midnight, .light): Color(red: 0.98, green: 0.98, blue: 0.99)
    case (.midnight, _): Color(red: 0.16, green: 0.16, blue: 0.20)
    }
  }
}

@propertyWrapper
struct KitchenPalette: DynamicProperty {
  @AppStorage(KitchenTheme.preferenceKey) private var theme: KitchenTheme = .forest
  @Environment(\.colorScheme) private var scheme

  var wrappedValue: KitchenThemeColors { KitchenThemeColors(theme: theme, scheme: scheme) }
}
