defmodule ExasolTest do
  @moduledoc false
  use ExUnit.Case
  doctest Exasol

  @simple_query "SELECT 1 AS foo"
  @multiple_row_query "SELECT 1 AS foo, 'a' AS bar UNION ALL SELECT 2 AS foo, 'b' AS bar"

  test "Try to connect" do
    assert {:ok, _} = Exasol.connect("ws://localhost:8563", "sys", "exasol")
  end

  test "Execute a simple query" do
    {:ok, conn} = Exasol.connect("ws://localhost:8563", "sys", "exasol")
    result = Exasol.query(@simple_query, conn)

    assert {:ok, %{"responseData" => %{"numResults" => 1}}} = result
  end

  test "Convert query results to a table" do
    {:ok, conn} = Exasol.connect("ws://localhost:8563", "sys", "exasol")
    result = Exasol.query(@multiple_row_query, conn)

    assert Exasol.table(result) == [["FOO", "BAR"], [1, 2], ["a", "b"]]
  end

  test "Convert query results to a map" do
    {:ok, conn} = Exasol.connect("ws://localhost:8563", "sys", "exasol")
    result = Exasol.query(@multiple_row_query, conn)

    assert Exasol.map(result) == [%{"FOO" => 1, "BAR" => "a"}, %{"FOO" => 2, "BAR" => "b"}]
  end

  test "Inserting into a table" do
    {:ok, conn} = Exasol.connect("ws://localhost:8563", "sys", "exasol")
    Exasol.exec("CREATE TABLE public.dummy (foo INTEGER, bar VARCHAR(5))", conn)
    Exasol.exec("INSERT INTO public.dummy VALUES (1, 'beep')", conn)
    result = Exasol.query("SELECT * FROM public.dummy", conn)

    assert Exasol.map(result) == [%{"FOO" => 1, "BAR" => "beep"}]
  end

  test "Closing a connection" do
    {:ok, conn} = Exasol.connect("ws://localhost:8563", "sys", "exasol")
    assert {:ok, %{"responseData" => _}} = Exasol.query(@simple_query, conn)
    assert {:ok, %{"status" => "ok"}} = Exasol.close(conn)
    assert {:error, :disconnected} = Exasol.query(@simple_query, conn)
  end
end
