defmodule Exduckdb.DuckDBTest do
  use ExUnit.Case

  alias Exduckdb.DuckDB

  describe ".open/1" do
    test "opens a database in memory" do
      {:ok, conn} = DuckDB.open(":memory:")

      assert conn
    end

    test "opens a database on disk" do
      {:ok, path} = Temp.path()
      {:ok, conn} = DuckDB.open(path)

      assert conn

      File.rm(path)
    end
  end

  describe ".close/2" do
    test "closes a database in memory" do
      {:ok, conn} = DuckDB.open(":memory:")
      :ok = DuckDB.close(conn)
    end

    test "closing a database multiple times works properly" do
      {:ok, conn} = DuckDB.open(":memory:")
      :ok = DuckDB.close(conn)
      :ok = DuckDB.close(conn)
    end
  end

  describe ".execute/2" do
    test "creates a table" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      :ok = DuckDB.execute(conn, "insert into test (stuff) values ('This is a test')")
      {:ok, 1} = DuckDB.last_insert_rowid(conn)
      {:ok, 1} = DuckDB.changes(conn)
      :ok = DuckDB.close(conn)
    end

    test "handles incorrect syntax" do
      {:ok, conn} = DuckDB.open(":memory:")

      {:error, ~s|near "a": syntax error|} =
        DuckDB.execute(
          conn,
          "create a dumb table test (id integer primary key, stuff text)"
        )

      {:ok, 0} = DuckDB.changes(conn)
      :ok = DuckDB.close(conn)
    end

    test "creates a virtual table with fts3" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create virtual table things using fts3(content text)")

      :ok =
        DuckDB.execute(conn, "insert into things(content) VALUES ('this is content')")
    end

    test "creates a virtual table with fts4" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create virtual table things using fts4(content text)")

      :ok =
        DuckDB.execute(conn, "insert into things(content) VALUES ('this is content')")
    end

    test "creates a virtual table with fts5" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok = DuckDB.execute(conn, "create virtual table things using fts5(content)")

      :ok =
        DuckDB.execute(conn, "insert into things(content) VALUES ('this is content')")
    end
  end

  describe ".prepare/3" do
    test "preparing a valid sql statement" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = DuckDB.prepare(conn, "insert into test (stuff) values (?1)")

      assert statement
    end
  end

  describe ".release/2" do
    test "double releasing a statement" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = DuckDB.prepare(conn, "insert into test (stuff) values (?1)")
      :ok = DuckDB.release(conn, statement)
      :ok = DuckDB.release(conn, statement)
    end

    test "releasing a statement" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = DuckDB.prepare(conn, "insert into test (stuff) values (?1)")
      :ok = DuckDB.release(conn, statement)
    end

    test "releasing a nil statement" do
      {:ok, conn} = DuckDB.open(":memory:")
      :ok = DuckDB.release(conn, nil)
    end
  end

  describe ".bind/3" do
    test "binding values to a valid sql statement" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = DuckDB.prepare(conn, "insert into test (stuff) values (?1)")
      :ok = DuckDB.bind(conn, statement, ["testing"])
    end

    test "trying to bind with incorrect amount of arguments" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = DuckDB.prepare(conn, "insert into test (stuff) values (?1)")
      {:error, :arguments_wrong_length} = DuckDB.bind(conn, statement, [])
    end

    test "binds datetime value as string" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = DuckDB.prepare(conn, "insert into test (stuff) values (?1)")
      :ok = DuckDB.bind(conn, statement, [DateTime.utc_now()])
    end

    test "binds date value as string" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = DuckDB.prepare(conn, "insert into test (stuff) values (?1)")
      :ok = DuckDB.bind(conn, statement, [Date.utc_today()])
    end

    test "raises an error when binding non UTC datetimes" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = DuckDB.prepare(conn, "insert into test (stuff) values (?1)")

      msg = "#DateTime<2021-08-25 13:23:25+00:00 UTC Europe/Berlin> is not in UTC"

      assert_raise ArgumentError, msg, fn ->
        {:ok, dt} = DateTime.from_naive(~N[2021-08-25 13:23:25], "Etc/UTC")
        # Sneak in other timezone without a tz database
        other_tz = struct(dt, time_zone: "Europe/Berlin")

        DuckDB.bind(conn, statement, [other_tz])
      end
    end
  end

  describe ".columns/2" do
    test "returns the column definitions" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = DuckDB.prepare(conn, "select id, stuff from test")

      {:ok, columns} = DuckDB.columns(conn, statement)

      assert ["id", "stuff"] == columns
    end
  end

  describe ".step/2" do
    test "returns results" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      :ok = DuckDB.execute(conn, "insert into test (stuff) values ('This is a test')")
      {:ok, 1} = DuckDB.last_insert_rowid(conn)
      :ok = DuckDB.execute(conn, "insert into test (stuff) values ('Another test')")
      {:ok, 2} = DuckDB.last_insert_rowid(conn)

      {:ok, statement} =
        DuckDB.prepare(conn, "select id, stuff from test order by id asc")

      {:row, columns} = DuckDB.step(conn, statement)
      assert [1, "This is a test"] == columns
      {:row, columns} = DuckDB.step(conn, statement)
      assert [2, "Another test"] == columns
      assert :done = DuckDB.step(conn, statement)
    end

    test "returns no results" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = DuckDB.prepare(conn, "select id, stuff from test")
      assert :done = DuckDB.step(conn, statement)
    end

    test "works with insert" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = DuckDB.prepare(conn, "insert into test (stuff) values (?1)")
      :ok = DuckDB.bind(conn, statement, ["this is a test"])
      assert :done == DuckDB.step(conn, statement)
    end
  end

  describe ".multi_step/3" do
    test "returns results" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      :ok = DuckDB.execute(conn, "insert into test (stuff) values ('one')")
      :ok = DuckDB.execute(conn, "insert into test (stuff) values ('two')")
      :ok = DuckDB.execute(conn, "insert into test (stuff) values ('three')")
      :ok = DuckDB.execute(conn, "insert into test (stuff) values ('four')")
      :ok = DuckDB.execute(conn, "insert into test (stuff) values ('five')")
      :ok = DuckDB.execute(conn, "insert into test (stuff) values ('six')")

      {:ok, statement} =
        DuckDB.prepare(conn, "select id, stuff from test order by id asc")

      {:rows, rows} = DuckDB.multi_step(conn, statement, 4)
      assert rows == [[1, "one"], [2, "two"], [3, "three"], [4, "four"]]

      {:done, rows} = DuckDB.multi_step(conn, statement, 4)
      assert rows == [[5, "five"], [6, "six"]]
    end
  end

  describe ".multi_step/2" do
    test "returns results" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      :ok = DuckDB.execute(conn, "insert into test (stuff) values ('one')")
      :ok = DuckDB.execute(conn, "insert into test (stuff) values ('two')")
      :ok = DuckDB.execute(conn, "insert into test (stuff) values ('three')")
      :ok = DuckDB.execute(conn, "insert into test (stuff) values ('four')")
      :ok = DuckDB.execute(conn, "insert into test (stuff) values ('five')")
      :ok = DuckDB.execute(conn, "insert into test (stuff) values ('six')")

      {:ok, statement} =
        DuckDB.prepare(conn, "select id, stuff from test order by id asc")

      {:done, rows} = DuckDB.multi_step(conn, statement)

      assert rows == [
               [1, "one"],
               [2, "two"],
               [3, "three"],
               [4, "four"],
               [5, "five"],
               [6, "six"]
             ]
    end
  end

  describe "working with prepared statements after close" do
    test "returns proper error" do
      {:ok, conn} = DuckDB.open(":memory:")

      :ok =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = DuckDB.prepare(conn, "insert into test (stuff) values (?1)")
      :ok = DuckDB.close(conn)
      :ok = DuckDB.bind(conn, statement, ["this is a test"])

      {:error, message} =
        DuckDB.execute(conn, "create table test (id integer primary key, stuff text)")

      assert message == "DuckDB was invoked incorrectly."

      assert :done == DuckDB.step(conn, statement)
    end
  end

  describe "serialize and deserialize" do
    test "serialize a database to binary and deserialize to new database" do
      {:ok, path} = Temp.path()
      {:ok, conn} = DuckDB.open(path)

      :ok =
        DuckDB.execute(conn, "create table test(id integer primary key, stuff text)")

      assert {:ok, binary} = DuckDB.serialize(conn, "main")
      assert is_binary(binary)
      DuckDB.close(conn)
      File.rm(path)

      {:ok, conn} = DuckDB.open(":memory:")
      assert :ok = DuckDB.deserialize(conn, "main", binary)

      assert :ok =
               DuckDB.execute(conn, "insert into test(id, stuff) values (1, 'hello')")

      assert {:ok, statement} = DuckDB.prepare(conn, "select id, stuff from test")
      assert {:row, [1, "hello"]} = DuckDB.step(conn, statement)
    end
  end
end
