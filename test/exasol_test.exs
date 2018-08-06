defmodule ExasolTest do
  use ExUnit.Case
  doctest Exasol

  test "Try to connect" do
    assert Exasol.connect("localhost:8464", "root", "test") == {:ok, _}
  end
end
