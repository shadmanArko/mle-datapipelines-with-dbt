# dbt Intro: Build a Local Postgres Pipeline

This walkthrough shows how to go from raw NYC Taxi trip data to a working **dbt** project on top of PostgreSQL. By the end, you will have a pipeline that you can:

1. connect to with `dbt debug`,
2. populate with `dbt seed`,
3. build with `dbt run`,
4. validate with `dbt test`,
5. document with `dbt docs generate`.

## What is dbt?

**dbt (data build tool)** is a transformation framework for analytics engineering. It sits on top of your data warehouse and lets you define transformations as version-controlled SQL models.

dbt is especially useful in **ELT (Extract, Load, Transform)** workflows:

- Raw data is loaded into the warehouse first.
- dbt transforms that raw data into cleaner, more useful models.
- Tests and documentation live next to the SQL that defines the pipeline.

```mermaid
flowchart LR
    subgraph ELT
        elt1["Extract"] --> elt2["Load raw data into warehouse"] --> elt3["Transform in warehouse with dbt"]
    end
```

dbt is popular because it makes warehouse transformations easy to:

- review in Git,
- test and document,
- organize into reusable layers,
- run in different environments such as `dev` and `prod`.

## How dbt fits into a pipeline

A dbt project usually models data in layers.

| Layer | Purpose |
| --- | --- |
| **source / raw** | Data loaded from the outside world |
| **staging** | Light cleanup and column renaming |
| **intermediate** | Reusable business logic or aggregations |
| **mart** | Stakeholder-facing outputs |

