defmodule FeteBot.Fetes do
  defmodule Event do
    @enforce_keys [:epoch, :session, :start_time, :end_time]
    defstruct(@enforce_keys)
  end

  alias FeteBot.TimeUtils

  @start_time ~U[2022-03-01 07:00:00Z]
  @epoch_interval Timex.Duration.from_hours(68)

  @sessions 12
  @session_interval Timex.Duration.from_hours(2)
  @session_length Timex.Duration.from_seconds(27 * 60 + 25)

  def calendar(now \\ DateTime.utc_now()) do
    {previous, next} = current_epochs(now)
    previous_events = events_for_epoch(previous)

    if List.last(previous_events).end_time |> TimeUtils.is_after?(now) do
      previous_events
    else
      events_for_epoch(next)
    end
  end

  defp epochs, do: Stream.iterate({0, @start_time}, &step_time(&1, @epoch_interval))
  defp sessions(start), do: Stream.iterate({1, start}, &step_time(&1, @session_interval))
  defp step_time({n, dt}, interval), do: {n + 1, Timex.add(dt, interval)}

  defp current_epochs(now) do
    epochs() |> Enum.reduce_while(:start, &current_epoch_bracket(now, &1, &2))
  end

  defp current_epoch_bracket(_, first, :start), do: {:cont, first}

  defp current_epoch_bracket(now, {_n, time} = curr, last) do
    if time |> TimeUtils.is_after?(now) do
      {:halt, {last, curr}}
    else
      {:cont, curr}
    end
  end

  defp events_for_epoch({epoch, start}) do
    sessions(start)
    |> Enum.take(@sessions)
    |> Enum.map(&event_for_epoch(epoch, &1))
  end

  defp event_for_epoch(epoch, {session, start_time}) do
    end_time = Timex.add(start_time, @session_length)

    %Event{
      epoch: epoch,
      session: session,
      start_time: start_time,
      end_time: end_time
    }
  end
end
