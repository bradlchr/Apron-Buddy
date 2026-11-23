import SwiftUI

struct DishCategoryArtwork: View {
  var category: DishCategory

  var body: some View {
    Canvas { context, size in
      let side = min(size.width, size.height)
      var context = context
      context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
      context.scaleBy(x: side / 100, y: side / 100)
      let style = StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round)
      context.stroke(dishOutline, with: .color(.white.opacity(0.88)), style: style)
    }
    .accessibilityHidden(true)
  }

  private var dishOutline: Path {
    var path = Path()
    func line(_ points: CGPoint...) {
      guard let first = points.first else { return }
      path.move(to: first)
      for point in points.dropFirst() { path.addLine(to: point) }
    }
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    switch category {
    case .pasta:
      path.addEllipse(in: CGRect(x: 12, y: 13, width: 76, height: 76))
      for y in [34.0, 44.0, 54.0, 64.0] {
        path.move(to: point(28, y))
        path.addQuadCurve(to: point(51, y), control: point(39, y - 14))
        path.addQuadCurve(to: point(72, y), control: point(62, y + 14))
      }
    case .seafood:
      path.move(to: point(16, 50))
      path.addQuadCurve(to: point(70, 50), control: point(45, 18))
      path.addLine(to: point(88, 34))
      path.addLine(to: point(88, 66))
      path.addLine(to: point(70, 50))
      path.addQuadCurve(to: point(16, 50), control: point(45, 82))
      path.addEllipse(in: CGRect(x: 30, y: 46, width: 5, height: 5))
    case .poultry:
      path.move(to: point(38, 59))
      path.addCurve(to: point(65, 17), control1: point(32, 34), control2: point(45, 17))
      path.addCurve(to: point(81, 52), control1: point(85, 17), control2: point(89, 36))
      path.addQuadCurve(to: point(48, 65), control: point(73, 72))
      line(point(38, 59), point(26, 70), point(19, 70), point(16, 76), point(23, 82), point(30, 83), point(33, 76), point(48, 65))
    case .dessert:
      line(point(23, 53), point(29, 81), point(71, 81), point(77, 53))
      path.move(to: point(21, 53))
      path.addQuadCurve(to: point(41, 34), control: point(16, 36))
      path.addQuadCurve(to: point(63, 34), control: point(51, 11))
      path.addQuadCurve(to: point(79, 53), control: point(85, 34))
      line(point(21, 53), point(79, 53))
      line(point(42, 63), point(44, 74))
      line(point(58, 63), point(56, 74))
    case .baking, .breakfast:
      path.move(to: point(16, 69))
      path.addQuadCurve(to: point(84, 69), control: point(50, 9))
      path.addQuadCurve(to: point(16, 69), control: point(52, 95))
      line(point(38, 45), point(44, 55))
      line(point(51, 42), point(57, 52))
      line(point(64, 46), point(70, 56))
    case .vegetarian:
      path.move(to: point(27, 75))
      path.addQuadCurve(to: point(71, 25), control: point(12, 27))
      path.addQuadCurve(to: point(27, 75), control: point(83, 76))
      line(point(21, 85), point(62, 36))
      line(point(40, 61), point(39, 45))
      line(point(51, 49), point(64, 50))
    case .appetizer, .soup, .dinner:
      path.move(to: point(14, 49))
      path.addQuadCurve(to: point(86, 49), control: point(50, 40))
      path.addQuadCurve(to: point(65, 76), control: point(81, 68))
      line(point(65, 76), point(35, 76))
      path.addQuadCurve(to: point(14, 49), control: point(19, 68))
      for x in [39.0, 52.0, 65.0] {
        path.move(to: point(x, 34))
        path.addQuadCurve(to: point(x + 1, 18), control: point(x - 9, 25))
      }
    }
    return path
  }
}
