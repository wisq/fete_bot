defmodule FeteBot.Notifier do
  require Logger

  # alias FeteBot.Repo

  alias Nostrum.Api, as: Discord
  alias Nostrum.Struct.{Message, Message.Reaction, Emoji, User}
  alias Nostrum.Cache.Me

  @alarm_clock "\u{23F0}"
  @default_reactions %{@alarm_clock => 0}

  # import Ecto.Query, only: [from: 2]
  # alias Ecto.Changeset

  defmodule State do
    @enforce_keys [:message]
    defstruct(
      message: nil,
      notified: MapSet.new()
    )

    alias FeteBot.Notifier
    alias __MODULE__

    def notify_catchup(user, state) do
      case MapSet.member?(state.notified, user.id) do
        true ->
          state

        false ->
          send_catchup_message(user, state.message.channel_id)
          %State{state | notified: MapSet.put(state.notified, user.id)}
      end
    end

    defp send_catchup_message(user, channel_id) do
      Notifier.send_dm(
        user,
        "Hi!  I was doing some cleanup, and I just noticed you reacted to my message on #{channel_link(channel_id)}.  Dealing with that now …"
      )
    end

    defp channel_link(id) when is_integer(id), do: "<##{id}>"
  end

  def update_reactions(%Message{reactions: nil} = msg) do
    %Message{msg | reactions: []}
    |> update_reactions()
  end

  def update_reactions(%Message{} = msg) do
    msg.reactions
    |> Map.new(fn %Reaction{emoji: emoji, count: count} ->
      {Emoji.api_name(emoji), count}
    end)
    |> then(fn rs -> Map.merge(@default_reactions, rs) end)
    |> with_state(%State{message: msg}, fn {emoji, count}, state ->
      handle_reaction_count(emoji, count, state)
    end)
  end

  defp with_state(list, initial, reducer) do
    list
    |> Enum.reduce(initial, fn item, state ->
      %State{} = reducer.(item, state)
    end)
  end

  defp handle_reaction_count(@alarm_clock, 0, %State{message: msg} = state) do
    Logger.info("Creating alarm clock reaction on message ##{msg.id}.")

    case Discord.create_reaction(msg.channel_id, msg.id, @alarm_clock) do
      {:ok} ->
        :ok

      {:error, err} ->
        Logger.error("Error creating alarm clock reaction on message ##{msg.id}: #{inspect(err)}")
    end

    state
  end

  defp handle_reaction_count(@alarm_clock, 1, state), do: state

  defp handle_reaction_count(@alarm_clock = emoji, count, state) when count > 1 do
    get_reacting_users(state.message, emoji)
    |> with_state(state, &handle_alarm_clock_reaction(&1, emoji, &2))
  end

  defp handle_reaction_count(emoji, count, %State{message: msg} = state) do
    state =
      get_reacting_users(msg, emoji)
      |> with_state(state, &handle_unknown_reaction(&1, emoji, &2))

    Discord.delete_reaction(msg.channel_id, msg.id, emoji)
    state
  end

  defp get_reacting_users(msg, emoji) do
    case Discord.get_reactions(msg.channel_id, msg.id, emoji) do
      {:ok, users} ->
        me_id = Me.get().id
        users |> Enum.reject(fn u -> u.id == me_id end)

      {:error, err} ->
        Logger.debug("Error getting #{inspect(emoji)} reactions for ##{msg.id}: #{inspect(err)}")
    end
  end

  defp handle_alarm_clock_reaction(user, emoji, %State{message: msg} = state) do
    Logger.info("Handling alarm clock reaction for #{inspect_user(user)} ...")
    state = State.notify_catchup(user, state)
    # TODO: actually set up alarms
    Discord.delete_user_reaction(msg.channel_id, msg.id, emoji, user.id)
    state
  end

  defp handle_unknown_reaction(user, emoji, state) do
    Logger.info("Unknown reaction emoji: #{inspect(emoji)}")
    state = State.notify_catchup(user, state)
    send_dm(user, "Sorry, I don't understand the #{format_emoji(emoji)} emote.")
    state
  end

  def send_dm(%User{} = user, text) do
    Logger.info("Sending a DM to #{inspect_user(user)}: #{inspect(text)}")

    with {:ok, channel} <- Discord.create_dm(user.id),
         {:ok, _} <- Discord.create_message(channel.id, text) do
      :ok
    end
  end

  defp format_emoji(name) do
    if name =~ ~r{^[A-Za-z_]+:\d+$} do
      "<:#{name}>"
    else
      name
    end
  end

  defp inspect_user(%User{username: name, discriminator: num, id: id}) do
    full_name = "#{name}##{num}"
    inspect(full_name) <> " (##{id})"
  end
end
