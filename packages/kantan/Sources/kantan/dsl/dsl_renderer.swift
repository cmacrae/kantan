import AppKit
import SwiftUI

// MARK: - Default Text Color Environment Key

/// Custom environment key for propagating the theme's foreground color into
/// DSL-rendered popup/menu views. Falls back to `.primary` when no theme is set.
private struct DefaultTextColorKey: EnvironmentKey {
  static let defaultValue: Color = .primary
}

extension EnvironmentValues {
  var defaultTextColor: Color {
    get { self[DefaultTextColorKey.self] }
    set { self[DefaultTextColorKey.self] = newValue }
  }
}

// MARK: - Color Parsing

/// Resolve a color string from a node property. Supports named system colors
/// and hex color strings.
private func resolveColor(
  _ colorString: String?, isNative: Bool, fallback: Color = .primary
) -> Color {
  guard let colorString = colorString, !colorString.isEmpty else { return fallback }
  switch colorString.lowercased() {
  case "primary": return .primary
  case "secondary": return .secondary
  case "accent": return .accentColor
  case "red": return .red
  case "orange": return .orange
  case "yellow": return .yellow
  case "green": return .green
  case "blue": return .blue
  case "purple": return .purple
  case "pink": return .pink
  case "gray", "grey": return .gray
  case "white": return .white
  case "black": return .black
  case "clear": return .clear
  default:
    return dslColorFromHex(colorString) ?? fallback
  }
}

/// Map a `TextWeight` enum to a SwiftUI `Font.Weight`.
private func dslFontWeight(from weight: TextWeight?) -> Font.Weight {
  guard let weight = weight else { return .regular }
  switch weight {
  case .ultraLight: return .ultraLight
  case .thin: return .thin
  case .light: return .light
  case .regular: return .regular
  case .medium: return .medium
  case .semibold: return .semibold
  case .bold: return .bold
  case .heavy: return .heavy
  case .black: return .black
  }
}

/// Map a `ViewAlignment` to a SwiftUI `HorizontalAlignment`.
private func horizontalAlignment(from alignment: ViewAlignment?) -> HorizontalAlignment {
  guard let alignment = alignment else { return .leading }
  switch alignment {
  case .leading, .topLeading, .bottomLeading: return .leading
  case .center, .top, .bottom: return .center
  case .trailing, .topTrailing, .bottomTrailing: return .trailing
  }
}

/// Map a `ViewAlignment` to a SwiftUI `VerticalAlignment`.
private func verticalAlignment(from alignment: ViewAlignment?) -> VerticalAlignment {
  guard let alignment = alignment else { return .center }
  switch alignment {
  case .top, .topLeading, .topTrailing: return .top
  case .center, .leading, .trailing: return .center
  case .bottom, .bottomLeading, .bottomTrailing: return .bottom
  }
}

/// Map a `ViewAlignment` to a SwiftUI `Alignment` (for ZStack).
private func combinedAlignment(from alignment: ViewAlignment?) -> Alignment {
  guard let alignment = alignment else { return .center }
  switch alignment {
  case .topLeading: return .topLeading
  case .top: return .top
  case .topTrailing: return .topTrailing
  case .leading: return .leading
  case .center: return .center
  case .trailing: return .trailing
  case .bottomLeading: return .bottomLeading
  case .bottom: return .bottom
  case .bottomTrailing: return .bottomTrailing
  }
}

/// Map a `TextAlignment` (from view_node) to a SwiftUI `SwiftUI.TextAlignment`.
private func swiftUITextAlignment(from align: DSLTextAlignment?) -> SwiftUI.TextAlignment {
  guard let align = align else { return .leading }
  switch align {
  case .leading: return .leading
  case .center: return .center
  case .trailing: return .trailing
  }
}

/// Resolve a template string to a `Double`, returning nil if resolution or
/// parsing fails.
private func resolveDouble(_ template: String, resolver: TemplateResolver) -> Double? {
  let resolved = resolver.resolve(template)
  return Double(resolved)
}

// MARK: - ViewNode Common Properties Accessor

