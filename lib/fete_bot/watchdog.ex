defmodule FeteBot.Watchdog do
  use GenServer
  require Logger

  @prefix "[#{inspect(__MODULE__)}]"
  @pids_to_monitor [
    FeteBot.Tracker.Scheduler,
    FeteBot.Notifier.Scheduler
  ]
  @interval 30_000

  def children do
    case enabled?() do
      true -> [__MODULE__]
      false -> []
    end
  end

  defp enabled?, do: !(watchdog_file() |> is_nil())

  defp watchdog_file do
    Application.get_env(:fete_bot, __MODULE__, [])
    |> Keyword.get(:file, nil)
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_) do
    {:ok, nil, 5_000}
  end

  def handle_info(:timeout, nil) do
    {:noreply, find_all_pids(), @interval}
  end

  def handle_info(:timeout, old_pids) do
    new_pids = find_all_pids()

    Enum.zip(old_pids, new_pids)
    |> Enum.reduce(:pass, &check_pid_changed/2)
    |> maybe_touch_file()

    {:noreply, new_pids, @interval}
  end

  defp find_all_pids do
    @pids_to_monitor
    |> Enum.map(fn module ->
      {module, Process.whereis(module)}
    end)
  end

  defp check_pid_changed({{module, old_pid}, {module, new_pid}}, state) do
    cond do
      is_nil(new_pid) ->
        Logger.warn("#{@prefix} Process is not running: #{inspect(module)}")
        :fail

      new_pid != old_pid ->
        Logger.warn("#{@prefix} Process was restarted: #{inspect(module)}")
        :fail

      true ->
        state
    end
  end

  defp maybe_touch_file(:pass) do
    file = watchdog_file()

    case File.touch(file) do
      :ok -> :ok
      {:error, e} -> Logger.warn("#{@prefix} Got #{inspect(e)} touching #{file}")
    end
  end

  defp maybe_touch_file(:fail) do
    Logger.warn("#{@prefix} Not updating watchdog file.")
  end
end
