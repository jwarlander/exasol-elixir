defmodule CirroConnect do
  use WebSockex
  alias CirroConnect.MessageRegister, as: Register

  @moduledoc "Cirro WebSocket-based SQL connector - Copyright Cirro Inc, 2018"

  @timeout 60_000
  @protocol_default "ws://" # TODO: get wss:// working with fresh cert

  @doc "Connect to Cirro"
  def connect(url, user, password) do
    Register.start()
    fullurl = if (url =~ "s://"), do: url, else: @protocol_default <> url <> "/websockets/query"
    {:ok, wsconn} = WebSockex.start_link(fullurl, __MODULE__, :ok)
    authenticate(wsconn, user, password)
    receive do
      {:cirro_connect, %{"error" => true, "message" => error_message}} -> {:error, error_message}
      {:cirro_connect, %{"error" => false} = response} -> {:ok, {wsconn, response["task"]["authtoken"]}}
    after
      @timeout -> {:error, "Timed out waiting for authentication response"}
    end
  end

  @doc "Connect to Cirro and return a pipeable connection"
  def connect!(url, user, password) do
    {:ok, state} = connect(url, user, password)
    state
  end

  @doc "Execute a rowless SQL statement"
  def exec(query, {wsconn, authtoken}, options \\ %{}) do
    dispatch(:execute, wsconn, authtoken, query, options)
  end

  @doc "Execute a query, returning status, rows and metadata"
  def query(query, {wsconn, authtoken}, options \\ %{}) do
    dispatch(:query, wsconn, authtoken, query, options)
  end

  @doc "Execute a query, returning rows and matadata without status"
  def query!(query, {wsconn, authtoken}, options \\ %{}) do
    dispatch(:query, wsconn, authtoken, query, options)
    |> map()
  end

  @doc "Fetch the next fetchsize batch of results"
  def next({wsconn, authtoken}, id) do
    wssend(wsconn, %{id: id, authtoken: authtoken, command: :next})
    await_results(wsconn)
  end

  @doc "Cancel a query"
  def cancel({wsconn, authtoken}, id) do
    wssend(wsconn, %{id: id, authtoken: authtoken, command: :cancel})
    {:ok, {wsconn, authtoken}}
  end

  @doc "Fetch the task table"
  def tasks({wsconn, authtoken}) do
    dispatch(:tasks, wsconn, authtoken, nil, %{})
    |> rows()
  end

  @doc "Fetch the connections table"
  def connections({wsconn, authtoken}) do
    dispatch(:connections, wsconn, authtoken, nil, %{})
    |> rows()
  end

  @doc "Close a named connection"
  def close({wsconn, authtoken}, %{name: name}) do
    wssend(
      wsconn,
      %{
        id: Register.next_id(),
        authtoken: authtoken,
        command: :close,
        options: %{
          name: name
        }
      }
    )
    {:ok, {wsconn, authtoken}}
  end

  @doc "Close the connection to Cirro"
  def close({wsconn, _}) do
    if is_connected({wsconn, nil}) do
      WebSockex.send_frame(wsconn, :close)
    end
    {:ok, "closed"}
  end

  @doc "Handle incorrect close gracefully"
  def close(nil) do
    {:error, "invalid connection"}
  end

  @doc "Handle abrupt termination of web socket"
  def terminate(reason, state) do
    IO.puts("\nCirroConnect WebSocket Terminating:\n#{inspect reason}\n\n#{inspect state}\n")
    exit(:normal)
  end

  @doc "Convert a query's output to a List of Maps of column => value"
  def map({:ok, results}) do
    %{"meta" => meta, "rows" => rows} = results
    colnames = meta
               |> Enum.map(
                    fn %{"name" => name} ->
                      name
                      |> String.downcase
                      |> String.to_atom
                    end
                  )
    rows
    |> Enum.map(
         fn row ->
           Enum.zip(colnames, row)
           |> Enum.into(%{})
         end
       )
  end

  def map({:error, results}) do
    {:error, results}
  end

  @doc "Return just the rows from a query"
  def rows({:ok, results}) do
    %{"rows" => rows} = results
    rows
  end

  def rows({:error, results}) do
    {:error, results}
  end

  @doc "Convert a query's output to a list of lists, where the first row contains the column names"
  def table({:ok, results}) do
    %{"meta" => meta, "rows" => rows} = results
    [Enum.map(meta, fn (x) -> x["name"] end) | rows]
  end

  def table({:error, results}) do
    {:error, results}
  end

  @doc "Are we connected?"
  def is_connected({wsconn, _authtoken}) do
    case Process.whereis(:cirro_message_register) do
      nil -> false
      _ -> Process.alive?(wsconn)
    end
  end

  def is_connected(nil) do
    false
  end

  ##
  ## Inner workingnesses
  ##

  defp dispatch(calltype, wsconn, authtoken, query, options) do
    wssend(
      wsconn,
      %{id: Register.next_id(), authtoken: authtoken, command: calltype, statement: to_string(query), options: options}
    )
    await_results(wsconn)
  end

  defp await_results(_wsconn) do
    receive do
      {:cirro_connect, %{"error" => true, "message" => error_message}} -> {:error, error_message}
      {:cirro_connect, %{"cancelled" => true, "message" => error_message}} -> {:error, error_message}
      {:cirro_connect, %{"error" => false} = response} -> {:ok, response}
      {:error} -> {:error, "Unknown error"}
    after
      @timeout -> {:error, "Timed out waiting for response"}
    end
  end

  defp authenticate(wsconn, user, password) do
    wssend(
      wsconn,
      %{
        id: Register.next_id(),
        command: "authenticate",
        options: %{
          user: user,
          password_encrypted: :base64.encode(password)
        }
      }
    )
  end

  defp wssend(wsconn, message) do
    Register.put(message.id, self())
    WebSockex.send_frame(wsconn, {:text, Poison.encode! message})
  end

  def handle_frame({:text, text}, state) do
    response = Poison.decode! text
    id = response["task"]["id"]
    case Register.get(id) do
      {:ok, caller} -> Register.delete(id)
                       send(caller, {:cirro_connect, response})
                       {:ok, state}
      :error -> {:ok, state}
    end
  end

  def handle_frame(:close, state) do
    {:close, state}
  end

  def handle_disconnect(_, state) do
    {:ok, state}
  end

end
