defmodule FeteBot.Tracker.Reactions do
  require Logger

  alias Nostrum.Struct.{Message, Emoji, User, Event.MessageReactionAdd}
  alias Nostrum.Cache.Me

  alias FeteBot.{Tracker, Notifier}
  alias FeteBot.Discord

  @reaction_commands %{
    "\u{23F0}" => :setup_alarms
  }

  # We merge the actual counts into this, ensuring
  # that we handle the complete absence of the emoji.
  @default_reaction_counts Map.new(@reaction_commands, fn {e, _} -> {e, 0} end)

  def on_reaction_add(%MessageReactionAdd{emoji: emoji} = event) do
    case Map.fetch(@reaction_commands, Emoji.api_name(emoji)) do
      {:ok, command} -> on_command(command, event)
      :error -> :noop
    end
  end

  defp on_command(:setup_alarms, event) do
    if Tracker.is_tracker_message?(event.channel_id, event.message_id) do
      Notifier.setup_alarms(event.user_id)
      Discord.delete_user_reaction(event.channel_id, event.message_id, event.emoji, event.user_id)
    end
  end

  def update(msg) do
    Map.merge(
      @default_reaction_counts,
      reaction_counts_by_emoji(msg)
    )
    |> Enum.each(&update_message_reactions(msg, &1))
  end

  defp reaction_counts_by_emoji(%Message{reactions: nil}), do: %{}

  defp reaction_counts_by_emoji(%Message{reactions: reactions}) do
    reactions |> Map.new(fn r -> {Emoji.api_name(r.emoji), r.count} end)
  end

  defp update_message_reactions(msg, {emoji, count}) do
    case Map.fetch(@reaction_commands, emoji) do
      {:ok, _} -> ensure_one_reaction(msg, emoji, count)
      :error -> delete_unknown_reaction(msg, emoji)
    end
  end

  defp ensure_one_reaction(_msg, _emoji, 1), do: :noop

  defp ensure_one_reaction(msg, emoji, 0) do
    Logger.info("Creating #{emoji} reaction on message ##{msg.id}.")
    Discord.create_reaction(msg.channel_id, msg.id, emoji)
  end

  defp ensure_one_reaction(msg, emoji, count) when count > 0 do
    Logger.warn("Too many #{emoji} reactions (#{count}) on message ##{msg.id}, pruning.")

    me_id = Me.get().id

    with {:ok, users} <- Discord.get_reactions(msg.channel_id, msg.id, emoji) do
      users
      |> Enum.each(fn
        %User{id: ^me_id} -> :noop
        %User{id: uid} -> Discord.delete_user_reaction(msg.channel_id, msg.id, emoji, uid)
      end)
    end
  end

  defp delete_unknown_reaction(msg, emoji) do
    Logger.warn("Deleting unknown reaction #{inspect(emoji)} on message ##{msg.id}")
    Discord.delete_reaction(msg.channel_id, msg.id, emoji)
  end
end
