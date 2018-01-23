defmodule CirroConnectTest do
  use ExUnit.Case
  doctest CirroConnect

  test "Try to connect" do
    assert CirroConnect.connect("localhost:8464", "root", "test") == {:ok, _}
  end
end
