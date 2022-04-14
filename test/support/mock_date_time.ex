defmodule FeteBot.Test.MockDateTime do
  use GenServer
  require Logger

  alias FeteBot.Test.MockGenServer
  alias FeteBot.TimeUtils

  @ets :mock_date_time
  @prefix "[#{inspect(__MODULE__)}]"

  defmodule State do
    @enforce_keys [:ets]
    defstruct(
      ets: nil,
      mock_servers: %{}
    )
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def utc_now(pid \\ self()) do
    case ets_lookup(pid) do
      {:ok, :realtime} -> DateTime.utc_now()
      {:ok, %DateTime{} = dt} -> dt
      {:ok, other_pid} when is_pid(other_pid) -> utc_now(other_pid)
      :error -> use_realtime(pid)
    end
  end

  defp ets_lookup(pid, ets \\ @ets) do
    case :ets.lookup(ets, pid) do
      [{^pid, :realtime}] -> {:ok, :realtime}
      [{^pid, other_pid}] when is_pid(other_pid) -> {:ok, other_pid}
      [{^pid, %DateTime{} = dt}] -> {:ok, dt}
      [] -> :error
    end
  end

  defp use_realtime(pid) do
    :ok = GenServer.call(__MODULE__, {:using_realtime, pid})
    DateTime.utc_now()
  end

  def mock_time(%DateTime{} = datetime, pid \\ self()) do
    :ok = GenServer.call(__MODULE__, {:mock_time, pid, datetime})
  end

  def advance_to(%DateTime{} = datetime, pid \\ self()) do
    :ok = GenServer.call(__MODULE__, {:advance_to, pid, datetime})
  end

  def advance_by(%Timex.Duration{} = duration, pid \\ self()) do
    utc_now()
    |> Timex.add(duration)
    |> advance_to(pid)
  end

  def add_pid(pid, ref_pid \\ self()) when is_pid(pid) do
    :ok = GenServer.call(__MODULE__, {:add_pid, pid, ref_pid})
  end

  def add_mock_server(pid, ref_pid \\ self()) when is_pid(pid) do
    :ok = GenServer.call(__MODULE__, {:add_mock_server, pid, ref_pid})
  end

  @impl true
  def init(_) do
    ets = :ets.new(@ets, [:named_table, :set, :protected])
    {:ok, %State{ets: ets}}
  end

  @impl true
  def handle_call({:mock_time, pid, datetime}, _from, %State{ets: ets} = state) do
    Logger.debug("#{@prefix} mocking time for #{inspect(pid)}")

    case ets_lookup(pid, ets) do
      :error ->
        datetime |> increase_precision() |> set_time(pid, ets)
        Process.monitor(pid)
        servers = state.mock_servers |> Map.put(pid, [])
        {:reply, :ok, %State{state | mock_servers: servers}}

      {:ok, _} ->
        {:reply, {:error, :already_mocked}, state}
    end
  end

  @impl true
  def handle_call({:using_realtime, pid}, _from, %State{ets: ets} = state) do
    case ets_lookup(pid, ets) do
      :error ->
        :ets.insert(ets, {pid, :realtime})
        Process.monitor(pid)
        {:reply, :ok, state}

      {:ok, _} ->
        {:reply, {:error, :already_mocked}, state}
    end
  end

  @impl true
  def handle_call({:add_pid, pid, ref_pid}, _from, %State{ets: ets} = state) do
    case ets_lookup(pid, ets) do
      :error ->
        :ets.insert(ets, {pid, ref_pid})
        Process.monitor(pid)
        {:reply, :ok, state}

      {:ok, _} ->
        {:reply, {:error, :already_mocked}, state}
    end
  end

  @impl true
  def handle_call({:add_mock_server, server_pid, ref_pid}, from, state) do
    case handle_call({:add_pid, server_pid, ref_pid}, from, state) do
      {:reply, :ok, ^state} ->
        servers = state.mock_servers |> Map.update!(ref_pid, fn ps -> [server_pid | ps] end)
        {:reply, :ok, %State{state | mock_servers: servers}}

      {:reply, {:error, _}, ^state} = rval ->
        rval
    end
  end

  @impl true
  def handle_call({:advance_to, ref_pid, datetime}, from, state) do
    with {:ok, servers} <- Map.fetch(state.mock_servers, ref_pid),
         {:ok, now} <- ets_lookup(ref_pid, state.ets),
         true <- datetime |> TimeUtils.is_after?(now) do
      case next_timeout(datetime, servers) do
        {:advance_to, ^datetime} ->
          Logger.debug("#{@prefix} advancing to requested time")
          set_time(datetime, ref_pid, state.ets)
          {:reply, :ok, state}

        {server_pid, dt} when is_pid(server_pid) ->
          Logger.debug("#{@prefix} triggering server: #{inspect(server_pid)}")
          set_time(dt, ref_pid, state.ets)
          MockGenServer.trigger_timeout(server_pid)
          handle_call({:advance_to, ref_pid, datetime}, from, state)
      end
    else
      :error -> {:reply, {:error, :not_mocked}, state}
      false -> {:reply, {:error, :backwards_time_advance}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _, :process, pid, _}, %State{ets: ets} = state) do
    case ets_lookup(pid, ets) do
      {:ok, :realtime} ->
        :ets.delete(ets, pid)
        {:noreply, state}

      {:ok, %DateTime{}} ->
        Logger.debug("#{@prefix} deleting mocked pid #{inspect(pid)}")
        :ets.delete(ets, pid)
        {:noreply, %State{state | mock_servers: state.mock_servers |> Map.delete(pid)}}

      {:ok, ref_pid} when is_pid(ref_pid) ->
        Logger.debug("#{@prefix} deleting pid #{inspect(pid)} with parent #{inspect(ref_pid)}")
        :ets.delete(ets, pid)
        {:noreply, state}

      :error ->
        Logger.warn("#{@prefix} Don't know anything about monitored process #{inspect(pid)}")
        {:noreply, state}
    end
  end

  defp next_timeout(advance_dt, server_pids) do
    server_pids
    |> Enum.map(&{&1, MockGenServer.get_timeout(&1) |> fudge_server_timeout()})
    |> Enum.reject(fn {_, dt} -> is_nil(dt) end)
    |> Enum.concat([{:advance_to, advance_dt}])
    |> Enum.min_by(fn {_, dt} -> DateTime.to_unix(dt) end)
  end

  defp set_time(datetime, pid, ets) do
    Logger.debug("#{@prefix} new time for #{inspect(pid)} is #{inspect(datetime)}")
    :ets.insert(ets, {pid, datetime})
  end

  # GenServers that rely on timeouts cannot expect absolute precision -- the
  # time they wake up will be up to a few milliseconds (or thousands of
  # microseconds) later than expected.
  #
  # This also means that if multiple GenServers are waiting for the exact same
  # timeout, there's no guarantee what order they'll activate.
  #
  # Note that this may mask some bugs involving datetime comparison and 0ms
  # timeout loops, e.g. on servers that are testing "is my next event BEFORE
  # the current time" rather than "before OR EQUAL TO" the current time.
  #
  # TBH, those shouldn't actually happen in the real world, so I think that's
  # okay. Nevertheless, feel free to disable this temporarily if you want to
  # check for those.
  defp fudge_server_timeout(nil), do: nil

  defp fudge_server_timeout(datetime) do
    usecs = Enum.random(1..10000)
    datetime |> DateTime.add(usecs, :microsecond)
  end

  # Increase precision on timestamps to 6 (the max).
  # This allows us to see microseconds in debug logs.
  @precision 6
  defp increase_precision(%DateTime{microsecond: {_, p}} = dt) when p >= @precision, do: dt

  defp increase_precision(%DateTime{microsecond: {usecs, _}} = dt) do
    %DateTime{dt | microsecond: {usecs, @precision}}
  end
end
