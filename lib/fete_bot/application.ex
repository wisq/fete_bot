defmodule FeteBot.Application do
  # require Logger
  use Application

  def start(_type, _args) do
    children =
      [
        FeteBot.Repo
      ] ++ bot_children() ++ test_children() ++ FeteBot.HealthCheck.children()

    options = [strategy: :rest_for_one, name: FeteBot.Supervisor]
    Supervisor.start_link(children, options)
  end

  def config(name) do
    Application.fetch_env!(:fete_bot, __MODULE__)
    |> Keyword.fetch!(name)
  end

  def bot_children() do
    if config(:start_bot) do
      [
        FeteBot.Consumer,
        FeteBot.Tracker.Scheduler,
        FeteBot.Notifier.Scheduler
      ]
    else
      []
    end
  end

  def test_children() do
    if config(:start_test) do
      [
        FeteBot.Test.MockDiscord,
        FeteBot.Test.MockDateTime
      ]
    else
      []
    end
  end
end
