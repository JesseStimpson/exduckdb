defmodule Exduckdb.Basic do
  @moduledoc """
  A very basis API without lots of options to allow simpler usage for basic needs.
  """

  alias Exduckdb.Connection
  alias Exduckdb.Query
  alias Exduckdb.DuckDB
  alias Exduckdb.Error
  alias Exduckdb.Result

  def open(path) do
    Connection.connect(database: path)
  end

  def close(conn = %Connection{}) do
    with :ok <- DuckDB.close(conn.db) do
      :ok
    else
      {:error, reason} -> {:error, %Error{message: reason}}
    end
  end

  def exec(conn = %Connection{}, stmt, args \\ []) do
    %Query{statement: stmt} |> Connection.handle_execute(args, [], conn)
  end

  def rows(exec_result) do
    case exec_result do
      {:ok, %Query{}, %Result{rows: rows, columns: columns}, %Connection{}} ->
        {:ok, rows, columns}

      {:error, %Error{message: message}, %Connection{}} ->
        {:error, message}
    end
  end

end
