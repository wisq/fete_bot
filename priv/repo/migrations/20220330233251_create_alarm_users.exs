defmodule FeteBot.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:alarm_users) do
      timestamps()

      add(:user_id, :bigint, null: false)
      add(:dm_id, :bigint, null: false)
      add(:summary_message_id, :bigint, null: true)
    end

    create(index(:alarm_users, :user_id, name: "users_unique_index", unique: true))
  end
end
