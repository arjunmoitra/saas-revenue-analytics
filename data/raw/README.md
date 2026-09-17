# Raw source extracts

Synthetic SaaS billing data produced by `scripts/generate_synthetic_data.py`
(seeded, so re-running the script reproduces these files byte for byte).
The shape mimics a Stripe-style billing system. It does **not** represent any
real company.

| File | Grain | Notes |
| --- | --- | --- |
| `raw_plans.csv` | One row per plan + billing interval | Per-seat pricing in integer cents. `basic_*` plans are retired. |
| `raw_customers.csv` | One row per customer account | Country, segment and casing are intentionally inconsistent. |
| `raw_subscriptions.csv` | One row per subscription **version** | A new version is created on every plan, seat or interval change. `previous_subscription_id` links versions. Trials never bill. |
| `raw_invoices.csv` | One row per invoice | One invoice per billing period. Statuses: `paid`, `open`, `uncollectible`, `void` (voided invoices are re-issued). |
| `raw_invoice_line_items.csv` | One row per invoice line | `subscription`, `one_time` (onboarding fee) and `discount` lines, each with a service period. |
| `raw_payments.csv` | One row per payment attempt | Includes failed attempts, partial payments and refunds (negative `amount_cents`, `payment_type = refund`). Status casing is inconsistent. |

Monetary columns are in cents. Dates are ISO-8601 strings. Empty strings are nulls.
