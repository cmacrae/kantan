import SwiftUI

// MARK: - Module Visibility Wrapper

/// Observes a single ModuleViewModel so that changes to `shouldDisplay`
/// trigger a re-evaluation of the conditional content.
/// Without this, the parent ForEach does not re-render when an individual
/// view model's published property changes.
private struct ModuleVisibilityView: View {
  @ObservedObject var viewModel: ModuleViewModel
  let popupManager: PopupManager
  let horizontalPadding: CGFloat
  /// The placement of the module's group.
  let placement: String
  /// Whether the group has slid behind the notch to make room.
  let isDisplaced: Bool
  @Environment(\.groupAnchorsTrailing) private var groupAnchorsTrailing

  /// How the module enters and leaves: sliding to and from the edge its
  /// group is anchored to, or at once.
  private var transition: AnyTransition {
    guard viewModel.moduleConfig.slides(at: placement) else { return .identity }
    return .move(edge: groupAnchorsTrailing ? .trailing : .leading).combined(with: .opacity)
  }

  var body: some View {
    if viewModel.shouldDisplay, !isDisplaced {
      ModuleContainerView(viewModel: viewModel, popupManager: popupManager)
        .padding(.horizontal, viewModel.moduleConfig.type == "drawer" ? 0 : horizontalPadding)
        .transition(transition)
    } else {
      // Out of the bar, the module has no width for another to follow.
      Color.clear.frame(width: 0, height: 0)
        .onAppear { ModuleWidths.shared.set(0, for: viewModel.id) }
    }
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

  private var isMasked: Bool {
    modules.count == 1 && modules[0].moduleConfig.mask != nil
  }

  /// The edge the group grows away from, which stays put while its panel
  /// resizes around content changing width.
  private var anchor: Alignment {
    placement == "right" || placement == "notchleft" ? .trailing : .leading
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(modules) { vm in
        ModuleVisibilityView(
          viewModel: vm,
          popupManager: popupManager,
          horizontalPadding: isMasked ? 0 : CGFloat(themeProvider.config.padding),
          placement: placement, isDisplaced: displaced.placements.contains(placement)
        )
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
