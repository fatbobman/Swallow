//
// Copyright (c) Vatsal Manot
//

import OrderedCollections
@_spi(Internal) import Swallow

/// InstanceMirror 提供了一种强大的反射机制，允许在运行时检查和操作 Swift 对象的内部结构。
/// 目的是提供比 Swift 标准库中的 Mirror 更强大的反射功能
public struct InstanceMirror<Subject>: _InstanceMirrorType, _VisitableMirror, MirrorType {
    /// 被反射的对象
    public var subject: Any
    /// 被反射对象的类型元数据
    public let typeMetadata: TypeMetadata.NominalOrTuple
    /// 获取固定类型的元数据
    package var _fixedTypeMetadata: TypeMetadata {
        TypeMetadata(__fixed_type(of: self.subject))
    }

    private init<T>(
        unchecked subject: T,
        typeMetadata: TypeMetadata.NominalOrTuple
    ) {
        self.subject = subject
        self.typeMetadata = typeMetadata
    }

    /// 这是整个反射系统的核心部分，解决了从任意类型获取正确类型元数据的复杂问题。
    /// 接收任意类型的值 (Any)
    /// 尝试获取该值的正确类型元数据
    /// 特殊处理可选类型值
    /// 构建适当的 InstanceMirror 实例
    @usableFromInline
    internal init?(
        _typeErasedSubject subject: Any
    ) {
        // 获取类型元数据
        func _typeMetadataFromValue<T>(_ x: T) -> TypeMetadata.NominalOrTuple? {
            TypeMetadata.NominalOrTuple(type(of: x))
        }

        guard let metadata = _openExistential(subject, do: _typeMetadataFromValue) ?? TypeMetadata.NominalOrTuple.of(subject) else {
            if TypeMetadata(type(of: subject)).kind == .optional {
                guard let value = Optional(_unwrapping: subject) else {
                    return nil
                }

                self.init(_typeErasedSubject: value)

                return
            }

            assertionFailure()

            return nil
        }

        self.init(
            unchecked: subject,
            typeMetadata: metadata
        )
    }
}

extension InstanceMirror {
    /// 进一步屏障，确保其他（非 AnyObject）类型的 subject 不会被错误地转换为 Optional<AnyObject>
    @inlinable
    public init?(
        _ subject: Subject
    ) {
        if swift_isClassType(Subject.self) {
            if unsafeBitCast(subject, to: Optional<AnyObject>.self) == nil {
                return nil
            }
        }

        self.init(_typeErasedSubject: subject)
    }

    /// 专为符合 AnyObject 的类型设计的初始化方法
    ///
    /// - Note: unsafeBitCast 在这里用于处理一种特殊情况：即使 Subject 在编译时不是可选类型，在运行时它的值可能实际上是 nil（特别是在涉及 Objective-C 互操作时）。
    ///         这种方法比用 as? 更直接，因为我们已经知道 Subject 是 AnyObject，不需要进行类型检查，只需要检查引用是否为 nil。
    ///         这个初始化方法是一个专门为类类型优化的路径，它:
    ///         确保不会用 nil 值创建 InstanceMirror
    ///         利用 unsafeBitCast 进行高效的底层检查
    ///         在通过检查后，使用 _typeErasedSubject 进行实际的初始化
    ///         这是一个底层优化，适用于已知符合特定约束的类型，体现了性能与类型安全之间的权衡。
    @inlinable
    public init?(
        _ subject: Subject
    ) where Subject: AnyObject {
        // 将 subject 直接按位重新解释为 Optional<AnyObject>，这允许在不进行正常的可选类型转换的情况下检查引用是否为 nil
        // 对于类类型，这种转换是低级别且高效的操作，防止使用 nil 对象创建 InstanceMirror
        if unsafeBitCast(subject, to: Optional<AnyObject>.self) == nil {
            // 如果 subject 是 nil，则返回 nil
            return nil
        }

        self.init(_typeErasedSubject: subject)
    }

