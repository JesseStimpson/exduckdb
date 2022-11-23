defmodule Exduckdb.MixProject do
  use Mix.Project

  @version "0.9.0"

  def project do
    [
      app: :exduckdb,
      version: @version,
      elixir: "~> 1.10",
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["all"],
      make_clean: ["clean"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: description(),
      test_paths: test_paths(System.get_env("EXDUCKDB_INTEGRATION")),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Docs
      name: "Exduckdb",
      source_url: "https://github.com/mpope9/exduckdb/",
      homepage_url: "https://github.com/mpope9/exduckdb/",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:db_connection, "~> 2.4"},
      {:elixir_make, "~> 0.6", runtime: false},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:temp, "~> 0.4", only: [:dev, :test]}
    ]
  end

  defp description do
    "An Elixir DuckDB library"
  end

  defp package do
    [
      files: ~w(
        lib
        .formatter.exs
        mix.exs
        README.md
        LICENSE
        .clang-format
        c_src/utf8.h
        c_src/duckdb_nif.c
        Makefile*
        c_src/duckdb/src/*
        c_src/duckdb/tools/sqlite3_api_wrapper/*
      ),
      name: "exduckdb",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/mpope9/exduckdb/"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: docs_extras(),
      source_ref: "v#{@version}",
      source_url: "https://github.com/mpope9/exduckdb/"
    ]
  end

  defp docs_extras do
    [
      "README.md": [title: "Readme"],
      "CHANGELOG.md": []
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp test_paths(nil), do: ["test"]
  defp test_paths(_any), do: ["integration_test/exduckdb"]
end