extension ViewNode {
  /// Access the `CommonNodeProperties` for any node case.
  var common: CommonNodeProperties {
    switch self {
    case .vstack(_, _, _, let c),
      .hstack(_, _, _, _, let c),
      .zstack(_, _, let c),
      .scroll(_, _, let c),
      .spacer(_, let c),
      .group(_, let c),
      .text(_, _, _, _, _, _, _, let c),
      .icon(_, _, _, _, let c),
      .image(_, _, _, _, let c),
      .divider(let c),
      .header(_, let c),
      .rect(_, _, _, _, _, _, let c),
      .circle(_, _, _, _, let c),
      .capsule(_, _, _, let c),
      .action(_, _, _, _, let c),
      .check(_, _, _, _, let c),
      .toggle(_, _, _, let c),
      .button(_, _, _, _, let c),
      .foreach(_, _, let c),
      .`if`(_, _, _, let c),
      .progress(_, _, _, _, let c),
      .gauge(_, _, _, _, _, let c),
      .badge(_, _, _, let c),
      .grid(_, _, _, let c):
      return c
    }
  }
}

// MARK: - Max Recursion Depth

private let maxRecursionDepth = 32

// MARK: - DSL Renderer View

/// Recursive SwiftUI view that interprets a `ViewNode` tree and renders
/// it as native SwiftUI. Used inside popup panels (NSPanel with NSHostingView)
/// to render plugin-defined view trees.
struct DSLRendererView: View {
  let node: ViewNode
  let resolver: TemplateResolver
  let isNative: Bool
  let dismissHandler: () -> Void
  var depth: Int = 0
  @Environment(\.defaultTextColor) private var defaultTextColor

  var body: some View {
    if depth > maxRecursionDepth {
      EmptyView()
    } else {
      renderNode(node)
    }
  }

  // MARK: - Node Dispatch

  @ViewBuilder
  private func renderNode(_ node: ViewNode) -> some View {
    let content = nodeContent(node)
    applyCommonProperties(content, properties: node.common)
  }

  @ViewBuilder
  private func nodeContent(_ node: ViewNode) -> some View {
    switch node {
    // Layout
    case .vstack(let spacing, let alignment, let children, _):
      renderVStack(spacing: spacing, alignment: alignment, children: children)
    case .hstack(let spacing, let alignment, let children, let command, _):
      renderHStack(spacing: spacing, alignment: alignment, children: children, command: command)
    case .zstack(let alignment, let children, _):
      renderZStack(alignment: alignment, children: children)
    case .scroll(let axis, let children, _):
      renderScroll(axis: axis, children: children)
    case .spacer(let minLength, _):
      renderSpacer(minLength: minLength)
    case .group(let children, _):
      renderGroup(children: children)

    // Content
    case .text(
      let content, let size, let weight, let style, let color, let align,
      let strikethrough, _):
      renderText(
        content: content, size: size, weight: weight, style: style,
        color: color, align: align, strikethrough: strikethrough)
    case .icon(let name, let size, let color, let style, _):
      renderIcon(name: name, size: size, color: color, style: style)
    case .image(let url, let width, let height, let cornerRadius, _):
      renderImage(url: url, width: width, height: height, cornerRadius: cornerRadius)
    case .divider:
      renderDivider()
    case .header(let content, _):
      renderHeader(content: content)

    // Shape
    case .rect(
      let width, let height, let color, let cornerRadius,
      let strokeColor, let strokeWidth, _):
      renderRect(
        width: width, height: height, color: color,
        cornerRadius: cornerRadius, strokeColor: strokeColor, strokeWidth: strokeWidth)
    case .circle(let size, let color, let strokeColor, let strokeWidth, _):
      renderCircle(size: size, color: color, strokeColor: strokeColor, strokeWidth: strokeWidth)
    case .capsule(let width, let height, let color, _):
      renderCapsule(width: width, height: height, color: color)

    // Interactive
    case .action(let label, let icon, let command, _, _):
      DSLActionView(
        label: label, icon: icon, command: command,
        resolver: resolver, isNative: isNative, dismissHandler: dismissHandler)
    case .check(let label, let checked, let command, let uncheckedCommand, _):
      DSLCheckView(
        label: label, checked: checked, command: command,
        uncheckedCommand: uncheckedCommand,
        resolver: resolver, isNative: isNative, dismissHandler: dismissHandler)
    case .toggle(let label, let on, let command, _):
      DSLToggleView(
        label: label, on: on, command: command,
        resolver: resolver, isNative: isNative, dismissHandler: dismissHandler)
    case .button(let label, let icon, let command, let style, _):
      DSLButtonView(
        label: label, icon: icon, command: command, style: style,
        resolver: resolver, isNative: isNative, dismissHandler: dismissHandler)

    // Data
    case .foreach(let items, let child, _):
      renderForeach(items: items, child: child)
    case .`if`(let condition, let thenNode, let elseNode, _):
      renderIf(condition: condition, thenNode: thenNode, elseNode: elseNode)

    // Advanced
    case .progress(let value, let color, let trackColor, let style, _):
      renderProgress(value: value, color: color, trackColor: trackColor, style: style)
    case .gauge(let value, let min, let max, let label, let color, _):
      renderGauge(value: value, min: min, max: max, label: label, color: color)
    case .badge(let content, let color, let textColor, _):
      renderBadge(content: content, color: color, textColor: textColor)
    case .grid(let columns, let spacing, let children, _):
      renderGrid(columns: columns, spacing: spacing, children: children)
    }
  }

