defmodule FeteBot.Test.MockGenServer do
  use GenServer

  alias FeteBot.Test.MockDateTime

  defmodule State do
    @enforce_keys [:module]
    defstruct(
      module: nil,
      inner_state: nil,
      timeout_at: nil
    )
  end

  def child_spec(module, init_arg \\ nil, options \\ []) do
    module.child_spec(init_arg)
    |> Map.put(:start, {__MODULE__, :start_link, [module, init_arg, options]})
  end

  def start_link(module, init_arg, options) do
    GenServer.start_link(__MODULE__, {module, init_arg}, options)
  end

  def get_timeout(pid) do
    GenServer.call(pid, {__MODULE__, :get_timeout})
  end

  def trigger_timeout(pid) do
    GenServer.cast(pid, {__MODULE__, :trigger_timeout})
  end

  @impl true
  def init({module, init_arg}) do
    outer = %State{module: module}

    case module.init(init_arg) do
      {:ok, inner} -> encapsulate({:ok}, outer, inner)
      {:ok, inner, timeout} -> encapsulate({:ok}, outer, inner, timeout)
    end
  end

  @impl true
  def handle_cast({__MODULE__, :trigger_timeout}, outer) do
    case outer.module.handle_info(:timeout, outer.inner_state) do
      {:noreply, inner} -> encapsulate({:noreply}, outer, inner)
      {:noreply, inner, timeout} -> encapsulate({:noreply}, outer, inner, timeout)
    end
  end

  @impl true
  def handle_cast(message, outer) do
    case outer.module.handle_cast(message, outer.inner_state) do
      {:noreply, inner} -> encapsulate({:noreply}, outer, inner)
      {:noreply, inner, timeout} -> encapsulate({:noreply}, outer, inner, timeout)
    end
  end

  @impl true
  def handle_call({__MODULE__, :get_timeout}, _from, outer) do
    {:reply, outer.timeout_at, outer}
  end

  @impl true
  def handle_call(message, from, outer) do
    case outer.module.handle_call(message, from, outer.inner_state) do
      {:reply, reply, inner} -> encapsulate({:reply, reply}, outer, inner)
      {:reply, reply, inner, timeout} -> encapsulate({:reply, reply}, outer, inner, timeout)
    end
  end

  @impl true
  def handle_info(message, outer) do
    case outer.module.handle_info(message, outer.inner_state) do
      {:noreply, inner} -> encapsulate({:noreply}, outer, inner)
      {:noreply, inner, timeout} -> encapsulate({:noreply}, outer, inner, timeout)
    end
  end

  defp encapsulate(reply, outer, inner, timeout \\ nil) do
    timeout = msecs_to_datetime(timeout)
    outer = %State{outer | inner_state: inner, timeout_at: timeout}

    reply
    |> Tuple.to_list()
    |> Enum.concat([outer])
    |> List.to_tuple()
  end

  defp msecs_to_datetime(nil), do: nil

  defp msecs_to_datetime(ms) when is_integer(ms) do
    MockDateTime.utc_now()
    |> DateTime.add(ms, :millisecond)
  end
end
