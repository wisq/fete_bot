defmodule FeteBot.Repo.Migrations.CreateAlarms do
  use Ecto.Migration

  def change do
    create table(:alarms) do
      timestamps()

      add(:alarm_user_id, references("alarm_users"))
      add(:alarm_number, :smallint, null: false)
      add(:event, :alarm_event, null: false)
      add(:margin, :interval, null: false)

      add(:editing_message_id, :bigint, null: true)
      add(:last_alarm_message_id, :bigint, null: true)
    end

    create(
      index(:alarms, [:alarm_user_id, :alarm_number],
        name: "alarms_number_unique_index",
        unique: true
      )
    )
  end
end
