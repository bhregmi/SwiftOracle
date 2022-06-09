import cocilib




//OCI_CDT_NUMERIC
public enum DataTypes: Equatable {
    case number(scale: Int), int, timestamp, bool, string, datetime, long, interval, raw, object, collection, ref, cursor, file, lob, invalid
    init(col: OpaquePointer){
        let type = OCI_ColumnGetType(col)
        switch Int32(type) {
        case OCI_CDT_NUMERIC:
            let scale = OCI_ColumnGetScale(col)
            self = .number(scale: Int(scale))
            if scale == -127 || scale == 0 { self = .int } else { self = .number(scale: Int(scale)) }
        case OCI_CDT_TEXT:
            self = .string
        case OCI_CDT_TIMESTAMP:
            self = .timestamp
        case OCI_CDT_BOOLEAN:
            self = .bool
        case OCI_CDT_DATETIME:
            self = .datetime
        case OCI_CDT_LONG:
            self = .long
        case OCI_CDT_CURSOR:
            self = .cursor
        case OCI_CDT_LOB:
            self = .lob
        case OCI_CDT_FILE:
            self = .file
        case OCI_CDT_INTERVAL:
            self = .interval
        case OCI_CDT_RAW:
            self = .raw
        case OCI_CDT_OBJECT:
            self = .object
        case OCI_CDT_COLLECTION:
            self = .collection
        case OCI_CDT_REF:
            self = .ref
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
//




public class Cursor : Sequence, IteratorProtocol {
    
    public private(set) var resultPointer: OpaquePointer?
    public var statementPointer: OpaquePointer
    public let connection: OpaquePointer
    public private(set) var sqlId: String = ""
    public private(set) var dbmsOutputContent: String = ""
    
    private var _columns: [Column]?
    
    private var binded_vars: [BindVar] = []
    
    public init(connection: OpaquePointer) {
        self.connection = connection
        statementPointer = OCI_StatementCreate(connection)
    }
    
    public init(connectionPtr: OpaquePointer, statementPtr: OpaquePointer) {
        self.connection = connectionPtr
        self.statementPointer = statementPtr
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
            let name_p = OCI_ColumnGetName(col)
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
    
    public func reset() {
        _columns = nil
        binded_vars = []
        if resultPointer != nil{
            OCI_ReleaseResultsets(statementPointer)
        }
        resultPointer = nil
        sqlId = ""
        dbmsOutputContent = ""
    }
    
    public func bind(_ name: String, bindVar: BindVar) {
        bindVar.bind(statementPointer, name, connection)
        binded_vars.append(bindVar)
    }
    
    public func bind(_ name: String, bindVar: BindVarArray) {
        bindVar.bind(statementPointer, name)
    }
    
    public func register(_ name: String, type: DataTypes) {
        switch type {
        case .int:
            OCI_RegisterInt(statementPointer, name)
        default:
            assert(1==0)
        }
    }
    
    public func execute(_ statement: String, params: [String: BindVar]=[:], register: [String: DataTypes]=[:], prefetchSize: Int = 20, enableDbmsOutput: Bool = false) throws {
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
        
        if enableDbmsOutput {
            OCI_ServerEnableOutput(connection, 1000000, 100, 32767)
        }
        
        let executed = OCI_Execute(statementPointer);
        if executed != 1 {
            log.error("Error in \(#function)")
            throw DatabaseErrors.SQLError(DatabaseError())
        }
        
        sqlId = String(validatingUTF8: OCI_GetSqlIdentifier(statementPointer)) ?? ""
        resultPointer = OCI_GetResultset(statementPointer)
        
        if enableDbmsOutput {
            var outputPtr = OCI_ServerGetOutput(connection)
            while outputPtr != nil {
                self.dbmsOutputContent = self.dbmsOutputContent + (String(validatingUTF8: outputPtr!) ?? "") + "\n"
                outputPtr = OCI_ServerGetOutput(connection)
            }
            OCI_ServerDisableOutput(connection)
        }
    }
    
    public func executePreparedStatement(prefetchSize: Int = 20) throws {
        let _ = OCI_SetPrefetchSize(statementPointer, UInt32(prefetchSize))
        let _ = OCI_SetFetchSize(statementPointer, UInt32(prefetchSize))
        
        resultPointer = OCI_GetResultset(statementPointer)
    }
    
    /// This methond works only for DML statements. Oracle does not support array binding to a single variable in a WHERE clause of a regular SELECT statement. 
    public func executeArrayBinds(_ statement: String, withArrayBinds params: [String: BindVarArray]=[:], register: [String: DataTypes]=[:], prefetchSize: Int = 20) throws {
        reset()
        let prepared = OCI_Prepare(statementPointer, statement)
        assert(prepared == 1)
        
        let _ = OCI_SetPrefetchSize(statementPointer, UInt32(prefetchSize))
        let _ = OCI_SetFetchSize(statementPointer, UInt32(prefetchSize))
        
        let arraySize = params.first?.value.count ?? 0
        OCI_BindArraySetSize(statementPointer, UInt32(arraySize));
        
        for (name, bindVar) in params {
            bind(name, bindVar: bindVar)
        }
        
        for (name, type) in register {
            self.register(name, type: type)
        }
        
        let executed = OCI_Execute(statementPointer);
        
        if executed != 1 {
            log.error("Error in \(#function)")
            throw DatabaseErrors.SQLError(DatabaseError())
        }
        sqlId = String(validatingUTF8: OCI_GetSqlIdentifier(statementPointer)) ?? ""
        resultPointer = OCI_GetResultset(statementPointer)
    }
    
    public func executeBulkDML(_ statement: String, params: [String: BindVarArray]=[:]) throws -> (Int, [String]) {
        reset()
        let prepared = OCI_Prepare(statementPointer, statement)
        assert(prepared == 1)
        
        let arraySize = params.first?.value.count ?? 0
        
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
        } else {
            sqlId = String(validatingUTF8: OCI_GetSqlIdentifier(statementPointer)) ?? ""
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
    
    public func fetchOneSwifty(withStringRepresentation: Bool = false) -> SwiftyRow? {
        guard let row = fetchone() else { return nil }
        return SwiftyRow(withRow: row, withStringRepresentation: withStringRepresentation)
    }
    
    public func nextSwifty(withStringRepresentation: Bool = false) -> SwiftyRow? {
        return fetchOneSwifty(withStringRepresentation: withStringRepresentation)
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
    
    public func getColumnLabels() -> [String] {
        columns.compactMap { $0.name }
    }
    
}



