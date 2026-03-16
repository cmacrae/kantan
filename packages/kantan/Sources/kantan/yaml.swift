import Foundation
import Yams

enum Yaml: Hashable, Sendable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([Yaml])
  case dictionary([Yaml: Yaml])

  // MARK: - Parsing

  static func load(_ text: String) throws -> Yaml {
    let result = try Yams.load(yaml: text)
    return fromAny(result)
  }

  // MARK: - Any conversion

  private static func fromAny(_ value: Any?) -> Yaml {
    switch value {
    case nil:
      return .null
    case is NSNull:
      return .null
    case let b as Bool:
      return .bool(b)
    case let i as Int:
      return .int(i)
    case let d as Double:
      return .double(d)
    case let s as String:
      return .string(s)
    case let arr as [Any]:
      return .array(arr.map { fromAny($0) })
    case let dict as [(key: AnyHashable, value: Any)]:
      var yamlDict: [Yaml: Yaml] = [:]
      for pair in dict {
        yamlDict[fromAnyKey(pair.key)] = fromAny(pair.value)
      }
      return .dictionary(yamlDict)
    case let dict as [AnyHashable: Any]:
      var yamlDict: [Yaml: Yaml] = [:]
      for (key, val) in dict {
        yamlDict[fromAnyKey(key)] = fromAny(val)
      }
      return .dictionary(yamlDict)
    default:
      // Last resort: try String conversion
      return .string(String(describing: value!))
    }
  }

  private static func fromAnyKey(_ key: AnyHashable) -> Yaml {
    if let s = key as? String { return .string(s) }
    if let i = key as? Int { return .int(i) }
    if let b = key as? Bool { return .bool(b) }
    if let d = key as? Double { return .double(d) }
    return .string(String(describing: key))
  }

  // MARK: - Subscripts

  subscript(index: Int) -> Yaml {
    get {
      switch self {
      case .array(let array):
        if array.indices.contains(index) {
          return array[index]
        }
        return .null
      default:
        return .null
      }
    }
    set {
      switch self {
      case .array(let array):
        let emptyCount = max(0, index + 1 - array.count)
        let empty = [Yaml](repeating: .null, count: emptyCount)
        var new = array
        new.append(contentsOf: empty)
        new[index] = newValue
        self = .array(new)
      default:
        var array = [Yaml](repeating: .null, count: index + 1)
        array[index] = newValue
        self = .array(array)
      }
    }
  }

  subscript(key: Yaml) -> Yaml {
    get {
      switch self {
      case .dictionary(let dictionary):
        return dictionary[key] ?? .null
      default:
        return .null
      }
    }
    set {
      switch self {
      case .dictionary(let dictionary):
        var new = dictionary
        new[key] = newValue
        self = .dictionary(new)
      default:
        var dictionary = [Yaml: Yaml]()
        dictionary[key] = newValue
        self = .dictionary(dictionary)
      }
    }
  }

  // MARK: - Property accessors

  var bool: Bool? {
    switch self {
    case .bool(let b): return b
    default: return nil
    }
  }

  var int: Int? {
    switch self {
    case .int(let i): return i
    case .double(let f):
      if Double(Int(f)) == f { return Int(f) }
      return nil
    default: return nil
    }
  }

  var double: Double? {
    switch self {
    case .double(let f): return f
    case .int(let i): return Double(i)
    default: return nil
    }
  }

  var string: String? {
    switch self {
    case .string(let s): return s
    default: return nil
    }
  }

  var array: [Yaml]? {
    switch self {
    case .array(let a): return a
    default: return nil
    }
  }

  var dictionary: [Yaml: Yaml]? {
    switch self {
    case .dictionary(let d): return d
    default: return nil
    }
  }

  var count: Int? {
    switch self {
    case .array(let a): return a.count
    case .dictionary(let d): return d.count
    default: return nil
    }
  }

  // MARK: - Equality

  static func == (lhs: Yaml, rhs: Yaml) -> Bool {
    switch (lhs, rhs) {
    case (.null, .null): return true
    case (.bool(let l), .bool(let r)): return l == r
    case (.int(let l), .int(let r)): return l == r
    case (.int(let l), .double(let r)): return Double(l) == r
    case (.double(let l), .double(let r)): return l == r
    case (.double(let l), .int(let r)): return l == Double(r)
    case (.string(let l), .string(let r)): return l == r
    case (.array(let l), .array(let r)): return l == r
    case (.dictionary(let l), .dictionary(let r)): return l == r
    default: return false
    }
  }
}

// MARK: - Literal expressible conformances

extension Yaml: ExpressibleByNilLiteral {
  init(nilLiteral: ()) { self = .null }
}

extension Yaml: ExpressibleByBooleanLiteral {
  init(booleanLiteral: BooleanLiteralType) { self = .bool(booleanLiteral) }
}

extension Yaml: ExpressibleByIntegerLiteral {
  init(integerLiteral: IntegerLiteralType) { self = .int(integerLiteral) }
}

extension Yaml: ExpressibleByFloatLiteral {
  init(floatLiteral: FloatLiteralType) { self = .double(floatLiteral) }
}

extension Yaml: ExpressibleByStringLiteral {
  init(stringLiteral: StringLiteralType) { self = .string(stringLiteral) }
  init(extendedGraphemeClusterLiteral: StringLiteralType) {
    self = .string(extendedGraphemeClusterLiteral)
  }
  init(unicodeScalarLiteral: StringLiteralType) { self = .string(unicodeScalarLiteral) }
}

extension Yaml: ExpressibleByArrayLiteral {
  init(arrayLiteral elements: Yaml...) { self = .array(elements) }
}

extension Yaml: ExpressibleByDictionaryLiteral {
  init(dictionaryLiteral elements: (Yaml, Yaml)...) {
    var dictionary = [Yaml: Yaml]()
    for (k, v) in elements { dictionary[k] = v }
    self = .dictionary(dictionary)
  }
}

// MARK: - Description

extension Yaml: CustomStringConvertible {
  var description: String {
    switch self {
    case .null: return "Null"
    case .bool(let b): return "Bool(\(b))"
    case .int(let i): return "Int(\(i))"
    case .double(let f): return "Double(\(f))"
    case .string(let s): return "String(\(s))"
    case .array(let s): return "Array(\(s))"
    case .dictionary(let m): return "Dictionary(\(m))"
    }
  }
}

// MARK: - String subscript convenience

extension Yaml {
  /// Convenience subscript for string keys (most common access pattern).
  subscript(key: String) -> Yaml {
    get { self[Yaml.string(key)] }
    set { self[Yaml.string(key)] = newValue }
  }
}
