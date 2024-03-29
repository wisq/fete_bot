defmodule FeteBot.Notifier.Reactions do
  require Logger
  alias Nostrum.Struct.{Message, Emoji}

  alias FeteBot.Discord
  alias FeteBot.Notifier
  alias FeteBot.Notifier.Alarm

  @alarm_number_commands 1..9 |> Map.new(fn n -> {Alarm.number_emoji(n), {:edit, n}} end)
  @generic_n_emoji "\u{1F1F3}"

  @summary_commands %{
    "\u{23F0}" => :add,
    "\u{274C}" => :delete_all
  }
  @all_summary_commands Map.merge(@summary_commands, @alarm_number_commands)

  @editing_commands [
    {:back_large, "\u{23EE}\u{FE0F}"},
    {:back_small, "\u{23EA}"},
    {:cycle_event, "\u{1F389}"},
    {:fwd_small, "\u{23E9}"},
    {:fwd_large, "\u{23ED}\u{FE0F}"},
    {:delete, "\u{274C}"},
    {:finished, "\u{2705}"}
  ]
  @editing_commands_map Map.new(@editing_commands, fn {c, e} -> {e, c} end)

  @alarm_commands %{
    "\u{274C}" => :delete
  }
  @all_alarm_commands Map.merge(@alarm_commands, @alarm_number_commands)

  def on_reaction_add(event) do
    emoji = Emoji.api_name(event.emoji)

    cond do
      handle_summary_command(emoji, event.channel_id, event.message_id) -> :ok
      handle_editing_command(emoji, event.channel_id, event.message_id) -> :ok
      handle_alarm_command(emoji, event.channel_id, event.message_id) -> :ok
      true -> :noop
    end
  end

  def on_reaction_remove(event), do: on_reaction_add(event)

  defp handle_summary_command(emoji, channel_id, message_id) do
    with {:ok, command} <- Map.fetch(@all_summary_commands, emoji),
         {:ok, user} <- Notifier.find_user_by_summary_message(channel_id, message_id) do
      on_summary_command(command, user)
      true
    else
      :error -> false
    end
  end

  defp handle_editing_command(emoji, channel_id, message_id) do
    with {:ok, command} <- Map.fetch(@editing_commands_map, emoji),
         {:ok, alarm} <- Notifier.find_alarm_by_editing_message(channel_id, message_id) do
      on_editing_command(command, alarm)
      true
    else
      :error -> false
    end
  end

  defp handle_alarm_command(emoji, channel_id, message_id) do
    with {:ok, command} <- Map.fetch(@all_alarm_commands, emoji),
         {:ok, alarm} <- Notifier.find_alarm_by_last_alarm_message(channel_id, message_id) do
      on_alarm_command(command, alarm)
      true
    else
      :error -> false
    end
  end

  def add_summary_reactions(%Message{} = msg, alarms) when is_list(alarms) do
    alarms
    |> Enum.map(&Alarm.number_emoji/1)
    |> Enum.sort()
    |> add_summary_command_emoji()
    |> Enum.each(fn emoji ->
      add_reaction(msg, emoji)
    end)
  end

  defp add_summary_command_emoji(list) do
    if Enum.count(list) >= Alarm.max_per_user() do
      @summary_commands
      |> Map.reject(fn {_, cmd} -> cmd == :add end)
    else
      @summary_commands
    end
    |> Map.keys()
    |> then(&Enum.concat(list, &1))
  end

  def add_editing_reactions(%Message{} = msg) do
    @editing_commands
    |> Enum.each(fn {_, emoji} ->
      add_reaction(msg, emoji)
    end)
  end

  def add_alarm_reactions(%Message{} = msg, %Alarm{} = alarm) do
    [
      Alarm.number_emoji(alarm)
      | Map.keys(@alarm_commands)
    ]
    |> Enum.each(&add_reaction(msg, &1))
  end

  defp add_reaction(%Message{} = msg, emoji) do
    case Discord.create_reaction(msg.channel_id, msg.id, emoji) do
      {:ok} ->
        :ok

      {:error, %{status_code: 429, response: %{retry_after: secs}}} when secs < 5.0 ->
        ms = ceil(secs * 1000)
        Logger.warning("Rate-limited adding reactions, sleeping for #{ms}ms")
        Process.sleep(ms)
        add_reaction(msg, emoji)
    end
  end

  defp on_summary_command(:add, user), do: Notifier.create_alarm(user)
  defp on_summary_command(:delete_all, user), do: Notifier.delete_all_alarms(user)
  defp on_summary_command({:edit, n}, user), do: Notifier.edit_alarm(user, n)

  defp on_editing_command(:back_large, alarm), do: Notifier.change_alarm_margin(alarm, 5)
  defp on_editing_command(:back_small, alarm), do: Notifier.change_alarm_margin(alarm, 1)
  defp on_editing_command(:fwd_small, alarm), do: Notifier.change_alarm_margin(alarm, -1)
  defp on_editing_command(:fwd_large, alarm), do: Notifier.change_alarm_margin(alarm, -5)
  defp on_editing_command(:cycle_event, alarm), do: Notifier.cycle_alarm_event(alarm)
  defp on_editing_command(:delete, alarm), do: Notifier.delete_alarm(alarm)
  defp on_editing_command(:finished, alarm), do: Notifier.finish_editing_alarm(alarm)

  defp on_alarm_command({:edit, n}, %{alarm_number: n} = alarm), do: Notifier.edit_alarm(alarm)
  defp on_alarm_command({:edit, _}, _), do: :ignore
  defp on_alarm_command(:delete, alarm), do: Notifier.delete_alarm(alarm)

  def alarm_editing_legend do
    @editing_commands
    |> Enum.map(fn {cmd, emoji} ->
      "#{emoji} — #{editing_description(cmd)}"
    end)
    |> Enum.join("\n")
  end

  defp editing_description(:back_large), do: "five minutes earlier"
  defp editing_description(:back_small), do: "one minute earlier"
  defp editing_description(:fwd_large), do: "five minutes later"
  defp editing_description(:fwd_small), do: "one minute later"
  defp editing_description(:cycle_event), do: "toggle alarm type (each fête / each series)"
  defp editing_description(:delete), do: "delete this alarm"
  defp editing_description(:finished), do: "done editing"

  def summary_legend(can_edit) do
    case can_edit do
      true -> [{@generic_n_emoji, :edit}]
      false -> []
    end
    |> Enum.concat(@summary_commands)
    |> Enum.map(fn {emoji, cmd} ->
      "#{emoji} — #{summary_description(cmd)}"
    end)
    |> Enum.join("\n")
  end

  defp summary_description(:edit), do: "edit alarm #{@generic_n_emoji}"
  defp summary_description(:add), do: "add a new alarm"
  defp summary_description(:delete_all), do: "delete **all** alarms"
end
