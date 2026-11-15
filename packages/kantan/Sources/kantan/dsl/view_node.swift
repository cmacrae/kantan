import Foundation

// MARK: - Common Node Properties

/// Shared optional properties that any node can carry.
/// The renderer applies these after laying out the node-specific content.
struct CommonNodeProperties: Sendable, Decodable {
  let padding: Padding?
  let frame: FrameProperties?
  let opacity: Double?
  let background: String?
  let cornerRadius: Double?
  let visible: String?

  enum CodingKeys: String, CodingKey {
    case padding, frame, opacity, background, cornerRadius, visible
  }

  init(
    padding: Padding? = nil,
    frame: FrameProperties? = nil,
    opacity: Double? = nil,
    background: String? = nil,
    cornerRadius: Double? = nil,
    visible: String? = nil
  ) {
    self.padding = padding
    self.frame = frame
    self.opacity = opacity
    self.background = background
    self.cornerRadius = cornerRadius
    self.visible = visible
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.padding = try container.decodeIfPresent(Padding.self, forKey: .padding)
    self.frame = try container.decodeIfPresent(FrameProperties.self, forKey: .frame)
    self.opacity = try container.decodeIfPresent(Double.self, forKey: .opacity)
    self.background = try container.decodeIfPresent(String.self, forKey: .background)
    self.cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius)
    if let literal = try? container.decodeIfPresent(Bool.self, forKey: .visible) {
      self.visible = Self.visible(literal: literal)
    } else {
      self.visible = try container.decodeIfPresent(String.self, forKey: .visible)
    }
  }

  /// The `visible` property for a literal boolean: none for true, so the
  /// node always shows, and an empty variable name, which is always falsy,
  /// for false.
  static func visible(literal: Bool) -> String? {
    literal ? nil : ""
  }

  static let empty = CommonNodeProperties()
}

// MARK: - Padding

/// Padding expressed as a uniform value or per-edge values via named keys.
/// Per-edge form uses `{top, leading, bottom, trailing}`; missing keys default to 0.
/// Positional arrays are rejected to avoid CSS-axis-order confusion (CSS uses
/// `top, right, bottom, left`; SwiftUI uses leading/trailing for RTL safety).
enum Padding: Sendable, Decodable {
  case uniform(Double)
  case edges(top: Double, leading: Double, bottom: Double, trailing: Double)

  private enum EdgeKeys: String, CodingKey {
    case top, leading, bottom, trailing
  }

  init(from decoder: Decoder) throws {
    if let single = try? decoder.singleValueContainer() {
      if let value = try? single.decode(Double.self) {
        self = .uniform(value)
        return
      }
      if (try? single.decode([Double].self)) != nil {
        throw DecodingError.dataCorruptedError(
          in: single,
          debugDescription:
            "Padding arrays are not supported. Use a number for uniform padding, "
            + "or `{top, leading, bottom, trailing}` for per-edge padding.")
      }
    }
    let container = try decoder.container(keyedBy: EdgeKeys.self)
    let top = try container.decodeIfPresent(Double.self, forKey: .top) ?? 0
    let leading = try container.decodeIfPresent(Double.self, forKey: .leading) ?? 0
    let bottom = try container.decodeIfPresent(Double.self, forKey: .bottom) ?? 0
    let trailing = try container.decodeIfPresent(Double.self, forKey: .trailing) ?? 0
    self = .edges(top: top, leading: leading, bottom: bottom, trailing: trailing)
  }
}

// MARK: - Frame Properties

/// Constraint-based frame sizing.
struct FrameProperties: Sendable, Decodable {
  let w: Double?
  let h: Double?
  let maxW: Double?
  let maxH: Double?
  let minW: Double?
  let minH: Double?
}

// MARK: - Alignment

/// Alignment for stacks and zstack.
enum ViewAlignment: String, Sendable, Decodable {
  case leading, trailing, center, top, bottom
  case topLeading, topTrailing, bottomLeading, bottomTrailing
}

// MARK: - Scroll Axis

enum ScrollAxis: String, Sendable, Decodable {
  case vertical, horizontal
}

// MARK: - Text Weight

enum TextWeight: String, Sendable, Decodable {
  case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black
}

// MARK: - Text Style

enum TextStyle: String, Sendable, Decodable {
  case normal, italic, monospaced, secondary
}

// MARK: - Text Alignment

enum DSLTextAlignment: String, Sendable, Decodable {
  case leading, center, trailing
}

