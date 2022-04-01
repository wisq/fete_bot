defmodule FeteBot.Application do
  # require Logger
  use Application

  def start(_type, _args) do
    children =
      [
        FeteBot.Repo
      ] ++ bot_children()

    options = [strategy: :rest_for_one, name: FeteBot.Supervisor]
    Supervisor.start_link(children, options)
  end

  def start_bot? do
    Application.fetch_env!(:fete_bot, __MODULE__)
    |> Keyword.fetch!(:start_bot)
  end

  def bot_children() do
    if start_bot?() do
      [
        FeteBot.Consumer,
        FeteBot.Tracker.Scheduler,
        FeteBot.Notifier.Scheduler
      ]
    else
      []
    end
  end
end
