
import cocilib
import Foundation

public struct SwiftyField: Identifiable, Equatable, Comparable, CustomStringConvertible {
    public var description: String {
        "name: \(name), type: \(type), value: \(string ?? "")"
    }
    
    public let name: String
    public let type: DataTypes
    public let index: Int
    public let value: Any?
    public let isNull: Bool
    public let valueString: String
    
    public init(name: String, type: DataTypes, index: Int, value: Any?, isNull: Bool, valueString: String = "") {
        self.name = name
        self.type = type
        self.index = index
        self.value = value
        self.isNull = isNull
        self.valueString = valueString
    }
    
    public var string: String? {
        value as? String
    }
    
    public var int: Int? {
        value as? Int
    }
    
    public var double: Double? {
        value as? Double
    }
    
    public var date: Date? {
        value as? Date
    }
    
    public var timestamp: DateComponents? {
        value as? DateComponents
    }
    
    public var toString: String {
        guard !self.isNull else { return "" }
        switch type {
            case .int: return "\(int!)"
            case .number(scale: -127): return "\(int!)"
            case .number(_): return "\(double!)"
            case .string: return string!
            case .timestamp: return "\(timestamp!)"
            case .datetime: return "\(date!)"
            default: return "unsupported type \(type)"
        }
    }
    
    public static func == (lhs: SwiftyField, rhs: SwiftyField) -> Bool {
        guard !lhs.isNull && !rhs.isNull else { return false }
        guard lhs.type == rhs.type else {return false }
        switch lhs.type {
            case .int: return lhs.int == rhs.int
            case .number(scale: 0): return lhs.int == rhs.int
            case .number(_): return lhs.double == rhs.double
            case .string: return lhs.string == rhs.string
            case .datetime: return lhs.date == rhs.date
            case .timestamp: return lhs.timestamp == rhs.timestamp
            default: return false
        }
    }
    
    public static func < (lhs: SwiftyField, rhs: SwiftyField) -> Bool {
        guard !(lhs.isNull && rhs.isNull) else { return false }
        guard !lhs.isNull else { return true }
        guard !rhs.isNull else { return false }
        guard lhs.type == rhs.type else {return false }
        switch lhs.type {
            case .int: return lhs.int! < rhs.int!
            case .number(scale: 0): return lhs.int! < rhs.int!
            case .number(_): return lhs.double! < rhs.double!
            case .string: return lhs.string! < rhs.string!
            case .datetime: return lhs.date! < rhs.date!
            case .timestamp: return false
            default: return false
        }
    }
    
    public var id: String { get { name } }
    
    
}

public class Field {
    private let resultPointer: OpaquePointer
    private let index: UInt32
    let type: DataTypes
    
    init(resultPointer: OpaquePointer, index: Int, type: DataTypes){
        self.resultPointer = resultPointer
        self.index = UInt32(index+1)
        self.type = type
    }
    public var isNull: Bool {
        return OCI_IsNull(resultPointer, index) == 1
    }
    public var string: String {
        // https://github.com/vrogier/ocilib/issues/112
        // https://github.com/vrogier/ocilib/issues/313
        if type != .long {
            guard let s = OCI_GetString(resultPointer, index) else { return "" }
            return String(validatingUTF8: s)!
        } else {
            guard let lg = OCI_GetLong(resultPointer, index) else { return "" }
            let longType = OCI_LongGetType(lg)
            if longType == OCI_BLOB { return "LONG RAW not supported by SwiftOracle" }
            else {
                guard let s = OCI_GetString(resultPointer, index) else { return "" }
                return String(validatingUTF8: s)!
            }
        }
    }
    
    public var int: Int {
        return Int(OCI_GetInt(resultPointer, index))
    }
    public var double: Double {
        return OCI_GetDouble(resultPointer, index)
    }
    
    public var cursor: OpaquePointer {
        return OCI_GetStatement(resultPointer, index)
    }
    
    public var datetime: Date {
        let ociDate = OCI_GetDate(resultPointer, index)!
        var year: Int32 = 0, month: Int32 = 0, day: Int32 = 0, hour: Int32 = 0, min: Int32 = 0, sec: Int32 = 0
        OCI_DateGetDateTime(ociDate, &year, &month, &day, &hour, &min, &sec)
        // compose a Swift Date value
        var dateComponents = DateComponents()
        dateComponents.year = Int(year)
        dateComponents.month = Int(month)
        dateComponents.day = Int(day)
        dateComponents.hour = Int(hour)
        dateComponents.minute = Int(min)
        dateComponents.second = Int(sec)
        dateComponents.timeZone = TimeZone(secondsFromGMT: 0)
        let userCalendar = Calendar.current
        let date = userCalendar.date(from: dateComponents)!
        return date
    }
    
