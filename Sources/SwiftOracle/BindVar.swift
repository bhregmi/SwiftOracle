import cocilib

public class BindVar: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral, ExpressibleByFloatLiteral  {
    let bind: (OpaquePointer, String) -> Void
    var value: Any
    public var stringValue: String
    
    public init(_ value: Int) {
        var v = Int32(value)
        bind = { st, name in OCI_BindInt(st, name, &v) }
        self.value = v
        self.stringValue = String(value)
    }
    public init (_ value: String) {
        var v = Array(value.utf8CString).map( {Int8(bitPattern: UInt8($0)) })
        bind = {st, name in OCI_BindString(st, name, &v, 0)}
        self.value = v
        self.stringValue = value
    }
    public init (_ value: Bool) {
        var v = Int32((value) ? 1: 0)
        bind = {st, name in OCI_BindBoolean(st, name, &v)}
        self.value = v
        self.stringValue = value ? "true" : "false"
    }
    
    public init (_ value: Double) {
        var v = value
        bind = {st, name in OCI_BindDouble(st, name, &v)}
        self.value = v
        self.stringValue = String(value)
    }
    
    public required convenience init(stringLiteral value: String) {
        self.init(value)
    }
    public required convenience init(extendedGraphemeClusterLiteral value: String) {
        self.init(value)
    }
    public required convenience init(unicodeScalarLiteral value: String) {
        self.init( value)
    }
    public required convenience init(integerLiteral value: Int){
        self.init(value)
    }
    public required convenience init(booleanLiteral value: Bool) {
        self.init(value)
    }
    public required convenience init(floatLiteral value: Double) {
        self.init(value)
    }
    
}

