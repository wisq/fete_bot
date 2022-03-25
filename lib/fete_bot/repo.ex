defmodule FeteBot.Repo do
  use Ecto.Repo,
    otp_app: :fete_bot,
    adapter: Ecto.Adapters.Postgres

  def create_public_schema(conn, {:database, expected_db}) do
    sql = "CREATE SCHEMA IF NOT EXISTS public"

    FeteBot.Mutex.run(:fetebot_create_public_schema, fn ->
      [[actual_db]] = Postgrex.query!(conn, "SELECT current_database()", []).rows

      if actual_db == expected_db do
        Postgrex.query!(conn, sql, [])
      end
    end)
  end
end
