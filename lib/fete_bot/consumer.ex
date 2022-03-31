defmodule FeteBot.Consumer do
  use Nostrum.Consumer

  # alias Nostrum.Api

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    case msg.content do
      "!fetebot " <> rest ->
        FeteBot.Commands.run(rest, msg)

      _ ->
        :ignore
    end
  end

  def handle_event({:MESSAGE_REACTION_ADD, event, _}) do
    case event.guild_id do
      nil -> FeteBot.Notifier.Reactions.on_reaction_add(event)
      id when is_integer(id) -> FeteBot.Tracker.Reactions.on_reaction_add(event)
    end
  end

  def handle_event({:MESSAGE_REACTION_REMOVE, event, _}) do
    case event.guild_id do
      nil -> FeteBot.Notifier.Reactions.on_reaction_remove(event)
      _ -> :noop
    end
  end

  def handle_event({event, _, _}) do
    IO.inspect(event)
    :noop
  end
end
