//
// Copyright (c) Vatsal Manot
//

import Swift

/*
// 不使用 @Indirect
struct Document {
    var pages: [Page]
}

// 使用 @Indirect
struct OptimizedDocument {
    @Indirect var pages: [Page]
}

// 创建包含1000页的文档
let largePageArray = Array(repeating: Page(), count: 1000)

// 场景1: 文档复制然后轻微修改
var doc1 = Document(pages: largePageArray)
var doc2 = doc1                 // 复制整个文档和引用
doc2.pages[0] = newPage         // 触发整个pages数组的完整复制

// 场景2: 使用@Indirect的文档
var optDoc1 = OptimizedDocument(pages: largePageArray)
var optDoc2 = optDoc1           // 只复制Indirect的引用，不复制数组
optDoc2.pages[0] = newPage      // 只在这一点创建新的引用盒子和数组副本
*/

/// A property wrapper that allows for an indirect, copy-on-write behavior.
/// 在上面的例子中，`var optDoc2 = optDoc1` 只复制了 `Indirect` 的引用，而不是整个数组。
/// An indirect, copy-on-write wrapper over a value.
@frozen
@propertyWrapper
public struct Indirect<Value>: ParameterlessPropertyWrapper {
    @MutableValueBox
    private var storage: ReferenceBox<Value>

    public var wrappedValue: Value {
        get {
            return storage.value
        } set {
            if isKnownUniquelyReferenced(&storage) {
                storage.value = newValue
            } else {
                storage = .init(newValue)
            }
        }
    }

    public var unsafelyUnwrapped: Value {
        get {
            storage.value
        } nonmutating set {
            storage.value = newValue
        }
    }

    public var projectedValue: Indirect<Value> {
        self
    }

    public init(wrappedValue: Value) {
        self.storage = .init(wrappedValue)
    }
}

// MARK: - Conformances

extension Indirect: Encodable where Value: Encodable {

}

extension Indirect: Decodable where Value: Decodable {

}

extension Indirect: CustomStringConvertible {
    public var description: String {
        String(describing: wrappedValue)
    }
}

extension Indirect: Equatable where Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

extension Indirect: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        wrappedValue.hash(into: &hasher)
    }
}

extension Indirect: @unchecked Sendable where Value: Sendable {

}
