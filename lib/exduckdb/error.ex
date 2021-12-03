defmodule Exduckdb.Error do
  @moduledoc false
  defexception [:message, :statement]

  @impl true
  def message(%__MODULE__{message: message, statement: nil}), do: message

  def message(%__MODULE__{message: message, statement: statement}),
    do: "#{message}\n#{statement}"
end
