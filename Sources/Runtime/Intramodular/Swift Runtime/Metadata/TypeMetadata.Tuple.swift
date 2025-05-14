//
// Copyright (c) Vatsal Manot
//

import Swallow

/*
```swift
let tuple = (i:3,s:"asdg",d:3.0)
let metadata = TypeMetadata(type(of: tuple))

if metadata.kind == .tuple, let type = metadata.typed as? TypeMetadata.Tuple {
    print(type.fields)
}

// output: [Field(name: "i", type: Int, offset: 0), Field(name: "s", type: String, offset: 8), Field(name: "d", type: Double, offset: 24)]
*/
extension TypeMetadata {
    /// 用于在运行时表示和操作 Swift 元组类型。它是 TypeMetadata 的一个子类型，专门用于处理元组类型的元数据。
    public struct Tuple {
        public let base: Any.Type

        public init?(_ base: Any.Type) {
            guard _MetadataType(base: base).kind == .tuple else {
                return nil
            }

            self.base = base
        }
    }
}

extension TypeMetadata.Tuple {
    public var fields: [NominalTypeMetadata.Field] {
        zip(_metadata.labels(), _metadata.elementLayouts()).map { name, layout in
            NominalTypeMetadata.Field(
                name: name,
                type: .init(layout.type),
                offset: layout.offset
            )
        }
    }
}

// MARK: - Conformances

@_spi(Internal)
extension TypeMetadata.Tuple: _SwiftRuntimeTypeMetadataRepresenting {
    public typealias _MetadataType = _SwiftRuntimeTypeMetadata<_TupleMetadataLayout>
}

// MARK: - Helpers

extension TypeMetadata {
    public init<C: Collection>(
        tupleWithTypes types: C
    ) throws where C.Element == TypeMetadata {
        switch types.count {
            case 0:
                self = .init(Void.self)
            case 1:
                self = types[atDistance: 0]
            case 2:
                self = _concatenate(types[atDistance: 0], types[atDistance: 1])
            case 3:
                self = _concatenate(types[atDistance: 0], types[atDistance: 1], types[atDistance: 2])
            case 4:
                self = _concatenate(types[atDistance: 0], types[atDistance: 1], types[atDistance: 2], types[atDistance: 3])
            case 5:
                self = _concatenate(types[atDistance: 0], types[atDistance: 1], types[atDistance: 2], types[atDistance: 3], types[atDistance: 4])
            case 6:
                self = _concatenate(types[atDistance: 0], types[atDistance: 1], types[atDistance: 2], types[atDistance: 3], types[atDistance: 4], types[atDistance: 5])
            default:
                assertionFailure()

                self = try Array(types).reduce({ .init(_concatenate($0.base, $1.base)) }).forceUnwrap() // ugly workaround
        }
    }

    public init<C: Collection>(
        tupleWithTypes types: C
    ) throws where C.Element == Any.Type {
        try self.init(tupleWithTypes: types.lazy.map({ TypeMetadata($0) }))
    }
}
