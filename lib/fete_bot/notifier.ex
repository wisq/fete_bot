defmodule FeteBot.Notifier do
  require Logger

  # alias FeteBot.Repo
  # alias FeteBot.Tracker.Channel

  alias Nostrum.Api, as: Discord
  alias Nostrum.Struct.{Message, Emoji, User}
  alias Nostrum.Cache.Me

  @alarm_clock "\u{23F0}"

  def on_reaction_add(_) do
    :pending
  end

  def update_reactions(msg) do
    reaction_counts_by_emoji(msg)
    |> Map.put_new(@alarm_clock, 0)
    |> Enum.each(&update_message_reactions(msg, &1))
  end

  defp reaction_counts_by_emoji(%Message{reactions: nil}), do: %{}

  defp reaction_counts_by_emoji(%Message{reactions: reactions}) do
    reactions |> Map.new(fn r -> {Emoji.api_name(r.emoji), r.count} end)
  end

  defp update_message_reactions(msg, {@alarm_clock, 0}) do
    Logger.info("Creating alarm clock emoji on message ##{msg.id}.")
    Discord.create_reaction(msg.channel_id, msg.id, @alarm_clock)
  end

  defp update_message_reactions(msg, {@alarm_clock, 1}), do: :noop

  defp update_message_reactions(msg, {@alarm_clock, count}) when count > 0 do
    Logger.warn("Too many alarm clock reactions on message ##{msg.id}, pruning.")

    me_id = Me.get().id

    with {:ok, users} <- Discord.get_reactions(msg.channel_id, msg.id, @alarm_clock) do
      users
      |> Enum.each(fn
        %User{id: ^me_id} -> :noop
        %User{id: uid} -> Discord.delete_user_reaction(msg.channel_id, msg.id, @alarm_clock, uid)
      end)
    end
  end

  defp update_message_reactions(msg, {emoji, _count}) do
    Logger.warn("Deleting unknown reaction #{inspect(emoji)} on message ##{msg.id}")
    Discord.delete_reaction(msg.channel_id, msg.id, emoji)
  end
end
