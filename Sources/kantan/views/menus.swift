import SwiftUI

// MARK: - Themed Menu (SwiftUI)

/// SwiftUI menu rendered inside an NSVisualEffectView(.menu) panel.
/// Uses native system colors (.primary/.secondary) in native mode;
/// applies the user's theme foreground color in theme mode.
struct SwiftUIThemedMenuView: View {
    let descriptors: [MenuItemDescriptor]
    let isNative: Bool
    let fgColor: Color
    let dismissHandler: () -> Void
    let rebuilder: (() -> Void)?

    /// Resolved foreground: system .primary in native mode, theme color otherwise.
    private var resolvedFg: Color {
        isNative ? .primary : fgColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(descriptors.enumerated()), id: \.offset) { _, descriptor in
                if descriptor.isSeparator {
                    Divider()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                } else if descriptor.isCheck {
                    SwiftUIMenuCheckView(
                        label: descriptor.label ?? "",
                        isChecked: descriptor.isChecked,
                        isNative: isNative,
                        fgColor: fgColor,
                        action: {
                            dismissHandler()
                            descriptor.toggleAction? {
                                rebuilder?()
                            }
                        }
                    )
                } else if descriptor.isToggle {
                    SwiftUIMenuToggleView(
                        label: descriptor.label ?? "",
                        isOn: descriptor.isToggleOn,
                        isNative: isNative,
                        fgColor: fgColor,
                        action: {
                            dismissHandler()
                            descriptor.toggleAction? {
                                rebuilder?()
                            }
                        }
                    )
                } else if descriptor.isHeader {
                    Text(descriptor.label ?? "")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(resolvedFg.opacity(0.5))
                        .padding(.horizontal, 16)
                        .frame(height: 22, alignment: .leading)
                } else {
                    SwiftUIMenuItemView(
                        label: descriptor.label ?? "",
                        icon: descriptor.icon,
                        iconGlyph: descriptor.iconGlyph,
                        isNative: isNative,
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
    var iconGlyph: String? = nil
    let isNative: Bool
    let fgColor: Color
    let action: () -> Void
    @State private var isHovered = false

    private var resolvedFg: Color {
        isNative ? .primary : fgColor
    }

    var body: some View {
        HStack(spacing: 8) {
            if let iconGlyph = iconGlyph, !iconGlyph.isEmpty {
                Text(iconGlyph)
                    .font(.system(size: 13))
                    .foregroundStyle(isHovered && isNative ? .white : resolvedFg)
                    .frame(width: 16, alignment: .center)
            } else if let icon = icon {
                NSViewWrapper(nsView: icon)
                    .frame(width: 10, height: 10)
            }
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(isHovered && isNative ? .white : resolvedFg)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(isNative ? 1.0 : 0.3) : .clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            action()
        }
    }
}

// MARK: - Menu Toggle View

struct SwiftUIMenuToggleView: View {
    let label: String
    @State var isOn: Bool
    let isNative: Bool
    let fgColor: Color
    let action: () -> Void

    private var resolvedFg: Color {
        isNative ? .primary : fgColor
    }

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(.accentColor)
            .foregroundStyle(resolvedFg)
            .padding(.horizontal, 14)
            .frame(height: 26)
            .onChange(of: isOn) { _, _ in
                action()
            }
    }
}

struct SwiftUIMenuCheckView: View {
    let label: String
    let isChecked: Bool
    let isNative: Bool
    let fgColor: Color
    let action: () -> Void

    private var resolvedFg: Color {
        isNative ? .primary : fgColor
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isChecked ? resolvedFg.opacity(0.4) : resolvedFg)
                .imageScale(.medium)
            Text(label)
                .strikethrough(isChecked)
                .foregroundStyle(isChecked ? resolvedFg.opacity(0.4) : resolvedFg)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
        .contentShape(Rectangle())
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
