defmodule PreprocessingTest do
  use ExUnit.Case
  doctest Preprocessing

  test "greets the world" do
    assert Preprocessing.hello() == :world
  end
end
