defmodule FeteBot.Notifier do
  require Logger

  alias Ecto.Multi
  import Ecto.Query, only: [from: 2]
  alias Nostrum.Error.ApiError

  alias FeteBot.Repo
  alias FeteBot.Discord
  alias FeteBot.Notifier.{AlarmUser, Alarm, Reactions, Scheduler}
  alias FeteBot.Fetes

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
    delete_message(user.dm_id, old_id)
    %AlarmUser{user | summary_message_id: nil} |> post_summary()
  end

  defp post_summary(%AlarmUser{} = user) do
    user = Repo.preload(user, :alarms)
    msg = Discord.create_message!(user.dm_id, summary_text(user.alarms))
    AlarmUser.update_summary_changeset(user, msg.id) |> Repo.update!()
    Reactions.add_summary_reactions(msg, user.alarms)
  end

  defp summary_text([]) do
    [
      "You have no alarms set up.",
      Reactions.summary_legend(false)
    ]
    |> Enum.join("\n\n")
  end

  defp summary_text(alarms) do
    [
      "You have the following alarms:",
      alarms
      |> Enum.sort_by(& &1.alarm_number)
      |> Enum.map(&Alarm.formatted_description/1)
      |> Enum.join("\n"),
      Reactions.summary_legend(true)
    ]
    |> Enum.join("\n\n")
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

  def find_alarm_by_editing_message(channel_id, message_id) do
    query =
      from(a in Alarm,
        join: u in assoc(a, :alarm_user),
        where: u.dm_id == ^channel_id and a.editing_message_id == ^message_id
      )

    case Repo.one(query) do
      %Alarm{} = alarm -> {:ok, alarm}
      nil -> :error
    end
  end

  def find_alarm_by_last_alarm_message(channel_id, message_id) do
    query =
      from(a in Alarm,
        join: u in assoc(a, :alarm_user),
        where: u.dm_id == ^channel_id and a.last_alarm_message_id == ^message_id
      )

    case Repo.one(query) do
      %Alarm{} = alarm -> {:ok, alarm}
      nil -> :error
    end
  end

  def create_alarm(%AlarmUser{} = user) do
    user = Repo.preload(user, :alarms)

    case Alarm.find_available_number(user.alarms) do
      {:ok, n} ->
        Alarm.new_alarm(user, n) |> Repo.insert!()
        Scheduler.refresh_user(user)
        Repo.preload(user, :alarms, force: true) |> post_summary()

      :error ->
        # They shouldn't have this emoji available anyway.
        # If they're gonna "hack" the emoji system, ignore them.
        # TODO: Consider adding proper error messages that we clean up later.
        :ignore
    end
  end

  def delete_all_alarms(%AlarmUser{} = user) do
    from(a in Alarm,
      where: a.alarm_user_id == ^user.id,
      select: {a.editing_message_id, a.last_alarm_message_id}
    )
    |> Repo.delete_all()
    |> then(fn {_, msg_ids} ->
      msg_ids
      |> Enum.each(fn {id1, id2} ->
        delete_message(user.dm_id, id1)
        delete_message(user.dm_id, id2)
      end)
    end)

    Scheduler.refresh_user(user)
    Repo.preload(user, :alarms, force: true) |> post_summary()
  end

  def edit_alarm(%AlarmUser{} = user, number) when is_integer(number) do
    case Repo.get_by(Alarm, alarm_user_id: user.id, alarm_number: number) do
      %Alarm{} = alarm ->
        %Alarm{alarm | alarm_user: user}
        |> post_alarm_edit_message()

      nil ->
        emoji = Alarm.number_emoji(number)
        Discord.create_message(user.dm_id, "You don't have a #{emoji} alarm.")
    end
  end

  def edit_alarm(%Alarm{} = alarm), do: alarm |> post_alarm_edit_message()

  defp post_alarm_edit_message(%Alarm{editing_message_id: old_id} = alarm)
       when is_integer(old_id) do
    alarm = Repo.preload(alarm, :alarm_user)
    delete_message(alarm.alarm_user.dm_id, old_id)
    post_alarm_edit_message(%Alarm{alarm | editing_message_id: nil})
  end

  defp post_alarm_edit_message(%Alarm{} = alarm) do
    alarm = Repo.preload(alarm, :alarm_user)
    user = alarm.alarm_user
    text = alarm_editing_text(alarm)
    msg = Discord.create_message!(user.dm_id, text)
    Alarm.update_editing_message_changeset(alarm, msg.id) |> Repo.update!()
    Reactions.add_editing_reactions(msg)
  end

  defp update_alarm_edit_message(%Alarm{} = alarm) do
    alarm = Repo.preload(alarm, :alarm_user)
    user = alarm.alarm_user
    text = alarm_editing_text(alarm)
    Discord.edit_message(user.dm_id, alarm.editing_message_id, text)
  end

  defp alarm_editing_text(alarm) do
    [
      "Use the reactions below to edit this alarm:",
      Alarm.formatted_description(alarm),
      Reactions.alarm_editing_legend()
    ]
    |> Enum.join("\n\n")
  end

  def change_alarm_margin(alarm, mins) do
    Alarm.add_margin_changeset(alarm, Timex.Duration.from_minutes(mins))
    |> Repo.update!()
    |> update_alarm_edit_message()
  end

  def cycle_alarm_event(alarm) do
    Alarm.cycle_event_changeset(alarm)
    |> Repo.update!()
    |> update_alarm_edit_message()
  end

  def delete_alarm(alarm) do
    alarm = Repo.preload(alarm, :alarm_user)
    user = alarm.alarm_user
    delete_message(user.dm_id, alarm.editing_message_id)
    delete_message(user.dm_id, alarm.last_alarm_message_id)
    Repo.delete!(alarm)
    Scheduler.refresh_user(user)
    Repo.preload(user, :alarms, force: true) |> post_summary()
  end

  def finish_editing_alarm(alarm) do
    alarm = Repo.preload(alarm, :alarm_user)
    user = alarm.alarm_user
    delete_message(user.dm_id, alarm.editing_message_id)
    Scheduler.refresh_user(user)
    Repo.preload(user, :alarms, force: true) |> post_summary()
  end

  def all_alarms_by_events(types) do
    from(a in Alarm, where: a.event in ^types)
    |> Repo.all()
  end

  def all_alarms_by_events_and_user(types, user_id) do
    from(a in Alarm, where: a.event in ^types and a.alarm_user_id == ^user_id)
    |> Repo.all()
  end

  defp delete_message(_, nil), do: :noop

  defp delete_message(channel_id, message_id) do
    case Discord.delete_message(channel_id, message_id) do
      {:ok} ->
        :ok

      {:error, %{status_code: 429, response: %{retry_after: secs}}} when secs < 5.0 ->
        ms = ceil(secs * 1000)
        Logger.warning("Rate-limited deleting messages, sleeping for #{ms}ms")
        Process.sleep(ms)
        delete_message(channel_id, message_id)

      {:error, %{status_code: 404, response: %{code: 10008}}} ->
        :not_found
    end
  end

  def trigger_alarm(%Alarm{} = alarm, %Fetes.Event{} = event) do
    alarm = Repo.preload(alarm, :alarm_user)
    user = alarm.alarm_user

    if is_integer(old_id = alarm.last_alarm_message_id),
      do: delete_message(user.dm_id, old_id)

    try do
      # Posts an unformatted message first, then edits it to a formatted one.
      # This makes notifications look better:
      #   - desktop notifications can't handle markdown
      #   - mobile notifications additionally can't handle timestamps
      text1 = Alarm.unformatted_alarm_message(alarm, event)
      msg = Discord.create_message!(user.dm_id, text1)
      Alarm.update_last_alarm_message_changeset(alarm, msg.id) |> Repo.update!()

      text2 = Alarm.formatted_alarm_message(alarm, event)
      msg = Discord.edit_message!(user.dm_id, msg.id, text2)
      Reactions.add_alarm_reactions(msg, alarm)
    rescue
      err in ApiError ->
        Logger.warning("Unable to send alarm ##{alarm.id}: #{ApiError.message(err)}")
    end
  end
end