    @inlinable
    public init(
        reflecting subject: Subject
    ) throws {
        do {
            self = try Self(_typeErasedSubject: __fixed_opaqueExistential(subject)).unwrap()
        } catch {
            do {
                self = try Self(_typeErasedSubject: subject).unwrap()
            } catch(_) {
                runtimeIssue("Failed to reflect subject of type: \(type(of: _unwrapPossiblyOptionalAny(subject)))")

                throw error
            }
        }
    }
}

public struct _TypedInstanceMirrorElement<T> {
    public let key: AnyCodingKey
    public let value: T
}

extension InstanceMirror {
    public var supertypeMirror: InstanceMirror<Any>? {
        guard let supertypeMetadata = typeMetadata.supertypeMetadata else {
            return nil
        }

        return .init(
            unchecked: subject as Any,
            typeMetadata: supertypeMetadata
        )
    }

    public var fieldDescriptors: [NominalTypeMetadata.Field] {
        typeMetadata.fields
    }

    public var allFieldDescriptors: [NominalTypeMetadata.Field] {
        guard let supertypeMirror = supertypeMirror else {
            return fieldDescriptors
        }

        return [NominalTypeMetadata.Field](supertypeMirror.allFieldDescriptors.join(fieldDescriptors))
    }

    public var keys: [AnyCodingKey] {
        allFieldDescriptors.map({ .init(stringValue: $0.name) })
    }

    public var allKeys: [AnyCodingKey] {
        allFieldDescriptors.map({ AnyCodingKey(stringValue: $0.name) })
    }

    /// Accesses the value of the given field.
    ///
    /// This is **unsafe**.
    public subscript(
        field: NominalTypeMetadata.Field
    ) -> Any? {
        get {
            if keys.count == 1, fieldDescriptors.first!.type.kind == .existential, typeMetadata.memoryLayout.size == MemoryLayout<Any>.size {
                let mirror = Mirror(reflecting: subject)

                assert(mirror.children.count == 1)

                let child = mirror.children.first!

                assert(child.label == field.key.stringValue)

                return child.value
            }

            let result: Any? = OpaqueExistentialContainer.withUnretainedValue(subject) {
                $0.withUnsafeBytes { bytes -> Any? in
                    let result: Any? = field.type.opaqueExistentialInterface.copyValue(from: bytes.baseAddress?.advanced(by: field.offset))

                    return result
                }
            }

            return result
        } set {
            guard let newValue else {
                assertionFailure()

                return
            }

            assert(type(of: newValue) == field.type.base)

            var _subject: Any = subject

            OpaqueExistentialContainer.withUnretainedValue(&_subject) {
                $0.withUnsafeMutableBytes { bytes in
                    field.type.opaqueExistentialInterface.reinitializeValue(
                        at: bytes.baseAddress?.advanced(by: field.offset),
                        to: newValue
                    )
                }
            }

            subject = _subject as! Subject
        }
    }

    public subscript(
        _ key: AnyCodingKey
    ) -> Any {
        get {
            func getValue<T>(from x: T) -> Any {
                assert(T.self != Any.self)

                var x = x

                return _swift_getFieldValue(&x, forKey: key.stringValue)
            }

            let subject: any Any = __fixed_opaqueExistential(subject)

            let result: Any = _openExistential(subject, do: getValue)

            return result
        } set {
            guard let field = _fieldDescriptorForKey(key) else {
                assertionFailure()

                return
            }

            self[field] = newValue
        }
    }

    func _fieldDescriptorForKey(
        _ key: AnyCodingKey
    ) -> NominalTypeMetadata.Field? {
        if let result = InstanceMirrorCache._cachedFieldsByNameByType[_fixedTypeMetadata]?[key] {
            return result
        }

        return typeMetadata.allFields.first(where: { $0.key == key })
    }
}

extension InstanceMirror {
    public typealias _TypedElement<T> = _TypedInstanceMirrorElement<T>

    public func forEachChild<T>(
        conformingTo protocolType: T.Type,
        _ operation: (_TypedElement<T>) throws -> Void,
        ingoring: (_TypedElement<Any>) -> Void
    ) rethrows {
        for (key, value) in self.allChildren {
            if TypeMetadata.of(value).conforms(to: protocolType) {
                let element = _TypedElement<T>(
                    key: key,
                    value: value as! T
                )

                try operation(element)
            } else {
                ingoring(_TypedElement<Any>(key: key, value: value))
            }
        }
    }

