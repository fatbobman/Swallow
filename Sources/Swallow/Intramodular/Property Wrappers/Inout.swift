//
// Copyright (c) Vatsal Manot
//

import Swift

/*
struct UserView {
    @Inout var user: User

    init(userStore: UserStore, userID: ID) {
        _user = Inout(
            get: { userStore.getUser(id: userID) },
            set: { userStore.updateUser(id: userID, with: $0) }
        )
    }
}
*/

/// 类似 Binding 的属性包装器，不依赖 SwiftUI, 不会引发视图更新。
@propertyWrapper
public struct Inout<Value>: PropertyWrapper {
    public let get: @Sendable () -> Value
    public let set: @Sendable (Value) -> Void

    public var wrappedValue: Value {
        get {
            return get()
        } nonmutating set {
            set(newValue)
        }
    }

    public var projectedValue: Self {
        self
    }

    public init(
        get: @escaping @Sendable () -> Value,
        set: @escaping @Sendable (Value) -> Void
    ) {
        self.get = get
        self.set = set
    }

    public init(
        _ get: @autoclosure @escaping @Sendable () -> Value,
        _ set: @escaping @Sendable (Value) -> Void
    ) {
        self.init(get: get, set: set)
    }

    public subscript<Subject>(
        dynamicMember keyPath: WritableKeyPath<Value, Subject>
    ) -> Inout<Subject> {
        get {
            Inout<Subject>(
                get: {
                    wrappedValue[keyPath: keyPath]
                },
                set: {
                    wrappedValue[keyPath: keyPath] = $0
                }
            )
        }
    }
}

// MARK: - Conformances

extension Inout: CustomStringConvertible {
    public var description: String {
        String(describing: wrappedValue)
    }
}

extension Inout: Sendable where Value: Sendable {

}

// MARK: - SwiftUI Additions

#if canImport(SwiftUI)
import SwiftUI

extension Binding {
    public init(_ x: Inout<Value>) {
        self.init(get: { x.wrappedValue }, set: { x.wrappedValue = $0 })
    }
}
#endif
