import cocilib




//OCI_CDT_NUMERIC
public enum DataTypes: Equatable {
    case number(scale: Int), int, timestamp, bool, string, datetime, invalid
    init(col: OpaquePointer){
        let type = OCI_ColumnGetType(col)
        switch Int32(type) {
        case OCI_CDT_NUMERIC:
            let scale = OCI_ColumnGetScale(col)
            self = .number(scale: Int(scale))
        case OCI_CDT_TEXT:
            self = .string
        case OCI_CDT_TIMESTAMP:
            self = .timestamp
        case OCI_CDT_BOOLEAN:
            self = .bool
        case OCI_CDT_DATETIME:
            self = .datetime
        default:
            self = .invalid
            assert(1==0)
        }
    }
}


//    datetime = OCI_CDT_DATETIME,
//    text = OCI_CDT_TEXT,
//    long = OCI_CDT_LONG,
//    cursor = OCI_CDT_CURSOR,
//    lob = OCI_CDT_LOB,
//    file =  OCI_CDT_FILE,
//    timestamp = OCI_CDT_TIMESTAMP,
//    interval = OCI_CDT_INTERVAL,
//    raw = OCI_CDT_RAW,
//    object = OCI_CDT_OBJECT,
//    collection = OCI_CDT_COLLECTION,
//    ref = OCI_CDT_REF,
//    bool = OCI_CDT_BOOLEAN
//}




public class Cursor : Sequence, IteratorProtocol {
    
    public var resultPointer: OpaquePointer?
    private var statementPointer: OpaquePointer
    private let connection: OpaquePointer
    
    private var _columns: [Column]?
    
    private var binded_vars: [BindVar] = []
    
    public init(connection: OpaquePointer) {
        self.connection = connection
        statementPointer = OCI_StatementCreate(connection)
    }
    
    deinit {
        clear()
    }
    public func clear() {
        OCI_StatementFree(statementPointer)
    }
    private func get_columns() -> [Column] {
        guard let resultPointer=self.resultPointer else {
            return []
        }
        var result: [Column] = []
        let colsCount = OCI_GetColumnCount(resultPointer)
        for i in 1...colsCount {
            let col = OCI_GetColumn(resultPointer, i)
            let name_p =  OCI_ColumnGetName(col)
            let name =  String(validatingUTF8: name_p!)
            
            let type = DataTypes(col: col!)
            result.append(
                Column(name: name!, type: type
                )
            )
        }
        return result
    }
    public var affected: Int {
        return Int(OCI_GetAffectedRows(statementPointer))
    }
    
    func reset() {
        _columns = nil
        binded_vars = []
        if resultPointer != nil{
            OCI_ReleaseResultsets(statementPointer)
        }
        resultPointer = nil
    }
    
    public func bind(_ name: String, bindVar: BindVar) {
        bindVar.bind(statementPointer, name)
        binded_vars.append(bindVar)
    }
    
    public func bind(_ name: String, bindVar: BindVarArray) {
        bindVar.bind(statementPointer, name)
//        binded_vars.append(bindVar)
    }
    
    public func register(_ name: String, type: DataTypes) {
        switch type {
        case .int:
            OCI_RegisterInt(statementPointer, name)
        default:
            assert(1==0)
        }
    }
    
    public func execute(_ statement: String, params: [String: BindVar]=[:], register: [String: DataTypes]=[:], prefetchSize: Int = 20) throws {
        reset()
        let prepared = OCI_Prepare(statementPointer, statement)
        assert(prepared == 1)
        
        let _ = OCI_SetPrefetchSize(statementPointer, UInt32(prefetchSize))
        let _ = OCI_SetFetchSize(statementPointer, UInt32(prefetchSize))
        
        for (name, bindVar) in params {
            bind(name, bindVar: bindVar)
        }
        for (name, type) in register {
            self.register(name, type: type)
        }
        let executed = OCI_Execute(statementPointer);
        if executed != 1{
            throw DatabaseErrors.NotExecuted
        }
        resultPointer = OCI_GetResultset(statementPointer)
    }
    
    public func executeBulkDML(_ statement: String, params: [String: BindVarArray]=[:]) throws -> (Int, [String]) {
        reset()
        let prepared = OCI_Prepare(statementPointer, statement)
        assert(prepared == 1)
        
        let arraySize = params.first?.value.count ?? 0
//        print("arraySize: \(arraySize)")
        
        OCI_BindArraySetSize(statementPointer, UInt32(arraySize));
        
        for (name, bindVar) in params {
            bind(name, bindVar: bindVar)
        }

        let executed = OCI_Execute(statementPointer);
        var errors: [String] = []
        
        if executed != 1 {
            var err = OCI_GetBatchError(statementPointer)
            while (err != nil) {
                errors.append("Error at row \(OCI_ErrorGetRow(err)) : \(OCI_ErrorGetString(err))")
                err = OCI_GetBatchError(statementPointer)
            }
        }
        return (affected, errors)
    }
    
    public func fetchone() -> Row? {
        guard let resultPointer=resultPointer else {
            return nil
        }
        let fetched = OCI_FetchNext(resultPointer)
        if fetched == 0 {
            return nil
        }
        return Row(resultPointer: resultPointer, columns: self.columns)
        
    }
    public func next() -> Row? {
        return fetchone()
    }
    
    public func fetchOneSwifty() -> SwiftyRow? {
        guard let row = fetchone() else { return nil }
        return SwiftyRow(withRow: row)
    }
    
    public func nextSwifty() -> SwiftyRow? {
        return fetchOneSwifty()
    }
    
    public var count: Int {
        guard let resultPointer=self.resultPointer else {
            return 0
        }
        return Int(OCI_GetRowCount(resultPointer))
    }
    
    public var columns: [Column] {
        if _columns == nil {
            _columns = get_columns()
        }
        return _columns!
    }
}



