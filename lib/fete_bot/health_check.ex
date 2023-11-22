defmodule FeteBot.HealthCheck do
  import Plug.Conn

  def children do
    env = Application.fetch_env!(:fete_bot, __MODULE__)
    {enabled, opts} = Keyword.pop!(env, :enabled)

    case enabled do
      true -> [{Bandit, opts |> Keyword.put(:plug, __MODULE__)}]
      false -> []
    end
  end

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    shards = all_shard_pids()
    healthy = shards |> Enum.count(&is_healthy/1)
    total = Enum.count(shards)

    text = "healthy: #{healthy} / #{total}\n"
    code = if healthy > 0, do: 200, else: 503

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(code, text)
  end

  # Logic borrowed from Nostrum.Util.get_all_shard_latencies/0
  defp all_shard_pids do
    Nostrum.Shard.Supervisor
    |> Supervisor.which_children()
    |> Enum.filter(fn {_id, _pid, _type, [modules]} -> modules == Nostrum.Shard end)
    |> Enum.flat_map(fn {_id, pid, _type, _modules} -> Supervisor.which_children(pid) end)
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
  end

  defp is_healthy(pid) do
    case Nostrum.Shard.Session.get_ws_state(pid) do
      {:connected, _} -> true
      {_, _} -> false
    end
  end
end
