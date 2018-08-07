defmodule Exasol do
  @moduledoc """
  Exasol WebSocket-based SQL connector
  """
  use WebSockex
  require Logger

  @timeout 5_000
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

  @doc "Execute a rowless SQL statement"
  def exec(query, wsconn, options \\ %{}) do
    dispatch(:execute, wsconn, %{sqlText: query}, options)
  end

  @doc "Execute a query, returning status, rows and metadata"
  def query(query, wsconn, options \\ %{}) do
    dispatch(:execute, wsconn, %{sqlText: query}, options)
  end

  @doc "Fetch rows from a result set"
  def fetch(wsconn, handle, start_position, num_bytes) do
    query = %{resultSetHandle: handle, startPosition: start_position, numBytes: num_bytes}
    dispatch(:fetch, wsconn, query, %{})
  end

  @doc "Skip any remaining rows of a query"
  def close_result_set(wsconn, handles) when is_list(handles) do
    dispatch(:closeResultSet, wsconn, %{resultSetHandles: handles}, %{})
  end

  @doc "Cancel a query"
  def cancel(wsconn) do
    wssend(wsconn, %{command: :abortQuery})
    {:ok, wsconn}
  end

  @doc "Close the connection to Exasol"
  def close(wsconn) do
    if is_connected(wsconn) do
      wssend(wsconn, %{command: :disconnect})
      WebSockex.send_frame(wsconn, :close)
    end

    {:ok, "closed"}
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
    result = get_in(results, ["responseData", "results"]) |> Enum.at(0)
    %{"resultSet" => %{"columns" => meta, "data" => rows}} = result
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

  @doc "Dump a message (example)"
  def dump_message(message) do
    IO.puts("EVENT: " <> inspect(message))
  end

  ##
  ## Inner workingnesses
  ##

  defp finalize_connection(wsconn, user, password) do
    with {:ok, key} <- start_login(wsconn),
         :ok = authenticate(wsconn, user, password, key),
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

  defp dispatch(calltype, wsconn, query, options) do
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
    case Process.alive?(wsconn) do
      true ->
        WebSockex.send_frame(wsconn, {:text, Poison.encode!(message)})
        :ok

      false ->
        {:error, "Invalid Exasol connection"}
    end
  end

  def handle_frame({:text, text}, %{caller: caller} = state) do
    response = Poison.decode!(text)
    {:ok, _} = respond(caller, response)
    {:ok, state}
  end

  def handle_frame(:close, state) do
    {:close, state}
  end

  def handle_disconnect(_, state) do
    {:ok, state}
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
