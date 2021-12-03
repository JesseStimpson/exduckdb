# exduckdb

A quick-n-dirty Elixir DuckDB library.

Mostly true to the original fork of [Exqlite](https://github.com/elixir-sqlite/exqlite), currently tracking version [0.3.1](https://github.com/duckdb/duckdb/releases/tag/v0.3.1) of DuckDB through git submodules.

Implemented using the provided [sqlite3_api_wrapper](https://github.com/duckdb/duckdb/tree/master/tools/sqlite3_api_wrapper) from DuckDB.

## Caveats

### Upstream Sqlite caveats
* Prepared statements are not cached.
* Prepared statements are not immutable. You must be careful when manipulating
  statements and binding values to statements. Do not try to manipulate the
  statements concurrently. Keep it isolated to one process.
* Simultaneous writing is not supported by SQLite3 and will not be supported
  here.
* All native calls are run through the Dirty NIF scheduler.
* Datetimes are stored without offsets. This is due to how SQLite3 handles date
  and times. If you would like to store a timezone, you will need to create a
  second column somewhere storing the timezone name and shifting it when you
  get it from the database. This is more reliable than storing the offset as
  `+03:00` as it does not respect daylight savings time.


## Installation

```elixir
defp deps do
  {:exduckdb, "~> 0.9.0"}
end
```


## Configuration

```elixir
config :exduckdb, default_chunk_size: 100
```

* `default_chunk_size` - The chunk size that is used when multi-stepping when
  not specifying the chunk size explicitly.


## Usage

The `Exduckdb.DuckDB` module usage is fairly straight forward.

```elixir
# We'll just keep it in memory right now
{:ok, conn} = Exduckdb.DuckDB.open(":memory:")

# Create the table
:ok = Exduckdb.DuckDB.execute(conn, "create table test (id integer primary key, stuff text)");

# Prepare a statement
{:ok, statement} = Exduckdb.DuckDB.prepare(conn, "insert into test (stuff) values (?1)")
:ok = Exduckdb.DuckDB.bind(conn, statement, ["Hello world"])

# Step is used to run statements
:done = Exduckdb.DuckDB.step(conn, statement)

# Prepare a select statement
{:ok, statement} = Exduckdb.DuckDB.prepare(conn, "select id, stuff from test");

# Get the results
{:row, [1, "Hello world"]} = Exduckdb.DuckDB.step(conn, statement)

# No more results
:done = Exduckdb.DuckDB.step(conn, statement)

# Release the statement.
#
# It is recommended you release the statement after using it to reclaim the memory
# asap, instead of letting the garbage collector eventually releasing the statement.
#
# If you are operating at a high load issuing thousands of statements, it would be
# possible to run out of memory or cause a lot of pressure on memory.
:ok = Exduckdb.DuckDB.release(conn, statement)
```
