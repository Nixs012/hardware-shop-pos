---
name: pos-domain-rules
description: Canonical business rules for this hardware-shop POS system — stock deduction, profit/loss calculation, low-stock thresholds, staff permissions, and offline-sync conflict handling. ALWAYS use this skill whenever writing or modifying code that touches sales/checkout, inventory, stock levels, pricing, profit calculations, staff roles, or offline data sync — even if the user's request doesn't explicitly mention "business rules." Treat this as the single source of truth over ad-hoc assumptions.
---

# POS Domain Rules — Hardware Shop

This skill defines the non-negotiable business logic for this project. If any generated code contradicts these rules, the rules win — flag the conflict to the user rather than silently picking one.

## 1. Product / Stock Model

Every product record must store, at minimum:
- `id`, `name`, `sku` (barcode or internal code), `category`
- `cost_price` (what the shop paid) — **required**, not optional, because profit/loss depends on it
- `selling_price` (what the customer pays)
- `quantity_on_hand`
- `low_stock_threshold` (default 5 if the client hasn't specified one per product)
- `unit` (e.g., piece, kg, meter, box) — hardware shops often sell by non-piece units (nails by kg, wire by meter, paint by liter)

**Rule:** Never allow a sale to be recorded without a `cost_price` set on the product. If a product is added without one, prompt for it or default it to `selling_price` with a visible flag (`cost_price_estimated: true`) so profit reports can be filtered/caveated later.

## 2. Sale / Checkout Flow

1. A sale is a list of line items: `{product_id, quantity, unit_price_at_sale, unit_cost_at_sale}`.
2. **Always snapshot `unit_price_at_sale` and `unit_cost_at_sale` on the line item at the moment of sale.** Do not compute profit later by re-joining against the current product price — prices change over time and historical reports must reflect what was true at the time of that sale.
3. On sale completion:
   - Decrement `quantity_on_hand` by the sold quantity, immediately and atomically.
   - If the resulting `quantity_on_hand` is negative, do not silently allow it — this indicates a stock discrepancy. Either block the sale (configurable) or allow with a visible "oversold" warning, per client preference (default: warn, don't block, since hardware shops often sell items not yet logged as restocked).
   - If `quantity_on_hand` falls at or below `low_stock_threshold`, flag the product for the low-stock report/alert.
4. Every sale record needs a timestamp, the staff member who processed it, and the payment method (cash / M-Pesa / card / credit).

## 3. Profit & Loss Calculation

```
line_profit = (unit_price_at_sale - unit_cost_at_sale) * quantity
period_profit = sum(line_profit for all sales in period) - sum(recorded expenses in period)
```

- Expenses (rent, transport, wages, etc.) are a separate ledger the client can log manually — don't assume automatic bank/mobile-money feeds unless the client explicitly requests and provides access to that integration.
- Credit sales ("khata") count toward revenue and profit at the time of sale, not at the time the customer eventually pays — but must be tracked separately as "outstanding" so the owner can see unpaid credit at any time. Do not conflate "profit" with "cash actually collected."

## 4. Staff Roles & Permissions

Two roles by default, unless the client specifies more:
- **Owner/Admin**: sees everything — cost prices, profit margins, reports, can add/edit/delete products and staff.
- **Cashier**: can process sales, view stock quantity (not cost price), cannot see profit/margin figures, cannot delete products or edit prices.

Always gate cost_price and profit fields behind the Admin role check at the data-access layer, not just by hiding UI elements — a cashier should not be able to retrieve this data even by inspecting API responses.

## 5. Offline-First Sync Rules

The Android billing app must function fully offline (add sale, view stock, print receipt) and sync when connectivity returns.

- Every locally created sale gets a client-generated UUID at creation time, not a server-assigned ID — this avoids ID collisions when multiple offline devices sync later.
- Stock decrements happen locally immediately (optimistic), then reconcile with the server on sync.
- **Conflict rule for stock quantity:** if two devices sell the same product offline and both decrement locally, on sync the server applies both decrements (sum them) rather than picking one and discarding the other — lost sales are worse than a temporarily negative stock count, which then surfaces as a discrepancy for the owner to review.
- Never silently drop a sale record due to a sync conflict. If a conflict can't be auto-resolved, surface it in an "Needs Review" queue rather than discarding data.

## 6. Reporting Period Definitions

- "Daily" = calendar day in the shop's local timezone (not UTC) — set this explicitly, don't rely on server default timezone.
- "Weekly" = Monday–Sunday unless the client specifies otherwise.
- "Monthly" = calendar month.
- Reports must be able to filter by staff member (to see which cashier processed what) and by category (useful for a hardware shop with distinct departments like plumbing/electrical/tools).
