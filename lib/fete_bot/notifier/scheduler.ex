defmodule FeteBot.Notifier.Scheduler do
  use GenServer
  require Logger

  defmodule State do
    defstruct(
      next_event: nil,
      alarm_queue: []
    )
  end

  defmodule QueueEntry do
    @enforce_keys [:time, :event, :alarm]
    defstruct(@enforce_keys)
  end

  alias FeteBot.{Notifier, TimeUtils}
  alias FeteBot.Notifier.AlarmUser
  alias FeteBot.Fetes.Event

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def next_event(%Event{} = event) do
    GenServer.cast(__MODULE__, {:next_event, event})
  end

  def refresh_user(%AlarmUser{} = user) do
    GenServer.cast(__MODULE__, {:refresh_user, user.id})
  end

  def init(nil) do
    {:ok, %State{}}
  end

  def handle_cast({:next_event, event}, %State{next_event: event} = state) do
    # next_event is unchanged
    {:noreply, state} |> with_timeout()
  end

  def handle_cast({:next_event, event}, state) do
    Logger.info("Queueing alarms for session ##{event.session} at #{event.start_time} ...")

    {:noreply,
     %State{
       state
       | next_event: event,
         alarm_queue: state.alarm_queue |> update_queue(event)
     }}
    |> with_timeout()
  end

  def handle_cast({:refresh_user, user_id}, state) do
    Logger.info("Refreshing alarms for user ##{user_id} ...")

    {:noreply,
     %State{
       state
       | alarm_queue: state.alarm_queue |> refresh_queue_user(state.next_event, user_id)
     }}
    |> with_timeout()
  end

  def handle_info(:timeout, state) do
    {triggered, remaining} = state.alarm_queue |> queue_pop_expired()
    triggered |> Enum.each(&trigger_alarm/1)
    {:noreply, %State{alarm_queue: remaining}} |> with_timeout()
  end

  defp trigger_alarm(%QueueEntry{event: event, alarm: alarm}) do
    Notifier.trigger_alarm(alarm, event)
  end

  defp with_timeout({rv1, state}) do
    case calculate_timeout(state.alarm_queue) do
      nil -> {rv1, state}
      t when t >= 0 -> {rv1, state, t}
    end
  end

  defp calculate_timeout([]) do
    Logger.info("No alarms are pending.")
    nil
  end

  defp calculate_timeout([%QueueEntry{time: time, alarm: alarm} | _]) do
    Logger.info("Next alarm will be ##{alarm.id} (for user ##{alarm.alarm_user_id}) at #{time}.")

    time
    |> DateTime.diff(DateTime.utc_now(), :millisecond)
    |> handle_negative_timeout()
  end

  defp handle_negative_timeout(t) when t >= 0, do: t

  defp handle_negative_timeout(t) when t < 0 do
    Logger.warn("Notifier is lagging by #{abs(t)}ms")
    0
  end

  defp update_queue(queue, %Event{} = event) when is_list(queue) do
    # There exists a possible race condition where an alarm is just about to
    # trigger, but then we do a queue update -- and the update takes long
    # enough that by the time we get to the "discard expired alarms" step,
    # those alarms are now in the past.
    #
    # To prevent this, we use the time of the first alarm in the queue as our
    # cutoff time for the queue pop step.
    cutoff = queue_cutoff_time(queue)

    queue
    |> queue_delete_by_event(event)
    |> queue_add_event(event)
    |> queue_sort()
    |> queue_pop_expired(cutoff)
    |> elem(1)
  end

  defp refresh_queue_user(queue, event, user_id) do
    cutoff = queue_cutoff_time(queue)

    queue
    |> queue_delete_by_user(user_id)
    |> queue_add_event(event, user_id)
    |> queue_sort()
    |> queue_pop_expired(cutoff)
    |> elem(1)
  end

  defp queue_cutoff_time([]), do: DateTime.utc_now()

  defp queue_cutoff_time([%QueueEntry{time: time} | _]) do
    now = DateTime.utc_now()
    if time |> TimeUtils.is_before?(now), do: time, else: now
  end

  defp queue_delete_by_event(queue, event), do: queue |> Enum.reject(&(&1.event == event))

  defp queue_delete_by_user(queue, user_id),
    do: queue |> Enum.reject(&(&1.alarm.alarm_user_id == user_id))

  defp queue_add_event(queue, event, user_id \\ nil) do
    event
    |> event_alarm_types()
    |> fetch_alarms(user_id)
    |> Enum.map(fn alarm ->
      %QueueEntry{
        time: event.start_time |> Timex.subtract(alarm.margin),
        event: event,
        alarm: alarm
      }
    end)
    |> Enum.concat(queue)
  end

  defp fetch_alarms(types, nil), do: Notifier.all_alarms_by_events(types)
  defp fetch_alarms(types, user_id), do: Notifier.all_alarms_by_events_and_user(types, user_id)

  defp queue_sort(queue) do
    queue
    |> Enum.sort_by(&DateTime.to_unix(&1.time, :microsecond))
  end

  defp queue_pop_expired(queue, cutoff \\ DateTime.utc_now()) do
    queue
    |> Enum.split_while(fn %QueueEntry{time: time} ->
      time |> TimeUtils.is_before?(cutoff)
    end)
  end

  defp event_alarm_types(%Event{session: 1}), do: [:epoch, :session]
  defp event_alarm_types(%Event{session: _}), do: [:session]
end
