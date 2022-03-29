defmodule FeteBot.Tracker do
  require Logger

  alias FeteBot.Repo
  alias FeteBot.Tracker.{Channel, Scheduler, Formatter}

  alias Nostrum.Api, as: Discord
  alias Nostrum.Struct.Message

  # import Ecto.Query, only: [from: 2]
  alias Ecto.Changeset

  def enable(channel_id) do
    case Channel.insert_changeset(channel_id) |> Repo.insert() do
      {:ok, %Channel{channel_id: ^channel_id} = channel} ->
        Scheduler.manual_update(channel)
        :ok

      {:error, %Changeset{errors: [channel_id: {"already exists", _}]}} ->
        {:error, :already_enabled}
    end
  end

  def disable(channel_id) do
    case Repo.get_by(Channel, channel_id: channel_id) do
      %Channel{message_id: message_id} = channel ->
        # Try to delete our message, but ignore errors.
        if !is_nil(message_id), do: Discord.delete_message(channel_id, message_id)
        Repo.delete!(channel)
        :ok

      nil ->
        {:error, :not_enabled}
    end
  end

  def post_all_schedules(events, now) do
    text = Formatter.generate_schedule(events, now)

    Repo.all(Channel)
    |> Enum.each(&update_message!(text, &1))
  end

  def post_schedule(channel, events, now) do
    Formatter.generate_schedule(events, now)
    |> update_message!(channel)
  end

  defp update_message!(text, %Channel{message_id: nil} = channel) do
    case Discord.create_message(channel.channel_id, text) do
      {:ok, msg} ->
        channel
        |> Channel.message_id_changeset(msg.id)
        |> Repo.update!()

      {:error, err} ->
        Logger.error("Got #{inspect(err)} trying to post a new message to #{inspect(channel)}.")
    end
  end

  defp update_message!(text, %Channel{message_id: msg_id} = channel) when is_integer(msg_id) do
    case Discord.edit_message(channel.channel_id, msg_id, text) do
      {:ok, %Message{id: ^msg_id}} ->
        :ok

      {:ok, %Message{} = msg} ->
        channel
        |> Channel.message_id_changeset(msg.id)
        |> Repo.update!()

      {:error, err} ->
        Logger.error("Got #{inspect(err)} trying to edit message in #{inspect(channel)}.")
    end
  end
end
