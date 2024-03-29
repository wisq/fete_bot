defmodule FeteBot.Notifier.Alarm do
  use Ecto.Schema

  alias __MODULE__
  import Ecto.Changeset
  alias Timex.Duration

  alias FeteBot.Notifier.AlarmUser

  schema "alarms" do
    timestamps()
    belongs_to(:alarm_user, AlarmUser)
    field(:alarm_number, :integer)
    field(:event, Ecto.Enum, values: [:epoch, :session])
    field(:margin, Ecto.Timex.Duration)
    field(:editing_message_id, :integer)
    field(:last_alarm_message_id, :integer)
  end

  def min_margin(_), do: Duration.from_seconds(0)

  def max_margin(:epoch), do: Duration.from_hours(3)
  def max_margin(:session), do: Duration.from_minutes(90)

  @max_per_user 5
  def max_per_user, do: @max_per_user

  def find_available_number(alarms) do
    taken = alarms |> Enum.map(& &1.alarm_number)

    1..@max_per_user
    |> Enum.find(&(&1 not in taken))
    |> then(fn
      n when is_integer(n) -> {:ok, n}
      nil -> :error
    end)
  end

  def default_alarm(%AlarmUser{} = user), do: new_alarm(user, 1)

  def new_alarm(%AlarmUser{} = user, number) do
    %Alarm{
      alarm_user_id: user.id,
      event: :session,
      alarm_number: number,
      margin: Duration.from_minutes(5)
    }
  end

  def update_editing_message_changeset(%Alarm{} = alarm, msg_id) do
    alarm
    |> change(editing_message_id: msg_id)
  end

  def update_last_alarm_message_changeset(%Alarm{} = alarm, msg_id) do
    alarm
    |> change(last_alarm_message_id: msg_id)
  end

  def cycle_event_changeset(%Alarm{} = alarm) do
    new_event = cycle_event(alarm.event)

    alarm
    |> change(
      event: new_event,
      margin: alarm.margin |> constrain_margin(new_event)
    )
  end

  defp cycle_event(:epoch), do: :session
  defp cycle_event(:session), do: :epoch

  def add_margin_changeset(%Alarm{} = alarm, %Duration{} = duration) do
    alarm
    |> change(
      margin:
        alarm.margin
        |> Duration.add(duration)
        |> constrain_margin(alarm.event)
    )
  end

  defp constrain_margin(margin, event) do
    margin
    |> Duration.to_microseconds()
    |> min(max_margin(event) |> Duration.to_microseconds())
    |> max(min_margin(event) |> Duration.to_microseconds())
    |> Duration.from_microseconds()
  end

  def formatted_description(alarm) do
    [
      number_emoji(alarm.alarm_number),
      " — Set for **",
      describe_margin(alarm.margin),
      "** before ",
      describe_event(alarm.event)
    ]
    |> Enum.join("")
  end

  def number_emoji(%Alarm{alarm_number: n}), do: number_emoji(n)
  def number_emoji(n) when n in 1..9, do: "#{n}\uFE0F\u20E3"

  defp describe_margin(duration) do
    Timex.Duration.to_minutes(duration, truncate: true)
    |> describe_minutes()
  end

  defp describe_alarm_start_time(duration) do
    Timex.Duration.to_minutes(duration, truncate: true)
    |> describe_alarm_start_minutes()
  end

  defp describe_minutes(0), do: "immediately"
  defp describe_minutes(1), do: "one minute"
  defp describe_minutes(2), do: "two minutes"
  defp describe_minutes(3), do: "three minutes"
  defp describe_minutes(4), do: "four minutes"
  defp describe_minutes(5), do: "five minutes"
  defp describe_minutes(6), do: "six minutes"
  defp describe_minutes(7), do: "seven minutes"
  defp describe_minutes(8), do: "eight minutes"
  defp describe_minutes(9), do: "nine minutes"
  defp describe_minutes(10), do: "ten minutes"
  defp describe_minutes(n), do: "#{n} minutes"

  defp describe_alarm_start_minutes(0), do: "is starting right now!"
  defp describe_alarm_start_minutes(n), do: "will start in #{describe_minutes(n)}."

  defp describe_event(:epoch), do: "the **next series** of fêtes"
  defp describe_event(:session), do: "**each fête** in a series"

  defp next_event(:epoch), do: "**next series** of fêtes"
  defp next_event(:session), do: "**next fête**"

  def unformatted_alarm_message(alarm, _event) do
    [
      "The ",
      next_event(alarm.event) |> String.replace("**", ""),
      " ",
      describe_alarm_start_time(alarm.margin)
    ]
    |> Enum.join("")
  end

  def formatted_alarm_message(alarm, event) do
    [
      "The ",
      next_event(alarm.event),
      " will start at ",
      timestamp(event.start_time),
      " (",
      relative(event.start_time),
      ")."
    ]
    |> Enum.join("")
  end

  defp timestamp(datetime, format \\ "t") do
    "<t:#{DateTime.to_unix(datetime)}:#{format}>"
  end

  defp relative(datetime), do: timestamp(datetime, "R")
end
