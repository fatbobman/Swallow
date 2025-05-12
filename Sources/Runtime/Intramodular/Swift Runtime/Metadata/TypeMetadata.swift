//
// Copyright (c) Vatsal Manot
//

import ObjectiveC
import Swallow

/// 提供了在运行时访问和操作 Swift 类型元数据的能力。
/// 它是 Swallow 反射系统的基础组件，允许开发者在运行时检查类型信息、验证类型关系和执行类型操作。
@frozen
public struct TypeMetadata: _TypeMetadataType {
  public let base: Any.Type

  /// 类型的内存大小
  public var size: Int {
    swift_getSize(of: base)
  }

  @_transparent
  public init(_ base: Any.Type) {
    self.base = base
  }

  @_optimize(speed)
  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(base))
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    ObjectIdentifier(lhs.base) == ObjectIdentifier(rhs.base)
  }

  /// Creates a new instance of `TypeMetadata` from a given type.
  /// - Parameter type: The type to create the `TypeMetadata` instance from.
  /// - Returns: A new instance of `TypeMetadata` representing the given type.
  public static func of(_ x: Any) -> Self {
    TypeMetadata(Swift.type(of: x))
  }

  /// 通过名称创建一个新的 `TypeMetadata` 实例。
  /// - Parameter name: The name of the type to create the `TypeMetadata` instance from.
  /// - Returns: A new instance of `TypeMetadata` representing the type with the given name.
  /// - Note: 自定义类型会收到一定的限制， NSObject 子类可以成功，系统类型可以成功。
  public init?(name: String) {
    guard let type: Any.Type = _typeByName(name) else {
      return nil
    }

    self.init(type)
  }

  public init?(
    name: String,
    mangledName: String?
  ) {
    guard let type: Any.Type = _typeByName(name) ?? mangledName.flatMap(_typeByName) else {
      return nil
    }

    self.init(type)
  }
}

// MARK: - Conformances

extension TypeMetadata: CustomStringConvertible {
  public var description: String {
    String(describing: base)
  }
}

extension TypeMetadata: MetatypeRepresentable {
  public init(metatype: Any.Type) {
    self.init(metatype)
  }

  public func toMetatype() -> Any.Type {
    base
  }
}

/// 提供了多种方式获取类型的名称信息。这对于反射系统至关重要，因为它允许查询和展示类型的名称。
extension TypeMetadata: Named {
  /// 检查类型名称是否以下划线开头
  public var hasUnderscoredName: Bool {
    _unqualifiedName.hasPrefix("_")
  }

  /// 获取基本类型名称（使用默认选项），调用底层 Swift 运行时函数 _typeName
  public var _name: String {
    _typeName(base)
  }

  /// 获取完全限定的类型名称，包括模块名，例如：Swift.Int.type, Foundation.Date.Type
  public var _qualifiedName: String {
    _typeName(base, qualified: true)
  }

  /// 获取不完全限定的类型名称，不包括模块名，例如：Int.Type, Date.Type
  public var _unqualifiedName: String {
    _typeName(base, qualified: false)
  }

  /// 获取类型的 mangled 名称(编码名称是 Swift 在底层用于唯一标识类型的字符串), 例如：19SubjectOptionalTest8MyMirrorC
  @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
  public var mangledName: String? {
    _mangledTypeName(base)
  }

  /// 获取类型的名称（包含模块名），例如：Swift.Int.Type, Foundation.Date.Type
  public var name: String {
    _qualifiedName
  }
}

// MARK: - Supplementary

/// Returns whether a given value is a type of a type (a metatype).
///
/// ```swift
/// isMetatype(Int.self) // false
/// isMetatype(Int.Type.self) // true
/// ```
public func _isTypeOfType(_ x: some Any) -> Bool {
  guard let type = x as? Any.Type else {
    return false
  }

  let metadata = TypeMetadata(type)

  switch metadata.kind {
  case .metatype, .existentialMetatype:
    return true
  default:
    return false
  }
}

public extension Metatype {
  /// ```swift
  /// Metatype(Int.self)._isTypeOfType // false
  /// Metatype(Int.Type.self)._isTypeOfType // true
  /// ```
  var _isTypeOfType: Bool {
    Runtime._isTypeOfType(_unwrapBase())
  }

  /// `Optional<T>.Type` -> `T.Type`
  ///
  /// Notes:
  /// - Not to be confused with `Optional<T.Type>` -> `T.Type`.
  var unwrapped: Metatype<Any.Type> {
    Metatype<Any.Type>(_getUnwrappedType(from: _unwrapBase()))
  }
}

public extension TypeMetadata {
  /// Determines if the current type is covariant to the specified type.
  ///
  /// Covariance allows a type to be used in place of its supertype. For example,
  /// if type `B` is a subtype of type `A`, then `B` is covariant to `A`.
  ///
  /// - Parameter other: The type to check for covariance against.
  /// - Returns: `true` if the current type is covariant to the specified type, otherwise `false`.
  func _isCovariant(to other: TypeMetadata) -> Bool {
    func _checkIsCovariant(_ type: (some Any).Type) -> Bool {
      func _isCovariant<U>(to otherType: U.Type) -> Bool {
        let result = type == otherType || type is U.Type

        if !result {
          if let type = type as? AnyClass, let otherType = otherType as? AnyClass {
            return unsafeBitCast(type, to: NSObject.Type.self).isSubclass(of: unsafeBitCast(otherType, to: NSObject.Type.self))
          }
        }

        return result
      }

      return _openExistential(other.base, do: _isCovariant(to:))
    }

    return _openExistential(base, do: _checkIsCovariant)
  }
}

// MARK: - Internal

private func swift_getSize(
  of type: Any.Type
) -> Int {
  func project<T>(_: T.Type) -> Int {
    MemoryLayout<T>.size
  }

  return _openExistential(type, do: project)
}