  // MARK: - Common Properties

  @ViewBuilder
  private func applyCommonProperties<Content: View>(
    _ content: Content, properties: CommonNodeProperties
  ) -> some View {
    content
      .modifier(VisibilityModifier(visible: properties.visible, resolver: resolver))
      .modifier(PaddingModifier(padding: properties.padding))
      .modifier(FrameModifier(frame: properties.frame))
      .modifier(
        BackgroundModifier(
          background: properties.background,
          cornerRadius: properties.cornerRadius,
          isNative: isNative,
          resolver: resolver
        )
      )
      .modifier(OpacityModifier(opacity: properties.opacity))
  }

  // MARK: - Layout Nodes

  @ViewBuilder
  private func renderVStack(
    spacing: Double?, alignment: ViewAlignment?, children: [ViewNode]
  ) -> some View {
    VStack(
      alignment: horizontalAlignment(from: alignment),
      spacing: spacing.map { CGFloat($0) }
    ) {
      renderChildren(children)
    }
  }

  @ViewBuilder
  private func renderHStack(
    spacing: Double?, alignment: ViewAlignment?, children: [ViewNode], command: String? = nil
  ) -> some View {
    let resolvedCommand = command.map { resolver.resolve($0) }
    let hasCommand = !(resolvedCommand?.isEmpty ?? true)
    DSLClickableHStack(
      spacing: spacing, alignment: verticalAlignment(from: alignment),
      command: hasCommand ? resolvedCommand : nil,
      environment: resolver.commandEnvironment,
      isNative: isNative, dismissHandler: dismissHandler
    ) {
      renderChildren(children)
    }
  }

  @ViewBuilder
  private func renderZStack(alignment: ViewAlignment?, children: [ViewNode]) -> some View {
    ZStack(alignment: combinedAlignment(from: alignment)) {
      renderChildren(children)
    }
  }

  @ViewBuilder
  private func renderScroll(axis: ScrollAxis?, children: [ViewNode]) -> some View {
    let axisSet: Axis.Set = axis == .horizontal ? .horizontal : .vertical
    ScrollView(axisSet) {
      if axisSet == .vertical {
        VStack(spacing: 0) {
          renderChildren(children)
        }
      } else {
        HStack(spacing: 0) {
          renderChildren(children)
        }
      }
    }
  }

  @ViewBuilder
  private func renderSpacer(minLength: Double?) -> some View {
    Spacer(minLength: minLength.map { CGFloat($0) })
  }

  @ViewBuilder
  private func renderGroup(children: [ViewNode]) -> some View {
    Group {
      renderChildren(children)
    }
  }

