# SwiftOracle
OCILIB wrapper for Swift, linux compatible

## New in this release
- Added support for REF Cursors. See an example below.
- Added a layer of "swifty" objects - SwiftyField, SwiftyRow. This is still work in progress.

## New in previous release
- Added array binding (BindVarArray)
- Added executeBulkDML that uses arrays of bind variables in DMLs for greatly improved performance
- Added connection and sesssion pooling
- Added Bindvar stringValue representation
- Added Date support;
- Added prefetchSize in cursor.execute to support efficient data transfers
- Added a dependency on C bridge to OCILIB (swift 5 compatible)



This is wrapper for ocilib (https://github.com/vrogier/ocilib). 

Installation
(1) Installing Oracle Instant Client  
Download Basic package (zip) and SDK package (zip) for your platform from https://www.oracle.com/database/technologies/instant-client/downloads.html  

Unzip both into one directory, ex. /Users/me/instantclient_19_8. This will be your ORACLE_HOME.  
Set environment variables:  
export ORACLE_HOME=/Users/me/instantclient_19_8  
export TNS_ADMIN=$ORACLE_HOME/network/admin  
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$ORACLE_HOME  
export PATH=$PATH:$ORACLE_HOME  

(2) Make sure you have C compiler installed

(3) Installing OCILIB  
git clone https://github.com/vrogier/ocilib.git  
cd ocilib  
./configure --with-oracle-home=$ORACLE_HOME --with-oracle-lib-path=$ORACLE_HOME --with-oracle-headers-path=$ORACLE_HOME/sdk/include --disable-dependency-tracking  
make  
chmod 755 config/install-sh  
sudo make install  

Make sure there are no errors in either of these steps (warning are OK.)  

(4) If using SwiftOracle with SPM, make sure to set LD_LIBRARY_PATH as above and also include linker flags, ex., -Xlinker -L/usr/local/lib  

(5) If using Xcode, set the following project Build Settings:   

Header Search Paths -> /Users/me/instantclient_19_8/sdk/include, /usr/local/include.  
Library Search Paths -> /Users/me/instantclient_19_8, /usr/local/lib.  
Runpath Search Paths -> /Users/me/instantclient_19_8.  



PR are welcome.  

Here is what you can do:  

```swift
let service = OracleService(host: "dv", port:"1521", service: "xe")

let b = Connection(service: service, user:"broq", pwd:"anypassword")

try b.open()
b.autocommit = true


let cursor = try b.cursor()

try cursor.execute("select * from users where login=:login or 1=1", params: ["login": "user2"])
for r in cursor {
    print(r.dict)
    print(r.list)
    print(r["LOGIN"]!.string)
    print(r["ID"]!.int)
}

try cursor.execute("select * from sources where id=:id", params: ["id": 3])
for r in cursor {
    print(r)
}
try cursor.execute("select * from sources where reverse_enabled=:ids or 1=1", params: ["ids": 1.0 ])
for r in cursor {
    print(r["OWNER"]! as? String)
    print(r)
}

try cursor.execute("insert into users (id, login, alive) values (USERS_ID_SEQ.nextval, :2, :3) RETURNING id INTO :id ", params: ["2": "фіва", "3": 3,], register: ["id": .int])
cursor.register("id", type: .int)

for r in cursor {
    print(r)
}

print(cursor.affected)

```

REF Cursor example   

```swift
import Foundation
import SwiftOracle

// Create a DB stored function that returns a REF cursor
/* 
 create or replace function get_refcursor(i_type in varchar2, i_maxrows in number) return sys_refcursor as
 cv sys_refcursor;
 begin
 open cv for select object_name, object_id from user_objects where object_type = i_type and rownum <= i_maxrows;
 return cv;
 end;
 /
*/
 
let service = OracleService(from_string: "test_database")
let conn = Connection(service: service, user: "user", pwd: "password")
let sql = "select level as rnum, get_refcursor('PACKAGE', level) as cv from dual connect by level < 6"

try conn.open()
let mainCursor = try conn.cursor()
try mainCursor.execute(sql)
print("executed main cursor")

for r in mainCursor {
    print("main cursor row number: \(r["RNUM"]!.int)")
    let cursorPtr = r["CV"]!.cursor
    let cur = try conn.cursor(statementPtr: cursorPtr)
    try cur.executePreparedStatement()
    print("printing child cursor output")
    for r1 in cur {
        print("object_name: \(r1["OBJECT_NAME"]!.string), object_id: \(r1["OBJECT_ID"]!.int)")
    }
}


```


Unfortunately, the original SwiftOracle only supported one way, input bind variables. The output value returned by a procedure is not mapped to Swift BindVar instance. I haven't modified this interface yet.

There is a simple workaround: turn your procedure into a function that returns a value and use select myfunc(input_param) from dual;

If you can't modify the procedure, you can wrap it into a function to return the modified value. Here is an example.

Assuming your procedure is as follows, and parameter1 is in out parameter, and we want to return the modified value.
```
create or replace procedure test_proc(parameter1 in out varchar2) as
begin
  parameter1 := 'modified value'; 
end test_proc;
```
We can create a wrapper function as follows:

```
create or replace function test_func(parameter1 in varchar2) return varchar2 as
  myVar varchar2(100) := parameter1;
begin
  test_proc(myVar);
  return myVar;
end test_func;
```
And then use
```
select test_func('some value') from dual;
```

This will return "modified value".

In Swift, we would simple invoke the above select statement:
```
let sqlStr = "select test_func(:p1) from dual"
try cursor.execute(sqlStr, params: [":p1" : BindVar("some value")])
// fetch the data
while let row = cursor.nextSwifty() {
    for f in row.fields {
        responseString += "\(f.toString)\t"
    }
}
```



