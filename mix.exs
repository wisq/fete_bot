defmodule FeteBot.MixProject do
  use Mix.Project

  def project do
    [
      app: :fete_bot,
      version: "0.1.0",
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {FeteBot.Application, []},
      extra_applications: extra_applications(Mix.env())
    ]
  end

  defp extra_applications(:test), do: [:logger]
  defp extra_applications(_), do: [:logger, :nostrum]

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}

      # Using latest master to workaround https://github.com/Kraigie/nostrum/pull/522
      {:nostrum, github: "Kraigie/nostrum", ref: "1ec397f", runtime: false},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:timex, "~> 3.7"},
      {:ecto_timex_duration, git: "https://github.com/wisq/ecto_timex_duration.git"},
      {:briefly, "~> 0.4", only: :test, runtime: false},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},
      # Elixir v1.15 workaround:
      {:ssl_verify_fun, "~> 1.1.6", manager: :rebar3, runtime: false, override: true}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