  @ViewBuilder
  private func renderChildren(_ children: [ViewNode]) -> some View {
    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
      DSLRendererView(
        node: child, resolver: resolver, isNative: isNative,
        dismissHandler: dismissHandler, depth: depth + 1)
    }
  }

  // MARK: - Content Nodes

  @ViewBuilder
  private func renderText(
    content: String, size: Double?, weight: TextWeight?,
    style: TextStyle?, color: String?, align: DSLTextAlignment?,
    strikethrough: Bool?
  ) -> some View {
    let resolved = resolver.resolve(content)
    let fontSize = size ?? 13.0
    let fwt = dslFontWeight(from: weight)
    let isSecondary = style == .secondary
    let fgColor = resolveColor(
      color.map { resolver.resolve($0) },
      isNative: isNative,
      fallback: defaultTextColor)

    Text(resolved)
      .font(.system(size: CGFloat(fontSize), weight: fwt))
      .strikethrough(strikethrough == true)
      .foregroundStyle(fgColor)
      .opacity(isSecondary ? 0.5 : 1.0)
      .multilineTextAlignment(swiftUITextAlignment(from: align))
  }

  @ViewBuilder
  private func renderIcon(
    name: String, size: Double?, color: String?, style: IconStyle?
  ) -> some View {
    let resolvedName = resolver.resolve(name)
    let fontSize = size ?? 13.0
    let fgColor = resolveColor(
      color.map { resolver.resolve($0) },
      isNative: isNative,
      fallback: defaultTextColor)

    if iconFontsAvailable {
      let resolved = resolveIconName(resolvedName)
      if let fontOverride = resolved.fontNameOverride {
        // Bundled icon font glyph — render with the correct font family and scale.
        let scaledSize = Int(round(fontSize * resolved.scaleFactor))
        Text(resolved.glyph)
          .font(
            FontConfig(descriptor: "\(fontOverride):\(scaledSize)", source: .bundled).swiftUIFont
          )
          .foregroundStyle(fgColor)
      } else if resolvedName.allSatisfy({ $0.isASCII }) && !resolvedName.isEmpty {
        Image(systemName: resolvedName)
          .font(.system(size: CGFloat(fontSize)))
          .foregroundStyle(fgColor)
      } else {
        Text(resolved.glyph)
          .font(.system(size: CGFloat(fontSize)))
          .foregroundStyle(fgColor)
      }
    } else if resolvedName.allSatisfy({ $0.isASCII }) && !resolvedName.isEmpty {
      // No bundled fonts — treat ASCII names as SF Symbols.
      Image(systemName: resolvedName)
        .font(.system(size: CGFloat(fontSize)))
        .foregroundStyle(fgColor)
    } else {
      // Non-ASCII literal glyph — render as text.
      Text(resolvedName)
        .font(.system(size: CGFloat(fontSize)))
        .foregroundStyle(fgColor)
    }
  }

  @ViewBuilder
  private func renderImage(
    url: String, width: Double?, height: Double?, cornerRadius: Double?
  ) -> some View {
    let resolvedURL = resolver.resolve(url)
    let radius = cornerRadius ?? 0

    if let parsedURL = URL(string: resolvedURL) {
      AsyncImage(url: parsedURL) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(
              width: width.map { CGFloat($0) },
              height: height.map { CGFloat($0) }
            )
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(radius)))
        case .failure:
          Image(systemName: "photo")
            .foregroundStyle(.secondary)
            .frame(
              width: width.map { CGFloat($0) },
              height: height.map { CGFloat($0) }
            )
        case .empty:
          ProgressView()
            .frame(
              width: width.map { CGFloat($0) },
              height: height.map { CGFloat($0) }
            )
        @unknown default:
          EmptyView()
        }
      }
    } else {
      Image(systemName: "photo")
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func renderDivider() -> some View {
    Divider()
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
  }

  @ViewBuilder
  private func renderHeader(content: String) -> some View {
    let resolved = resolver.resolve(content)
    Text(resolved)
      .font(.system(size: 12, weight: .bold))
      .foregroundStyle(defaultTextColor)
      .frame(height: 22, alignment: .leading)
  }

  // MARK: - Shape Nodes

  @ViewBuilder
  private func renderRect(
    width: Double?, height: Double?, color: String?,
    cornerRadius: Double?, strokeColor: String?, strokeWidth: Double?
  ) -> some View {
    let fillColor = resolveColor(
      color.map { resolver.resolve($0) },
      isNative: isNative,
      fallback: .clear)
    let radius = CGFloat(cornerRadius ?? 0)
    let w = width.map { CGFloat($0) }
    let h = height.map { CGFloat($0) }

    if let sc = strokeColor.map({ resolver.resolve($0) }) {
      let stroke = resolveColor(sc, isNative: isNative, fallback: .clear)
      let sw = CGFloat(strokeWidth ?? 1.0)
      RoundedRectangle(cornerRadius: radius)
        .fill(fillColor)
        .overlay(
          RoundedRectangle(cornerRadius: radius)
            .strokeBorder(stroke, lineWidth: sw)
        )
        .frame(width: w, height: h)
    } else {
      RoundedRectangle(cornerRadius: radius)
        .fill(fillColor)
        .frame(width: w, height: h)
    }
  }

  @ViewBuilder
  private func renderCircle(
    size: Double?, color: String?, strokeColor: String?, strokeWidth: Double?
  ) -> some View {
    let fillColor = resolveColor(
      color.map { resolver.resolve($0) },
      isNative: isNative,
      fallback: .clear)
    let s = size.map { CGFloat($0) }

    if let sc = strokeColor.map({ resolver.resolve($0) }) {
      let stroke = resolveColor(sc, isNative: isNative, fallback: .clear)
      let sw = CGFloat(strokeWidth ?? 1.0)
      Circle()
        .fill(fillColor)
        .overlay(Circle().strokeBorder(stroke, lineWidth: sw))
        .frame(width: s, height: s)
    } else {
      Circle()
        .fill(fillColor)
        .frame(width: s, height: s)
    }
  }

  @ViewBuilder
  private func renderCapsule(width: Double?, height: Double?, color: String?) -> some View {
    let fillColor = resolveColor(
      color.map { resolver.resolve($0) },
      isNative: isNative,
      fallback: .clear)
    let w = width.map { CGFloat($0) }
    let h = height.map { CGFloat($0) }

    Capsule()
      .fill(fillColor)
      .frame(width: w, height: h)
  }

  // MARK: - Data Nodes

  @ViewBuilder
  private func renderForeach(items: String, child: ViewNode) -> some View {
    let dataItems = resolver.data[items] ?? []
    ForEach(Array(dataItems.enumerated()), id: \.offset) { _, element in
      DSLForeachElementView(
        element: element, child: child, resolver: resolver,
        isNative: isNative, dismissHandler: dismissHandler, depth: depth + 1)
    }
  }

  @ViewBuilder
  private func renderIf(condition: String, thenNode: ViewNode, elseNode: ViewNode?) -> some View {
    if dslEvaluateTruthy(condition, resolver: resolver) {
      DSLRendererView(
        node: thenNode, resolver: resolver, isNative: isNative,
        dismissHandler: dismissHandler, depth: depth + 1)
    } else if let elseNode = elseNode {
      DSLRendererView(
        node: elseNode, resolver: resolver, isNative: isNative,
        dismissHandler: dismissHandler, depth: depth + 1)
    }
  }

  // MARK: - Advanced Nodes

  @ViewBuilder
  private func renderProgress(
    value: String, color: String?, trackColor: String?, style: ProgressStyle?
  ) -> some View {
    let resolvedValue = resolveDouble(value, resolver: resolver) ?? 0.0
    let clampedValue = min(max(resolvedValue, 0.0), 1.0)
    let track = resolveColor(
      trackColor.map { resolver.resolve($0) },
      isNative: isNative,
      fallback: isNative ? Color.secondary.opacity(0.2) : Color.primary.opacity(0.15))
    let tint = resolveColor(
      color.map { resolver.resolve($0) },
      isNative: isNative,
      fallback: .accentColor)

    if style == .ring {
      ZStack {
        SwiftUI.Circle()
          .stroke(track, lineWidth: 4)
        SwiftUI.Circle()
          .trim(from: 0, to: clampedValue)
          .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
    } else {
      // Bar style (default)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 2)
            .fill(track)
            .frame(height: 6)
          RoundedRectangle(cornerRadius: 2)
            .fill(tint)
            .frame(width: geo.size.width * clampedValue, height: 6)
        }
      }
      .frame(height: 6)
    }
  }

  @ViewBuilder
  private func renderGauge(
    value: String, min: Double?, max: Double?, label: String?, color: String?
  ) -> some View {
    let resolvedValue = resolveDouble(value, resolver: resolver) ?? 0.0
    let minVal = min ?? 0.0
    let maxVal = max ?? 1.0
    let resolvedLabel = label.map { resolver.resolve($0) } ?? ""
    let tint = resolveColor(
      color.map { resolver.resolve($0) },
      isNative: isNative,
      fallback: .accentColor)

    Gauge(value: resolvedValue, in: minVal...maxVal) {
      Text(resolvedLabel)
        .font(.system(size: 11))
    }
    .tint(tint)
  }

  @ViewBuilder
  private func renderBadge(content: String, color: String?, textColor: String?) -> some View {
    let resolved = resolver.resolve(content)
    let bgColor = resolveColor(
      color.map { resolver.resolve($0) },
      isNative: isNative,
      fallback: .accentColor)
    let fgColor = resolveColor(
      textColor.map { resolver.resolve($0) },
      isNative: isNative,
      fallback: .white)

    Text(resolved)
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(fgColor)
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .background(Capsule().fill(bgColor))
  }

  @ViewBuilder
  private func renderGrid(columns: Int?, spacing: Double?, children: [ViewNode]) -> some View {
    let columnCount = columns ?? 2
    let gap = spacing ?? 8.0
    let gridColumns = Array(
      repeating: GridItem(.flexible(), spacing: CGFloat(gap)),
      count: columnCount)

    LazyVGrid(columns: gridColumns, spacing: CGFloat(gap)) {
      renderChildren(children)
    }
  }
}

