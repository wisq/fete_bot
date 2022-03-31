defmodule FeteBot.Tracker.Scheduler do
  use GenServer

  alias FeteBot.{Tracker, Notifier, Fetes, TimeUtils}

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def manual_update(channel) do
    GenServer.cast(__MODULE__, {:manual, channel})
  end

  def init(nil) do
    # TODO: instead of just waiting one second, we should start our behaviour
    # when we receive a `:READY` event from Discord.  Or maybe track the guild
    # ID on each Channel record, and trigger on a `:GUILD_AVAILABLE`?  This
    # would also allow us to fix our messages in the case of temporary downtime.
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
    events |> next_starting_event(now) |> Notifier.Scheduler.next_event()
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

  defp next_starting_event(events, now) do
    events
    |> Enum.find(&TimeUtils.is_after?(&1.start_time, now))
  end
end
