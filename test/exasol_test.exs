defmodule ExasolTest do
  use ExUnit.Case
  doctest Exasol

  test "Try to connect" do
    assert {:ok, _} = Exasol.connect("ws://localhost:8563", "sys", "exasol")
  end

  test "Execute a simple query" do
    {:ok, conn} = Exasol.connect("ws://localhost:8563", "sys", "exasol", debug: [:trace])

    result =
      Exasol.query("SELECT 1 AS foo, 'a' AS bar UNION ALL SELECT 2 AS foo, 'b' AS bar", conn)

    assert {:ok, %{"responseData" => %{"numResults" => 1}}} = result
    assert Exasol.table(result) == [["FOO", "BAR"], [1, 2], ["a", "b"]]
  end
end
