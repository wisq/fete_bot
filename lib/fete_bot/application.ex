defmodule FeteBot.Application do
  # require Logger
  use Application

  def start(_type, _args) do
    children = [
      FeteBot.Repo,
      FeteBot.Consumer,
      FeteBot.Tracker.Scheduler
    ]

    options = [strategy: :rest_for_one, name: FeteBot.Supervisor]
    Supervisor.start_link(children, options)
  end
end
