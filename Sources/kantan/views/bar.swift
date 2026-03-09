import SwiftUI

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
                ModuleContainerView(viewModel: vm, popupManager: popupManager)
                    .padding(.horizontal, isMasked ? 0 : CGFloat(themeProvider.globalConfig.padding))
            }
        }
        .frame(maxWidth: isMasked ? .infinity : nil)
        .fixedSize(horizontal: !isMasked, vertical: false)
        .frame(height: CGFloat(themeProvider.globalConfig.height))
        .environmentObject(themeProvider)
    }
}
