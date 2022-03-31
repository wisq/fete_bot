defmodule FeteBot.Notifier.Reactions do
  def on_reaction_add(event) do
    IO.inspect(event)
  end

  def on_reaction_remove(event) do
    IO.inspect(event)
  end
end
