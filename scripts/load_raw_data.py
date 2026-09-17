"""
Load the raw CSV extracts in data/raw/ into the `raw` schema of the DuckDB
warehouse that dbt reads from.

The raw layer is deliberately "dumb": every column keeps the type it had in
the source system (ids and dates as text, money as integer cents). All casting,
renaming and cleaning happens in the dbt staging layer so the lineage is
auditable end to end.

Usage:
    python scripts/load_raw_data.py            # uses data/saas_revenue.duckdb
    python scripts/load_raw_data.py --db path  # custom warehouse path
"""

from __future__ import annotations

import argparse
from pathlib import Path

import duckdb

PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = PROJECT_ROOT / "data" / "raw"
DEFAULT_DB = PROJECT_ROOT / "data" / "saas_revenue.duckdb"

# Explicit column types per raw table. VARCHAR for anything the source emits
# as text (including dates and booleans) so the staging layer owns the casts.
RAW_TABLES: dict[str, dict[str, str]] = {
    "raw_plans": {
        "plan_id": "VARCHAR",
        "plan_name": "VARCHAR",
        "tier": "VARCHAR",
        "tier_rank": "INTEGER",
        "billing_interval": "VARCHAR",
        "unit_price_cents": "BIGINT",
        "currency": "VARCHAR",
        "is_active": "VARCHAR",
        "created_at": "VARCHAR",
    },
    "raw_customers": {
        "customer_id": "VARCHAR",
        "company_name": "VARCHAR",
        "primary_email": "VARCHAR",
        "country": "VARCHAR",
        "industry": "VARCHAR",
        "segment": "VARCHAR",
        "acquisition_channel": "VARCHAR",
        "created_at": "VARCHAR",
        "updated_at": "VARCHAR",
    },
    "raw_subscriptions": {
        "subscription_id": "VARCHAR",
        "customer_id": "VARCHAR",
        "plan_id": "VARCHAR",
        "quantity": "INTEGER",
        "status": "VARCHAR",
        "is_trial": "VARCHAR",
        "start_date": "VARCHAR",
        "end_date": "VARCHAR",
        "canceled_at": "VARCHAR",
        "cancellation_reason": "VARCHAR",
        "previous_subscription_id": "VARCHAR",
        "created_at": "VARCHAR",
        "updated_at": "VARCHAR",
    },
    "raw_invoices": {
        "invoice_id": "VARCHAR",
        "invoice_number": "VARCHAR",
        "customer_id": "VARCHAR",
        "subscription_id": "VARCHAR",
        "status": "VARCHAR",
        "currency": "VARCHAR",
        "subtotal_cents": "BIGINT",
        "tax_cents": "BIGINT",
        "total_cents": "BIGINT",
        "issued_at": "VARCHAR",
        "due_at": "VARCHAR",
        "service_period_start": "VARCHAR",
        "service_period_end": "VARCHAR",
    },
    "raw_invoice_line_items": {
        "line_item_id": "VARCHAR",
        "invoice_id": "VARCHAR",
        "line_type": "VARCHAR",
        "plan_id": "VARCHAR",
        "description": "VARCHAR",
        "quantity": "INTEGER",
        "unit_amount_cents": "BIGINT",
        "amount_cents": "BIGINT",
        "service_period_start": "VARCHAR",
        "service_period_end": "VARCHAR",
    },
    "raw_payments": {
        "payment_id": "VARCHAR",
        "invoice_id": "VARCHAR",
        "customer_id": "VARCHAR",
        "amount_cents": "BIGINT",
        "currency": "VARCHAR",
        "status": "VARCHAR",
        "payment_type": "VARCHAR",
        "payment_method": "VARCHAR",
        "paid_at": "VARCHAR",
        "failure_reason": "VARCHAR",
    },
}


def load(db_path: Path) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(db_path))
    con.execute("CREATE SCHEMA IF NOT EXISTS raw")

    for table, columns in RAW_TABLES.items():
        csv_path = RAW_DIR / f"{table}.csv"
        if not csv_path.exists():
            raise FileNotFoundError(f"{csv_path} not found. Run scripts/generate_synthetic_data.py first.")
        column_struct = ", ".join(f"'{name}': '{dtype}'" for name, dtype in columns.items())
        con.execute(f"DROP TABLE IF EXISTS raw.{table}")
        con.execute(
            f"""
            CREATE TABLE raw.{table} AS
            SELECT *
            FROM read_csv(
                '{csv_path.as_posix()}',
                header = true,
                columns = {{{column_struct}}},
                nullstr = ''
            )
            """
        )
        row_count = con.execute(f"SELECT count(*) FROM raw.{table}").fetchone()[0]
        print(f"raw.{table:<24} {row_count:>7,} rows")

    con.close()
    print(f"\nLoaded into {db_path.relative_to(PROJECT_ROOT)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB, help="DuckDB file to load into")
    args = parser.parse_args()
    load(args.db)
