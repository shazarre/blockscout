defmodule Explorer.Chain.Events.Publisher do
  @moduledoc """
  Publishes events related to the Chain context.
  """

  alias Explorer.Celo.Events.ContractEventStream

  # Tags from import runner phase
  @allowed_events ~w(addresses address_coin_balances address_token_balances blocks block_rewards internal_transactions celo_contract_event last_block_number staking_update token_transfers transactions contract_verification_result)a

  def broadcast(_data, false), do: :ok

  def broadcast(data, broadcast_type) do
    for {event_type, event_data} <- data, event_type in @allowed_events do
      send_data(event_type, broadcast_type, event_data)
    end
  end

  @spec broadcast(atom()) :: :ok
  def broadcast(event_type) do
    send_data(event_type)
    :ok
  end

  defp send_data(event_type) do
    sender().send_data(event_type)
  end

  defp sender do
    Application.get_env(:explorer, :realtime_events_sender)
  end

  # The :catchup type of event is not being consumed right now.
  # To avoid a large number of unread messages in the `mailbox` the dispatch of
  # these type of events is disabled for now.
  defp send_data(_event_type, :catchup, _event_data), do: :ok

  defp send_data(event_type, broadcast_type, event_data) do
    if event_type == :celo_contract_event do
      ContractEventStream.enqueue(event_data)
    end

    sender().send_data(event_type, broadcast_type, event_data)
  end
end
