"""
Generate a synthetic SaaS subscription billing dataset.

The output mimics the shape of a Stripe-style billing system:

    raw_plans               one row per plan + billing interval
    raw_customers           one row per customer account
    raw_subscriptions       one row per subscription *version* (a new row is
                            created on every plan / seat / interval change)
    raw_invoices            one row per invoice (one per billing period)
    raw_invoice_line_items  one row per line on an invoice
    raw_payments            one row per payment attempt, including refunds

Design choices that matter for the downstream models:

* Plan and seat changes only happen at billing-period boundaries, so there are
  no proration line items. The previous subscription version ends the day
  before the new one starts.
* Monetary amounts are stored as integer cents (like Stripe). The staging
  layer converts to dollars.
* Dates are written as ISO strings. Some string columns are intentionally
  messy (casing, whitespace, inconsistent country spellings) so the staging
  layer has real cleaning to do.
* Everything is seeded, so re-running the script reproduces identical files.

This is synthetic data. It does not represent any real company.
"""

from __future__ import annotations

import csv
import random
import uuid
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path

from faker import Faker

SEED = 20240917
START_DATE = date(2023, 1, 1)
AS_OF_DATE = date(2026, 8, 31)
N_CUSTOMERS = 600
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"

random.seed(SEED)
fake = Faker()
Faker.seed(SEED)


# --------------------------------------------------------------------------- #
# Reference data
# --------------------------------------------------------------------------- #

@dataclass(frozen=True)
class Plan:
    plan_id: str
    plan_name: str
    tier: str
    tier_rank: int
    billing_interval: str  # monthly | annual
    unit_price_cents: int  # per seat per interval
    is_active: bool


TIER_MONTHLY_PRICE = {"basic": 900, "starter": 1200, "growth": 2900, "scale": 5900, "enterprise": 9900}
TIER_RANK = {"basic": 0, "starter": 1, "growth": 2, "scale": 3, "enterprise": 4}
TIER_SEAT_RANGE = {
    "basic": (1, 5),
    "starter": (1, 10),
    "growth": (3, 30),
    "scale": (10, 80),
    "enterprise": (25, 200),
}

PLANS: list[Plan] = []
for tier, monthly in TIER_MONTHLY_PRICE.items():
    PLANS.append(Plan(f"{tier}_monthly", f"{tier.title()} (Monthly)", tier, TIER_RANK[tier], "monthly", monthly, tier != "basic"))
    # Annual plans are priced at 10 months: two months free for paying upfront.
    PLANS.append(Plan(f"{tier}_annual", f"{tier.title()} (Annual)", tier, TIER_RANK[tier], "annual", monthly * 10, tier != "basic"))

PLAN_BY_ID = {p.plan_id: p for p in PLANS}
ALL_TIERS = list(TIER_RANK)
ACTIVE_TIERS = ["starter", "growth", "scale", "enterprise"]
TIER_WEIGHTS = [0.42, 0.34, 0.17, 0.07]

COUNTRY_VARIANTS = {
    "US": ["US", "USA", "United States", "us", "U.S."],
    "GB": ["GB", "UK", "United Kingdom", "gb"],
    "CA": ["CA", "Canada", "canada"],
    "DE": ["DE", "Germany", "Deutschland"],
    "FR": ["FR", "France"],
    "AU": ["AU", "Australia"],
    "IN": ["IN", "India", "india"],
    "NL": ["NL", "Netherlands"],
    "SG": ["SG", "Singapore"],
    "BR": ["BR", "Brazil", "Brasil"],
}
COUNTRY_WEIGHTS = [0.48, 0.12, 0.09, 0.07, 0.05, 0.05, 0.05, 0.03, 0.03, 0.03]
INDUSTRIES = ["Software", "Financial Services", "Healthcare", "Retail", "Media", "Education", "Manufacturing", "Professional Services"]
CHANNELS = ["organic_search", "paid_search", "referral", "outbound", "partner", "event"]
CANCEL_REASONS = ["too_expensive", "missing_features", "switched_competitor", "no_longer_needed", "poor_support", "other", None]
PAYMENT_METHODS = ["card", "card", "card", "ach_debit", "wire"]


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.UUID(int=random.getrandbits(128)).hex[:14]}"


