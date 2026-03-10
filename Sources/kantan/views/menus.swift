import SwiftUI

// MARK: - Hoverable Row

struct HoverableRowView: View {
    let label: String
    let icon: String?
    let iconFont: Font?
    let iconWidth: CGFloat?
    let isNative: Bool
    let resolvedFg: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon, !icon.isEmpty {
                Text(icon)
                    .font(iconFont ?? .system(size: 13))
                    .foregroundStyle(isHovered && isNative ? .white : resolvedFg)
                    .frame(width: iconWidth, alignment: .center)
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
        .onHover { hovering in isHovered = hovering }
        .onTapGesture { action() }
    }
}

// MARK: - Themed Menu (SwiftUI)

struct SwiftUIThemedMenuView: View {
    let descriptors: [MenuItemDescriptor]
    let isNative: Bool
    let resolvedFg: Color
    let dismissHandler: () -> Void
    let rebuilder: (() -> Void)?

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
                        resolvedFg: resolvedFg,
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
                        resolvedFg: resolvedFg,
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
                        iconGlyph: descriptor.iconGlyph,
                        isNative: isNative,
                        resolvedFg: resolvedFg,
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
    var iconGlyph: String? = nil
    let isNative: Bool
    let resolvedFg: Color
    let action: () -> Void

    var body: some View {
        HoverableRowView(
            label: label,
            icon: iconGlyph,
            iconFont: nil,
            iconWidth: 16,
            isNative: isNative,
            resolvedFg: resolvedFg,
            action: action
        )
    }
}

// MARK: - Menu Toggle View

struct SwiftUIMenuToggleView: View {
    let label: String
    @State var isOn: Bool
    let resolvedFg: Color
    let action: () -> Void

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
    let resolvedFg: Color
    let action: () -> Void

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
