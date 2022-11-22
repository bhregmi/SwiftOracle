import cocilib
import Foundation

public class BindVar: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral, ExpressibleByFloatLiteral  {
    let bind: (OpaquePointer, String, OpaquePointer?) -> Void // value pointer, bind name, connection pointer
    var value: Any
    public var stringValue: String
    
    public init(_ value: Int) {
        var v = Int32(value)
        bind = { st, name, _ in OCI_BindInt(st, name, &v) }
        self.value = v
        self.stringValue = String(value)
    }
    
    public init (_ value: String) {
        var v = Array(value.utf8CString).map( {Int8(bitPattern: UInt8($0)) })
        bind = {st, name, _ in OCI_BindString(st, name, &v, 0)}
        self.value = v
        self.stringValue = value
    }
    public init (_ value: Bool) {
        var v = Int32((value) ? 1: 0)
        bind = {st, name, _ in OCI_BindBoolean(st, name, &v)}
        self.value = v
        self.stringValue = value ? "true" : "false"
    }
    
    public init (_ value: Double) {
        var v = value
        bind = {st, name, _ in OCI_BindDouble(st, name, &v)}
        self.value = v
        self.stringValue = String(value)
    }
    
    public init(_ value: BindCollection) {
        bind = { st, name, _ in OCI_BindColl(st, name, value.handle) }
        self.value = value
        self.stringValue = ""
    }
    
    public init (_ value: Date) {
        bind = { st, name, connPointer in
            let cal = Calendar(identifier: .gregorian)
            let year = cal.component(Calendar.Component.year, from: value)
            let month = cal.component(Calendar.Component.month, from: value)
            let day = cal.component(Calendar.Component.day, from: value)
            let hour = cal.component(Calendar.Component.hour, from: value)
            let min = cal.component(Calendar.Component.minute, from: value)
            let sec = cal.component(Calendar.Component.second, from: value)
            let ociDatePointer = OCI_DateCreate(connPointer!)
            
            if OCI_DateSetDateTime(ociDatePointer, Int32(year), Int32(month), Int32(day), Int32(hour), Int32(min), Int32(sec)) == 1 {
                OCI_BindDate(st, name, ociDatePointer)
            } else { throwFatalOCIError() }
        }
        self.value = value
        if #available(macOS 12.0, *) {
            self.stringValue = value.ISO8601Format()
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.calendar = Calendar(identifier: .iso8601)
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            self.stringValue = dateFormatter.string(from: value)
        }
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

// This does not work in multithreaded environment
// https://github.com/vrogier/ocilib/issues/320

public class BindCollection {
    private(set) var handle: OpaquePointer!
    private(set) var typeHandle: OpaquePointer!
    
    public init(conn: Connection, typeName: String) {
        typeHandle = OCI_TypeInfoGet(conn.connection, typeName, UInt32(OCI_TIF_TYPE))
        handle = OCI_CollCreate(typeHandle)
    }
    
    deinit {
        OCI_CollFree(handle)
        OCI_TypeInfoFree(typeHandle)
    }
    
    public func append(_ value: Int) {
        let elem: OpaquePointer = OCI_ElemCreate(typeHandle)
        OCI_ElemSetBigInt(elem, Int64(value))
        OCI_CollAppend(handle, elem)
        OCI_ElemFree(elem)
    }
    
    public func append(_ value: String) {
        let elem: OpaquePointer = OCI_ElemCreate(typeHandle)
        OCI_ElemSetString(elem, value)
        OCI_CollAppend(handle, elem)
        OCI_ElemFree(elem)
    }
}
