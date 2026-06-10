# cytopipe image — our CytoTable-based glue layer.
#
# Build from the repo root so the build context includes pyproject.toml and src/:
#   docker build -t cytopipe:dev -f containers/cytopipe/Dockerfile .
#
# STUB: pin a base image digest before production use.

FROM python:3.12-slim

# uv for fast, reproducible installs.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

# Install dependencies first (better layer caching), then the package.
COPY pyproject.toml ./
COPY src ./src
COPY README.md ./

# Install into the system environment (no project venv inside the container).
RUN uv pip install --system --no-cache .

ENTRYPOINT ["cytopipe"]