def add_months(d: date, months: int) -> date:
    """Add calendar months, clamping the day to the end of the target month."""
    month_index = d.month - 1 + months
    year = d.year + month_index // 12
    month = month_index % 12 + 1
    last_day = (date(year + (month == 12), (month % 12) + 1, 1) - timedelta(days=1)).day
    return date(year, month, min(d.day, last_day))


def iso_ts(d: date, hour: int | None = None) -> str:
    hour = random.randint(0, 23) if hour is None else hour
    return datetime(d.year, d.month, d.day, hour, random.randint(0, 59), random.randint(0, 59)).isoformat() + "Z"


def messy_case(value: str) -> str:
    roll = random.random()
    if roll < 0.08:
        return value.upper()
    if roll < 0.14:
        return value.title()
    if roll < 0.18:
        return f" {value} "
    return value


def weighted_signup_date() -> date:
    """Signups skew toward later periods to mimic a growing company."""
    span_days = (AS_OF_DATE - timedelta(days=45) - START_DATE).days
    offset = int(span_days * (random.random() ** 0.7))
    return START_DATE + timedelta(days=offset)


# --------------------------------------------------------------------------- #
# Records
# --------------------------------------------------------------------------- #

@dataclass
class Customer:
    customer_id: str
    company_name: str
    primary_email: str
    country: str
    industry: str
    segment: str
    acquisition_channel: str
    created_at: date
    tax_rate: float
    coupon_pct: int  # 0 when no coupon
    has_onboarding_fee: bool


@dataclass
class SubscriptionVersion:
    subscription_id: str
    customer_id: str
    plan_id: str
    quantity: int
    start_date: date
    end_date: date | None
    status: str
    canceled_at: date | None
    cancellation_reason: str | None
    is_trial: bool
    previous_subscription_id: str | None
    created_at: date
    updated_at: date


@dataclass
class Invoice:
    invoice_id: str
    invoice_number: str
    customer_id: str
    subscription_id: str
    issued_at: date
    due_at: date
    service_period_start: date
    service_period_end: date
    status: str
    subtotal_cents: int
    tax_cents: int
    total_cents: int
    currency: str
    lines: list[dict] = field(default_factory=list)


customers: list[Customer] = []
subscriptions: list[SubscriptionVersion] = []
invoices: list[Invoice] = []
line_items: list[dict] = []
payments: list[dict] = []


# --------------------------------------------------------------------------- #
# Customers
# --------------------------------------------------------------------------- #

def make_customers() -> None:
    for _ in range(N_CUSTOMERS):
        company = fake.company()
        domain = company.lower().replace(",", "").replace(".", "").replace(" ", "").replace("-", "")[:18] + ".com"
        country_code = random.choices(list(COUNTRY_VARIANTS), COUNTRY_WEIGHTS)[0]
        tier = random.choices(ACTIVE_TIERS, TIER_WEIGHTS)[0]
        segment = {"starter": "SMB", "growth": "SMB", "scale": "Mid-Market", "enterprise": "Enterprise"}[tier]
        customers.append(
            Customer(
                customer_id=new_id("cus"),
                company_name=messy_case(company),
                primary_email=messy_case(f"billing@{domain}").strip(),
                country=random.choice(COUNTRY_VARIANTS[country_code]),
                industry=random.choice(INDUSTRIES),
                segment=messy_case(segment).strip(),
                acquisition_channel=random.choice(CHANNELS),
                created_at=weighted_signup_date(),
                tax_rate=0.08 if country_code == "US" and random.random() < 0.6 else 0.0,
                coupon_pct=random.choice([10, 15, 20]) if random.random() < 0.12 else 0,
                has_onboarding_fee=random.random() < 0.30,
            )
        )
        # Stash the initial tier on the object for the subscription builder.
        customers[-1].__dict__["_initial_tier"] = tier


# --------------------------------------------------------------------------- #
# Subscriptions
# --------------------------------------------------------------------------- #

def pick_seats(tier: str) -> int:
    low, high = TIER_SEAT_RANGE[tier]
    return random.randint(low, high)


def churn_probability(tier: str, interval: str) -> float:
    """Per-billing-period cancellation probability."""
    base = {"basic": 0.035, "starter": 0.032, "growth": 0.022, "scale": 0.014, "enterprise": 0.009}[tier]
    return base * (5.0 if interval == "annual" else 1.0)


