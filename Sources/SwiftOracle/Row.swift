
import cocilib
import Foundation

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
        let s = OCI_GetString(resultPointer, index)!
        return String(validatingUTF8: s)!
    }
    public var int: Int {
        return Int(OCI_GetInt(resultPointer, index))
    }
    public var double: Double {
        return OCI_GetDouble(resultPointer, index)
    }
    
    public var datetime: Date {
        let ociDate = OCI_GetDate(resultPointer, index)!
        var year: Int32 = 0, month: Int32 = 0, day: Int32 = 0, hour: Int32 = 0, min: Int32 = 0, sec: Int32 = 0
        OCI_DateGetDateTime(ociDate, &year, &month, &day, &hour, &min, &sec)
//        var ociDateStrPtr: UnsafeMutablePointer<otext>?
//        OCI_DateToText(ociDate, "DD/MM/YYYY HH24:MI:SS", 260, ociDateStrPtr);
//        let ociDateStr = String(validatingUTF8: ociDateStrPtr!)!
//        let formatter = DateFormatter()
//        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
//        let date: Date = formatter.date(from: ociDateStr)!
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
    
    public var value: Any? {
        if self.isNull{
            return nil as Any?
        }
        switch type {
        case .string, .timestamp:
            return self.string
        case let .number(scale):
            if scale==0 {
                return self.int
            }
            else{
                return self.double
            }
        case .datetime:
            return self.datetime
        default:
            assert(0==1,"bad value \(type)")
            return "asd" as! AnyObject
        }
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
        let maybeIndex = columns.index(where: {$0.name==name})
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
