defmodule FeteBot.Tracker.Scheduler do
  use GenServer

  alias FeteBot.{Tracker, Fetes, TimeUtils}

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def manual_update(channel) do
    GenServer.cast(__MODULE__, {:manual, channel})
  end

  def init(nil) do
    # {events, timeout} = next_events_and_timeout([])
    # {:ok, events, timeout}
    {:ok, [], 1000}
  end

  def handle_cast({:manual, channel}, events) do
    now = DateTime.utc_now()
    {events, timeout} = next_events_and_timeout(events)
    Tracker.post_schedule(channel, events, now)
    {:noreply, events, timeout}
  end

  def handle_info(:timeout, events) do
    now = DateTime.utc_now()
    {events, timeout} = next_events_and_timeout(events, now)
    Tracker.post_all_schedules(events, now)
    {:noreply, events, timeout}
  end

  defp next_events_and_timeout(events, now \\ DateTime.utc_now()) do
    case events |> event_wakeups() |> Enum.drop_while(&TimeUtils.is_before?(&1, now)) do
      [] ->
        Fetes.calendar(now) |> next_events_and_timeout(now)

      [next_wakeup | _] ->
        {events, DateTime.diff(next_wakeup, now, :millisecond)}
    end
  end

  defp event_wakeups(events) do
    events
    |> Enum.flat_map(fn e -> [e.start_time, e.end_time] end)
  end
end
