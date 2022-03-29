defmodule FeteBot.Repo.Migrations.CreateChannels do
  use Ecto.Migration

  def change do
    create table(:channels) do
      timestamps()

      add(:channel_id, :bigint, null: false)
      add(:message_id, :bigint, null: true)
    end

    create(index(:channels, :channel_id, name: "channels_unique_index", unique: true))
  end
end
