import Foundation
import cocilib
import Logging

//@_exported import SQL

let defaultLogger = Logger(label: "com.iliasazonov.swiftoracle")
var log: Logger = defaultLogger

public func setLogger(logger: Logger) {
    log = logger
}

public struct DatabaseError: CustomStringConvertible, Error {
    let errorPtr: OpaquePointer
    public let text: String
    public let type: DatabaseErrorType
    public let code: Int
    public let statement: String
    
    public init(_ errorPointer: OpaquePointer = OCI_GetLastError()) {
        self.errorPtr = errorPointer
        self.text = String(validatingUTF8: OCI_ErrorGetString(errorPointer))!
        self.type = DatabaseError.getType(errorPointer)
        self.code = Int(OCI_ErrorGetOCICode(errorPointer))
        self.statement = DatabaseError.getStatement(errorPointer)
    }
    
    public var description: String {
        "Error \(type)-\(code), \(text)\n in statement: \(statement)"
    }
    
    public var localizedDescription: String { description }
        
    static private func getType(_ errorPointer: OpaquePointer) -> DatabaseErrorType {
        let typeNumber = Int32(OCI_ErrorGetType(errorPointer))
        switch typeNumber {
            case OCI_ERR_ORACLE: return .ORACLE
            case OCI_ERR_OCILIB: return .OCILIB
            default: return .UNKNOWN
        }
    }
    
    static private func getStatement(_ errorPointer: OpaquePointer) -> String {
        let st = OCI_ErrorGetStatement(errorPointer)
        guard let text = OCI_GetSql(st) else { return "" }
        return String(validatingUTF8: text) ?? "<not identified>"
    }
    
}

public enum DatabaseErrors: Error {
    case NotConnected, NotExecuted, SQLError(_ error: DatabaseError)
}

public enum DatabaseErrorType {
    case ORACLE, OCILIB, UNKNOWN
}

public enum FormatType: Int {
    case date = 1
    case timestamp = 2
    case numeric = 3
    case binaryDouble = 4
    case binaryFloat = 5
    case timestampTZ = 6
}

func error_callback(_ error: OpaquePointer) {
    print(DatabaseError(error))
}

public struct ConnectionInfo {
    let service_name: String, user:String, pwd: String, sysDBA: Bool
}



public struct OracleService {
	
    var raw_str: String?, host:String?, port:String?, service:String?
    public init(from_string raw_str: String){
        self.raw_str = raw_str
    }
	
    public init(host: String, port: String, service: String) {
        self.host = host; self.port = port; self.service = service
    }
    
    var string: String {
        if let raw_str = raw_str {
            return raw_str
        }
        if let host = host, let port = port, let service = service  {
            return "\(host):\(port)/\(service)"
        }
        return ""
    }
}



public class Connection {
    // associatedtype Error: ErrorType
    
    // environment singleton
    private let env: OCILIBEnvironment
    
    private var connection: OpaquePointer? = nil
    let conn_info: ConnectionInfo
    
    public required init(service: OracleService, user:String, pwd: String, sysDBA: Bool = false) {
        conn_info = ConnectionInfo(service_name: service.string, user: user, pwd: pwd, sysDBA: sysDBA)
        log.debug("Initializing OCILIB")
        self.env = OCILIBEnvironment.shared
//        OCI_Initialize({error_callback($0)} as? POCI_ERROR, nil, UInt32(OCI_ENV_DEFAULT | OCI_ENV_CONTEXT | (threaded ? OCI_ENV_THREADED : 0) )); //should be once per app
        log.debug("OCILIB initialized")
    }
    
    public func close() {
        guard let connection = connection else {
            return
        }
        log.debug("Releasing connection")
        OCI_ConnectionFree(connection)
        self.connection = nil
        log.debug("Connection released")
    }
	
