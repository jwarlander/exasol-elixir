defmodule Exasol do
  @moduledoc """
  Exasol WebSocket-based SQL connector
  """
  use WebSockex
  require Logger

  @fetch_size 64_000_000
  @timeout 15_000
  @valid_attributes [
    :autocommit,
    :compressionEnabled,
    :currentSchema,
    :dateFormat,
    :dateLanguage,
    :datetimeFormat,
    :defaultLikeEscapeCharacter,
    :feedbackInterval,
    :numericCharacters,
    :openTransaction,
    :queryTimeout,
    :snapshotTransactionsEnabled,
    :timestampUtcEnabled,
    :timezone,
    :timeZoneBehavior
  ]

  ##
  ## Public API - Connection Handling
  ##

  @doc "Connect to Exasol"
  def connect(url, user, password, options \\ []) do
    opts = Keyword.merge(options, [{:server_name_indication, :disable}])

    case WebSockex.start_link(url, __MODULE__, %{caller: self()}, opts) do
      {:ok, wsconn} -> finalize_connection(wsconn, user, password)
      {:error, error} -> {:error, error}
    end
  end

  @doc "Connect to Exasol and return a pipeable connection"
  def connect!(url, user, password, options \\ []) do
    {:ok, state} = connect(url, user, password, options)
    state
  end

  @doc "Close the connection to Exasol"
  def close(wsconn) do
    WebSockex.cast(wsconn, :close)
    await_results(@timeout)
  end

  @doc "Are we connected?"
  def is_connected(nil), do: false

  def is_connected(wsconn) do
    Process.alive?(wsconn)
  end

  ##
  ## Public API - Queries
  ##

  @doc "Execute an SQL statement, discarding the results"
  def exec(query, wsconn, options \\ %{}) do
    case dispatch(:execute, wsconn, %{sqlText: query}, options) do
      {:ok, response} ->
        {:ok, _} = close_result_sets(wsconn, response["responseData"]["results"])
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Execute a query, returning status, rows and metadata

  Note that a `resultSetHandle` might be returned, which then would have to be
  used in order to get the actual data, and then should be closed using
  `close_result_sets/2`
  """
  def query(query, wsconn, options \\ %{}) do
    dispatch(:execute, wsconn, %{sqlText: query}, options)
  end

  def query_all(query, wsconn, options \\ %{}) do
    case query(query, wsconn, options) do
      {:ok, response} ->
        {:ok, new_response} = do_query_all(response, wsconn, options)
        {:ok, _} = close_result_sets(wsconn, response["responseData"]["results"])
        {:ok, new_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_query_all(response, wsconn, options) do
    results = get_in(response, ["responseData", "results"])
    fetch_size = Map.get(options, :fetchSize, @fetch_size)

    case Enum.at(results, 0) do
      %{"resultSet" => %{"numRows" => 0}} ->
        {:ok, response}

      %{"resultSet" => %{"data" => _}} ->
        {:ok, response}

      %{"resultSet" => %{"resultSetHandle" => _}} = result ->
        {:ok, new_result} = fetch_all(wsconn, result, fetch_size)
        {:ok, put_in(response, ["responseData", "results"], [new_result])}
    end
  end

  @doc "Fetch rows from a result set"
  def fetch(wsconn, handle, start_position, num_bytes) do
    query = %{resultSetHandle: handle, startPosition: start_position, numBytes: num_bytes}
    dispatch(:fetch, wsconn, query, %{})
  end

  def fetch_all(wsconn, result, num_bytes, position \\ 0, rows \\ []) do
    handle = get_in(result, ["resultSet", "resultSetHandle"])
    {:ok, response} = fetch(wsconn, handle, position, num_bytes)

    new_rows = get_in(response, ["responseData", "data"])
    rows = append_rows(rows, new_rows)

    num_rows = get_in(response, ["responseData", "numRows"])
    total_rows = get_in(result, ["resultSet", "numRows"])

    if position + num_rows < total_rows do
      fetch_all(wsconn, result, num_bytes, position + num_rows, rows)
    else
      new_result =
        result
        |> put_in(["resultSet", "data"], rows)
        |> put_in(["resultSet", "numRowsInMessage"], total_rows)

      {:ok, new_result}
    end
  end

  defp append_rows([], new_rows), do: new_rows

  defp append_rows(rows, new_rows) do
    for {col_cur, col_new} <- Enum.zip(rows, new_rows) do
      col_cur ++ col_new
    end
  end

  @doc "Skip any remaining rows of a query"
  def close_result_set(wsconn, handles) when is_list(handles) do
    dispatch(:closeResultSet, wsconn, %{resultSetHandles: handles}, %{})
  end

  @doc "Close result sets from a given list of results"
  def close_result_sets(wsconn, results) when is_list(results) do
    handles =
      results
      |> Enum.filter(&has_result_set?/1)
      |> Enum.map(fn %{"resultSet" => %{"resultSetHandle" => handle}} -> handle end)

    dispatch(:closeResultSet, wsconn, %{resultSetHandles: handles})
  end

  def close_result_sets(_, nil), do: {:ok, :no_result_sets}

  defp has_result_set?(%{"resultSet" => %{"resultSetHandle" => _}}), do: true
  defp has_result_set?(_), do: false

  @doc "Cancel a query"
  def cancel(wsconn) do
    wssend(wsconn, %{command: :abortQuery})
    {:ok, wsconn}
  end

  ##
  ## Public API - Data Transformation
  ##

  @doc "Convert a query's output to a List of Maps of column => value"
  def map(%{"responseData" => %{"results" => results}}),
    do: Enum.flat_map(results, &do_map/1)

  def map({:ok, %{"responseData" => %{"results" => results}}}),
    do: Enum.flat_map(results, &do_map/1)

  def map({:error, results}),
    do: {:error, results}

  defp do_map(%{"resultSet" => %{"numRows" => 0}}), do: []

  defp do_map(%{"resultSet" => %{"columns" => meta, "data" => cols}}) do
    colnames = Enum.map(meta, fn %{"name" => name} -> name end)

    cols
    |> Enum.zip()
    |> Enum.map(fn fields ->
      colnames
      |> Enum.zip(Tuple.to_list(fields))
      |> Enum.into(%{})
    end)
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
    result = get_in(results, ["responseData", "results"]) |> Enum.at(0)
    %{"resultSet" => %{"columns" => meta, "data" => rows}} = result
    [Enum.map(meta, fn x -> x["name"] end) | rows]
  end

  def table({:error, results}) do
    {:error, results}
  end

  ##
  ## Inner workingnesses
  ##

  defp finalize_connection(wsconn, user, password) do
    with {:ok, key} <- start_login(wsconn),
         :ok <- authenticate(wsconn, user, password, key),
         do: {:ok, wsconn}
  end

  defp start_login(wsconn) do
    result =
      wssend(wsconn, %{
        command: "login",
        protocolVersion: 1
      })

    case result do
      :ok ->
        receive do
          %{"status" => "ok", "responseData" => %{"publicKeyPem" => key}} ->
            {:ok, key}

          %{"status" => "error", "exception" => %{"text" => error_message}} ->
            {:error, error_message}

          msg ->
            {:error, {:unknown_response, inspect(msg)}}
        after
          @timeout -> {:error, "Timed out waiting for authentication response"}
        end

      error ->
        error
    end
  end

  defp authenticate(wsconn, user, password, key) do
    result =
      wssend(wsconn, %{
        username: user,
        password: encrypt(password, key),
        useCompression: false
      })

    case result do
      :ok ->
        receive do
          %{"status" => "ok", "responseData" => %{"sessionId" => _id}} ->
            :ok

          %{"status" => "error", "exception" => %{"text" => error_message}} ->
            {:error, error_message}

          msg ->
            {:error, {:unknown_response, inspect(msg)}}
        after
          @timeout -> {:error, "Timed out waiting for authentication response"}
        end

      error ->
        error
    end
  end

  defp encrypt(str, pem) do
    [entry] = :public_key.pem_decode(pem)
    key = :public_key.pem_entry_decode(entry)

    str
    |> :public_key.encrypt_public(key)
    |> Base.encode64()
  end

  defp dispatch(calltype, wsconn, query, options \\ %{}) do
    case wssend(
           wsconn,
           Map.merge(query, %{
             command: calltype,
             attributes: Map.take(options, @valid_attributes)
           })
         ) do
      :ok -> await_results(options[:timeout] || @timeout)
      error -> error
    end
  end

  defp wssend(wsconn, message) do
    if Process.alive?(wsconn) do
      WebSockex.cast(wsconn, {:send, message})
    else
      {:error, :disconnected}
    end
  end

  defp await_results(timeout) do
    receive do
      %{"status" => "error", "exception" => %{"text" => error_message}} ->
        {:error, error_message}

      %{"status" => "ok"} = response ->
        {:ok, response}

      {:error, error} ->
        {:error, error}

      {:error} ->
        {:error, "Unknown error"}
    after
      timeout -> {:error, "Timed out waiting for results"}
    end
  end

  ##
  ## WebSockex Callbacks
  ##

  def handle_frame({:text, text}, %{caller: caller} = state) do
    response = Poison.decode!(text)
    {:ok, _} = respond(caller, response)
    {:ok, state}
  end

  def handle_frame(:close, state) do
    {:close, state}
  end

  def handle_cast(:close, state) do
    {:reply, {:text, Poison.encode!(%{command: :disconnect})}, Map.put(state, :stage, :closing)}
  end

  def handle_cast({:send, _}, %{stage: :closing, caller: caller} = state) do
    respond(caller, {:error, :disconnected})
    {:ok, state}
  end

  def handle_cast({:send, message}, state) do
    {:reply, {:text, Poison.encode!(message)}, state}
  end

  def handle_disconnect(_, state) do
    IO.puts("Disconnecting (#{inspect(state)})")
    {:ok, state}
  end

  @doc "Handle termination of web socket"
  def terminate(reason, state) do
    case state do
      %{stage: :closing} ->
        :ok

      _ ->
        Logger.error("Exasol WebSocket Terminating:\n#{inspect(reason)}\n\n#{inspect(state)}\n")
    end

    exit(:normal)
  end

  defp respond(recipient, response) when is_nil(recipient) do
    {:ok, response}
  end

  defp respond(recipient, response) when is_pid(recipient) do
    case Process.alive?(recipient) do
      true ->
        send(recipient, response)
        {:ok, response}

      false ->
        {:error,
         "Process that initiated the Exasol connection (#{inspect(recipient)}) is no longer running"}
    end
  end

  defp respond(recipient, response) when is_function(recipient) do
    spawn(fn -> recipient.(response) end)
  end
end
