# Data Pipelines with dbt

This repository is a hands-on introduction to **dbt (data build tool)**. You will build a small analytics pipeline on top of NYC Yellow Taxi trip data: first on a local PostgreSQL database, then packaged into a Docker image, and optionally on DuckDB as a lightweight alternative runtime.

## Learning Objectives

By the end of this repository, you should be able to:

- Build a beginner-friendly dbt project on top of Postgres.
- Run the same dbt project inside Docker.
- Switch the same project to DuckDB with only small configuration changes.
- Understand how staging, intermediate and mart layers fit together in a simple analytics pipeline.

## Learning Path

| File / Folder | Description |
|---|---|
| [**01 - Intro to dbt**](01-dbt-intro.md) | Build and test a Postgres-based dbt project. |
| [**02 - Dockerize dbt**](02-dockerize-dbt.md) | Run the same project in Docker against Postgres. |
| [**03 - DuckDB (Optional)**](03-OPTIONAL-duckdb.md) | Run the same project with DuckDB. |

### Additional Folders and Files

| File / Folder | Description |
|---|---|
| [**solutions**](solutions/) | Chapter-end reference snapshots. |
| [**assets**](assets/) | Visual aids referenced in the repository. |
| [**pyproject.toml**](pyproject.toml) | Project configuration and dependencies. |
| [**uv.lock**](uv.lock) | Dependency lock file. |

## Prerequisites

- **Docker Desktop**: required to run the local PostgreSQL container used throughout this course. Follow the [installation instructions](https://docs.docker.com/get-docker/) if you do not have it yet. Make sure it is **installed and running** before you start the walkthrough.

> [!NOTE]
> **Windows Users:** The commands in this walkthrough use bash syntax. Use **Git Bash** (installed with [Git for Windows](https://git-scm.com/downloads/win)) instead of PowerShell to run them.

## Setup

Use [uv](https://docs.astral.sh/uv/getting-started/installation/) 0.13.5 or newer
and Python 3.13.17 or a newer 3.13 patch release, as defined in
[`.python-version`](.python-version).

Rebuild existing Docker images with `--pull --no-cache` after this update
to refresh their system certificates and dependencies.

> [!NOTE]
> Throughout these steps, text in angle brackets like `<repo-name>` is a **placeholder**. Replace it, including the `< >` brackets, with your own value. For example, `cd <repo-name>` becomes `cd mle-datapipelines-with-dbt`.

### 1. Use This Repository as a Template

Click **Use this template** on GitHub.

When creating the repository:

- Set yourself as the **Owner**
- Choose a repository name
- Disable **Include all branches**
- Click **Create repository**

> [!IMPORTANT]
> If you are working in pairs or groups, only **one person** should complete this step.

---

### 2. Add Collaborators (Pairs/Groups Only)

If working with teammates:

1. Open the repository on GitHub
2. Go to **Settings → Collaborators**
3. Add your teammates as collaborators
4. Share the repository link with your team

Teammates should accept the invitation before continuing.

---

### 3. Clone the Repository

Copy the SSH URL from the **Code** button on GitHub, then run:

```bash
git clone <copied-ssh-url>
```

The copied SSH URL will look like `git@github.com:<your-username>/<repo-name>.git`.

---

### 4. Move into the Project Folder and Install Dependencies

This installs all dependencies and creates a virtual environment in `.venv/`.

```bash
cd <repo-name>
uv sync
```

---

### 5. Open the Repository in VS Code

> [!NOTE]
> Make sure you open VS Code from the project root so it automatically detects the environment created by `uv sync`.

Launch VS Code in the project root folder:

```bash
code .
```

Every command in the walkthrough runs through `uv run`, so this environment is used automatically.

## Walkthrough

The main walkthrough in [**01-dbt-intro**](./01-dbt-intro.md) is self-contained. It shows you how to:

1. Start a local Postgres container.
2. Load the January 2025 Yellow Taxi source data into `public.yellow_taxi`.
3. Build, test and document a dbt project on top of that source.

Treat chapter 01 as the source of truth for first-time setup. Chapters 02 and 03 both assume you already finished that workspace, with chapter 03 being optional.

## Solutions

Chapter-end snapshots are available in [**solutions**](./solutions/README.md):

- [**solutions/01-dbt-intro**](./solutions/01-dbt-intro): chapter 01 end state
- [**solutions/02-dockerize-dbt**](./solutions/02-dockerize-dbt): chapter 02 end state
- [**solutions/03-OPTIONAL-duckdb**](./solutions/03-OPTIONAL-duckdb): chapter 03 optional end state

Use these as reference states if you want to compare your work with a validated version of the project. They complement the tutorials, but they are not meant to replace the step-by-step walkthroughs.
