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

  var body: some View {
    if viewModel.shouldDisplay {
      ModuleContainerView(viewModel: viewModel, popupManager: popupManager)
        .padding(.horizontal, horizontalPadding)
    }
  }
}

// MARK: - Module Group View

/// Renders a single group of modules in an HStack.
/// Each group gets its own NSPanel in the multi-panel architecture.
struct ModuleGroupView: View {
  let modules: [ModuleViewModel]
  let popupManager: PopupManager
  @ObservedObject var themeProvider: ThemeProvider

  private var isMasked: Bool {
    modules.count == 1 && modules[0].moduleConfig.mask != nil
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(modules) { vm in
        ModuleVisibilityView(
          viewModel: vm,
          popupManager: popupManager,
          horizontalPadding: isMasked ? 0 : CGFloat(themeProvider.config.padding)
        )
      }
    }
    .frame(maxWidth: isMasked ? .infinity : nil)
    .fixedSize(horizontal: !isMasked, vertical: false)
    .frame(height: CGFloat(themeProvider.config.height))
    .environmentObject(themeProvider)
  }
}