    public func open() throws {
        log.debug("Attempting connection \(conn_info.user)@\(conn_info.service_name) \(conn_info.sysDBA ? "as SYSDBA" : "as regular user")")
        connection = OCI_ConnectionCreate(conn_info.service_name, conn_info.user, conn_info.pwd, conn_info.sysDBA ? UInt32(OCI_SESSION_SYSDBA) : UInt32(OCI_SESSION_DEFAULT));
        if connection == nil {
            let err = DatabaseError()
            log.error("Connection failed: \(err.description)")
            throw DatabaseErrors.SQLError(err)
        }
    }
	
    public func cursor() throws -> Cursor {
        guard let connection = connection else {
            throw DatabaseErrors.NotConnected
        }
        return Cursor(connection: connection)
    }
    
    public func cursor(statementPtr: OpaquePointer) throws -> Cursor {
        guard let connection = connection else {
            throw DatabaseErrors.NotConnected
        }
        return Cursor(connectionPtr: connection, statementPtr: statementPtr)
    }
	
    public var connected: Bool {
        guard let connection = connection else {
            return false
        }
        return OCI_IsConnected(connection) == 1
    }
	
    public var autocommit: Bool {
        set(newValue) {
            OCI_SetAutoCommit(connection!, (newValue) ? 1 : 0)
        }
        get {
            return OCI_GetAutoCommit(connection!) == 1
        }
    }
    
    public func setFormat(fmtType: FormatType, fmtString: String, isGlobal: Bool = false) throws {
        if isGlobal {
            if (OCI_SetFormat(nil, UInt32(fmtType.rawValue), fmtString) == 0) {
                throw DatabaseErrors.SQLError(DatabaseError())
            }
        } else {
            if (OCI_SetFormat(connection, UInt32(fmtType.rawValue), fmtString) == 0) {
                throw DatabaseErrors.SQLError(DatabaseError())
            }
        }
    }
    
    public func ping() -> Bool {
        return OCI_Ping(connection) == 1
    }
    
    public func `break`() {
        OCI_Break(connection)
    }
	
    func transaction_create() throws {
        guard let connection = connection else {
            throw DatabaseErrors.NotExecuted
        }
//        OCI_TransactionCreate(connection, nil, nil, nil)
    }
	
    deinit {
        close()
        // cleanup is performed by the environment singleton
//        OCI_Cleanup()  //should be once per app
    }
    
}

public func throwFatalOCIError(_ message: String = "") -> Never {
    guard let errPtr: OpaquePointer = OCI_GetLastError() else { fatalError("Could not retrieve OCI error. \(message)") }
//        print(Thread.callStackSymbols)
    fatalError(String(cString: OCI_ErrorGetString(errPtr)) + " \(message)")
}

public struct PooledConnection {
    private(set) var connection: OpaquePointer? = nil
    
    init(connHandle: OpaquePointer?) {
        connection = connHandle
    }
    
    public func cursor() throws -> Cursor {
        guard let connection = connection else {
            throw DatabaseErrors.NotConnected
        }
        return Cursor(connection: connection)
    }
    
    public func cursor(statementPtr: OpaquePointer) throws -> Cursor {
        guard let connection = connection else {
            throw DatabaseErrors.NotConnected
        }
        return Cursor(connectionPtr: connection, statementPtr: statementPtr)
    }
    
    var autocommit: Bool {
        set(newValue) {
            OCI_SetAutoCommit(connection!, (newValue) ? 1 : 0)
        }
        get {
            return OCI_GetAutoCommit(connection!) == 1
        }
    }
    
    public func commit() {
        OCI_Commit(connection)
    }
    
    public func rollback() {
        OCI_Rollback(connection)
    }
    
    
    
