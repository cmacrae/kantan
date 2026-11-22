import AppKit
import SwiftUI

@MainActor
final class AppMenusModel: ObservableObject {
  /// The titles, relative to the screen's left edge.
  @Published var titles: [AppMenuTitle] = []
  /// How far the view starts from that edge.
  @Published var inset: CGFloat = 0
  @Published var hovered: Int?
}

/// The app menus' titles in the bar's font and colour, each centred in the
/// slot of the native title beneath it.
struct AppMenusView: View {
  /// The least room left either side of a title in its slot.
  private static let titlePadding: CGFloat = 4
  private static let appleLogoSize: CGFloat = 14.5

  @ObservedObject var model: AppMenusModel
  @ObservedObject var theme: ThemeProvider

  var body: some View {
    let fg = Color(nsColor: theme.globalFgNSColor())
    let fonts = titleFonts
    let open = model.titles.firstIndex(where: \.isOpen)
    GeometryReader { geometry in
      ZStack(alignment: .topLeading) {
        ForEach(Array(model.titles.enumerated()), id: \.offset) { index, title in
          Group {
            if title.isApple {
              Image(systemName: "apple.logo")
                .font(.system(size: Self.appleLogoSize))
                .offset(y: -0.5)
            } else {
              Text(title.title)
                .font(Font(title.isAppName ? fonts.bold : fonts.regular))
                .lineLimit(1)
                .fixedSize()
            }
          }
          .foregroundStyle(fg)
          .frame(width: title.frame.width, height: geometry.size.height)
          .background(
            Capsule()
              .fill(fg.opacity(highlight(index, open: open)))
              .padding(.vertical, 4)
          )
          .offset(x: title.frame.minX - model.inset)
        }
      }
    }
  }

  private func highlight(_ index: Int, open: Int?) -> Double {
    if let open { return index == open ? 0.18 : 0 }
    return index == model.hovered ? 0.09 : 0
  }

  /// The bar's font, shrunk evenly until every title fits: the native
  /// titles take the clicks, so their slots can't grow.
  private var titleFonts: (regular: NSFont, bold: NSFont) {
    let manager = NSFontManager.shared
    let regular = theme.globalTextFont.nsFont
    let bold = manager.convert(regular, toHaveTrait: .boldFontMask)
    let scale =
      model.titles.filter { !$0.isApple }.map { title -> CGFloat in
        let font = title.isAppName ? bold : regular
        let width = (title.title as NSString).size(withAttributes: [.font: font]).width
        return width > 0 ? (title.frame.width - 2 * Self.titlePadding) / width : 1
      }.min() ?? 1
    guard scale < 1, scale > 0 else { return (regular, bold) }
    let size = regular.pointSize * scale
    return (manager.convert(regular, toSize: size), manager.convert(bold, toSize: size))
  }
}