// MARK: - Foreach Element View

/// Wraps a single `foreach` iteration. Creates a child resolver with the
/// element's values pushed onto the scope stack, so variable resolution
/// sees the foreach element's keys first.
private struct DSLForeachElementView: View {
  let element: [String: String]
  let child: ViewNode
  let resolver: TemplateResolver
  let isNative: Bool
  let dismissHandler: () -> Void
  let depth: Int

  var body: some View {
    DSLRendererView(
      node: child, resolver: scopedResolver, isNative: isNative,
      dismissHandler: dismissHandler, depth: depth
    )
  }

  private var scopedResolver: TemplateResolver {
    let r = TemplateResolver(
      variables: resolver.variables, data: resolver.data)
    r.commandEnvironment = resolver.commandEnvironment
    // Copy existing scope stack and push current element
    for scope in resolver.scopeStack {
      r.pushScope(scope)
    }
    r.pushScope(element)
    return r
  }
}

// MARK: - Interactive Node Views

/// HStack that optionally becomes clickable when a command is provided.
/// Without a command it renders as a plain HStack.
private struct DSLClickableHStack<Content: View>: View {
  let spacing: Double?
  let alignment: VerticalAlignment
  let command: String?
  let environment: [String: String]
  let isNative: Bool
  let dismissHandler: () -> Void
  @ViewBuilder let content: Content
  @State private var isHovered = false