    public func aqDequeue(queueName: String, payloadType: String) -> (String, String) {
//        var typeInfo: OpaquePointer?
//        var deq: OpaquePointer?
//        var msg: OpaquePointer?
        var msgId: String = ""
        var corrId: String = ""
        guard let typeInfo = OCI_TypeInfoGet(connection, payloadType.cString(using: .ascii), UInt32(OCI_TIF_TYPE)) else { throwFatalOCIError() }
        guard let deq: OpaquePointer = OCI_DequeueCreate(typeInfo, queueName) else { throwFatalOCIError() }
        guard let msg: OpaquePointer = OCI_DequeueGet(deq) else { throwFatalOCIError() }
        let msgIdMaxLen: Int = 16
        let lenPtr = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        lenPtr.initialize(to: UInt32(msgIdMaxLen))
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: msgIdMaxLen)
        buf.assign(repeating: 0, count: msgIdMaxLen)
        var data: Data
        var hexes: [String]
        let ret: Bool = (OCI_MsgGetID(msg, buf, lenPtr) != 0)
        if ret {
            data = Data(bytes: buf, count: msgIdMaxLen)
            hexes = data.map { String(format: "%02X", $0) }
            msgId = hexes.joined()
            if let correlationPtr = OCI_MsgGetCorrelation(msg) {
                corrId = String(validatingUTF8: correlationPtr) ?? ""
            } else { corrId = "" }
        }
        commit()
        OCI_DequeueFree(deq);
        return (msgId, corrId)
    }
    
    public func aqEnqueue(queueName: String, payloadType: String, correlationId: String?) -> String {
        var msgId: String = ""
        var corrId: String = ""
        let msgIdMaxLen: Int = 16
        let lenPtr = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        lenPtr.initialize(to: UInt32(msgIdMaxLen))
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: msgIdMaxLen)
        buf.assign(repeating: 0, count: msgIdMaxLen)
        var data: Data
        var hexes: [String]
        
        guard let typeInfo = OCI_TypeInfoGet(connection, payloadType.cString(using: .ascii), UInt32(OCI_TIF_TYPE)) else { throwFatalOCIError() }
        guard let enq: OpaquePointer = OCI_EnqueueCreate(typeInfo, queueName) else { throwFatalOCIError() }
        guard let msg: OpaquePointer = OCI_MsgCreate(typeInfo) else { throwFatalOCIError() }
        if let corrId = correlationId {
            OCI_MsgSetCorrelation(msg, corrId)
        }
        let enqSuccess: Bool = (OCI_EnqueuePut(enq, msg) != 0)
        if enqSuccess {
            commit()
            let ret: Bool = ( OCI_MsgGetID(msg, buf, lenPtr) != 0)
            if ret {
                data = Data(bytes: buf, count: msgIdMaxLen)
                hexes = data.map { String(format: "%02X", $0) }
                msgId = hexes.joined()
            }
        } else {
            rollback()
            print("Enqueue failed, corrId: \(correlationId)")
            throwFatalOCIError()
        }
        OCI_MsgFree(msg);
        OCI_EnqueueFree(enq);
        return msgId
    }
}

public enum PoolType {
    case Connection, Session
}

///
/// See OCILIB Pool implementation details here: http://vrogier.github.io/ocilib/doc/html/group___ocilib_c_api_pools.html
///

public class ConnectionPool {
    // environment singleton
    private let env: OCILIBEnvironment
    
    private(set) var minConn: UInt32 = 1
    private(set) var maxConn: UInt32
    private(set) var incrConn: UInt32 = 1
    private let conn_info: ConnectionInfo
    private var pool: OpaquePointer
    public var openConn: Int { Int(OCI_PoolGetOpenedCount(pool)) }
    
