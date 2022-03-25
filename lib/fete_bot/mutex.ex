defmodule FeteBot.Mutex do
  def run(name, func) do
    spawn_link(fn ->
      try do
        Process.register(self(), name)
        func.()
      rescue
        ArgumentError -> Process.whereis(name) |> wait_for_pid()
      end
    end)
    |> wait_for_pid()
  end

  defp wait_for_pid(nil), do: :ok

  defp wait_for_pid(pid) when is_pid(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    end
  end
end