  var body: some View {
    if let command = command, !command.isEmpty {
      HStack(alignment: alignment, spacing: spacing.map { CGFloat($0) }) {
        content
      }
      .background(
        RoundedRectangle(cornerRadius: 4)
          .fill(
            isHovered
              ? Color(nsColor: .selectedContentBackgroundColor).opacity(isNative ? 1.0 : 0.3)
              : .clear
          )
      )
      .contentShape(Rectangle())
      .onHover { hovering in isHovered = hovering }
      .onTapGesture {
        dismissHandler()
        runCommand(command, environment: environment)
      }
    } else {
      HStack(alignment: alignment, spacing: spacing.map { CGFloat($0) }) {
        content
      }
    }
  }
}

/// Hoverable action row: icon + label, highlights on hover, runs command on tap.
private struct DSLActionView: View {
  let label: String?
  let icon: String?
  let command: String?
  let resolver: TemplateResolver
  let isNative: Bool
  let dismissHandler: () -> Void
  @State private var isHovered = false
  @Environment(\.defaultTextColor) private var defaultTextColor

  var body: some View {
    let resolvedLabel = resolver.resolve(label ?? "")
    let resolvedIcon = icon.map { resolver.resolve($0) }

    HStack(spacing: 8) {
      if let iconName = resolvedIcon, !iconName.isEmpty {
        if iconFontsAvailable {
          let resolved = resolveIconName(iconName)
          if let fontOverride = resolved.fontNameOverride {
            let scaledSize = Int(round(13.0 * resolved.scaleFactor))
            Text(resolved.glyph)
              .font(
                FontConfig(descriptor: "\(fontOverride):\(scaledSize)", source: .bundled)
                  .swiftUIFont
              )
              .foregroundStyle(hoverFgColor)
              .frame(width: 16, alignment: .center)
          } else if iconName.allSatisfy({ $0.isASCII }) {
            Image(systemName: iconName)
              .font(.system(size: 13))
              .foregroundStyle(hoverFgColor)
              .frame(width: 16, alignment: .center)
          } else {
            Text(resolved.glyph)
              .font(.system(size: 13))
              .foregroundStyle(hoverFgColor)
              .frame(width: 16, alignment: .center)
          }
        } else if iconName.allSatisfy({ $0.isASCII }) {
          Image(systemName: iconName)
            .font(.system(size: 13))
            .foregroundStyle(hoverFgColor)
            .frame(width: 16, alignment: .center)
        } else {
          Text(iconName)
            .font(.system(size: 13))
            .foregroundStyle(hoverFgColor)
            .frame(width: 16, alignment: .center)
        }
      }
      Text(resolvedLabel)
        .font(.system(size: 13))
        .foregroundStyle(hoverFgColor)
      Spacer()
    }
    .padding(.horizontal, 14)
    .frame(height: 28)
    .background(
      RoundedRectangle(cornerRadius: 4)
        .fill(
          isHovered
            ? Color(nsColor: .selectedContentBackgroundColor).opacity(isNative ? 1.0 : 0.3)
            : .clear
        )
    )
    .onHover { hovering in isHovered = hovering }
    .onTapGesture {
      dismissHandler()
      guard let command = command, !command.isEmpty else { return }
      let resolved = resolver.resolve(command)
      runCommand(resolved, environment: resolver.commandEnvironment)
    }
  }