// MARK: - Icon Style

enum IconStyle: String, Sendable, Decodable {
  case regular, filled
}

// MARK: - Button Style

enum DSLButtonStyle: String, Sendable, Decodable {
  case `default`, bordered, borderless, plain
}

// MARK: - Progress Style

enum ProgressStyle: String, Sendable, Decodable {
  case bar, ring
}

// MARK: - ViewNode

/// A declarative node in the view tree.
///
/// Each case represents a distinct UI element that plugins and native modules
/// can emit. Renderers switch exhaustively over the cases to produce platform
/// views. Recursive cases (`foreach`, `if`) use `indirect` to allow the enum
/// to reference itself without boxing overhead at the call site.
enum ViewNode: Sendable {
  // MARK: Layout Nodes

  case vstack(
    spacing: Double?,
    alignment: ViewAlignment?,
    children: [ViewNode],
    common: CommonNodeProperties
  )

  case hstack(
    spacing: Double?,
    alignment: ViewAlignment?,
    children: [ViewNode],
    command: String?,
    common: CommonNodeProperties
  )

  case zstack(
    alignment: ViewAlignment?,
    children: [ViewNode],
    common: CommonNodeProperties
  )

  case scroll(
    axis: ScrollAxis?,
    children: [ViewNode],
    common: CommonNodeProperties
  )

  case spacer(
    minLength: Double?,
    common: CommonNodeProperties
  )

  case group(
    children: [ViewNode],
    common: CommonNodeProperties
  )

  // MARK: Content Nodes

  case text(
    content: String,
    size: Double?,
    weight: TextWeight?,
    style: TextStyle?,
    color: String?,
    align: DSLTextAlignment?,
    strikethrough: Bool?,
    common: CommonNodeProperties
  )

  case icon(
    name: String,
    size: Double?,
    color: String?,
    style: IconStyle?,
    common: CommonNodeProperties
  )

  case image(
    url: String,
    width: Double?,
    height: Double?,
    cornerRadius: Double?,
    common: CommonNodeProperties
  )

  case divider(
    common: CommonNodeProperties
  )

  case header(
    content: String,
    common: CommonNodeProperties
  )

  // MARK: Shape Nodes

  case rect(
    width: Double?,
    height: Double?,
    color: String?,
    cornerRadius: Double?,
    strokeColor: String?,
    strokeWidth: Double?,
    common: CommonNodeProperties
  )

  case circle(
    size: Double?,
    color: String?,
    strokeColor: String?,
    strokeWidth: Double?,
    common: CommonNodeProperties
  )

  case capsule(
    width: Double?,
    height: Double?,
    color: String?,
    common: CommonNodeProperties
  )

  // MARK: Interactive Nodes

  case action(
    label: String?,
    icon: String?,
    command: String?,
    iconFont: String?,
    common: CommonNodeProperties
  )

  case check(
    label: String?,
    checked: String?,
    command: String?,
    uncheckedCommand: String?,
    common: CommonNodeProperties
  )

  case toggle(
    label: String?,
    on: String?,
    command: String?,
    common: CommonNodeProperties
  )

  case button(
    label: String?,
    icon: String?,
    command: String?,
    style: DSLButtonStyle?,
    common: CommonNodeProperties
  )

  // MARK: Data Nodes

  indirect case foreach(
    items: String,
    child: ViewNode,
    common: CommonNodeProperties
  )

  indirect case `if`(
    condition: String,
    then: ViewNode,
    `else`: ViewNode?,
    common: CommonNodeProperties
  )

  // MARK: Advanced Nodes

  case progress(
    value: String,
    color: String?,
    trackColor: String?,
    style: ProgressStyle?,
    common: CommonNodeProperties
  )

  case gauge(
    value: String,
    min: Double?,
    max: Double?,
    label: String?,
    color: String?,
    common: CommonNodeProperties
  )

  case badge(
    content: String,
    color: String?,
    textColor: String?,
    common: CommonNodeProperties
  )

  case grid(
    columns: Int?,
    spacing: Double?,
    children: [ViewNode],
    common: CommonNodeProperties
  )
}

// MARK: - ViewNode + Decodable

extension ViewNode: Decodable {
  private enum CodingKeys: String, CodingKey {
    case type

    // Layout
    case spacing, children, alignment, axis, minLength

    // Content
    case content, size, weight, style, color, align, strikethrough
    case name, url, width, height, cornerRadius

