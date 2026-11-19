import SwiftUI

// MARK: - Module Visibility Wrapper

/// Observes a single ModuleViewModel so that changes to `shouldDisplay`
/// trigger a re-evaluation of the conditional content.
/// Without this, the parent ForEach does not re-render when an individual
/// view model's published property changes.
private struct ModuleVisibilityView: View {
  @ObservedObject var viewModel: ModuleViewModel
  let popupManager: PopupManager
  /// The room at the module's leading and trailing edges.
  let padding: (leading: CGFloat, trailing: CGFloat)
  /// Whether the module's icon anchors the bar's centre.
  let anchorsCenter: Bool
  /// The placement of the module's group.
  let placement: String
  /// Whether the group has slid behind the notch to make room.
  let isDisplaced: Bool
  /// How the module's side of the notch is shared.
  let tuckPhase: TuckPhase
  @Environment(\.groupAnchorsTrailing) private var groupAnchorsTrailing

  /// How the module enters and leaves: sliding to and from the edge its
  /// group is anchored to, or at once.
  private var transition: AnyTransition {
    guard viewModel.moduleConfig.slides(at: placement) else { return .identity }
    return .move(edge: groupAnchorsTrailing ? .trailing : .leading).combined(with: .opacity)
  }

  /// Whether the module is out of the bar for the others on its side of
  /// the notch.
  private var isTuckedAway: Bool {
    viewModel.moduleConfig.sharesNotch
      && tuckPhase.hides(givesWay: viewModel.moduleConfig.tuck != nil)
  }

  /// How the module makes way for the others on its side of the notch and
  /// returns: one that gives way slides behind the notch, and any other
  /// fades, leaving quickly.
  private var tuckTransition: AnyTransition {
    guard viewModel.moduleConfig.tuck == nil else {
      return .move(edge: groupAnchorsTrailing ? .trailing : .leading).combined(with: .opacity)
    }
    return .asymmetric(
      insertion: .opacity.animation(ModuleAnimation.entrance),
      removal: .opacity.animation(ModuleAnimation.exit))
  }

  /// What stands in for a module out of the bar: nothing, with no width
  /// for another module to follow.
  private var absent: some View {
    Color.clear.frame(width: 0, height: 0)
      .onAppear { ModuleWidths.shared.set(0, for: viewModel.id) }
  }

  var body: some View {
    if viewModel.shouldDisplay, !isDisplaced {
      // A container of its own, so the module showing and hiding and the
      // module making way each keep their own transition.
      ZStack {
        if isTuckedAway {
          absent
        } else {
          ModuleContainerView(viewModel: viewModel, popupManager: popupManager)
            .padding(.leading, viewModel.moduleConfig.type == "drawer" ? 0 : padding.leading)
            .padding(.trailing, viewModel.moduleConfig.type == "drawer" ? 0 : padding.trailing)
            .environment(\.anchorsCenter, anchorsCenter)
            .transition(tuckTransition)
        }
      }
      .transition(transition)
    } else {
      absent
    }
  }
}

// MARK: - Center Anchor

/// Where the icon anchoring the bar's centre is drawn: its centre, in its
/// group's own space.
struct AnchorIconKey: PreferenceKey {
  static let space = "kantan.group"
  static let defaultValue: CGFloat? = nil

  static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
    value = value ?? nextValue()
  }
}

private struct AnchorsCenterKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// Whether the module's icon anchors the bar's centre.
  var anchorsCenter: Bool {
    get { self[AnchorsCenterKey.self] }
    set { self[AnchorsCenterKey.self] = newValue }
  }
}

// MARK: - Group Anchor

private struct GroupAnchorsTrailingKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// Whether the module's group keeps its trailing edge in place, growing
  /// toward the leading one, as groups right of the bar's centre do.
  var groupAnchorsTrailing: Bool {
    get { self[GroupAnchorsTrailingKey.self] }
    set { self[GroupAnchorsTrailingKey.self] = newValue }
  }
}

private struct GroupPlacementKey: EnvironmentKey {
  static let defaultValue = "left"
}

extension EnvironmentValues {
  /// The placement of the module's group.
  var groupPlacement: String {
    get { self[GroupPlacementKey.self] }
    set { self[GroupPlacementKey.self] = newValue }
  }
}

// MARK: - Module Group View

/// Renders a single group of modules in an HStack.
/// Each group gets its own NSPanel in the multi-panel architecture.
struct ModuleGroupView: View {
  let modules: [ModuleViewModel]
  let placement: String
  let popupManager: PopupManager
  @ObservedObject var themeProvider: ThemeProvider
  @ObservedObject var displaced: DisplacedPlacements
  @ObservedObject var tucks: NotchTucks
  var centerAnchor: CenterAnchor? = nil

