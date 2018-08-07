defmodule ExasolTest do
  @moduledoc false
  use ExUnit.Case
  doctest Exasol

  test "Try to connect" do
    assert {:ok, _} = Exasol.connect("ws://localhost:8563", "sys", "exasol")
  end

  test "Execute a simple query" do
    {:ok, conn} = Exasol.connect("ws://localhost:8563", "sys", "exasol")

    result = Exasol.query("SELECT 1 AS foo", conn)

    assert {:ok, %{"responseData" => %{"numResults" => 1}}} = result
  end

  test "Convert query results to a table" do
    {:ok, conn} = Exasol.connect("ws://localhost:8563", "sys", "exasol")

    result =
      Exasol.query("SELECT 1 AS foo, 'a' AS bar UNION ALL SELECT 2 AS foo, 'b' AS bar", conn)

    assert Exasol.table(result) == [["FOO", "BAR"], [1, 2], ["a", "b"]]
  end

  test "Convert query results to a map" do
    {:ok, conn} = Exasol.connect("ws://localhost:8563", "sys", "exasol")

    result =
      Exasol.query("SELECT 1 AS foo, 'a' AS bar UNION ALL SELECT 2 AS foo, 'b' AS bar", conn)

    assert Exasol.map(result) == [%{"FOO" => 1, "BAR" => "a"}, %{"FOO" => 2, "BAR" => "b"}]
  end
end