  private var hoverFgColor: Color {
    if isHovered && isNative {
      return .white
    }
    return defaultTextColor
  }
}

/// Check item: circle/checkmark.circle.fill + label (strikethrough when checked).
private struct DSLCheckView: View {
  let label: String?
  let checked: String?
  let command: String?
  let uncheckedCommand: String?
  let resolver: TemplateResolver
  let isNative: Bool
  let dismissHandler: () -> Void
  @State private var isToggled = false
  @Environment(\.defaultTextColor) private var defaultTextColor

  var body: some View {
    let resolvedLabel = resolver.resolve(label ?? "")
    let initialChecked = checked.map { resolver.resolveBool($0) } ?? false
    let isChecked = isToggled != initialChecked
    let fgColor = defaultTextColor

    HStack(spacing: 8) {
      Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(isChecked ? fgColor.opacity(0.4) : fgColor)
        .imageScale(.medium)
      Text(resolvedLabel)
        .font(.system(size: 13))
        .strikethrough(isChecked)
        .foregroundStyle(isChecked ? fgColor.opacity(0.4) : fgColor)
      Spacer()
    }
    .padding(.horizontal, 14)
    .frame(height: 26)
    .contentShape(Rectangle())
    .onTapGesture {
      // Pick the right command based on current visual state:
      // If currently unchecked → checking → use command
      // If currently checked → unchecking → use uncheckedCommand (fall back to command)
      let cmd = isChecked ? (uncheckedCommand ?? command) : command
      isToggled.toggle()
      guard let cmd = cmd, !cmd.isEmpty else { return }
      let resolved = resolver.resolve(cmd)
      runCommand(resolved, environment: resolver.commandEnvironment)
    }
  }
}

/// Toggle switch with label.
private struct DSLToggleView: View {
  let label: String?
  let on: String?
  let command: String?
  let resolver: TemplateResolver
  let isNative: Bool
  let dismissHandler: () -> Void
  @State private var isOn: Bool
  @Environment(\.defaultTextColor) private var defaultTextColor

  init(
    label: String?, on: String?, command: String?, resolver: TemplateResolver,
    isNative: Bool, dismissHandler: @escaping () -> Void
  ) {
    self.label = label
    self.on = on
    self.command = command
    self.resolver = resolver
    self.isNative = isNative
    self.dismissHandler = dismissHandler
    _isOn = State(initialValue: on.map { resolver.resolveBool($0) } ?? false)
  }

  /// The switch's state, running the command only when it's flipped.
  private var switchState: Binding<Bool> {
    Binding(
      get: { isOn },
      set: { newValue in
        isOn = newValue
        dismissHandler()
        guard let command, !command.isEmpty else { return }
        runCommand(resolver.resolve(command), environment: resolver.commandEnvironment)
      })
  }

  var body: some View {
    Toggle(resolver.resolve(label ?? ""), isOn: switchState)
      .toggleStyle(.switch)
      .controlSize(.small)
      .tint(.accentColor)
      .foregroundStyle(defaultTextColor)
      .padding(.horizontal, 14)
      .frame(height: 26)
  }
}

