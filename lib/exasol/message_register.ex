defmodule Exasol.MessageRegister do
  use GenServer

  @moduledoc """
  Message Register for Exasol WebSocket-based SQL connector
  This keeps track of which process made what request
  """

  def start() do
    GenServer.start(__MODULE__, :ok, name: :exasol_message_register)
  end

  def get(message_id) do
    GenServer.call(:exasol_message_register, {:get, message_id})
  end

  def put(message_id, listener) do
    GenServer.cast(:exasol_message_register, {:put, message_id, listener})
  end

  def delete(message_id) do
    GenServer.cast(:exasol_message_register, {:delete, message_id})
  end

  def next_id() do
    System.unique_integer
    |> to_string
  end

  def init(:ok) do
    {:ok, %{}}
  end

  def handle_call({:get, name}, _from, map) do
    {:reply, Map.fetch(map, name), map}
  end

  def handle_cast({:put, message_id, listener}, map) do
    {:noreply, Map.put(map, message_id, listener)}
  end

  def handle_cast({:delete, message_id}, map) do
    {:noreply, Map.delete(map, message_id)}
  end

end
