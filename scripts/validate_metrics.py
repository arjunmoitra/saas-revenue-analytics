"""
Independent cross-check of the warehouse's financial calculations.

Recomputes a handful of key numbers straight from the raw CSVs with pandas
(no dbt logic reused) and compares them to the dbt marts in DuckDB:

  1. Month-end MRR for three hand-picked customers (an upgrader, a churner and
     an annual-plan customer), month by month.
  2. Company-wide MRR and active customers for the snapshot month.
  3. Invoice header totals versus line items, and recognised revenue versus
     billed line amounts.

Exit code is non-zero if any check fails, so it can run in CI after dbt build.
"""

from __future__ import annotations

import sys
from pathlib import Path

import duckdb
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW = PROJECT_ROOT / "data" / "raw"
DB = PROJECT_ROOT / "data" / "saas_revenue.duckdb"
AS_OF = pd.Timestamp("2026-08-31")
TOLERANCE = 0.01

failures: list[str] = []


def check(label: str, expected: float, actual: float) -> None:
    ok = abs(expected - actual) <= TOLERANCE
    status = "OK  " if ok else "FAIL"
    print(f"  [{status}] {label:<52} expected {expected:>14,.2f}  actual {actual:>14,.2f}")
    if not ok:
        failures.append(label)


def load_raw() -> tuple[pd.DataFrame, pd.DataFrame]:
    plans = pd.read_csv(RAW / "raw_plans.csv")
    subs = pd.read_csv(RAW / "raw_subscriptions.csv", parse_dates=["start_date", "end_date"])
    subs = subs[subs["is_trial"] == False].merge(plans[["plan_id", "billing_interval", "unit_price_cents"]], on="plan_id")  # noqa: E712
    subs["end_date"] = subs["end_date"].fillna(AS_OF)
    divisor = subs["billing_interval"].map({"monthly": 1, "annual": 12})
    subs["mrr"] = subs["unit_price_cents"] / 100 * subs["quantity"] / divisor
    return plans, subs


def mrr_at(subs: pd.DataFrame, month_end: pd.Timestamp) -> pd.Series:
    """MRR per customer for subscription versions active on the given month end."""
    active = subs[(subs["start_date"] <= month_end) & (subs["end_date"] >= month_end)]
    return active.groupby("customer_id")["mrr"].sum()


def main() -> int:
    plans, subs = load_raw()
    con = duckdb.connect(str(DB), read_only=True)

    # ---- 1. Hand-picked customers ------------------------------------------------
    picks = con.execute(
        """
        (select customer_id, 'upgrade' as why from marts.dim_subscriptions where change_type = 'upgrade' order by customer_id limit 1)
        union all
        (select customer_id, 'churned' from marts.dim_customers where customer_status = 'churned' order by customer_id limit 1)
        union all
        (select customer_id, 'annual' from marts.dim_subscriptions where billing_interval = 'annual' and is_open order by customer_id limit 1)
        """
    ).fetchall()

    months = pd.date_range("2023-01-31", AS_OF, freq="ME")
    for customer_id, why in picks:
        print(f"\nCustomer {customer_id} ({why})")
        versions = subs[subs["customer_id"] == customer_id].sort_values("start_date")
        for _, v in versions.iterrows():
            print(f"    {v.plan_id:<20} seats={v.quantity:<4} {v.start_date.date()} -> {v.end_date.date()}  mrr={v.mrr:,.2f}")
        warehouse = con.execute(
            "select month_end_date, mrr from marts.fct_mrr_movements where customer_id = ? order by 1", [customer_id]
        ).df()
        warehouse["month_end_date"] = pd.to_datetime(warehouse["month_end_date"])
        for month_end in months:
            expected = float(mrr_at(versions, month_end).get(customer_id, 0.0))
            row = warehouse[warehouse["month_end_date"] == month_end]
            actual = float(row["mrr"].iloc[0]) if not row.empty else 0.0
            if expected == 0 and actual == 0 and row.empty:
                continue  # before first paid month: no row expected
            check(f"MRR {month_end.strftime('%Y-%m')}", expected, actual)

    # ---- 2. Company-wide snapshot month -------------------------------------------
    print("\nCompany-wide, snapshot month")
    expected_by_customer = mrr_at(subs, AS_OF)
    metrics = con.execute(
        "select mrr, arr, active_customers, arpu from marts.metrics_monthly where month_end_date = ?", [AS_OF.date()]
    ).fetchone()
    check("total MRR", float(expected_by_customer.sum()), float(metrics[0]))
    check("total ARR", float(expected_by_customer.sum() * 12), float(metrics[1]))
    check("active customers", float((expected_by_customer > 0).sum()), float(metrics[2]))
    check("ARPU", float(expected_by_customer.sum() / (expected_by_customer > 0).sum()), float(metrics[3]))

    # MRR waterfall identity for the whole history
    identity_breaks = con.execute(
        """
        select count(*) from marts.metrics_monthly
        where abs(beginning_mrr + new_mrr + expansion_mrr + reactivation_mrr - contraction_mrr - churned_mrr - mrr) > 0.01
        """
    ).fetchone()[0]
    check("months where MRR waterfall identity breaks", 0, float(identity_breaks))

    # ---- 3. Invoices and revenue recognition -------------------------------------
    print("\nInvoices and revenue recognition")
    invoices = pd.read_csv(RAW / "raw_invoices.csv")
    lines = pd.read_csv(RAW / "raw_invoice_line_items.csv")
    line_sums = lines.groupby("invoice_id")["amount_cents"].sum()
    merged = invoices.set_index("invoice_id").join(line_sums.rename("line_cents"))
    mismatches = int((merged["subtotal_cents"] != merged["line_cents"]).sum())
    check("invoices whose subtotal != sum of lines", 0, float(mismatches))

    non_void = invoices[invoices["status"] != "void"]["invoice_id"]
    billed_ex_tax = lines[lines["invoice_id"].isin(non_void)]["amount_cents"].sum() / 100
    recognized_total = con.execute("select sum(recognized_revenue) from intermediate.int_revenue_recognition").fetchone()[0]
    check("recognized revenue == non-void line amounts", float(billed_ex_tax), float(recognized_total))

    con.close()
    print()
    if failures:
        print(f"{len(failures)} check(s) FAILED")
        return 1
    print("All checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