For this tutorial we will use **dbt Core** with the Postgres adapter `dbt-postgres`. If you want to explore managed orchestration later, have a look at [dbt Cloud](https://www.getdbt.com/).

## Before you start

From the root of this repository, create a new folder for this walkthrough:

```bash
mkdir dbt-intro
cd dbt-intro
```

Nesting `dbt-intro/` inside the repository lets `uv run` find the repository's environment automatically, so every `python` and `dbt` command in this tutorial can run through `uv run` without activating anything manually, the same way on macOS, Windows and Linux. This also keeps the tutorial non-destructive and makes it easier to compare your results after the steps below with the solution reference.

Before continuing, confirm Docker is running:

```bash
docker version
```

If Docker is not running yet, start Docker Desktop or your local Docker daemon before moving on.

## 1. Start PostgreSQL in Docker

Start a local Postgres container:

```bash
docker run -d \
  --name ny-taxi-db \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=ny_taxi \
  -p 5432:5432 \
  postgres:17
```

Expected result:

- Docker prints a long container ID,
- a container named `ny-taxi-db` is now running.

Wait until the database is ready:

```bash
wait_for_postgres() {
  local deadline=$((SECONDS + 60))
  while (( SECONDS < deadline )); do
    if docker exec ny-taxi-db pg_isready -t 1 -U postgres -d ny_taxi; then
      return 0
    fi
    sleep 1
  done
  printf '%s\n' 'PostgreSQL was not ready within 60 seconds. Check: docker logs ny-taxi-db' >&2
  return 1
}
wait_for_postgres
```

Success looks like:

- the loop ends on its own,
- Postgres prints `accepting connections`.

If port `5432` is already in use on your machine, map a different host port such as `5433:5432` and then use that same host port everywhere in this tutorial:

- in the Python bootstrap script below,
- in `~/.dbt/profiles.yml`.

## 2. Download and load the raw source table

Create a small data folder and download the January 2025 Parquet file:

```bash
mkdir -p data
curl -L \
  -o data/yellow_tripdata_2025-01.parquet \
  https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2025-01.parquet
```

Now load that Parquet file into `public.yellow_taxi` in Postgres:

```bash
uv run python - <<'PY'
import pyarrow.parquet as pq
from time import perf_counter
from sqlalchemy import create_engine, text

engine = create_engine(
    "postgresql+psycopg2://postgres:postgres@localhost:5432/ny_taxi"
)
parquet_file = pq.ParquetFile("data/yellow_tripdata_2025-01.parquet")
expected_rows = parquet_file.metadata.num_rows
started_at = perf_counter()
loaded_rows = 0
print(f"Loading {expected_rows:,} rows into public.yellow_taxi", flush=True)

with engine.begin() as conn:
    conn.execute(text("drop table if exists public.yellow_taxi"))

first_batch = True
for batch_number, batch in enumerate(parquet_file.iter_batches(batch_size=50000), start=1):
    batch_started_at = perf_counter()
    df = batch.to_pandas()
    df.to_sql(
        "yellow_taxi",
        engine,
        schema="public",
        if_exists="replace" if first_batch else "append",
        index=False,
        method="multi",
        chunksize=5000,
    )
    first_batch = False
    loaded_rows += len(df)
    print(
        f"Batch {batch_number}: {loaded_rows:,}/{expected_rows:,} rows loaded; "
        f"batch {perf_counter() - batch_started_at:.1f}s, "
        f"elapsed {perf_counter() - started_at:.1f}s",
        flush=True,
    )

with engine.begin() as conn:
    row_count = conn.execute(
        text("select count(*) from public.yellow_taxi")
    ).scalar_one()

assert row_count == expected_rows, (
    f"Row count mismatch: Parquet contains {expected_rows:,} rows, "
    f"but PostgreSQL contains {row_count:,}."
)
print(f"Loaded {row_count} rows into public.yellow_taxi; row-count validation passed.")
engine.dispose()
PY
```

This load step can take a while on a laptop. Each completed batch reports progress and elapsed time. The final assertion compares the database count with the Parquet metadata; a completed insert alone is not proof of a complete load.

If you load the full January 2025 file, the row count should be **3,475,226**.

Success looks like:

- the Python script finishes without an exception,
- it prints `Loaded 3475226 rows into public.yellow_taxi`.

You can also verify the amount of rows directly from Docker:

```bash
docker exec -it ny-taxi-db \
  psql -U postgres -d ny_taxi \
  -c "select count(*) as row_count from public.yellow_taxi;"
```

### Expected source table

Before you touch dbt, make sure the source table `public.yellow_taxi` exists and that it contains these columns:

```text
VendorID
tpep_pickup_datetime
tpep_dropoff_datetime
passenger_count
trip_distance
RatecodeID
store_and_fwd_flag
PULocationID
DOLocationID
payment_type
fare_amount
extra
mta_tax
tip_amount
tolls_amount
improvement_surcharge
total_amount
congestion_surcharge
Airport_fee
cbd_congestion_fee
```

To do this, you can run:

```bash
docker exec ny-taxi-db \
  psql -U postgres -d ny_taxi \
  -c "\d public.yellow_taxi"
```

This exact schema is what the staging model below expects.

## 3. Initialize a dbt project

Create a new dbt project (without interactive profile prompts):

```bash
uv run dbt init dbt_intro --skip-profile-setup
```

This creates:

- a project folder called `dbt_intro`,
- a project config file called `dbt_project.yml`,
- the standard starter folders and example models.

Move into the project folder:

```bash
cd dbt_intro
```

## 4. Clean up the starter example

`dbt init` creates example starter models. We are going to replace those with our own tutorial models.

Delete the example folder:

```bash
rm -rf models/example
```

Then open `dbt_project.yml` in any editor you like and remove the `example:` block under `models.dbt_intro`:

```yaml
models:
  dbt_intro:
    example:
      +materialized: view
```

The surrounding comments can stay. If you skip this cleanup, dbt will still work, but it will print an unused-configuration warning.

## 5. Create `profiles.yml`

Open `~/.dbt/profiles.yml` in your preferred editor. If you want a command-line example:

```bash
nano ~/.dbt/profiles.yml
```

Or in VS Code:

```bash
code ~/.dbt/profiles.yml
```

If the file does not exist yet, create it. Then make sure it looks like this:

```yaml
dbt_intro:
  outputs:

    dev:
      dbname: ny_taxi
      host: localhost
      pass: postgres
      port: 5432
      schema: dbt_dev
      threads: 4
      type: postgres
      user: postgres

    prod:
      dbname: ny_taxi
      host: localhost
      pass: postgres
      port: 5432
      schema: dbt_prod
      threads: 4
      type: postgres
      user: postgres

  target: dev
```

This explicit file-based setup is easier to copy, review and debug than entering values through `dbt init` prompts.

### Why these schema names matter

dbt uses the target schema as a prefix when you also set a custom schema inside a model. That means:

- a model with `schema='stg'` lands in `dbt_dev_stg`,
- a model with `schema='int'` lands in `dbt_dev_int`,
- a model with `schema='driver'` lands in `dbt_dev_driver`.

That behavior is the default and it is expected.

## 6. Test the connection

Run:

```bash
uv run dbt debug
```

You should see:

- `profiles.yml file [OK found and valid]`
- `dbt_project.yml file [OK found and valid]`
- `Connection test: [OK connection ok]`
- `All checks passed!`

Success looks like:

- dbt can read both `dbt_project.yml` and `~/.dbt/profiles.yml`,
- the Postgres connection works without editing anything else.

It should look similar to this:

![dbt_debug_success](assets/01-dbt_debug.png)

## 7. Understand the project structure

Inside the dbt project folder you will see these main directories:

- [dbt_project.yml](https://docs.getdbt.com/reference/dbt_project.yml): project-level configuration
- [models](https://docs.getdbt.com/docs/build/models): SQL models that dbt turns into tables or views
- [seeds](https://docs.getdbt.com/docs/build/seeds): CSV files that dbt loads into the warehouse
- [tests](https://docs.getdbt.com/docs/build/data-tests): custom SQL tests
- [snapshots](https://docs.getdbt.com/docs/build/snapshots): slowly changing history for mutable data
- [macros](https://docs.getdbt.com/docs/build/jinja-macros): reusable Jinja logic
- [analyses](https://docs.getdbt.com/docs/build/analyses): ad hoc analytical SQL that is version-controlled but not materialized as a model

Key `dbt_project.yml` settings you should recognize:

- `name`: project name
- `profile`: which profile in `profiles.yml` to use
- `model-paths`, `seed-paths`, `snapshot-paths`, `macro-paths`: where dbt looks for resources
- `clean-targets`: directories removed by `dbt clean`

## 8. Create the staging layer

Create the folder:

```bash
mkdir -p models/staging
```

First define the source in `models/staging/src_yellow_taxi.yml`:

```yaml
version: 2

sources:
  - name: src_yellow_taxi
    schema: public
    tables:
      - name: yellow_taxi
```

This tells dbt: "My raw data lives in `public.yellow_taxi`."

Now create `models/staging/stg_yellow_taxi.sql`:

```sql
{{ config(materialized='table', schema='stg') }}

select
    "VendorID" as vendor_id,
    tpep_pickup_datetime as pickup_datetime,
    tpep_dropoff_datetime as dropoff_datetime,
    passenger_count,
    trip_distance,
    "RatecodeID" as rate_code_id,
    store_and_fwd_flag,
    "PULocationID" as pickup_location_id,
    "DOLocationID" as dropoff_location_id,
    payment_type,
    fare_amount,
    extra,
    mta_tax,
    tip_amount,
    tolls_amount,
    improvement_surcharge,
    total_amount,
    congestion_surcharge,
    "Airport_fee" as airport_fee,
    cbd_congestion_fee
from {{ source('src_yellow_taxi', 'yellow_taxi') }}
```

This model does only light cleanup:

- it reads directly from the raw source,
- it renames mixed-case columns into `snake_case`,
- it does not yet apply business logic.

If you want to limit development runs later, you can add:

```sql
{% if target.name == 'dev' %}
limit 100
{% endif %}
```

## 9. Add a seed file

Seeds are small CSV files that dbt can load into the warehouse for lookups and reference data.

Create `seeds/payment_type.csv`:

```csv
id,payment_type
1,Credit Card
2,Cash
3,No Charge
4,Dispute
5,Unknown
6,Voided Trip
```

This lookup will help us turn payment type codes into readable labels.

## 10. Create intermediate models

Create the intermediate folder:

```bash
mkdir -p models/intermediate
```

Create `models/intermediate/int_avg_tips_per_payment_type.sql`:

```sql
{{ config(materialized='table', schema='int') }}

with avg_tips as (
    select
        payment_type,
        avg(tip_amount) as avg_tip_amount
    from {{ ref('stg_yellow_taxi') }}
    where payment_type between 1 and 6
    group by 1
),
payment_type_lookup as (
    select
        id as payment_type_id,
        payment_type
    from {{ ref('payment_type') }}
)

select
    payment_type_lookup.payment_type,
    avg_tips.avg_tip_amount
from avg_tips
join payment_type_lookup
    on payment_type_lookup.payment_type_id = avg_tips.payment_type
```

Why do we filter to `payment_type between 1 and 6`?

- The raw dataset includes a `payment_type = 0`.
- Our seed file intentionally maps only `1` through `6`.
- Filtering here keeps the tutorial logic aligned with the lookup table.

Create `models/intermediate/int_avg_tips.sql`:

```sql
{{ config(materialized='table', schema='int') }}

select
    avg(tip_amount) as avg_tip_amount
from {{ ref('stg_yellow_taxi') }}
where payment_type between 1 and 6
```

This model computes the overall average tip across the known payment types.

## 11. Create a mart model

Create the mart folder:

```bash
mkdir -p models/mart/driver
```

Create `models/mart/driver/fct_best_tips.sql`:

```sql
{{ config(materialized='table', schema='driver') }}

with avg_tip as (
    select
        avg_tip_amount
    from {{ ref('int_avg_tips') }}
)

select
    payment_type,
    avg_tip_amount,
    case
        when avg_tip_amount < (select avg_tip_amount from avg_tip) then 'bad tip'
        when avg_tip_amount > (select avg_tip_amount from avg_tip) then 'good tip'
        else 'average tip'
    end as tip_status
from {{ ref('int_avg_tips_per_payment_type') }}
```

This model compares the average tip per payment method with the overall average tip and labels the result.

These are **recorded** tips, not total tipping behavior. The
[TLC data dictionary](https://www.nyc.gov/assets/tlc/downloads/pdf/data_dictionary_trip_records_yellow.pdf)
states that cash tips are not included. The illustrative `good tip` / `bad tip`
labels therefore cannot establish which payment method yields better actual tips.

### Model dependency graph

```mermaid
flowchart LR
    src["source('src_yellow_taxi', 'yellow_taxi')"] --> stg["stg_yellow_taxi"]
    stg --> intAvg["int_avg_tips"]
    stg --> intByType["int_avg_tips_per_payment_type"]
    seed["payment_type seed"] --> intByType
    intAvg --> mart["fct_best_tips"]
    intByType --> mart
```

## 12. Run the project

Now that the project files are in place, run the pipeline in order.

### Load the seed

```bash
uv run dbt seed
```

Expected result:

- dbt loads `payment_type.csv`,
- the table lands in the target schema, so in `dev` it becomes `dbt_dev.payment_type`.

### Build all models

```bash
uv run dbt run
```

Expected result in `dev`:

- `dbt_dev_stg.stg_yellow_taxi`
- `dbt_dev_int.int_avg_tips`
- `dbt_dev_int.int_avg_tips_per_payment_type`
- `dbt_dev_driver.fct_best_tips`

Success looks like:

- all four models finish with `OK`,
- dbt ends with `Completed successfully`.

### Run only the staging layer

```bash
uv run dbt run --select path:models/staging
```

### Run staging and intermediate layers only

```bash
uv run dbt run --select path:models/staging path:models/intermediate
```

## 13. Add realistic tests

dbt generic tests live in a schema YAML file. Create `models/staging/staging_schema.yml`:

```yaml
version: 2

models:
  - name: stg_yellow_taxi
    description: Staging model for January 2025 yellow taxi trips.
    columns:
      - name: vendor_id
        description: Vendor identifier from the source data.
        data_tests:
          - not_null
      - name: pickup_datetime
        description: Pickup timestamp.
        data_tests:
          - not_null
      - name: dropoff_datetime
        description: Dropoff timestamp.
        data_tests:
          - not_null
      - name: trip_distance
        description: Trip distance in miles.
        data_tests:
          - not_null
      - name: store_and_fwd_flag
        description: Whether the trip record was held in vehicle memory.
        data_tests:
          - accepted_values:
              arguments:
                values: ['Y', 'N']
      - name: payment_type
        description: Payment type code.
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('payment_type')
                field: id
              config:
                where: "payment_type between 1 and 6"
      - name: fare_amount
        description: Metered fare amount.
        data_tests:
          - not_null
      - name: total_amount
        description: Final charged amount.
        data_tests:
          - not_null

seeds:
  - name: payment_type
    columns:
      - name: id
        data_tests:
          - not_null
          - unique
      - name: payment_type
        data_tests:
          - not_null
          - unique
```

These tests are intentionally realistic for taxi trip data.

We do **not** use `unique` on staging fields such as `vendor_id`, `rate_code_id`, `pickup_location_id`, `dropoff_location_id` or `payment_type` because those values repeat across many trips and would fail immediately.

The seed is different: each ID must have exactly one distinct label. Its four tests prevent missing or duplicate lookup values. The [relationships test](https://docs.getdbt.com/reference/resource-properties/data-tests#relationships) checks that every staging payment code retained by the intermediate models (1 through 6) exists in the seed. This prevents the lookup join from silently dropping those codes; unique seed IDs prevent it from multiplying matches. Codes outside that range remain intentionally excluded. There are 13 tests in total.

Run the tests:

```bash
uv run dbt test
```

Expected result:

- all configured tests pass,
- dbt reports each `PASS` and ends with `Completed successfully`.

## 14. Generate documentation

dbt can turn your model metadata into browsable project docs.

Generate the artifacts:

```bash
uv run dbt docs generate
```

This writes documentation artifacts such as `manifest.json` and `catalog.json` into the `target/` directory.

Serve the docs locally:

```bash
uv run dbt docs serve
```

Press Ctrl+C in the terminal to exit the server.

## 15. Verification checklist

Use this checklist at the end of the tutorial:

1. `docker exec -it ny-taxi-db psql -U postgres -d ny_taxi -c "select count(*) from public.yellow_taxi;"` returns the expected row count.
2. `uv run dbt debug` ends with `All checks passed!`.
3. `uv run dbt seed` loads `dbt_dev.payment_type`.
4. `uv run dbt run` builds the staging, intermediate, and mart models.
5. `uv run dbt test` finishes with all tests passing.
6. `uv run dbt docs generate` writes docs artifacts into `target/`.

If all six checks succeed, your local dbt pipeline is working end to end.
