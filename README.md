# CirroConnect

**An Elixir websocket-based SQL connector for Cirro**

CirroConnect allows Elixir programs to connect to Cirro (http://www.cirro.com) using its websocket API and issue federated queries.

## Installation

Add the following to `mix.exs` to include it in your project:

```elixir
def deps do
  [
    {:cirro_connect, ">= 0.1.0"},
  ]
end
```


## Usage

###Connecting to Cirro
Here, and in all subsequent examples, `cirro.host.com` refers to your Cirro installation's exposed websocket address.
The ws:// protocol is currently active as the default. wss:// support will become the default in an upcoming release. 

To connect to Cirro, use `connect()` or `connect!()`
```elixir
# return connection status
CirroConnect.connect("cirro.host.com","cirro_user","password")
{:ok, {#PID<0.209.0>, "347456094e6885c5-6a83-48e0-a0d7-f08326c720af2141803887"}}
# return connection for use in other CirroConnect calls
CirroConnect.connect!("cirro.host.com","cirro_user","password")
{#PID<0.218.0>, "1289850004088516e1-0f84-4e00-9988-691a4ffc22852010714971"}
    
```

### Connectivity check
You can determine if your connection is currently active using the `is_connected()` function.

```elixir
c=CirroConnect.connect!("cirro.host.com","cirro_user","password")
CirroConnect.is_connected(c)
true
CirroConnect.close(c)
CirroConnect.is_connected(c)
false
```

### Queries

####Basic selection
```elixir
conn=CirroConnect.connect!("cirro.host.com","cirro_user","password") 
"SELECT * from dbbox_postgres.oxon.public.person"
|> CirroConnect.query(conn) 
{:ok,
 %{"complete" => true, "count" => 3, "end" => 1513853929898, "error" => false,
   "meta" => [%{"name" => "id", "type" => "INTEGER"},
    %{"name" => "name", "type" => "VARCHAR"},
    %{"name" => "age", "type" => "INTEGER"}],
   "rows" => [["1", "Foople Smith", "23"], ["3", "Procras Tinatus", "54"],
    ["2", "オーマー・マズリ", "54"]], "start" => 1513853929747,
   "task" => %{"authtoken" => "21364823203979e007-c7af-4518-a396-fe5fb827c81b374209238",
     "cancelled" => false, "command" => "query", "id" => "675",
     "options" => %{},
     "statement" => "SELECT * from dbbox_postgres.oxon.public.person"}}}
```

####Selection as a 'table' with a header row
```elixir
conn=CirroConnect.connect!("cirro.host.com","cirro_user","password") 
"SELECT * from dbbox_postgres.oxon.public.person"
|> CirroConnect.query(conn) 
|> CirroConnect.table()
[["id", "name", "age"],
["1", "Foople Smith", "23"],["3", "Procras Tinatus", "54"],["2", "オーマー・マズリ", "54"]]
```

####Selection returning a 'table' with just the rows
```elixir
conn=CirroConnect.connect!("cirro.host.com","cirro_user","password")
"SELECT * from dbbox_postgres.oxon.public.person" 
|> CirroConnect.query(conn) 
|> CirroConnect.rows()
[["1", "Foople Smith", "23"],["3", "Procras Tinatus", "54"],["2", "オーマー・マズリ", "54"]]
```

####Selection returning each row as a map of column name to value
```elixir
conn=CirroConnect.connect!("cirro.host.com","cirro_user","password")
"SELECT * from dbbox_postgres.oxon.public.person" 
|> CirroConnect.query(conn) 
|> CirroConnect.map()
[%{age: "23", id: "1", name: "Foople Smith"},
 %{age: "54", id: "3", name: "Procras Tinatus"},
 %{age: "54", id: "2", name: "オーマー・マズリ"}]
```

####Shortcut for returning each row as a map
```elixir
conn=CirroConnect.connect!("cirro.host.com","cirro_user","password") 
"SELECT * from dbbox_postgres.oxon.public.person"
|> CirroConnect.query!(conn)
[%{age: "23", id: "1", name: "Foople Smith"},
 %{age: "54", id: "3", name: "Procras Tinatus"},
 %{age: "54", id: "2", name: "オーマー・マズリ"}]
```

####Execute non-row-returning queries
The results should contain the _count_ of the number of affected rows. 
```elixir
conn=CirroConnect.connect!("cirro.host.com","cirro_user","password")
"DELETE from dbbox_postgres.oxon.public.personcopy" 
|> CirroConnect.exec(conn)                                   
{:ok,
 %{"complete" => true, "count" => 2, "end" => 1513855015278, "error" => false,
   "meta" => [], "rows" => [], "start" => 1513855015101,
   "task" => %{"authtoken" => "82424824185de34cd-1eb7-492e-9de5-75315a97e6372099360753",
     "cancelled" => false, "command" => "execute", "id" => "676",
     "options" => %{},
     "statement" => "DELETE from dbbox_postgres.oxon.public.personcopy"}}}
```

####Connection handling
Queries are run on arbitrary connections maintained by a server-side connection pool. 
To run several commands on a specific connection using multiple calls, you must give it a name
```elixir
conn=CirroConnect.connect!("cirro.host.com","cirro_user","password")

# execute a query on a named connection
"SELECT * from dbbox_postgres.oxon.public.person"
|> CirroConnect.query(conn,%{name: "my_specific_connection"})

# the following is guaranteed to execute on the same internal connection as the above statement
"SELECT * from dbbox_oracle.oxon.public.person"
|> CirroConnect.query(conn,%{name: "my_specific_connection"})
```

You should explicitly close a named connection. 
However, it will be automatically cleaned up after 60 seconds of inactivity.
```elixir
conn=CirroConnect.connect!("cirro.host.com","cirro_user","password")
CirroConnect.close(conn,%{name: "my_specific_connection"})
```

####Fetching batches of rows
It is possible to fetch a limited number of rows per call.
This currently involves making an initial query with an optional _fetchsize_ value. This returns up to _fetchsize_ rows. 
The value of _complete_ is false if there are more rows to retrieve. These can be fetched by calling _next()_ with 
the _id_ from the original result's _task_.
If you don't require further results, you can cancel the query with `CirroConnect.cancel(conn,id)` using the same id.
This calling convention will hopefully be made easier to handle when wrapped in a stream (TODO). 
```elixir
conn=CirroConnect.connect!("cirro.host.com","cirro_user","password")
"SELECT * FROM dbbox_postgres.oxon.public.person"                                 
|> CirroConnect.query(conn,%{fetchsize: 2}) 
{:ok,
 %{"complete" => false, "count" => 3, "end" => 1513858116713, "error" => false,
   "meta" => [%{"name" => "id", "type" => "INTEGER"},
    %{"name" => "name", "type" => "VARCHAR"},
    %{"name" => "age", "type" => "INTEGER"}],
   "rows" => [["1", "Foople Smith", "23"], ["3", "Procras Tinatus", "54"]],
   "start" => 1513858116158,
   "task" => %{"authtoken" => "262905974c2922bf5-f28e-4c35-a2bf-a97fe93075d22088770177",
     "cancelled" => false, "command" => "query", "id" => "669",
     "options" => %{"fetchsize" => "2"},
     "statement" => "SELECT * FROM dbbox_postgres.oxon.public.person"}}}
CirroConnect.next(conn,"669")                                                              
{:ok,
 %{"complete" => true, "count" => 0, "end" => 1513858125766, "error" => false,
   "meta" => [%{"name" => "id", "type" => "INTEGER"},
    %{"name" => "name", "type" => "VARCHAR"},
    %{"name" => "age", "type" => "INTEGER"}],
   "rows" => [["2", "オーマー・マズリ", "54"]],
   "start" => 1513858116158,
   "task" => %{"authtoken" => "262905974c2922bf5-f28e-4c35-a2bf-a97fe93075d22088770177",
     "cancelled" => false, "command" => "query", "id" => "669",
     "options" => %{"fetchsize" => "2"},
     "statement" => "SELECT * FROM dbbox_postgres.oxon.public.person"}}}
# don't issue another next here, or the call will block     
```


####Multiple statements
You can run multiple statements in the one request. 
The results of SELECTS are concatenated. 
The default delimiter is \; but can be overriden using the delimiter parameter
```elixir
conn=CirroConnect.connect!("cirro.host.com","cirro_user","password")
"SELECT * from dbbox_postgres.oxon.public.person ; SELECT * from dbbox_oracle.dbo.public.person"
|> CirroConnect.query(conn,%{delimiter: ";"})

# speed up UNION ALL queries
"SELECT * from dbbox_postgres.oxon.public.person UNION ALL SELECT * from dbbox_oracle.dbo.public.person"
|> CirroConnect.query(conn,%{delimiter: "UNION ALL"})

```

#### Listing active connections
It is possible to get list of the current Cirro connections your websocket connection is using
```elixir
conn=CirroConnect.connect!("cirro.host.com","cirro_user","password")
CirroConnect.connections(conn)                                             
[["*", "com.cirro.jdbc.client.net.security.NetConnection40@2cedebbd",
  "Tue Jan 02 16:06:42 UTC 2018", "2979", "Idle"]]
```

#### Listing tasks
You can get a list of the current tasks you have initiated that have not yet completed
```elixir
conn=CirroConnect.connect!("cirro.host.com","cirro_user","password")
CirroConnect.tasks(conn)                                             
[]
```

#### Disconnecting
To close all of your connections, and disconnect your connection to Cirro
```elixir
connection=CirroConnect.connect!("cirro.host.com","cirro_user","password")
CirroConnect.close(connection)
```