#if os(iOS)
import SwiftUI
import WidgetKit

struct CompactIslandContent<Regular: View, Narrow: View>: View {
  var regular: Regular
  var narrow: Narrow

  init(@ViewBuilder regular: () -> Regular, @ViewBuilder narrow: () -> Narrow) {
    self.regular = regular()
    self.narrow = narrow()
  }

  var body: some View {
    if #available(iOS 27.0, *) {
      WidthAwareIslandContent(regular: regular, narrow: narrow)
    } else {
      regular
    }
  }
}

@available(iOS 27.0, *)
private struct WidthAwareIslandContent<Regular: View, Narrow: View>: View {
  @Environment(\.isDynamicIslandLimitedInWidth) private var isLimited

  var regular: Regular
  var narrow: Narrow

  var body: some View {
    if isLimited {
      narrow
    } else {
      regular
    }
  }
}
#endif
