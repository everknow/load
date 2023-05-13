defmodule Load.SimProcess do

  @behaviour Load.Sim

  @impl true
  def init do
    # Application.get_env(:load, __MODULE__, %{})
    os_dir = Application.get_env(:load, :os_dir)
    os_command = Application.get_env(:load, :os_command)
    port = :erlang.open_port({:spawn, os_command}, [{:cd, os_dir}, :binary, :exit_status])
    sent = :erlang.port_command(port, "#{phrase}##{accounts_count}##{url}##{addr_prefix}##{faucet_amount}##{faucet_denom}##{chain_id}")
    if not sent, do: Logger.error("could not send to port")
    for 1..accounts_count do
      receive do
        {port, {:data, data}}
      end
      {:ok, tx_hash, state} = Load.Worker.hit("POST /#{path_to_cosmos_node}", [], data, %{})
    end

    # wait for all transactions

    %{}
  end

  @impl true
  def run(state) do
    payload = "example content"
    {:ok, res_payload, state} = Load.Worker.hit("POST /example/echo", [], payload, state)
    Logger.debug("sim received back #{res_payload}")
    state
  end


end
