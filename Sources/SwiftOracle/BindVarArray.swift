import cocilib

public class BindVarArray  {
    let bind: (OpaquePointer, String) -> Void
    var value: [Any]
    var count: Int
    
    public init(_ values: [Int]) {
        var v = values.map { Int32($0) }
        bind = { st, name in OCI_BindArrayOfInts(st, name, &v, 0) }
        self.value = v
        self.count = values.count
    }

    public init (_ values: [String]) {
        let stringSize = (values.map { $0.count }).max() ?? 0
        var v = Array((values.map { Array($0.padding(toLength: stringSize, withPad: "\0", startingAt: 0).utf8CString).map( {Int8(bitPattern: UInt8($0)) }) }).joined())
        bind = {st, name in OCI_BindArrayOfStrings(st, name, &v, UInt32(stringSize), 0)}
        self.value = v
        self.count = values.count
    }

    //    public init (_ value: Bool) {
//        var v = Int32((value) ? 1: 0)
//        bind = {st, name in OCI_BindBoolean(st, name, &v)}
//        self.value = v
//    }
    
    public init (_ values: [Double]) {
        var v = values
        bind = {st, name in OCI_BindArrayOfDoubles(st, name, &v, 0)}
        self.value = v
        self.count = values.count
    }
    
//    public required convenience init(stringLiteral value: String) {
//        self.init(value)
//    }
//    public required convenience init(extendedGraphemeClusterLiteral value: String) {
//        self.init(value)
//    }
//    public required convenience init(unicodeScalarLiteral value: String) {
//        self.init( value)
//    }
//    public required convenience init(integerLiteral value: Int){
//        self.init(value)
//    }
//    public required convenience init(booleanLiteral value: Bool) {
//        self.init(value)
//    }
//    public required convenience init(floatLiteral value: Double) {
//        self.init(value)
//    }
    
}
