defmodule FeteBotTest do
  use ExUnit.Case
  doctest FeteBot

  test "greets the world" do
    assert FeteBot.hello() == :world
  end
end
