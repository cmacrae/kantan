import SwiftUI

// MARK: - Bar View

/// Root SwiftUI view for the kantan status bar.
/// Renders left-aligned and right-aligned modules in an HStack.
struct KantanBarView: View {
    @ObservedObject var barViewModel: BarViewModel
    @ObservedObject var themeProvider: ThemeProvider

    var body: some View {
        HStack(spacing: 0) {
            ForEach(barViewModel.leftModules) { vm in
                ModuleContainerView(viewModel: vm, popupManager: barViewModel.popupManager)
            }

            Spacer()

            ForEach(barViewModel.rightModules) { vm in
                ModuleContainerView(viewModel: vm, popupManager: barViewModel.popupManager)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: CGFloat(themeProvider.globalConfig.height))
        .background(themeProvider.barBgColor())
        .background(.black.opacity(0.001)) // click-through for non-interactive areas
        .environmentObject(themeProvider)
    }
}