    // Shapes
    case strokeColor, strokeWidth

    // Interactive
    case label, icon, command, uncheckedCommand, iconFont, checked, on

    // Data
    case items, child, condition, then, `else`

    // Advanced
    case value, trackColor, min, max, columns, textColor
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)
    let common = try CommonNodeProperties(from: decoder)

    switch type {
    // MARK: Layout
    case "vstack":
      self = .vstack(
        spacing: try container.decodeIfPresent(Double.self, forKey: .spacing),
        alignment: try container.decodeIfPresent(ViewAlignment.self, forKey: .alignment),
        children: try container.decodeIfPresent([ViewNode].self, forKey: .children) ?? [],
        common: common
      )

    case "hstack":
      self = .hstack(
        spacing: try container.decodeIfPresent(Double.self, forKey: .spacing),
        alignment: try container.decodeIfPresent(ViewAlignment.self, forKey: .alignment),
        children: try container.decodeIfPresent([ViewNode].self, forKey: .children) ?? [],
        command: try container.decodeIfPresent(String.self, forKey: .command),
        common: common
      )

    case "zstack":
      self = .zstack(
        alignment: try container.decodeIfPresent(ViewAlignment.self, forKey: .alignment),
        children: try container.decodeIfPresent([ViewNode].self, forKey: .children) ?? [],
        common: common
      )

    case "scroll":
      self = .scroll(
        axis: try container.decodeIfPresent(ScrollAxis.self, forKey: .axis),
        children: try container.decodeIfPresent([ViewNode].self, forKey: .children) ?? [],
        common: common
      )

    case "spacer":
      self = .spacer(
        minLength: try container.decodeIfPresent(Double.self, forKey: .minLength),
        common: common
      )

    case "group":
      self = .group(
        children: try container.decodeIfPresent([ViewNode].self, forKey: .children) ?? [],
        common: common
      )

    // MARK: Content
    case "text":
      self = .text(
        content: try container.decode(String.self, forKey: .content),
        size: try container.decodeIfPresent(Double.self, forKey: .size),
        weight: try container.decodeIfPresent(TextWeight.self, forKey: .weight),
        style: try container.decodeIfPresent(TextStyle.self, forKey: .style),
        color: try container.decodeIfPresent(String.self, forKey: .color),
        align: try container.decodeIfPresent(DSLTextAlignment.self, forKey: .align),
        strikethrough: try container.decodeIfPresent(Bool.self, forKey: .strikethrough),
        common: common
      )

    case "icon":
      self = .icon(
        name: try container.decode(String.self, forKey: .name),
        size: try container.decodeIfPresent(Double.self, forKey: .size),
        color: try container.decodeIfPresent(String.self, forKey: .color),
        style: try container.decodeIfPresent(IconStyle.self, forKey: .style),
        common: common
      )

    case "image":
      self = .image(
        url: try container.decode(String.self, forKey: .url),
        width: try container.decodeIfPresent(Double.self, forKey: .width),
        height: try container.decodeIfPresent(Double.self, forKey: .height),
        cornerRadius: try container.decodeIfPresent(Double.self, forKey: .cornerRadius),
        common: common
      )

    case "divider":
      self = .divider(common: common)

    case "header":
      self = .header(
        content: try container.decode(String.self, forKey: .content),
        common: common
      )

    // MARK: Shapes
    case "rect":
      self = .rect(
        width: try container.decodeIfPresent(Double.self, forKey: .width),
        height: try container.decodeIfPresent(Double.self, forKey: .height),
        color: try container.decodeIfPresent(String.self, forKey: .color),
        cornerRadius: try container.decodeIfPresent(Double.self, forKey: .cornerRadius),
        strokeColor: try container.decodeIfPresent(String.self, forKey: .strokeColor),
        strokeWidth: try container.decodeIfPresent(Double.self, forKey: .strokeWidth),
        common: common
      )

    case "circle":
      self = .circle(
        size: try container.decodeIfPresent(Double.self, forKey: .size),
        color: try container.decodeIfPresent(String.self, forKey: .color),
        strokeColor: try container.decodeIfPresent(String.self, forKey: .strokeColor),
        strokeWidth: try container.decodeIfPresent(Double.self, forKey: .strokeWidth),
        common: common
      )

    case "capsule":
      self = .capsule(
        width: try container.decodeIfPresent(Double.self, forKey: .width),
        height: try container.decodeIfPresent(Double.self, forKey: .height),
        color: try container.decodeIfPresent(String.self, forKey: .color),
        common: common
      )

    // MARK: Interactive
    case "action":
      self = .action(
        label: try container.decodeIfPresent(String.self, forKey: .label),
        icon: try container.decodeIfPresent(String.self, forKey: .icon),
        command: try container.decodeIfPresent(String.self, forKey: .command),
        iconFont: try container.decodeIfPresent(String.self, forKey: .iconFont),
        common: common
      )

    case "check":
      self = .check(
        label: try container.decodeIfPresent(String.self, forKey: .label),
        checked: try container.decodeIfPresent(FlexibleString.self, forKey: .checked)?.value,
        command: try container.decodeIfPresent(String.self, forKey: .command),
        uncheckedCommand: try container.decodeIfPresent(
          String.self, forKey: .uncheckedCommand),
        common: common
      )

    case "toggle":
      self = .toggle(
        label: try container.decodeIfPresent(String.self, forKey: .label),
        on: try container.decodeIfPresent(FlexibleString.self, forKey: .on)?.value,
        command: try container.decodeIfPresent(String.self, forKey: .command),
        common: common
      )

    case "button":
      self = .button(
        label: try container.decodeIfPresent(String.self, forKey: .label),
        icon: try container.decodeIfPresent(String.self, forKey: .icon),
        command: try container.decodeIfPresent(String.self, forKey: .command),
        style: try container.decodeIfPresent(DSLButtonStyle.self, forKey: .style),
        common: common
      )

    // MARK: Data
    case "foreach":
      self = .foreach(
        items: try container.decode(String.self, forKey: .items),
        child: try container.decode(ViewNode.self, forKey: .child),
        common: common
      )

    case "if":
      self = .if(
        condition: try container.decode(String.self, forKey: .condition),
        then: try container.decode(ViewNode.self, forKey: .then),
        else: try container.decodeIfPresent(ViewNode.self, forKey: .else),
        common: common
      )

    // MARK: Advanced
    case "progress":
      self = .progress(
        value: try container.decode(FlexibleString.self, forKey: .value).value,
        color: try container.decodeIfPresent(String.self, forKey: .color),
        trackColor: try container.decodeIfPresent(String.self, forKey: .trackColor),
        style: try container.decodeIfPresent(ProgressStyle.self, forKey: .style),
        common: common
      )

    case "gauge":
      self = .gauge(
        value: try container.decode(FlexibleString.self, forKey: .value).value,
        min: try container.decodeIfPresent(Double.self, forKey: .min),
        max: try container.decodeIfPresent(Double.self, forKey: .max),
        label: try container.decodeIfPresent(String.self, forKey: .label),
        color: try container.decodeIfPresent(String.self, forKey: .color),
        common: common
      )

    case "badge":
      self = .badge(
        content: try container.decode(String.self, forKey: .content),
        color: try container.decodeIfPresent(String.self, forKey: .color),
        textColor: try container.decodeIfPresent(String.self, forKey: .textColor),
        common: common
      )

    case "grid":
      self = .grid(
        columns: try container.decodeIfPresent(Int.self, forKey: .columns),
        spacing: try container.decodeIfPresent(Double.self, forKey: .spacing),
        children: try container.decodeIfPresent([ViewNode].self, forKey: .children) ?? [],
        common: common
      )

    default:
      throw DecodingError.dataCorruptedError(
        forKey: .type,
        in: container,
        debugDescription: "Unknown ViewNode type: \(type)")
    }
  }
}

// MARK: - FlexibleString

/// Decodes a JSON value that may be a string, number, or bool into a String.
/// Used for fields like `progress.value`, `checked`, and `on` that accept
/// both literal values and template strings (e.g. "{cpu_percent}").
///
/// Booleans and numbers funnel through `dslCanonicalBool`/`dslCanonicalNumber`
/// so the type-erased payload always uses the canonical tokens consumed by
/// `TemplateResolver.resolveBool` and `resolveDouble`.
private struct FlexibleString: Decodable {
  let value: String

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let s = try? container.decode(String.self) {
      self.value = s
    } else if let b = try? container.decode(Bool.self) {
      self.value = dslCanonicalBool(b)
    } else if let d = try? container.decode(Double.self) {
      self.value = dslCanonicalNumber(d)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected string, number, or bool")
    }
  }
}
