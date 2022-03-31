defmodule FeteBot.Notifier do
  require Logger

  alias Nostrum.Api, as: Discord
  alias Ecto.Multi
  import Ecto.Query, only: [from: 2]

  alias FeteBot.Repo
  alias FeteBot.Notifier.{AlarmUser, Alarm, Reactions}

  def setup_alarms(user_id) do
    {:ok, dm} = Discord.create_dm(user_id)

    Multi.new()
    |> Multi.insert(:alarm_user, AlarmUser.insert_changeset(user_id, dm.id))
    |> Multi.insert(:alarm, fn %{alarm_user: user} -> Alarm.default_alarm(user) end)
    |> Repo.transaction()
    |> then(fn
      {:ok, %{alarm_user: user, alarm: alarm}} ->
        %AlarmUser{user | alarms: [alarm]}
        |> post_summary()

      {:error, :alarm_user, %{errors: [user_id: {"already exists", _}]}, _} ->
        from(u in AlarmUser, where: u.user_id == ^user_id)
        |> Repo.one!()
        |> post_summary()

      {:error, stage, data} ->
        Logger.error("Failed stage #{inspect(stage)} of setup_alarms: #{inspect(data)}")
        Discord.create_message(dm.id, "Sorry, something went wrong. \u{1F622}  Try again later.")
    end)
  end

  defp post_summary(%AlarmUser{summary_message_id: old_id} = user) when is_integer(old_id) do
    Discord.delete_message(user.dm_id, old_id)
    %AlarmUser{user | summary_message_id: nil} |> post_summary()
  end

  defp post_summary(%AlarmUser{} = user) do
    user = Repo.preload(user, :alarms)
    msg = Discord.create_message!(user.dm_id, summary_text(user.alarms))
    AlarmUser.update_summary_changeset(user, msg.id) |> Repo.update!()
    Reactions.add_summary_reactions(msg, user.alarms)
  end

  defp summary_text([]), do: "You have no alarms set up."

  defp summary_text(alarms) do
    alarms
    |> Enum.sort_by(& &1.alarm_number)
    |> Enum.map(&Alarm.formatted_description/1)
    |> Enum.join("\n")
  end

  def find_user_by_summary_message(channel_id, message_id) do
    query =
      from(u in AlarmUser,
        where: u.dm_id == ^channel_id and u.summary_message_id == ^message_id
      )

    case Repo.one(query) do
      %AlarmUser{} = user -> {:ok, user}
      nil -> :error
    end
  end

  def create_alarm(%AlarmUser{} = user) do
    user = Repo.preload(user, :alarms)

    case Alarm.find_available_number(user.alarms) do
      {:ok, n} ->
        Alarm.new_alarm(user, n) |> Repo.insert!()
        Repo.preload(user, :alarms, force: true) |> post_summary()

      :error ->
        Discord.create_message(user.dm_id, "Sorry, you can't have any more alarms.")
    end
  end

  def delete_all_alarms(%AlarmUser{} = user) do
    from(a in Alarm, where: a.alarm_user_id == ^user.id) |> Repo.delete_all()
    Repo.preload(user, :alarms, force: true) |> post_summary()
  end
end
