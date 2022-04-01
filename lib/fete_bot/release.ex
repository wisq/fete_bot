# From https://hexdocs.pm/phoenix/releases.html
defmodule FeteBot.Release do
  @app :fete_bot

  defmodule Env do
    def mix_env do
      if Code.ensure_loaded?(Mix) do
        Mix.env()
      else
        System.fetch_env!("MIX_ENV") |> String.to_atom()
      end
    end
  end

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
