# SwiftOracle
OCILIB wrapper for Swift, linux compatible

Added Date support;
Added a dependency on C bridge to OCILIB (swift 5 compatible)

This is wrapper for ocilib (https://github.com/vrogier/ocilib). 

Installation
(1) Installing Oracle Instant Client  
Download Basic package (zip) and SDK package (zip) for your platform from https://www.oracle.com/database/technologies/instant-client/downloads.html  

Unzip both into one directory, ex. ~/instantclient_19_8. This will be your ORACLE_HOME.  
Set environment variables:  
export ORACLE_HOME=~/instantclient_19_8  
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
(5) If using Xcode, 




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