    public var timestamp: DateComponents {
        let ociDate = OCI_GetTimestamp(resultPointer, index)!
        var year: Int32 = 0, month: Int32 = 0, day: Int32 = 0, hour: Int32 = 0, min: Int32 = 0, sec: Int32 = 0, fsec: Int32 = 0, tzOffsetHr: Int32 = 0, tzOffsetMin: Int32 = 0;
        OCI_TimestampGetDateTime(ociDate, &year, &month, &day, &hour, &min, &sec, &fsec)
        OCI_TimestampGetTimeZoneOffset(ociDate, &tzOffsetHr, &tzOffsetMin)

        var dateComponents = DateComponents()
        dateComponents.year = Int(year)
        dateComponents.month = Int(month)
        dateComponents.day = Int(day)
        dateComponents.hour = Int(hour)
        dateComponents.minute = Int(min)
        dateComponents.second = Int(sec)
        dateComponents.nanosecond = Int(fsec) * 1000
        dateComponents.timeZone = TimeZone(secondsFromGMT: Int((tzOffsetHr*60 + tzOffsetMin) * 60))
//        let userCalendar = Calendar.current
//        let date = userCalendar.date(from: dateComponents)!
//        print("timezone: \(dateComponents.timeZone), date: \(date)")
        return dateComponents
    }
    
    public var value: Any? {
        if self.isNull{
            return nil as Any?
        }
        switch type {
            case .string, .collection, .lob, .object, .file, .raw, .long:
            return self.string
        case let .number(scale):
            return self.double
        case .int:
            return self.int
        case .datetime:
            return self.datetime
        case .timestamp:
            return self.timestamp
        case .cursor:
            return self.cursor
        default:
//            assert(0==1,"bad value \(type)")
            return "\(type) not supported"
        }
    }
}

public struct SwiftyRow: Identifiable, CustomStringConvertible {
    public var description: String {
        "\(dictString)"
    }
    
    public var id = UUID()
    public let fields: [SwiftyField]
    
    public init(withSwiftyFields fields: [SwiftyField]) {
        self.fields = fields
    }
    
    init(withRow row: Row, withStringRepresentation: Bool = false) {
        if withStringRepresentation {
            fields = row.columns.enumerated().map { (index, column) in
                SwiftyField(name: column.name, type: column.type, index: index, value: row[column.name]!.value, isNull: row[column.name]!.isNull, valueString: row[column.name]!.isNull ? "" : row[column.name]!.string)
            }
        } else {
            fields = row.columns.enumerated().map { (index, column) in
                SwiftyField(name: column.name, type: column.type, index: index, value: row[column.name]!.value, isNull: row[column.name]!.isNull)
            }
        }
    }
    
    public subscript (name: String) -> SwiftyField? {
        guard let index = fields.firstIndex(where: {$0.name==name}) else { return nil }
        return fields[index]
    }
    
    public subscript (index: Int) -> SwiftyField? {
        guard index >= 0 && index < fields.count else {  return nil }
        return fields[index]
    }
    
    public var dict: [String : Any?] {
        var result: [String : Any?]  = [:]
        for (index, column) in self.fields.enumerated() {
            result[column.name] = fields[index].value
        }
        return result
    }
    
    public var dictString: [String : String?] {
        var result: [String : String?]  = [:]
        for (index, column) in self.fields.enumerated() {
            result[column.name] = fields[index].valueString
        }
        return result
    }
        
    public var list: [Any?] {
        var result: [Any?]  = []
        for (index, _) in self.fields.enumerated() {
            result.append(fields[index].value)
        }
        return result
    }
    
    static public func less (colIndex: Int, lhs:SwiftyRow, rhs:SwiftyRow) -> Bool {
        return lhs.fields[colIndex] < rhs.fields[colIndex]
    }
}

public class Row {
    private let resultPointer: OpaquePointer
    let columns: [Column]
    //todo invalidate row
    init(resultPointer: OpaquePointer, columns: [Column]){
        self.resultPointer = resultPointer
        self.columns = columns
    }
    public subscript (name: String) -> Field? {
        let maybeIndex = columns.firstIndex(where: {$0.name==name})
        guard let index = maybeIndex else {
            return nil
        }
        return Field(resultPointer: resultPointer, index: index, type: columns[index].type)
    }
    public subscript (index: Int) -> Field? {
        guard index >= 0 && index < columns.count else {
            return nil
        }
        let c = columns[index]
        return Field(resultPointer: resultPointer, index: index, type: c.type)
    }
    public lazy var dict: [String : Any?] = {
        var result: [String : Any?]  = [:]
        for (index, column) in self.columns.enumerated() {
            result[column.name] = Field(resultPointer: self.resultPointer, index: index, type: column.type).value
        }
        return result
    }()
    public lazy var list: [Any?] = {
        var result: [Any?]  = []
        for (index, column) in self.columns.enumerated() {
            result.append(Field(resultPointer: self.resultPointer, index: index, type: column.type).value)
        }
        return result
    }()
}
