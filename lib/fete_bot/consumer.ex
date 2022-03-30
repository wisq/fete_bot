defmodule FeteBot.Consumer do
  use Nostrum.Consumer

  # alias Nostrum.Api

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    case msg.content do
      "!fetebot " <> rest ->
        FeteBot.Commands.run(rest, msg)

      _ ->
        :ignore
    end
  end

  def handle_event({:MESSAGE_REACTION_ADD, data, _}) do
    FeteBot.Notifier.on_reaction_add(data)
  end

  def handle_event({event, _, _}) do
    IO.inspect(event)
    :noop
  end
end