    public func recursiveForEachChild<T>(
        conformingTo protocolType: T.Type,
        _ operation: (_TypedElement<T>) throws -> Void
    ) rethrows {
        for (key, value) in self.allChildren {
            if TypeMetadata.of(value).conforms(to: protocolType) {
                let element = _TypedElement(key: key, value: value as! T)

                try operation(element)
            }

            if value is _InstanceMirrorType {
                fatalError()
            }

            guard let valueMirror = InstanceMirror<Any>(value) else {
                continue
            }

            try valueMirror.recursiveForEachChild(conformingTo: protocolType, operation)
        }
    }
}

// MARK: - Conformances

extension InstanceMirror: CustomStringConvertible {
    public var description: String {
        String(describing: subject)
    }
}

extension InstanceMirror: Sequence {
    public typealias Element = (key: AnyCodingKey, value: Any)
    public typealias Children = AnySequence<Element>
    public typealias AllChildren = AnySequence<Element>

    public var children: Children {
        .init(self)
    }

    public var allChildren: Children {
        guard let supertypeMirror = supertypeMirror else {
            return children
        }

        return .init(supertypeMirror.allChildren.join(children))
    }

    public func makeIterator() -> AnyIterator<Element> {
        keys.map({ ($0, self[$0]) }).makeIterator().eraseToAnyIterator()
    }
}

// MARK: - Internal

public protocol _InstanceMirrorType {

}

fileprivate enum InstanceMirrorCache {
    static var lock = OSUnfairLock()

    static var _cachedFieldsByNameByType: [TypeMetadata: [AnyCodingKey: NominalTypeMetadata.Field]] = [:]

    static func withCriticalRegion<T>(
        _ operation: (Self.Type) -> T
    ) -> T {
        lock.withCriticalScope {
            operation(self)
        }
    }
}

extension InstanceMirror {
    fileprivate func _cacheFields() {
        let type = _fixedTypeMetadata

        InstanceMirrorCache.withCriticalRegion {
            guard $0._cachedFieldsByNameByType[type] == nil else {
                return
            }
            var mirror: Mirror!

            $0._cachedFieldsByNameByType[type] = Dictionary(
                typeMetadata.fields.map { field in
                    if field.type._isInvalid {
                        mirror = mirror ?? Mirror(reflecting: subject)

                        guard let element = mirror.children.first(where: { $0.label == field.name }) else {
                            assertionFailure()

                            return field
                        }

                        return .init(
                            name: field.name,
                            type: TypeMetadata(Swift.type(of: element.value)),
                            offset: field.offset
                        )
                    } else {
                        return field
                    }
                }.map({ (AnyCodingKey(stringValue: $0.name), $0) }),
                uniquingKeysWith: { lhs, rhs in lhs }
            )
        }
    }
}

extension InstanceMirror {
    public func _smartForEachField<T>(
        ofPropertyWrapperType type: T.Type,
        depth: Int = 1,
        operation: (T) throws -> Void
    ) rethrows {
        try withExtendedLifetime(self.subject) {
            if let sequence = (subject as? any Sequence)?.__opaque_eraseToAnySequence(), depth != 0 {
                for element in sequence {
                    guard let mirror = InstanceMirror<Any>(element) else {
                        continue
                    }

                    try mirror._smartForEachField(ofPropertyWrapperType: type, depth: 0, operation: operation)
                }
            } else {
                for fieldDescriptor in fieldDescriptors {
                    guard fieldDescriptor.name.hasPrefix("_") else {
                        return
                    }

                    if let fieldValue: T = self[fieldDescriptor] as? T {
                        try withExtendedLifetime(fieldValue) {
                            try operation(fieldValue)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Deprecated

@available(*, deprecated, renamed: "InstanceMirror")
public typealias AnyNominalOrTupleMirror<Subject> = InstanceMirror<Subject>

extension InstanceMirror {
    @available(*, deprecated, renamed: "subject")
    public var value: Any {
        fatalError()
    }
}
