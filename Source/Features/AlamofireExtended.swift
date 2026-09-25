
public struct AlamofireExtension<ExtendedType> {
    public private(set) var type: ExtendedType

    public init(_ type: ExtendedType) {
        self.type = type
    }
}

public protocol AlamofireExtended {
    associatedtype ExtendedType

    static var af: AlamofireExtension<ExtendedType>.Type { get set }
    var af: AlamofireExtension<ExtendedType> { get set }
}

extension AlamofireExtended {
    public static var af: AlamofireExtension<Self>.Type {
        get { AlamofireExtension<Self>.self }
        set {}
    }

    public var af: AlamofireExtension<Self> {
        get { AlamofireExtension(self) }
        set {}
    }
}
