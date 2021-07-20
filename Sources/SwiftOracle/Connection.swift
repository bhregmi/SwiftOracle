
import cocilib

//@_exported import SQL


struct DatabaseError: CustomStringConvertible {
    let error: OpaquePointer
    var text: String {
        return String(validatingUTF8: OCI_ErrorGetString(error))!
    }
    var type: Int {
        return Int(OCI_ErrorGetType(error))
    }
    var code: Int {
        return Int(OCI_ErrorGetOCICode(error))
    }
    var statement: String {
        let st = OCI_ErrorGetStatement(error)
        let text = OCI_GetSql(st)!
        return String(validatingUTF8: text)!
    }
    init(_ error: OpaquePointer) {
        self.error = error
    }
    var description: String {
        return "text: \(text)),\n\tstatement: \(statement)"
    }
    
}

enum DatabaseErrors: Error {
    case NotConnected, NotExecuted
}

func error_callback(_ error: OpaquePointer) {
    print(DatabaseError(error))
}

public struct ConnectionInfo {
    let service_name: String, user:String, pwd: String
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
    
    private var connection: OpaquePointer? = nil
    
    
    let conn_info: ConnectionInfo
    
    public required init(service: OracleService, user:String, pwd: String) {
        conn_info = ConnectionInfo(service_name: service.string, user: user, pwd: pwd)
        OCI_Initialize({error_callback($0)} as? POCI_ERROR, nil, UInt32(OCI_ENV_DEFAULT)); //should be once per app
    }
    
    func close() {
        guard let connection = connection else {
            return
        }
        OCI_ConnectionFree(connection)
        self.connection = nil
    }
	
    public func open() throws {
        connection = OCI_ConnectionCreate(conn_info.service_name, conn_info.user, conn_info.pwd, UInt32(OCI_SESSION_DEFAULT));
    }
	
    public func cursor() throws -> Cursor {
        guard let connection = connection else {
            throw DatabaseErrors.NotConnected
        }
        return Cursor(connection: connection)
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
	
    func transaction_create() throws {
        guard let connection = connection else {
            throw DatabaseErrors.NotExecuted
        }
//        OCI_TransactionCreate(connection, nil, nil, nil)
    }
	
    deinit {
        close()
        OCI_Cleanup()  //should be once per app
    }
    
}

public struct PooledConnection {
    private(set) var connection: OpaquePointer? = nil
    
    init(connHandle: OpaquePointer) {
        connection = connHandle
    }
    
    public func cursor() throws -> Cursor {
        guard let connection = connection else {
            throw DatabaseErrors.NotConnected
        }
        return Cursor(connection: connection)
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
}

public enum PoolType {
    case Connection, Session
}

///
/// See OCILIB Pool implementation details here: http://vrogier.github.io/ocilib/doc/html/group___ocilib_c_api_pools.html
///

public class ConnectionPool {
    private(set) var minConn: UInt32 = 1
    private(set) var maxConn: UInt32
    private(set) var incrConn: UInt32 = 1
    private let conn_info: ConnectionInfo
    private var pool: OpaquePointer? = nil
    public var openConn: Int { Int(OCI_PoolGetOpenedCount(pool)) }
    
    public required init(service: OracleService, user:String, pwd: String, minConn: Int = 1, maxConn: Int, incrConn: Int = 1, poolType: PoolType = .Connection, isSysDBA: Bool = false) {
        self.minConn = UInt32(minConn)
        self.maxConn = UInt32(maxConn)
        self.incrConn = UInt32(incrConn)
        conn_info = ConnectionInfo(service_name: service.string, user: user, pwd: pwd)
        OCI_Initialize({error_callback($0)} as? POCI_ERROR, nil, UInt32(OCI_ENV_DEFAULT)); //should be once per app
        
        pool = OCI_PoolCreate(conn_info.service_name, conn_info.user, conn_info.pwd,
                              poolType == PoolType.Connection ? UInt32(OCI_POOL_CONNECTION) : UInt32(OCI_POOL_SESSION) ,
                              // SYSDBA is only available for session pools
                              (isSysDBA && poolType == PoolType.Session) ? UInt32(OCI_SESSION_SYSDBA) : UInt32(OCI_SESSION_DEFAULT),
                              self.minConn, self.maxConn, self.incrConn)
    }
    
    public func getConnection(tag: String?, autoCommit: Bool = false) -> PooledConnection {
        var conn: PooledConnection = PooledConnection(connHandle: OCI_PoolGetConnection(pool, tag))
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
    
    deinit {
        OCI_PoolFree(pool)
        OCI_Cleanup()  //should be once per app
    }
}
