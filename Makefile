.PHONY: setup data build test validate dashboard docs all clean

PY := .venv/bin/python
DBT := .venv/bin/dbt

setup:            ## create the virtualenv and install dbt-core, dbt-duckdb and helpers
	python3 -m venv .venv
	.venv/bin/pip install --quiet --upgrade pip
	.venv/bin/pip install --quiet -r requirements.txt
	$(DBT) deps

data:             ## regenerate the synthetic raw CSVs and load them into DuckDB
	$(PY) scripts/generate_synthetic_data.py
	$(PY) scripts/load_raw_data.py

build:            ## run seeds, models and tests from a clean state
	$(DBT) clean
	$(DBT) deps
	$(DBT) build

test:             ## run dbt tests only
	$(DBT) test

validate:         ## independent pandas cross-check of MRR/ARR/reconciliations
	$(PY) scripts/validate_metrics.py

dashboard:        ## rebuild dashboard/index.html from the marts
	$(PY) scripts/build_dashboard.py

docs:             ## generate and serve dbt docs
	$(DBT) docs generate
	$(DBT) docs serve

all: data build validate dashboard

clean:
	$(DBT) clean
	rm -f data/saas_revenue.duckdb data/saas_revenue.duckdb.wal
