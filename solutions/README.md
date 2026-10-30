# Solutions

This folder contains working reference snapshots for each tutorial chapter.

Each folder represents the expected end state after finishing that chapter:

- `01-dbt-intro/`: the validated Postgres-based dbt project from chapter 01
- `02-dockerize-dbt/`: the same project plus the Docker files from chapter 02
- `03-OPTIONAL-duckdb/`: the same project configured for the optional DuckDB runtime from chapter 03

How to use these snapshots:

- Each top-level `profiles.yml` file is an example of what should live at `~/.dbt/profiles.yml`.
- The `dbt_prod/profiles.yml` file in chapter 02 is the container-specific profile copied into the Docker image.
- These snapshots are reference states, not a replacement for the tutorial walkthroughs.

What is intentionally excluded:

- generated artifacts such as `target/` and `logs/`,
- virtual environments,
- downloaded Parquet files,
- the Postgres source table from chapters 01 and 02.
- the `ny_taxi.duckdb` database file from chapter 03.

That keeps the solution folders lightweight while still showing the exact hand-authored files that make the project work.
