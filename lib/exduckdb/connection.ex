defmodule Exduckdb.Connection do
  @moduledoc """
  This module imlements connection details as defined in DBProtocol.

  ## Attributes

  - `db` - The sqlite3 database reference.
  - `path` - The path that was used to open.
  - `transaction_status` - The status of the connection. Can be `:idle` or `:transaction`.

  ## Unknowns

  - How are pooled connections going to work? Since sqlite3 doesn't allow for
    simultaneous access. We would need to check if the write ahead log is
    enabled on the database. We can't assume and set the WAL pragma because the
    database may be stored on a network volume which would cause potential
    issues.

  Notes:
    - we try to closely follow structure and naming convention of myxql.
    - sqlite thrives when there are many small conventions, so we may not implement
      some strategies employed by other adapters. See https://sqlite.org/np1queryprob.html
  """

  use DBConnection
  alias Exduckdb.Error
  #alias Exduckdb.Pragma
  alias Exduckdb.Query
  alias Exduckdb.Result
  alias Exduckdb.DuckDB

  defstruct [
    :db,
    :path,
    :transaction_status,
    :status,
    :chunk_size
  ]

  @type t() :: %__MODULE__{
          db: DuckDB.db(),
          path: String.t(),
          transaction_status: :idle | :transaction,
          status: :idle | :busy
        }

  @impl true
  @doc """
  Initializes the Ecto Exduckdb adapter.

  For connection configurations we use the defaults that come with SQLite3, but
  we recommend which options to choose. We do not default to the recommended
  because we don't know what your environment is like.

  Allowed options:

    * `:database` - The path to the database. In memory is allowed. You can use
      `:memory` or `":memory:"` to designate that.
  """
  def connect(options) do
    database = Keyword.get(options, :database)

    options =
      Keyword.put_new(
        options,
        :chunk_size,
        Application.get_env(:exqlite, :default_chunk_size, 50)
      )

    case database do
      nil ->
        {:error,
         %Error{
           message: """
           You must provide a :database to the database. \
           Example: connect(database: "./") or connect(database: :memory)\
           """
         }}

      :memory ->
        do_connect(":memory:", options)

      _ ->
        do_connect(database, options)
    end
  end

  @impl true
  def disconnect(_err, %__MODULE__{db: db}) do
    with :ok <- DuckDB.close(db) do
      :ok
    else
      {:error, reason} -> {:error, %Error{message: reason}}
    end
  end

  @impl true
  def checkout(%__MODULE__{status: :idle} = state) do
    {:ok, %{state | status: :busy}}
  end

  def checkout(%__MODULE__{status: :busy} = state) do
    {:disconnect, %Error{message: "Database is busy"}, state}
  end

  @impl true
  def ping(state), do: {:ok, state}

  ##
  ## Handlers
  ##

  @impl true
  def handle_prepare(%Query{} = query, options, state) do
    with {:ok, query} <- prepare(query, options, state) do
      {:ok, query, state}
    end
  end

  @impl true
  def handle_execute(%Query{} = query, params, options, state) do
    with {:ok, query} <- prepare(query, options, state) do
      execute(:execute, query, params, state)
    end
  end

  @doc """
  Begin a transaction.

  For full info refer to sqlite docs: https://sqlite.org/lang_transaction.html

  Note: default transaction mode is DEFERRED.
  """
  @impl true
  def handle_begin(options, %{transaction_status: transaction_status} = state) do
    # TODO: This doesn't handle more than 2 levels of transactions.
    #
    # One possible solution would be to just track the number of open
    # transactions and use that for driving the transaction status being idle or
    # in a transaction.
    #
    # I do not know why the other official adapters do not track this and just
    # append level on the savepoint. Instead the rollbacks would just completely
    # revert the issues when it may be desirable to fix something while in the
    # transaction and then commit.
    case Keyword.get(options, :mode, :deferred) do
      :deferred when transaction_status == :idle ->
        handle_transaction(:begin, "BEGIN TRANSACTION", state)

      :transaction when transaction_status == :idle ->
        handle_transaction(:begin, "BEGIN TRANSACTION", state)

      :immediate when transaction_status == :idle ->
        handle_transaction(:begin, "BEGIN IMMEDIATE TRANSACTION", state)

      :exclusive when transaction_status == :idle ->
        handle_transaction(:begin, "BEGIN EXCLUSIVE TRANSACTION", state)

      mode
      when mode in [:deferred, :immediate, :exclusive, :savepoint] and
             transaction_status == :transaction ->
        handle_transaction(:begin, "SAVEPOINT exqlite_savepoint", state)
    end
  end

  @impl true
  def handle_commit(options, %{transaction_status: transaction_status} = state) do
    case Keyword.get(options, :mode, :deferred) do
      :savepoint when transaction_status == :transaction ->
        handle_transaction(
          :commit_savepoint,
          "RELEASE SAVEPOINT exqlite_savepoint",
          state
        )

      mode
      when mode in [:deferred, :immediate, :exclusive, :transaction] and
             transaction_status == :transaction ->
        handle_transaction(:commit, "COMMIT", state)
    end
  end

  @impl true
  def handle_rollback(options, %{transaction_status: transaction_status} = state) do
    case Keyword.get(options, :mode, :deferred) do
      :savepoint when transaction_status == :transaction ->
        with {:ok, _result, state} <-
               handle_transaction(
                 :rollback_savepoint,
                 "ROLLBACK TO SAVEPOINT exqlite_savepoint",
                 state
               ) do
          handle_transaction(
            :rollback_savepoint,
            "RELEASE SAVEPOINT exqlite_savepoint",
            state
          )
        end

      mode
      when mode in [:deferred, :immediate, :exclusive, :transaction] ->
        handle_transaction(:rollback, "ROLLBACK TRANSACTION", state)
    end
  end

  @doc """
  Close a query prepared by `c:handle_prepare/3` with the database. Return
  `{:ok, result, state}` on success and to continue,
  `{:error, exception, state}` to return an error and continue, or
  `{:disconnect, exception, state}` to return an error and disconnect.

  This callback is called in the client process.
  """
  @impl true
  def handle_close(query, _opts, state) do
    DuckDB.release(state.db, query.ref)
    {:ok, nil, state}
  end

  @impl true
  def handle_declare(%Query{} = query, params, opts, state) do
    # We emulate cursor functionality by just using a prepared statement and
    # step through it. Thus we just return the query ref as the cursor.
    with {:ok, query} <- prepare_no_cache(query, opts, state),
         {:ok, query} <- bind_params(query, params, state) do
      {:ok, query, query.ref, state}
    end
  end

  @impl true
  def handle_deallocate(%Query{} = query, _cursor, _opts, state) do
    DuckDB.release(state.db, query.ref)
    {:ok, nil, state}
  end

  @impl true
  def handle_fetch(%Query{statement: statement}, cursor, _opts, state) do
    case DuckDB.step(state.db, cursor) do
      :done ->
        {
          :halt,
          %Result{
            rows: [],
            command: :fetch,
            num_rows: 0
          },
          state
        }

      {:row, row} ->
        {
          :cont,
          %Result{
            rows: [row],
            command: :fetch,
            num_rows: 1
          },
          state
        }

      :busy ->
        {:error, %Error{message: "Database busy", statement: statement}, state}

      {:error, reason} ->
        {:error, %Error{message: reason, statement: statement}, state}
    end
  end

  @impl true
  def handle_status(_opts, state) do
    {state.transaction_status, state}
  end

  ### ----------------------------------
  #     Internal functions and helpers
  ### ----------------------------------

  # TODO: Support duckdb pragmas
  #defp set_pragma(db, pragma_name, value) do
  #  DuckDB.execute(db, "PRAGMA #{pragma_name} = #{value}")
  #end

  #defp get_pragma(db, pragma_name) do
  #  {:ok, statement} = DuckDB.prepare(db, "PRAGMA #{pragma_name}")

  #  case DuckDB.fetch_all(db, statement) do
  #    {:ok, [[value]]} -> {:ok, value}
  #    _ -> :error
  #  end
  #end

  #defp maybe_set_pragma(db, pragma_name, value) do
  #  case get_pragma(db, pragma_name) do
  #    {:ok, current} ->
  #      if current == value do
  #        :ok
  #      else
  #        set_pragma(db, pragma_name, value)
  #      end

  #    _ ->
  #      set_pragma(db, pragma_name, value)
  #  end
  #end

  defp do_connect(path, options) do
    with {:ok, db} <- DuckDB.open(path) do
         #:ok <- set_journal_mode(db, options) do
      state = %__MODULE__{
        db: db,
        path: path,
        transaction_status: :idle,
        status: :idle,
        chunk_size: Keyword.get(options, :chunk_size)
      }

      {:ok, state}
    else
      {:error, reason} ->
        {:error, %Exduckdb.Error{message: reason}}
    end
  end

  def maybe_put_command(query, options) do
    case Keyword.get(options, :command) do
      nil -> query
      command -> %{query | command: command}
    end
  end

  # Attempt to retrieve the cached query, if it doesn't exist, we'll prepare one
  # and cache it for later.
  defp prepare(%Query{statement: statement} = query, options, state) do
    query = maybe_put_command(query, options)

    with {:ok, ref} <- DuckDB.prepare(state.db, IO.iodata_to_binary(statement)),
         query <- %{query | ref: ref} do
      {:ok, query}
    else
      {:error, reason} ->
        {:error, %Error{message: reason, statement: statement}, state}
    end
  end

  # Prepare a query and do not cache it.
  defp prepare_no_cache(%Query{statement: statement} = query, options, state) do
    query = maybe_put_command(query, options)

    case DuckDB.prepare(state.db, statement) do
      {:ok, ref} ->
        {:ok, %{query | ref: ref}}

      {:error, reason} ->
        {:error, %Error{message: reason, statement: statement}, state}
    end
  end

  @spec maybe_changes(DuckDB.db(), Query.t()) :: integer() | nil
  defp maybe_changes(db, %Query{command: command})
       when command in [:update, :insert, :delete] do
    case DuckDB.changes(db) do
      {:ok, total} -> total
      _ -> nil
    end
  end

  defp maybe_changes(_, _), do: nil

  # when we have an empty list of columns, that signifies that
  # there was no possible return tuple (e.g., update statement without RETURNING)
  # and in that case, we return nil to signify no possible result.
  defp maybe_rows([], []), do: nil
  defp maybe_rows(rows, _cols), do: rows

  defp execute(call, %Query{} = query, params, state) do
    with {:ok, query} <- bind_params(query, params, state),
         {:ok, columns} <- get_columns(query, state),
         {:ok, rows} <- get_rows(query, state),
         {:ok, transaction_status} <- DuckDB.transaction_status(state.db),
         changes <- maybe_changes(state.db, query) do
      case query.command do
        command when command in [:delete, :insert, :update] ->
          {
            :ok,
            query,
            Result.new(
              command: call,
              num_rows: changes,
              rows: maybe_rows(rows, columns)
            ),
            %{state | transaction_status: transaction_status}
          }

        _ ->
          {
            :ok,
            query,
            Result.new(
              command: call,
              columns: columns,
              rows: rows,
              num_rows: Enum.count(rows)
            ),
            %{state | transaction_status: transaction_status}
          }
      end
    end
  end

  defp bind_params(%Query{ref: ref, statement: statement} = query, params, state)
       when ref != nil do
    case DuckDB.bind(state.db, ref, params) do
      :ok ->
        {:ok, query}

      {:error, reason} ->
        {:error, %Error{message: reason, statement: statement}, state}
    end
  end

  defp get_columns(%Query{ref: ref, statement: statement}, state) do
    case DuckDB.columns(state.db, ref) do
      {:ok, columns} ->
        {:ok, columns}

      {:error, reason} ->
        {:error, %Error{message: reason, statement: statement}, state}
    end
  end

  defp get_rows(%Query{ref: ref, statement: statement}, state) do
    case DuckDB.fetch_all(state.db, ref, state.chunk_size) do
      {:ok, rows} ->
        {:ok, rows}

      {:error, reason} ->
        {:error, %Error{message: reason, statement: statement}, state}
    end
  end

  defp handle_transaction(call, statement, state) do
    with :ok <- DuckDB.execute(state.db, statement),
         {:ok, transaction_status} <- DuckDB.transaction_status(state.db) do
      result = %Result{
        command: call,
        rows: [],
        columns: [],
        num_rows: 0
      }

      {:ok, result, %{state | transaction_status: transaction_status}}
    else
      {:error, reason} ->
        {:disconnect, %Error{message: reason, statement: statement}, state}
    end
  end
end
