defmodule FeteBot.Repo.Migrations.CreateAlarmEventType do
  use Ecto.Migration

  def up do
    execute("CREATE TYPE alarm_event AS ENUM ('epoch', 'session')")
  end

  def down do
    execute("DROP TYPE alarm_event")
  end
end
