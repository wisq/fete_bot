defmodule FeteBot.Consumer do
  use Nostrum.Consumer
  require Logger

  alias Nostrum.Cache.Me

  def handle_event({:GUILD_AVAILABLE, guild, _ws_state}) do
    Logger.info("Now active on guild ##{guild.id}: #{guild.name}")
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
    cond do
      event.user_id == Me.get().id -> :noop
      is_nil(event.guild_id) -> FeteBot.Notifier.Reactions.on_reaction_add(event)
      is_integer(event.guild_id) -> FeteBot.Tracker.Reactions.on_reaction_add(event)
    end
  end

  def handle_event({:MESSAGE_REACTION_REMOVE, event, _}) do
    cond do
      event.user_id == Me.get().id -> :noop
      is_nil(event.guild_id) -> FeteBot.Notifier.Reactions.on_reaction_remove(event)
      is_integer(event.guild_id) -> :noop
    end
  end

  def handle_event({_event, _, _}) do
    # IO.inspect(event)
    :noop
  end
end