/// Styled button with label and optional icon.
private struct DSLButtonView: View {
  let label: String?
  let icon: String?
  let command: String?
  let style: DSLButtonStyle?
  let resolver: TemplateResolver
  let isNative: Bool
  let dismissHandler: () -> Void

  var body: some View {
    let resolvedLabel = label.map { resolver.resolve($0) }
    let resolvedIcon = icon.map { resolver.resolve($0) }

    Button(action: {
      dismissHandler()
      guard let command = command, !command.isEmpty else { return }
      let resolved = resolver.resolve(command)
      runCommand(resolved, environment: resolver.commandEnvironment)
    }) {
      HStack(spacing: 6) {
        if let iconName = resolvedIcon, !iconName.isEmpty {
          if iconFontsAvailable {
            let resolved = resolveIconName(iconName)
            if let fontOverride = resolved.fontNameOverride {
              let scaledSize = Int(round(12.0 * resolved.scaleFactor))
              Text(resolved.glyph)
                .font(
                  FontConfig(descriptor: "\(fontOverride):\(scaledSize)", source: .bundled)
                    .swiftUIFont)
            } else if iconName.allSatisfy({ $0.isASCII }) {
              Image(systemName: iconName)
                .font(.system(size: 12))
            } else {
              Text(resolved.glyph)
                .font(.system(size: 12))
            }
          } else if iconName.allSatisfy({ $0.isASCII }) {
            Image(systemName: iconName)
              .font(.system(size: 12))
          } else {
            Text(iconName)
              .font(.system(size: 12))
          }
        }
        if let label = resolvedLabel {
          Text(label)
            .font(.system(size: 13))
        }
      }
    }
    .buttonStyle(.borderless)
  }
}

// MARK: - View Modifiers

/// Hide the node when the `visible` variable resolves to a falsy value.
private struct VisibilityModifier: ViewModifier {
  let visible: String?
  let resolver: TemplateResolver

  private var isVisible: Bool {
    guard let visibleKey = visible else { return true }
    return dslEvaluateTruthy(visibleKey, resolver: resolver)
  }

  func body(content: Content) -> some View {
    if isVisible {
      content
    }
  }
}

/// Apply padding from the node's common properties.
/// Supports uniform (single number) or per-edge ([top, leading, bottom, trailing]).
private struct PaddingModifier: ViewModifier {
  let padding: Padding?

  func body(content: Content) -> some View {
    if let padding = padding {
      switch padding {
      case .uniform(let value):
        content.padding(CGFloat(value))
      case .edges(let top, let leading, let bottom, let trailing):
        content.padding(
          EdgeInsets(
            top: CGFloat(top), leading: CGFloat(leading),
            bottom: CGFloat(bottom), trailing: CGFloat(trailing)))
      }
    } else {
      content
    }
  }
}

/// Apply explicit frame constraints from the node's common properties.
private struct FrameModifier: ViewModifier {
  let frame: FrameProperties?

  func body(content: Content) -> some View {
    if let frame = frame {
      content
        .frame(
          minWidth: frame.minW.map { CGFloat($0) },
          idealWidth: nil,
          maxWidth: frame.maxW.map { CGFloat($0) },
          minHeight: frame.minH.map { CGFloat($0) },
          idealHeight: nil,
          maxHeight: frame.maxH.map { CGFloat($0) }
        )
        .frame(
          width: frame.w.map { CGFloat($0) },
          height: frame.h.map { CGFloat($0) }
        )
    } else {
      content
    }
  }
}

/// Apply background color (with optional corner radius).
private struct BackgroundModifier: ViewModifier {
  let background: String?
  let cornerRadius: Double?
  let isNative: Bool
  let resolver: TemplateResolver

  func body(content: Content) -> some View {
    if let bgString = background {
      let resolved = resolver.resolve(bgString)
      let bgColor = resolveColor(resolved, isNative: isNative, fallback: .clear)
      let radius = CGFloat(cornerRadius ?? 0)
      if radius > 0 {
        content.background(RoundedRectangle(cornerRadius: radius).fill(bgColor))
      } else {
        content.background(bgColor)
      }
    } else {
      content
    }
  }
}

/// Apply opacity from the node's common properties.
private struct OpacityModifier: ViewModifier {
  let opacity: Double?

  func body(content: Content) -> some View {
    if let opacity = opacity {
      content.opacity(opacity)
    } else {
      content
    }
  }
}
