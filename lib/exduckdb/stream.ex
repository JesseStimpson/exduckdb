defmodule Exduckdb.Stream do
  @moduledoc false
  defstruct [:conn, :query, :params, :options]
  @type t :: %Exduckdb.Stream{}

  defimpl Enumerable do
    def reduce(%Exduckdb.Stream{query: %Exduckdb.Query{} = query} = stream, acc, fun) do
      # TODO: Possibly need to pass a chunk size option along so that we can let
      # the NIF chunk it.
      %Exduckdb.Stream{conn: conn, params: params, options: opts} = stream

      stream = %DBConnection.Stream{
        conn: conn,
        query: query,
        params: params,
        opts: opts
      }

      DBConnection.reduce(stream, acc, fun)
    end

    def reduce(%Exduckdb.Stream{query: statement} = stream, acc, fun) do
      %Exduckdb.Stream{conn: conn, params: params, options: opts} = stream
      query = %Exduckdb.Query{name: "", statement: statement}

      stream = %DBConnection.PrepareStream{
        conn: conn,
        query: query,
        params: params,
        opts: opts
      }

      DBConnection.reduce(stream, acc, fun)
    end

    def member?(_, _), do: {:error, __MODULE__}

    def count(_), do: {:error, __MODULE__}

    def slice(_), do: {:error, __MODULE__}
  end
end
