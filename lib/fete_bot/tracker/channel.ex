defmodule FeteBot.Tracker.Channel do
  use Ecto.Schema
  import Ecto.Changeset
  alias __MODULE__

  schema "channels" do
    timestamps()
    field(:channel_id, :integer)
    field(:message_id, :integer)
  end

  @doc """
  Returns an Ecto.Changeset representing a newly added channel
  """
  def insert_changeset(channel_id) when is_integer(channel_id) do
    %Channel{}
    |> change(channel_id: channel_id)
    |> unique_constraint(:channel_id, name: :channels_unique_index, message: "already exists")
  end

  @doc """
  Returns an Ecto.Changeset representing a change to the `message_id` field.
  """
  def message_id_changeset(channel, message_id)
      when is_integer(message_id) or is_nil(message_id) do
    channel
    |> change(message_id: message_id)
  end
end
