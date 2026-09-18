"""
Build the SaaS revenue dashboard as a single self-contained HTML file.

Reads only from the dbt marts (never raw tables), embeds the data as JSON and
renders the charts client-side with Plotly. Open dashboard/index.html in a
browser; there is no server and no external data dependency.

Usage:
    python scripts/build_dashboard.py
"""

from __future__ import annotations

import json
from pathlib import Path

import duckdb

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DB = PROJECT_ROOT / "data" / "saas_revenue.duckdb"
OUTPUT = PROJECT_ROOT / "dashboard" / "index.html"
TEMPLATE = PROJECT_ROOT / "dashboard" / "template.html"


def fetch(con: duckdb.DuckDBPyConnection, sql: str) -> list[dict]:
    cursor = con.execute(sql)
    columns = [d[0] for d in cursor.description]
    rows = []
    for record in cursor.fetchall():
        row = {}
        for col, value in zip(columns, record):
            if hasattr(value, "isoformat"):
                value = value.isoformat()
            elif value is not None and not isinstance(value, (int, float, str, bool)):
                value = float(value)
            row[col] = value
        rows.append(row)
    return rows


def main() -> None:
    con = duckdb.connect(str(DB), read_only=True)

    data = {
        "as_of_date": con.execute("select max(month_end_date) from marts.metrics_monthly").fetchone()[0].isoformat(),
        "monthly": fetch(
            con,
            """
            select
                month_start_date, mrr, arr, beginning_mrr, new_mrr, expansion_mrr, reactivation_mrr,
                contraction_mrr, churned_mrr, net_new_mrr, active_customers, new_customers,
                churned_customers, reactivated_customers, signups, recognized_revenue,
                recognized_recurring_revenue, recognized_one_time_revenue, billed_amount,
                collected_amount, deferred_revenue_balance, arpu, mrr_growth_rate,
                customer_churn_rate, mrr_churn_rate, gross_revenue_retention, net_revenue_retention
            from marts.metrics_monthly
            order by month_start_date
            """,
        ),
        "by_plan": fetch(
            con,
            """
            select
                month_start_date, plan_tier, plan_tier_rank, mrr, active_customers, active_seats,
                churned_customers, upgrades_into_tier, downgrades_into_tier, recognized_revenue, arpu
            from marts.metrics_monthly_by_plan
            where plan_tier <> 'basic'
            order by month_start_date, plan_tier_rank
            """,
        ),
        "customers_by_segment": fetch(
            con,
            """
            select segment, count(*) as active_customers, sum(current_mrr) as mrr
            from marts.dim_customers
            where is_active
            group by segment
            order by mrr desc
            """,
        ),
        "top_customers": fetch(
            con,
            """
            select company_name, segment, latest_plan_tier as plan_tier, latest_billing_interval as billing_interval,
                   latest_seats as seats, current_arr, paid_tenure_months
            from marts.dim_customers
            where is_active
            order by current_arr desc
            limit 10
            """,
        ),
        "cohorts": fetch(
            con,
            """
            with base as (
                select first_mrr_month, sum(new_mrr) as starting_mrr
                from marts.fct_mrr_movements
                where mrr_movement_type = 'new'
                group by first_mrr_month
            )
            select
                strftime(m.first_mrr_month, '%Y-%m') as cohort,
                m.months_since_first_paid,
                round(sum(m.mrr) / b.starting_mrr * 100, 1) as retention_pct
            from marts.fct_mrr_movements m
            inner join base b on m.first_mrr_month = b.first_mrr_month
            where m.first_mrr_month >= (select max(month_start_date) from marts.metrics_monthly) - interval 18 month
              and m.months_since_first_paid <= 12
            group by m.first_mrr_month, m.months_since_first_paid, b.starting_mrr
            order by m.first_mrr_month, m.months_since_first_paid
            """,
        ),
    }
    con.close()

    html = TEMPLATE.read_text().replace("/*__DATA__*/", json.dumps(data))
    OUTPUT.write_text(html)
    print(f"wrote {OUTPUT.relative_to(PROJECT_ROOT)} ({OUTPUT.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
