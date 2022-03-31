defmodule FeteBot.Notifier.AlarmUser do
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  alias FeteBot.Notifier.Alarm

  schema "alarm_users" do
    timestamps()

    has_many(:alarms, Alarm)

    field(:user_id, :integer)
    field(:dm_id, :integer)
    field(:summary_message_id, :integer)
  end

  def insert_changeset(user_id, dm_id) do
    %AlarmUser{}
    |> change(
      user_id: user_id,
      dm_id: dm_id
    )
    |> unique_constraint(:user_id, name: :users_unique_index, message: "already exists")
  end

  def update_summary_changeset(%AlarmUser{} = user, msg_id) do
    user
    |> change(summary_message_id: msg_id)
  end
end
