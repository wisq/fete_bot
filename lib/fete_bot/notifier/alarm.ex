defmodule FeteBot.Notifier.Alarm do
  use Ecto.Schema

  alias __MODULE__
  # import Ecto.Changeset

  alias FeteBot.Notifier.AlarmUser

  schema "alarms" do
    timestamps()
    belongs_to(:alarm_user, AlarmUser)
    field(:alarm_number, :integer)
    field(:event, Ecto.Enum, values: [:epoch, :session])
    field(:margin, Ecto.Timex.Duration)
  end

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
      margin: Timex.Duration.from_minutes(5)
    }
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
    case Timex.Duration.to_minutes(duration, truncate: true) do
      0 -> "immediately"
      1 -> "one minute"
      2 -> "two minutes"
      3 -> "three minutes"
      4 -> "four minutes"
      5 -> "five minutes"
      6 -> "six minutes"
      7 -> "seven minutes"
      8 -> "eight minutes"
      9 -> "nine minutes"
      10 -> "ten minutes"
      n -> "#{n} minutes"
    end
  end

  defp describe_event(:epoch), do: "the **next series** of fêtes"
  defp describe_event(:session), do: "**each fête** in a series"
end
