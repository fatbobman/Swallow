//
// Copyright (c) Vatsal Manot
//

import Swallow

/*
 struct MyStruct {
     let name:String
     var age:Int
 }

 let s = TypeMetadata(MyStruct.self)
 if s.kind == .struct,let type = s.typed as? TypeMetadata.Structure {
        print(type.fields)
        print(type.mangledName)
        print(type.allFields)
 }

 // [Field(name: "name", type: String, offset: 0), Field(name: "age", type: Int, offset: 16)]
 // MyStruct
 // [Field(name: "name", type: String, offset: 0), Field(name: "age", type: Int, offset: 16)]
 */
public extension TypeMetadata {
  struct Structure: _NominalTypeMetadataType {
    public let base: Any.Type

    public init?(_ base: Any.Type) {
      guard _MetadataType(base: base).kind == .struct else {
        return nil
      }

      self.base = base
    }
  }
}

public extension TypeMetadata.Structure {
  var mangledName: String {
    _metadata.mangledName()
  }

  var fields: [NominalTypeMetadata.Field] {
    _metadata.fields
  }
}

// MARK: - Conformances

@_spi(Internal)
extension TypeMetadata.Structure: _SwiftRuntimeTypeMetadataRepresenting {
  public typealias _MetadataType = _SwiftRuntimeTypeMetadata<_StructMetadataLayout>
}
