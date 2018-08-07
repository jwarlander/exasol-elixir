# Exasol

**An Elixir websocket-based SQL connector for Exasol**

Allows Elixir programs to connect to Exasol (https://www.exasol.com/) using its websocket API and issue queries.

_**NOTE:** Project is being adapted for Exasol; it is currently not in a working state for that purpose, however.._

Based on [CirroConnect](https://github.com/cirroinc/cirro_connect) - Copyright Cirro Inc, 2018.

## Installation

Add the following to `mix.exs` to include it in your project:

```elixir
def deps do
  [
    {:exasol, ">= 0.1.0"},
  ]
end
```


## Usage

### Connecting to Exasol
Here, and in all subsequent examples, `exasol.host.com` refers to your Exasol installation's exposed websocket address.
The ws:// protocol is currently active as the default. wss:// support will become the default in an upcoming release.

To connect to Exasol, use `connect()` or `connect!()`
```elixir
# return connection status
Exasol.connect("exasol.host.com","exasol_user","password")
{:ok, {#PID<0.209.0>, "347456094e6885c5-6a83-48e0-a0d7-f08326c720af2141803887"}}
# return connection for use in other Exasol calls
Exasol.connect!("exasol.host.com","exasol_user","password")
{#PID<0.218.0>, "1289850004088516e1-0f84-4e00-9988-691a4ffc22852010714971"}

```

### Connectivity check
You can determine if your connection is currently active using the `is_connected()` function.

```elixir
c=Exasol.connect!("exasol.host.com","exasol_user","password")
Exasol.is_connected(c)
true
Exasol.close(c)
Exasol.is_connected(c)
false
```

### Queries

#### Basic selection
```elixir
conn=Exasol.connect!("exasol.host.com","exasol_user","password")
"SELECT * FROM public.person"
|> Exasol.query(conn)
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
     "statement" => "SELECT * FROM public.person"}}}
```

#### Selection as a 'table' with a header row
```elixir
conn=Exasol.connect!("exasol.host.com","exasol_user","password")
"SELECT * FROM public.person"
|> Exasol.query(conn)
|> Exasol.table()
[["id", "name", "age"],
["1", "Foople Smith", "23"],["3", "Procras Tinatus", "54"],["2", "オーマー・マズリ", "54"]]
```

#### Selection returning a 'table' with just the rows
```elixir
conn=Exasol.connect!("exasol.host.com","exasol_user","password")
"SELECT * FROM public.person"
|> Exasol.query(conn)
|> Exasol.rows()
[["1", "Foople Smith", "23"],["3", "Procras Tinatus", "54"],["2", "オーマー・マズリ", "54"]]
```

#### Selection returning each row as a map of column name to value
```elixir
conn=Exasol.connect!("exasol.host.com","exasol_user","password")
"SELECT * FROM public.person"
|> Exasol.query(conn)
|> Exasol.map()
[%{age: "23", id: "1", name: "Foople Smith"},
 %{age: "54", id: "3", name: "Procras Tinatus"},
 %{age: "54", id: "2", name: "オーマー・マズリ"}]
```

#### Execute non-row-returning queries
The results should contain the _count_ of the number of affected rows.
```elixir
conn=Exasol.connect!("exasol.host.com","exasol_user","password")
"DELETE FROM public.personcopy"
|> Exasol.exec(conn)
{:ok,
 %{"complete" => true, "count" => 2, "end" => 1513855015278, "error" => false,
   "meta" => [], "rows" => [], "start" => 1513855015101,
   "task" => %{"authtoken" => "82424824185de34cd-1eb7-492e-9de5-75315a97e6372099360753",
     "cancelled" => false, "command" => "execute", "id" => "676",
     "options" => %{},
     "statement" => "DELETE FROM public.personcopy"}}}
```

#### Connection handling
Queries are run on arbitrary connections maintained by a server-side connection pool.
To run several commands on a specific connection using multiple calls, you must give it a name
```elixir
conn=Exasol.connect!("exasol.host.com","exasol_user","password")

# execute a query on a named connection
"SELECT * FROM public.person"
|> Exasol.query(conn,%{name: "my_specific_connection"})

# the following is guaranteed to execute on the same internal connection as the above statement
"SELECT * FROM public.person"
|> Exasol.query(conn,%{name: "my_specific_connection"})
```

You should explicitly close a named connection.
However, it will be automatically cleaned up after 60 seconds of inactivity.
```elixir
conn=Exasol.connect!("exasol.host.com","exasol_user","password")
Exasol.close(conn,%{name: "my_specific_connection"})
```

#### Fetching batches of rows
It is possible to fetch a limited number of rows per call.
This currently involves making an initial query with an optional _fetchsize_ value. This returns up to _fetchsize_ rows.
The value of _complete_ is false if there are more rows to retrieve. These can be fetched by calling _next()_ with
the _id_ from the original result's _task_.
If you don't require further results, you can cancel the query with `Exasol.cancel(conn,id)` using the same id.
This calling convention will hopefully be made easier to handle when wrapped in a stream (TODO).
```elixir
conn=Exasol.connect!("exasol.host.com","exasol_user","password")
"SELECT * FROM public.person"
|> Exasol.query(conn,%{fetchsize: 2})
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
     "statement" => "SELECT * FROM public.person"}}}
Exasol.next(conn,"669")
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
     "statement" => "SELECT * FROM public.person"}}}
# don't issue another next here, or the call will block
```


#### Multiple statements
You can run multiple statements in the one request.
The results of SELECTS are concatenated unless the `multi` option is `true` in which case the results will be sent back in response to calls to `next()`.
The default delimiter is `\;` but can be overriden using the `delimiter` parameter.
```elixir
conn=Exasol.connect!("exasol.host.com","exasol_user","password")
"SELECT * FROM public.person ; SELECT * FROM public.person"
|> Exasol.query(conn,%{delimiter: ";"})

# speed up UNION ALL queries
"SELECT * FROM public.person UNION ALL SELECT * FROM public.person"
|> Exasol.query(conn,%{delimiter: "UNION ALL"})

```

#### Listing active connections
It is possible to get list of the current Exasol connections your websocket connection is using
```elixir
conn=Exasol.connect!("exasol.host.com","exasol_user","password")
Exasol.connections(conn)
[["*", "com.cirro.jdbc.client.net.security.NetConnection40@2cedebbd",
  "Tue Jan 02 16:06:42 UTC 2018", "2979", "Idle"]]
```

#### Listing tasks
You can get a list of the current tasks you have initiated that have not yet completed
```elixir
conn=Exasol.connect!("exasol.host.com","exasol_user","password")
Exasol.tasks(conn)
[]
```

#### Monitoring Exasol
To listen to Exasol monitoring events, bind a process or function via the `monitor` function.
A process will then receive `{:exasol_monitor, event}` messages, whereas a function will just be called with these messages.
The event_type and session_id can be filtered using the optional options.
Exasol.watch_events is provided as an example.
```elixir
Exasol.connect!("exasol.host.com","exasol_user","password") |>
Exasol.monitor(%{event_type: "query"}, &Exasol.dump_message/1)
```

#### Disconnecting
To close all of your connections, and disconnect your connection to Exasol
```elixir
connection=Exasol.connect!("exasol.host.com","exasol_user","password")
Exasol.close(connection)
```

#### Custom message handling
By default, responses from Exasol are received by the current process.
Therefore each call will usually block until the results are returned.
You can provide custom recipient function or process to handle incoming messages.
Processes will receive messages, whereas functions will be supplied the message as an argument.
The process or function argument is an optional parameter after the options parameter.

Some examples
```elixir
# Function example
Exasol.query("SELECT * FROM EXA_ALL_ROLES",conn,%{delimiter: ";"},&MyThing.handle_results/1)
# Process example
pid=spawn(MyThing,:wait_for_exasol_messages,[])
Exasol.query("SELECT * FROM EXA_ALL_ROLES",conn,%{delimiter: ";"},pid)
```

The default process message handler looks like this:
```elixir
 def await_results() do
    receive do
      {:exasol_connect, %{"error" => true, "message" => error_message}} -> {:error, error_message}
      {:exasol_connect, %{"cancelled" => true, "message" => error_message}} -> {:error, error_message}
      {:exasol_connect, %{"error" => false} = response} -> {:ok, response}
      {:exasol_monitor, event} -> {:ok, event}
      {:error, error} -> {:error, error}
      {:error} -> {:error, "Unknown error"}
    end
  end
```

## Testing

Start a Docker instance of Exasol:

    docker run --detach --privileged --stop-timeout 120 -p 127.0.0.1:8563:8888 exasol/docker-db:latest

..then run tests:

    mix test