def build_subscription_chain(customer: Customer) -> None:
    """Walk forward period by period from signup, emitting a new subscription
    version on every change. Changes only happen on period boundaries."""
    tier = customer.__dict__["_initial_tier"]
    interval = "annual" if random.random() < (0.55 if tier == "enterprise" else 0.28) else "monthly"
    # A few early customers started on the retired Basic plan and were migrated.
    if customer.created_at < date(2023, 7, 1) and tier == "starter" and random.random() < 0.5:
        tier = "basic"
    quantity = pick_seats(tier)
    cursor = customer.created_at + timedelta(days=random.randint(0, 3))
    previous_id: str | None = None

    # Optional 14-day trial that never bills.
    if random.random() < 0.25:
        trial_end = cursor + timedelta(days=14)
        trial_plan = f"{tier if tier != 'basic' else 'starter'}_monthly"
        converts = random.random() < 0.70 and trial_end < AS_OF_DATE
        trial_id = new_id("sub")
        subscriptions.append(
            SubscriptionVersion(
                subscription_id=trial_id,
                customer_id=customer.customer_id,
                plan_id=trial_plan,
                quantity=quantity,
                start_date=cursor,
                end_date=trial_end if trial_end <= AS_OF_DATE else None,
                status="expired" if (not converts and trial_end <= AS_OF_DATE) else ("trialing" if trial_end > AS_OF_DATE else "converted"),
                canceled_at=None,
                cancellation_reason=None,
                is_trial=True,
                previous_subscription_id=None,
                created_at=cursor,
                updated_at=trial_end if trial_end <= AS_OF_DATE else cursor,
            )
        )
        if not converts:
            return
        cursor = trial_end + timedelta(days=1)
        previous_id = trial_id

    def period_length(iv: str) -> int:
        return 12 if iv == "annual" else 1

    def emit(start: date, end: date | None, status: str, canceled_at: date | None, reason: str | None) -> str:
        nonlocal previous_id
        sub_id = new_id("sub")
        subscriptions.append(
            SubscriptionVersion(
                subscription_id=sub_id,
                customer_id=customer.customer_id,
                plan_id=f"{tier}_{interval}",
                quantity=quantity,
                start_date=start,
                end_date=end,
                status=status,
                canceled_at=canceled_at,
                cancellation_reason=reason,
                is_trial=False,
                previous_subscription_id=previous_id,
                created_at=start,
                updated_at=end or start,
            )
        )
        previous_id = sub_id
        return sub_id

    version_start = cursor
    reactivations_left = 1
    while True:
        period_start = cursor
        period_end = add_months(period_start, period_length(interval)) - timedelta(days=1)

        if period_end >= AS_OF_DATE:
            # Open version: still active as of the snapshot date.
            emit(version_start, None, "active", None, None)
            return

        roll = random.random()
        p_churn = churn_probability(tier, interval)
        p_up = 0.014 if interval == "monthly" else 0.09
        p_down = 0.006 if interval == "monthly" else 0.05
        p_seats_up = 0.030 if interval == "monthly" else 0.16
        p_seats_down = 0.014 if interval == "monthly" else 0.08
        p_to_annual = 0.005 if interval == "monthly" else 0.0
        # Basic plan was retired: force migration to Starter at the first renewal after 2023-09.
        force_migration = tier == "basic" and period_end >= date(2023, 9, 30)

        next_start = period_end + timedelta(days=1)

        if roll < p_churn and not force_migration:
            canceled_at = period_start + timedelta(days=random.randint(3, max(3, (period_end - period_start).days - 1)))
            emit(version_start, period_end, "canceled", canceled_at, random.choice(CANCEL_REASONS))
            # Some churned customers come back later on a fresh subscription.
            if reactivations_left and random.random() < 0.10:
                reactivations_left -= 1
                gap_months = random.randint(2, 8)
                restart = add_months(next_start, gap_months)
                if restart < AS_OF_DATE - timedelta(days=30):
                    tier = random.choices(ACTIVE_TIERS, TIER_WEIGHTS)[0]
                    interval = "monthly"
                    quantity = pick_seats(tier)
                    cursor = restart
                    version_start = restart
                    previous_id = None
                    continue
            return

        changed = False
        if force_migration or roll < p_churn + p_up:
            if force_migration:
                tier, changed = "starter", True
            elif TIER_RANK[tier] < 4:
                tier = ALL_TIERS[TIER_RANK[tier] + 1]
                quantity = max(quantity, TIER_SEAT_RANGE[tier][0])
                changed = True
        elif roll < p_churn + p_up + p_down:
            if TIER_RANK[tier] > 1:
                tier = ALL_TIERS[TIER_RANK[tier] - 1]
                quantity = min(quantity, TIER_SEAT_RANGE[tier][1])
                changed = True
        elif roll < p_churn + p_up + p_down + p_seats_up:
            quantity = quantity + random.randint(1, max(1, quantity // 3))
            changed = True
        elif roll < p_churn + p_up + p_down + p_seats_up + p_seats_down:
            if quantity > TIER_SEAT_RANGE[tier][0]:
                quantity = max(TIER_SEAT_RANGE[tier][0], quantity - random.randint(1, max(1, quantity // 4)))
                changed = True
        elif roll < p_churn + p_up + p_down + p_seats_up + p_seats_down + p_to_annual:
            interval, changed = "annual", True

        if changed:
            emit(version_start, period_end, "superseded", None, None)
            version_start = next_start
        cursor = next_start


# --------------------------------------------------------------------------- #
# Invoices, line items, payments
# --------------------------------------------------------------------------- #

invoice_counter = 0


def next_invoice_number(issued: date) -> str:
    global invoice_counter
    invoice_counter += 1
    return f"INV-{issued.year}-{invoice_counter:06d}"


def build_invoices(customer: Customer, versions: list[SubscriptionVersion]) -> None:
    """Emit one invoice per billing period for each paid subscription version."""
    paid_versions = sorted((v for v in versions if not v.is_trial), key=lambda v: v.start_date)
    first_paid_invoice = True
    coupon_invoices_left = 3 if customer.coupon_pct else 0

    for version in paid_versions:
        plan = PLAN_BY_ID[version.plan_id]
        months = 12 if plan.billing_interval == "annual" else 1
        period_start = version.start_date
        last_service_day = version.end_date or AS_OF_DATE

        while period_start <= min(last_service_day, AS_OF_DATE):
            period_end = add_months(period_start, months) - timedelta(days=1)
            if version.end_date and period_end > version.end_date:
                # Should not happen because changes align to boundaries; guard anyway.
                period_end = version.end_date

            lines: list[dict] = []
            subscription_amount = plan.unit_price_cents * version.quantity
            lines.append(
                dict(
                    line_type="subscription",
                    plan_id=plan.plan_id,
                    description=f"{plan.plan_name} x {version.quantity} seats",
                    quantity=version.quantity,
                    unit_amount_cents=plan.unit_price_cents,
                    amount_cents=subscription_amount,
                    service_period_start=period_start,
                    service_period_end=period_end,
                )
            )
            if first_paid_invoice and customer.has_onboarding_fee:
                fee = {"basic": 0, "starter": 25000, "growth": 75000, "scale": 150000, "enterprise": 400000}[plan.tier]
                if fee:
                    lines.append(
                        dict(
                            line_type="one_time",
                            plan_id=None,
                            description="Onboarding & implementation fee",
                            quantity=1,
                            unit_amount_cents=fee,
                            amount_cents=fee,
                            service_period_start=period_start,
                            service_period_end=period_start,
                        )
                    )
            if coupon_invoices_left > 0:
                discount = -round(subscription_amount * customer.coupon_pct / 100)
                lines.append(
                    dict(
                        line_type="discount",
                        plan_id=plan.plan_id,
                        description=f"Coupon {customer.coupon_pct}% off",
                        quantity=1,
                        unit_amount_cents=discount,
                        amount_cents=discount,
                        service_period_start=period_start,
                        service_period_end=period_end,
                    )
                )
                coupon_invoices_left -= 1 if months == 1 else 3

            subtotal = sum(line["amount_cents"] for line in lines)
            tax = round(subtotal * customer.tax_rate)
            total = subtotal + tax
            issued = period_start
            invoice = Invoice(
                invoice_id=new_id("in"),
                invoice_number=next_invoice_number(issued),
                customer_id=customer.customer_id,
                subscription_id=version.subscription_id,
                issued_at=issued,
                due_at=issued + timedelta(days=30 if plan.billing_interval == "annual" else 14),
                service_period_start=period_start,
                service_period_end=period_end,
                status="paid",
                subtotal_cents=subtotal,
                tax_cents=tax,
                total_cents=total,
                currency="USD",
                lines=lines,
            )
            invoices.append(invoice)
            first_paid_invoice = False
            period_start = period_end + timedelta(days=1)


def build_payments() -> None:
    """Assign an invoice status and payment attempts to every invoice."""
    latest_invoice_by_customer: dict[str, Invoice] = {}
    for inv in invoices:
        current = latest_invoice_by_customer.get(inv.customer_id)
        if current is None or inv.issued_at > current.issued_at:
            latest_invoice_by_customer[inv.customer_id] = inv

    extra_invoices: list[Invoice] = []
    for inv in invoices:
        roll = random.random()
        days_since_issue = (AS_OF_DATE - inv.issued_at).days

        # Voided invoices: a corrected replacement is issued the same day.
        if roll < 0.012:
            inv.status = "void"
            replacement = Invoice(
                invoice_id=new_id("in"),
                invoice_number=next_invoice_number(inv.issued_at),
                customer_id=inv.customer_id,
                subscription_id=inv.subscription_id,
                issued_at=inv.issued_at,
                due_at=inv.due_at,
                service_period_start=inv.service_period_start,
                service_period_end=inv.service_period_end,
                status="paid",
                subtotal_cents=inv.subtotal_cents,
                tax_cents=inv.tax_cents,
                total_cents=inv.total_cents,
                currency=inv.currency,
                lines=[dict(line) for line in inv.lines],
            )
            extra_invoices.append(replacement)
            inv = replacement
            roll = random.random()

        if inv.total_cents <= 0:
            inv.status = "paid"
            continue

        # Recently issued invoices may still be open.
        if days_since_issue <= 14 and roll < 0.6:
            inv.status = "open"
            if random.random() < 0.3:
                add_payment(inv, inv.total_cents, "failed", inv.issued_at + timedelta(days=random.randint(0, 3)))
            continue

        # A small share of past-due invoices are written off.
        if roll < 0.03 + 0.012:
            inv.status = "uncollectible"
            add_payment(inv, inv.total_cents, "failed", inv.issued_at + timedelta(days=random.randint(0, 5)))
            if random.random() < 0.5:
                add_payment(inv, inv.total_cents, "failed", inv.issued_at + timedelta(days=random.randint(6, 20)))
            continue

        inv.status = "paid"
        paid_on = inv.issued_at + timedelta(days=random.randint(0, 12))
        pattern = random.random()
        if pattern < 0.85:
            add_payment(inv, inv.total_cents, "succeeded", paid_on)
        elif pattern < 0.92:
            add_payment(inv, inv.total_cents, "failed", inv.issued_at + timedelta(days=random.randint(0, 3)))
            add_payment(inv, inv.total_cents, "succeeded", paid_on + timedelta(days=random.randint(1, 10)))
        elif pattern < 0.97:
            first_part = round(inv.total_cents * random.uniform(0.3, 0.7))
            add_payment(inv, first_part, "succeeded", paid_on)
            add_payment(inv, inv.total_cents - first_part, "succeeded", paid_on + timedelta(days=random.randint(2, 20)))
        else:
            add_payment(inv, inv.total_cents, "succeeded", paid_on)
            refund = -round(inv.total_cents * random.choice([0.25, 0.5, 1.0]))
            add_payment(inv, refund, "succeeded", paid_on + timedelta(days=random.randint(3, 25)), payment_type="refund")

    invoices.extend(extra_invoices)

    # Mark the latest subscription of customers with an uncollectible latest invoice as past_due.
    for sub in subscriptions:
        if sub.status == "active":
            latest = latest_invoice_by_customer.get(sub.customer_id)
            if latest is not None and latest.status == "uncollectible":
                sub.status = "past_due"


def add_payment(inv: Invoice, amount_cents: int, status: str, paid_at: date, payment_type: str = "charge") -> None:
    if paid_at > AS_OF_DATE:
        return
    payments.append(
        dict(
            payment_id=new_id("py"),
            invoice_id=inv.invoice_id,
            customer_id=inv.customer_id,
            amount_cents=amount_cents,
            currency=inv.currency,
            status=random.choice([status, status.upper(), status.title()]),
            payment_type=payment_type,
            payment_method=random.choice(PAYMENT_METHODS),
            paid_at=iso_ts(paid_at),
            failure_reason=random.choice(["card_declined", "insufficient_funds", "expired_card"]) if status == "failed" else None,
        )
    )


# --------------------------------------------------------------------------- #
# Output
# --------------------------------------------------------------------------- #

def write_csv(name: str, rows: list[dict]) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUTPUT_DIR / f"{name}.csv"
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {len(rows):>7,} rows -> {path.relative_to(OUTPUT_DIR.parents[1])}")


def main() -> None:
    make_customers()
    for customer in customers:
        build_subscription_chain(customer)

    versions_by_customer: dict[str, list[SubscriptionVersion]] = {}
    for sub in subscriptions:
        versions_by_customer.setdefault(sub.customer_id, []).append(sub)
    for customer in customers:
        build_invoices(customer, versions_by_customer.get(customer.customer_id, []))
    build_payments()

    for inv in invoices:
        for line in inv.lines:
            line_items.append(
                dict(
                    line_item_id=new_id("il"),
                    invoice_id=inv.invoice_id,
                    line_type=line["line_type"],
                    plan_id=line["plan_id"],
                    description=line["description"],
                    quantity=line["quantity"],
                    unit_amount_cents=line["unit_amount_cents"],
                    amount_cents=line["amount_cents"],
                    service_period_start=line["service_period_start"].isoformat(),
                    service_period_end=line["service_period_end"].isoformat(),
                )
            )

    write_csv(
        "raw_plans",
        [
            dict(
                plan_id=p.plan_id,
                plan_name=p.plan_name,
                tier=p.tier,
                tier_rank=p.tier_rank,
                billing_interval=p.billing_interval,
                unit_price_cents=p.unit_price_cents,
                currency="USD",
                is_active=str(p.is_active).lower(),
                created_at=iso_ts(date(2022, 6, 1), 9),
            )
            for p in PLANS
        ],
    )
    write_csv(
        "raw_customers",
        [
            dict(
                customer_id=c.customer_id,
                company_name=c.company_name,
                primary_email=c.primary_email,
                country=c.country,
                industry=c.industry,
                segment=c.segment,
                acquisition_channel=c.acquisition_channel,
                created_at=iso_ts(c.created_at),
                updated_at=iso_ts(max(c.created_at, min(AS_OF_DATE, c.created_at + timedelta(days=random.randint(0, 400))))),
            )
            for c in customers
        ],
    )
    write_csv(
        "raw_subscriptions",
        [
            dict(
                subscription_id=s.subscription_id,
                customer_id=s.customer_id,
                plan_id=s.plan_id,
                quantity=s.quantity,
                status=s.status,
                is_trial=str(s.is_trial).lower(),
                start_date=s.start_date.isoformat(),
                end_date=s.end_date.isoformat() if s.end_date else "",
                canceled_at=iso_ts(s.canceled_at) if s.canceled_at else "",
                cancellation_reason=s.cancellation_reason or "",
                previous_subscription_id=s.previous_subscription_id or "",
                created_at=iso_ts(s.created_at),
                updated_at=iso_ts(s.updated_at),
            )
            for s in sorted(subscriptions, key=lambda s: (s.customer_id, s.start_date))
        ],
    )
    write_csv(
        "raw_invoices",
        [
            dict(
                invoice_id=i.invoice_id,
                invoice_number=i.invoice_number,
                customer_id=i.customer_id,
                subscription_id=i.subscription_id,
                status=i.status,
                currency=i.currency,
                subtotal_cents=i.subtotal_cents,
                tax_cents=i.tax_cents,
                total_cents=i.total_cents,
                issued_at=iso_ts(i.issued_at),
                due_at=i.due_at.isoformat(),
                service_period_start=i.service_period_start.isoformat(),
                service_period_end=i.service_period_end.isoformat(),
            )
            for i in sorted(invoices, key=lambda i: (i.issued_at, i.invoice_number))
        ],
    )
    write_csv("raw_invoice_line_items", line_items)
    write_csv("raw_payments", sorted(payments, key=lambda p: p["paid_at"]))


if __name__ == "__main__":
    main()
