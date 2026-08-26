---
name: report-generation
description: Consistent query patterns and structure for all daily/weekly/monthly sales, stock, and profit-loss reports in this POS system. ALWAYS use this skill when writing or modifying any reporting screen, dashboard chart, export function, or database query that aggregates sales/stock/profit data over a time period.
---

# Report Generation Patterns

Use these patterns everywhere reports are built (mobile app and web back-office) so results are consistent between the two, not calculated two different ways.

## 1. Standard Report Types (build these first, in this order of priority)

1. **Daily sales summary** — total revenue, total profit, number of transactions, breakdown by payment method, for a single selected day.
2. **Stock balance report** — current `quantity_on_hand` per product, filterable by category, with low-stock items visually flagged (see `pos-domain-rules` skill for the threshold logic).
3. **Weekly/Monthly sales summary** — same shape as daily, aggregated over the period, plus a day-by-day or week-by-week trend so the owner can see the shape of the period, not just a single total.
4. **Profit & loss** — period revenue, period cost-of-goods-sold, period expenses, net profit. Always show these four numbers together, never profit alone without its components — the owner needs to see *why* a period was profitable or not.
5. **Top/bottom sellers** — ranked by revenue and separately by profit margin (a high-revenue item can be low-margin, and hardware shop owners specifically care about this distinction).

## 2. Query Construction Rules

- Always filter by the **shop's local timezone day boundaries**, not UTC midnight — a sale at 11:50pm local time must count toward that local calendar day, not roll into the next UTC day. Store timestamps in UTC in the database, but convert to local time before bucketing into day/week/month.
- Use the line-item snapshot fields (`unit_price_at_sale`, `unit_cost_at_sale`) defined in `pos-domain-rules` — never re-join against current product prices for historical reports.
- Every report query must support an explicit `start_date`/`end_date` range as the underlying primitive — "daily," "weekly," "monthly" are just presets that compute a default range, not separate query implementations. This avoids duplicating aggregation logic three times.
- Support filtering any report by staff member and by product category as secondary dimensions, not just the top-level time period.

## 3. Performance Considerations

- For shops with a large sale history (thousands+ of transactions), pre-aggregate daily totals into a summary table/collection (`daily_summaries`) updated incrementally on each sale, rather than re-scanning the full sales history on every report view. Compute weekly/monthly views by summing the relevant daily summary rows.
- On the Android app (offline-first), reports shown while offline should be computed from locally cached data and clearly labeled "may not include unsynced data from other devices" if multi-device sync is in use.

## 4. Export Format

- Support exporting any report to Excel/CSV and/or PDF from the web back-office — this is a near-universal ask from small business owners for sharing with accountants or for tax purposes.
- Keep exported column headers identical to the on-screen report labels so the exported file is self-explanatory without extra documentation.
