defmodule FeteBot.Test.MockDateTime do
  use GenServer
  require Logger

  alias FeteBot.Test.MockGenServer

  @ets :mock_date_time
  @prefix "[#{inspect(__MODULE__)}]"

  defmodule State do
    @enforce_keys [:ets]
    defstruct(
      ets: nil,
      mock_servers: []
    )
  end

  def child_spec(%DateTime{} = start_time), do: super(start_time)

  def start_link(%DateTime{} = start_time) do
    GenServer.start_link(__MODULE__, start_time, name: __MODULE__)
  end

  def utc_now do
    case :ets.whereis(@ets) do
      ref when is_reference(ref) ->
        [now: now] = :ets.lookup(ref, :now)
        now

      nil ->
        DateTime.utc_now()
    end
  end

  alias FeteBot.TimeUtils

  def advance_to(%DateTime{} = datetime) do
    if datetime |> TimeUtils.is_before?(utc_now()),
      do: raise(ArgumentError, "Cannot go backwards in time")

    GenServer.call(__MODULE__, {:advance_to, datetime})
  end

  def advance_by(%Timex.Duration{} = duration) do
    utc_now()
    |> Timex.add(duration)
    |> advance_to()
  end

  def add_server(pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:add_server, pid})
    pid
  end

  @impl true
  def init(start_time) do
    ets = :ets.new(@ets, [:named_table, :set, :protected])
    start_time |> increase_precision() |> set_time(ets)
    {:ok, %State{ets: ets}}
  end

  @impl true
  def handle_cast({:add_server, pid}, state) do
    {:noreply, %State{state | mock_servers: [pid | state.mock_servers]}}
  end

  @impl true
  def handle_call({:advance_to, datetime}, from, state) do
    case next_timeout(datetime, state.mock_servers) do
      {:advance_to, ^datetime} ->
        Logger.debug("#{@prefix} advancing to requested time")
        set_time(datetime, state.ets)
        {:reply, :ok, state}

      {pid, dt} when is_pid(pid) ->
        Logger.debug("#{@prefix} triggering server: #{inspect(pid)}")
        set_time(dt, state.ets)
        MockGenServer.trigger_timeout(pid)
        handle_call({:advance_to, datetime}, from, state)
    end
  end

  defp next_timeout(advance_dt, server_pids) do
    server_pids
    |> Enum.map(&{&1, MockGenServer.get_timeout(&1) |> fudge_server_timeout()})
    |> Enum.concat([{:advance_to, advance_dt}])
    |> Enum.min_by(fn {_, dt} -> DateTime.to_unix(dt) end)
  end

  defp set_time(datetime, ets) do
    Logger.debug("#{@prefix} new time is #{inspect(datetime)}")
    :ets.insert(ets, {:now, datetime})
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
