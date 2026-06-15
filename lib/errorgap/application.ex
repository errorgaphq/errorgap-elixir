defmodule Errorgap.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Errorgap.Client
    ]
    Supervisor.start_link(children, strategy: :one_for_one, name: Errorgap.Supervisor)
  end
end