  /// The room at a module's edges: the bar's padding, but for the anchor
  /// of the bar's centre and the module on its icon's side, which sit as
  /// far apart as an icon and its text.
  private func padding(of module: ModuleViewModel) -> (leading: CGFloat, trailing: CGFloat) {
    let padding = isMasked ? 0 : CGFloat(themeProvider.config.padding)
    var edges = (leading: padding, trailing: padding)
    guard let anchor = centerAnchor, !isMasked else { return edges }
    if module.id == anchor.module {
      if anchor.iconTrails {
        edges.trailing = themeProvider.iconTextSpacing
      } else {
        edges.leading = themeProvider.iconTextSpacing
      }
    } else if module.id == anchor.neighbour {
      if anchor.iconTrails {
        edges.leading = 0
      } else {
        edges.trailing = 0
      }
    }
    return edges
  }

  private var isMasked: Bool {
    modules.count == 1 && modules[0].moduleConfig.mask != nil
  }

  /// The edge the group grows away from, which stays put while its panel
  /// resizes around content changing width.
  private var anchor: Alignment {
    switch placement {
    case "right", "notchleft": return .trailing
    case "center": return .center
    default: return .leading
    }
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(modules) { vm in
        ModuleVisibilityView(
          viewModel: vm,
          popupManager: popupManager,
          padding: padding(of: vm), anchorsCenter: vm.id == centerAnchor?.module,
          placement: placement, isDisplaced: displaced.placements.contains(placement),
          tuckPhase: tucks.phases[placement] ?? .idle
        )
      }
    }
    .coordinateSpace(name: AnchorIconKey.space)
    .onPreferenceChange(AnchorIconKey.self) { midX in
      MainActor.assumeIsolated {
        guard let anchor = centerAnchor, modules.contains(where: { $0.id == anchor.module })
        else { return }
        anchor.setIconMidX(midX)
      }
    }
    .frame(maxWidth: isMasked ? .infinity : nil)
    .fixedSize(horizontal: !isMasked, vertical: false)
    .frame(height: CGFloat(themeProvider.config.height))
    // No minimum width, so a panel still catching up with content that has
    // grown keeps the content at its anchor rather than widening at once.
    .frame(minWidth: 0, maxWidth: .infinity, alignment: anchor)
    .environmentObject(themeProvider)
    .environment(\.groupAnchorsTrailing, anchor == .trailing)
    .environment(\.groupPlacement, placement)
  }
}

// MARK: - Notch Glow

/// The outline of a notch: square where it meets the top of the screen,
/// rounded at its bottom corners.
struct NotchShape: Shape {
  /// The radius of the bottom corners of a MacBook's notch, in points.
  static let cornerRadius: CGFloat = 8

  func path(in rect: CGRect) -> Path {
    Path(
      roundedRect: rect,
      cornerRadii: RectangleCornerRadii(
        bottomLeading: Self.cornerRadius, bottomTrailing: Self.cornerRadius))
  }
}

/// A soft glow around each side of the notch with modules waiting behind
/// it, in the colour of the first of them. It follows the notch's side and
/// round its bottom corner, fading out beneath the notch.
struct NotchGlowView: View {
  /// How far the glow's view reaches past the notch, at its sides and below.
  static let reach: CGFloat = 26
  /// How far the glow carries on beneath the notch, past its corner.
  static let tail: CGFloat = 26

  @ObservedObject var tucks: NotchTucks
  @ObservedObject var themeProvider: ThemeProvider
  /// The modules that give way at each placement beside the notch.
  let modules: [String: [ModuleViewModel]]

  /// The glow of one side: the notch's shape, blurred past its edges, as
  /// far along as the side's bottom corner and its tail.
  private func glow(at placement: String, width: CGFloat) -> some View {
    let color =
      modules[placement]?.first(where: \.shouldDisplay).map { themeProvider.iconFgColor(for: $0) }
      ?? themeProvider.globalColors().fg
    let isLeft = placement == "notchleft"
    let solid = (Self.reach + NotchShape.cornerRadius) / width
    let clear = (Self.reach + NotchShape.cornerRadius + Self.tail) / width
    return NotchShape()
      .fill(color.opacity(0.7))
      .padding(.horizontal, Self.reach)
      .padding(.bottom, Self.reach)
      .blur(radius: 9)
      .mask(
        LinearGradient(
          stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: solid),
            .init(color: .clear, location: clear),
          ],
          startPoint: isLeft ? .leading : .trailing, endPoint: isLeft ? .trailing : .leading)
      )
      .opacity(tucks.phases[placement] == .tucked ? 1 : 0)
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        glow(at: "notchleft", width: geometry.size.width)
        glow(at: "notchright", width: geometry.size.width)
      }
    }
  }
}
