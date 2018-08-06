require Logger

defmodule Exasol do
  use WebSockex
  alias Exasol.MessageRegister, as: Register

  @moduledoc "Exasol WebSocket-based SQL connector"

  @timeout 60_000
  @protocol_default "wss://"
  @query_path "/websockets/query"
  @valid_options [
    :name,
    :fetchsize,
    :delimiter,
    :multi,
    :user,
    :password,
    :password_encrypted,
    :event_type,
    :session_id,
    :systems,
    :period
  ]

  @doc "Connect to Exasol"
  def connect(url, user, password, options \\ []) do
    Register.start()
    opts = Keyword.merge(options, [{:server_name_indication, :disable}])

    case WebSockex.start_link(finalize_url(url), __MODULE__, :ok, opts) do
      {:ok, wsconn} -> finalize_connection(wsconn, user, password)
      {:error, error} -> {:error, error}
    end
  end

  @doc "Connect to Exasol and return a pipeable connection"
  def connect!(url, user, password) do
    {:ok, state} = connect(url, user, password)
    state
  end

  @doc "Execute a rowless SQL statement"
  def exec(query, {wsconn, authtoken}, options \\ %{}, recipient \\ nil) do
    dispatch(:execute, wsconn, authtoken, Register.next_id(), query, options, recipient)
  end

  @doc "Execute a query, returning status, rows and metadata"
  def query(query, {wsconn, authtoken}, options \\ %{}, recipient \\ nil) do
    dispatch(:query, wsconn, authtoken, Register.next_id(), query, options, recipient)
  end

  @doc "Fetch the next fetchsize batch of results"
  def next({wsconn, authtoken}, id, recipient \\ nil) do
    dispatch(:next, wsconn, authtoken, id, nil, %{}, recipient)
  end

  @doc "Skip any remaining rows of a query"
  def skip({wsconn, authtoken}, id, recipient \\ nil) do
    dispatch(:skip, wsconn, authtoken, id, nil, %{}, recipient)
  end

  @doc "Cancel a query"
  def cancel({wsconn, authtoken}, id) do
    wssend(wsconn, %{id: id, authtoken: authtoken, command: :cancel}, nil)
    {:ok, {wsconn, authtoken}}
  end

  @doc "Fetch the task table"
  def tasks({wsconn, authtoken}, recipient \\ nil) do
    dispatch(:tasks, wsconn, authtoken, Register.next_id(), nil, %{}, recipient)
  end

  @doc "Fetch the connections table"
  def connections({wsconn, authtoken}, recipient \\ nil) do
    dispatch(:connections, wsconn, authtoken, Register.next_id(), nil, %{}, recipient)
  end

  @doc "Forward monitoring events to the given process - options can contain restrictions for session_id and event_type"
  def monitor({wsconn, authtoken}, options \\ %{}, recipient \\ nil) do
    id = Register.next_id()

    wssend(
      wsconn,
      %{id: id, authtoken: authtoken, command: :monitor, options: options},
      recipient
    )

    {:ok, id}
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
      },
      nil
    )

    {:ok, {wsconn, authtoken}}
  end

  @doc "Close the connection to Exasol"
  def close({wsconn, _}) do
    if is_connected({wsconn, nil}) do
      WebSockex.send_frame(wsconn, :close)
    end

    {:ok, "closed"}
  end

  @doc "Handle incorrect close gracefully"
  def close(nil) do
    {:error, "Invalid connection"}
  end

  @doc "Handletermination of web socket"
  def terminate(reason, state) do
    case state do
      :ok ->
        :ok

      _ ->
        Logger.error("Exasol WebSocket Terminating:\n#{inspect(reason)}\n\n#{inspect(state)}\n")
    end

    exit(:normal)
  end

  @doc "Convert a query's output to a List of Maps of column => value"
  def map({:ok, results}) do
    %{"meta" => meta, "rows" => rows} = results

    colnames =
      meta
      |> Enum.map(fn %{"name" => name} ->
        name
        |> String.downcase()
        |> String.to_atom()
      end)

    rows
    |> Enum.map(fn row ->
      Enum.zip(colnames, row)
      |> Enum.into(%{})
    end)
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
    [Enum.map(meta, fn x -> x["name"] end) | rows]
  end

  def table({:error, results}) do
    {:error, results}
  end

  @doc "Are we connected?"
  def is_connected({wsconn, _authtoken}) do
    case Process.whereis(:exasol_message_register) do
      nil -> false
      _ -> Process.alive?(wsconn)
    end
  end

  def is_connected(nil) do
    false
  end

  @doc "Wait for results (default)"
  def await_results(timeout \\ @timeout) do
    receive do
      {:exasol_connect, %{"error" => true, "message" => error_message}} ->
        {:error, error_message}

      {:exasol_connect, %{"cancelled" => true, "message" => error_message}} ->
        {:error, error_message}

      {:exasol_connect, %{"error" => false} = response} ->
        {:ok, response}

      {:exasol_monitor, event} ->
        {:ok, event}

      {:error, error} ->
        {:error, error}

      {:error} ->
        {:error, "Unknown error"}
    after
      timeout -> {:error, "Timed out waiting for results"}
    end
  end

  @doc "Dump a message (example)"
  def dump_message(message) do
    IO.puts("EVENT: " <> inspect(message))
  end

  ##
  ## Inner workingnesses
  ##

  defp finalize_url(url) do
    prefix = if url =~ "s://", do: url, else: @protocol_default <> url
    prefix <> @query_path
  end

  defp finalize_connection(wsconn, user, password) do
    case authenticate(wsconn, user, password) do
      :ok ->
        receive do
          {:exasol_connect, %{"error" => true, "message" => error_message}} ->
            {:error, error_message}

          {:exasol_connect, %{"error" => false} = response} ->
            {:ok, {wsconn, response["task"]["authtoken"]}}
        after
          @timeout -> {:error, "Timed out waiting for authentication response"}
        end

      error ->
        error
    end
  end

  defp dispatch(calltype, wsconn, authtoken, id, query, options, recipient)
       when is_nil(recipient) do
    case wssend(
           wsconn,
           %{
             id: id,
             authtoken: authtoken,
             command: calltype,
             statement: to_string(query),
             options:
               options
               |> Map.take(@valid_options)
           },
           self()
         ) do
      :ok -> await_results(options[:timeout] || @timeout)
      error -> error
    end
  end

  defp dispatch(calltype, wsconn, authtoken, id, query, options, recipient) do
    case wssend(
           wsconn,
           %{
             id: id,
             authtoken: authtoken,
             command: calltype,
             statement: to_string(query),
             options:
               options
               |> Map.take(@valid_options)
           },
           recipient
         ) do
      :ok -> {:ok, id}
      error -> error
    end
  end

  defp authenticate(wsconn, user, password) do
    wssend(
      wsconn,
      %{
        id: Register.next_id(),
        command: "authenticate",
        options: %{user: user, password_encrypted: :base64.encode(password)}
      },
      self()
    )
  end

  defp wssend(wsconn, message, recipient) when is_nil(recipient) do
    wssend(wsconn, message, self())
  end

  defp wssend(wsconn, message, recipient) do
    case Process.alive?(wsconn) do
      true ->
        Register.put(message.id, recipient)
        WebSockex.send_frame(wsconn, {:text, Poison.encode!(message)})
        :ok

      false ->
        {:error, "Invalid Exasol connection"}
    end
  end

  def handle_frame({:text, text}, state) do
    response = Poison.decode!(text)
    id = response["task"]["id"]

    case Register.get(id) do
      {:ok, caller} ->
        respond(id, caller, response)
        {:ok, state}

      :error ->
        {:ok, state}
    end
  end

  def handle_frame(:close, state) do
    {:close, state}
  end

  def handle_disconnect(_, state) do
    {:ok, state}
  end

  defp respond(id, recipient, response) do
    case response["task"]["command"] do
      "monitor" ->
        respond(recipient, {:exasol_monitor, response})

      _ ->
        Register.delete(id)
        respond(recipient, {:exasol_connect, response})
    end
  end

  defp respond(recipient, response) when is_nil(recipient) do
    {:ok, response}
  end

  defp respond(recipient, response) when is_pid(recipient) do
    case Process.alive?(recipient) do
      true ->
        send(recipient, response)

      false ->
        {:error,
         "Process that initiated the Exasol connection (#{inspect(recipient)}) is no longer running"}
    end
  end

  defp respond(recipient, response) when is_function(recipient) do
    spawn(fn -> recipient.(response) end)
  end
end
