defmodule ExasolTest do
  use ExUnit.Case
  doctest Exasol

  test "Try to connect" do
    assert {:ok, _} = Exasol.connect("ws://localhost:8563", "sys", "exasol", debug: [:trace])
  end
end