    public required init(service: OracleService, user:String, pwd: String, minConn: Int = 1, maxConn: Int, incrConn: Int = 1, poolType: PoolType = .Connection, isSysDBA: Bool = false) throws {
        self.minConn = UInt32(minConn)
        self.maxConn = UInt32(maxConn)
        self.incrConn = UInt32(incrConn)
        conn_info = ConnectionInfo(service_name: service.string, user: user, pwd: pwd, sysDBA: isSysDBA)
        log.debug("Initializing OCILIB")
        self.env = OCILIBEnvironment.shared
//        OCI_Initialize({error_callback($0)} as? POCI_ERROR, nil, UInt32(OCI_ENV_DEFAULT | OCI_ENV_CONTEXT | OCI_ENV_THREADED)); //should be once per app
        
        log.debug("Creating connection pool")
        guard let lpool = OCI_PoolCreate(conn_info.service_name, conn_info.user, conn_info.pwd,
                              poolType == PoolType.Connection ? UInt32(OCI_POOL_CONNECTION) : UInt32(OCI_POOL_SESSION) ,
                              // SYSDBA is only available for session pools
                              (isSysDBA && poolType == PoolType.Session) ? UInt32(OCI_SESSION_SYSDBA) : UInt32(OCI_SESSION_DEFAULT),
                              self.minConn, self.maxConn, self.incrConn)
        
        else { log.error("Error creating connection pool"); throw DatabaseErrors.NotConnected }
        pool = lpool
        log.debug("Connection pool created")
    }
    
    public func setFormat(fmtType: FormatType, fmtString: String) throws {
        if (OCI_SetFormat(nil, UInt32(fmtType.rawValue), fmtString) == 0) {
            throw DatabaseErrors.SQLError(DatabaseError())
        }
    }
    
    public func getConnection(tag: String? = nil, autoCommit: Bool = false) -> PooledConnection {
        guard let connPtr = OCI_PoolGetConnection(pool, tag) else { log.error("Error getting a connection from the pool"); throwFatalOCIError() }
        var conn: PooledConnection = PooledConnection(connHandle: connPtr)
        conn.autocommit = autoCommit
        return conn
    }
    
    public func returnConnection(conn: PooledConnection) {
        OCI_ConnectionFree(conn.connection);
    }
    
    public var statementCacheSize: Int {
        get {
            return Int(OCI_PoolGetStatementCacheSize(pool))
        }
        set {
            OCI_PoolSetStatementCacheSize(pool, UInt32(newValue))
        }
    }
    
    public var timeout: Int {
        get {
            return Int(OCI_PoolGetTimeout(pool))
        }
        set {
            OCI_PoolSetTimeout(pool, UInt32(newValue))
        }
    }
    
    public var noWait: Bool {
        get {
            return OCI_PoolGetNoWait(pool) == 1
        }
        set {
            OCI_PoolSetNoWait(pool, newValue ? 1 : 0)
        }
    }
    
    public var busyCount: Int {
        get {
            Int(OCI_PoolGetBusyCount(pool))
        }
    }
    
    public var openedCount: Int {
        get {
            Int(OCI_PoolGetOpenedCount(pool))
        }
    }
    
    public var minCount: Int {
        get {
            Int(OCI_PoolGetMin(pool))
        }
    }
    
    public var maxCount: Int {
        get {
            Int(OCI_PoolGetMax(pool))
        }
    }
    
    public var incCount: Int {
        get {
            Int(OCI_PoolGetIncrement(pool))
        }
    }
    
    public func close() {
        OCI_PoolFree(pool)
    }
    
}

// this is to make sure we initialize and de-initialize the OCILIB environment once per application
public class OCILIBEnvironment {
    public static let shared = OCILIBEnvironment()
    
    init() {
        // should be run once per app
//        OCI_Initialize({error_callback($0)} as? POCI_ERROR, nil, UInt32(OCI_ENV_DEFAULT | OCI_ENV_CONTEXT | OCI_ENV_THREADED));
        // should not use a generic error pointer in a thread context
        OCI_Initialize(nil, nil, UInt32(OCI_ENV_DEFAULT | OCI_ENV_CONTEXT | OCI_ENV_THREADED));
    }
    
    deinit {
        OCI_Cleanup()  //should be once per app
    }
}
