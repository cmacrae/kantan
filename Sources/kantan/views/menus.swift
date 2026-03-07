import SwiftUI

// MARK: - Themed Menu (SwiftUI)

/// SwiftUI replacement for the AppKit ThemedMenuView.
/// Renders MenuItemDescriptors with hover highlights and click handling.
struct SwiftUIThemedMenuView: View {
    let descriptors: [MenuItemDescriptor]
    let fgColor: Color
    let bgColor: Color
    let dismissHandler: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(descriptors.enumerated()), id: \.offset) { _, descriptor in
                if descriptor.isSeparator {
                    Divider()
                        .background(fgColor.opacity(0.15))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                } else if descriptor.isHeader {
                    Text(descriptor.label ?? "")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(fgColor.opacity(0.5))
                        .padding(.horizontal, 16)
                        .frame(height: 22, alignment: .leading)
                } else {
                    SwiftUIMenuItemView(
                        label: descriptor.label ?? "",
                        icon: descriptor.icon,
                        fgColor: fgColor,
                        action: {
                            dismissHandler()
                            descriptor.action?()
                        }
                    )
                }
            }
        }
        .padding(.vertical, 8)
        .frame(minWidth: 220)
    }
}

// MARK: - Menu Item View

struct SwiftUIMenuItemView: View {
    let label: String
    let icon: NSView?
    let fgColor: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                NSViewWrapper(nsView: icon)
                    .frame(width: 10, height: 10)
            }
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(fgColor)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? fgColor.opacity(0.1) : .clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            action()
        }
    }
}

// MARK: - NSView Wrapper

/// Bridges an NSView into SwiftUI for embedding AppKit icon views
/// (e.g. bluetooth indicator circles) in SwiftUI menus.
struct NSViewWrapper: NSViewRepresentable {
    let nsView: NSView

    func makeNSView(context: Context) -> NSView {
        return nsView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
    }
}
