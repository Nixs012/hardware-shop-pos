# Building a Custom POS System for a Hardware Shop
### A complete plan — architecture, features, client requirements, pricing (Kenya), and delivery steps

---

## 1. Is this feasible? Yes.

What you're describing is a **standard small-business POS**, not a technically exotic build. Apps like Zobaze POS, SnapPOS, Simba POS and dozens of others in Kenya are built on the same basic pattern: <cite index="14-1,17-1">a mobile/tablet app for billing and inventory that works offline and syncs to the cloud, with sales reporting, staff management, and thermal printer support</cite>. Zobaze specifically <cite index="1-1">supports offline billing and inventory management even without internet, syncing automatically to the cloud once internet is available</cite>, and <cite index="1-1">supports all ESC/POS thermal and normal printers via USB or Bluetooth, in 80mm, 58mm and A4 sizes, with automatic printing after every bill</cite>. That's your feature benchmark — all of it is buildable by a solo developer or small team in 6–10 weeks for an MVP.

You do **not** need to build something as broad as Zobaze (it serves restaurants, salons, multi-store chains, e-commerce, etc.). You need the **retail/hardware-shop subset**: billing, stock, reports, profit/loss, thermal printing, phone + computer access.

---

## 2. Recommended architecture

To hit "works on Android phone AND computer," you have two realistic paths. Here's the honest trade-off:

| Approach | What it means | Pros | Cons |
|---|---|---|---|
| **A. Web app (PWA) — recommended for you** | One codebase (e.g., React/Next.js or Flutter Web) that runs in a browser on both the phone and computer, installable as an "app" on Android via "Add to Home Screen" | 1 codebase, faster to build, cheaper, easy to update, works on any device with a browser | Bluetooth thermal printing from a browser is more limited (works, but needs specific setup — Web Bluetooth API or a small companion print-bridge); true offline needs careful engineering (service workers) |
| **B. Native Android app + separate web dashboard** | A real Android app (Flutter or Kotlin) for the till/counter, plus a web back-office (any framework) for the owner to view reports on a computer — this is exactly what Zobaze itself does | Best offline support, most reliable Bluetooth/USB thermal printing, feels like a "real" POS at the counter | Two codebases to maintain (app + web dashboard), slightly longer build time |

**My recommendation: Option B**, because it mirrors Zobaze's own model — <cite index="11-1">"Open the Web Back Office on a computer and bulk-import your items from Excel instead of typing each line"</cite> — i.e., the phone is the till, the computer is for reports/management, not for billing. This is also what your client actually needs: fast billing at the counter (phone), reporting/oversight from an office computer (web dashboard). It's more robust for thermal printing and offline reliability, which matter a lot in a hardware shop with unreliable power/internet.

### Suggested tech stack
- **Android app (till/counter):** Flutter (one codebase can *also* export to web/desktop later if you want, but I'd keep it native-Android-first for printer reliability) or Kotlin native.
- **Web back-office (computer):** React or Next.js — simple dashboard for stock, reports, staff.
- **Backend/database:** Firebase (Firestore + Auth + Storage) or Supabase (Postgres). Both give you: real-time sync, offline caching, authentication, and hosting for the back-office — with minimal server management. This is almost certainly what Zobaze and similar apps use under the hood.
- **Thermal printing:** ESC/POS command library over Bluetooth (`esc_pos_bluetooth` for Flutter) or USB — standard, well-documented, works with any 58mm/80mm thermal printer, same as <cite index="9-1">Zobaze's Bluetooth thermal printer setup</cite>.
- **Offline-first sync:** Firestore/Supabase local caching + a sync queue — bills save locally first, then push to cloud when internet returns, exactly like <cite index="5-1">Zobaze's offline-first design that syncs once you are back online</cite>.

---

## 3. Feature-by-feature technical plan

| Client requirement | How it's built |
|---|---|
| **Print receipts via thermal printer** | Pair printer via Bluetooth/USB in app settings once; app sends ESC/POS formatted receipt (shop name, items, totals, date) on every sale. Support 58mm & 80mm paper widths like Zobaze does. |
| **Add stock** | A "Products" module: name, SKU/barcode, category, cost price, selling price, quantity, low-stock threshold. Barcode scanning via phone camera (no extra hardware needed) or a USB/Bluetooth scanner. |
| **Stock balance report** | Real-time view of current quantity per item, with low-stock alerts — pulled live from the database, updates instantly after every sale or restock. |
| **Daily/weekly/monthly reports** | Sales aggregated by date range; simple date-filter screen with totals, top-selling items, and export to Excel/PDF (both easy to add). |
| **Profit/loss** | Requires you to capture **cost price** as well as **selling price** per item (many shop owners only think about selling price — you must get cost price from the client). Profit = Σ(selling price − cost price) per sale, minus recorded expenses, over a period. |

Nice-to-haves worth proposing later (Zobaze includes these, and Kenyan clients often ask for them once they see the basic system): **M-Pesa payment logging**, **customer credit/"khata" tracking** (very common for hardware shops that sell on credit to contractors), **multi-user staff logins with permissions**, **supplier/purchase order tracking**.

---

## 4. What you need from the client — a requirements checklist

Before writing a line of code, get written answers to these. This is also how you scope the price properly.

1. **Business basics:** Shop name, logo, physical address, currency (KES), tax handling (VAT registered? ETR/eTIMS required by KRA?).
2. **Product catalog:** Roughly how many products/SKUs (10 vs 2,000 changes your database design and import approach). Do they have an existing Excel list?
3. **Devices:** How many Android phones/tablets will be used at the counter? How many staff need logins? What computer(s) for the back office?
4. **Thermal printer:** Do they already own one, or do you need to recommend/help them buy one (58mm or 80mm, Bluetooth or USB)? Brand/model matters for testing.
5. **Payment methods to support:** Cash only, or also M-Pesa (Till/Paybill), card, credit/khata?
6. **Staff & permissions:** Will there be multiple cashiers? Does the owner want to restrict what staff can see/edit (e.g., hide cost price and profit from cashiers)?
7. **Internet reliability at the shop:** Confirms how critical offline mode is (usually very critical for Kenyan retail).
8. **Branding for receipts:** Logo, footer message ("Goods sold are not returnable" etc.), shop contact details.
9. **Multiple locations?** One shop now, but planning to open branches later? This affects whether you design for multi-store from day one.
10. **Data migration:** Does the client already track stock somewhere (Excel, notebook, another app) that needs importing?
11. **Budget and timeline expectations**, and who owns the domain/hosting account (see next section — this matters a lot).

I'd suggest presenting this as a short intake form or a 30–45 minute discovery call.

---

## 5. Domain, hosting, and who should own what

This is the part people often get wrong — **get this right for your own protection as a freelancer.**

### What you'll actually need
- **A domain name** (e.g., `yourclientshop.co.ke` or `.com`) — mainly for the web back-office and possibly a simple business landing page. ~$10–15/yr for `.com`, or a `.co.ke` domain via a local registrar (Truehost, Safaricom, Kenya Network Information Centre-accredited registrars) — typically **KSh 999–1,500/year**.
- **Backend hosting**: If you use Firebase/Supabase, the *free tier* comfortably covers a single small shop (a few thousand transactions/month) — so hosting cost can genuinely be **KSh 0/month** at launch, moving to a paid tier (~$25–35/month, roughly KSh 3,500–5,000) only once the business scales (many users, high transaction volume, large storage).
- **Web dashboard hosting**: Vercel/Netlify free tier is enough for the back-office site — again **KSh 0/month** to start.
- **Play Store listing** (if you publish the Android app so staff install it like a real app rather than sideloading an APK): **one-time $25 (~KSh 3,600)** Google Play Developer account fee — this is paid *once*, not yearly, and I'd recommend the client (or you, on their behalf) owns this account.

### Ownership — important
Register the **domain and any Play Store/Firebase accounts in the client's name/email**, not yours. You do the setup, but they own the account and pay the bill directly (or you invoice them for it as a pass-through cost, clearly separate from your dev fee). This protects both of you: if the working relationship ends, they aren't locked out of their own business system, and you're not stuck personally paying for someone else's hosting.

---

## 6. What to charge — Kenyan market pricing

I searched current Kenyan market rates so you can price competitively but fairly for a *custom-built* system (not a reseller of an existing app).

Local providers currently charge: <cite index="21-1">subscription POS apps run from about KSh 1,000–5,000 per month, while a custom system a business owns starts from around KSh 35,000 one-off, with multi-branch and advanced setups ranging from KSh 60,000 to KSh 120,000+ depending on features</cite>. Broader deployments including hardware run <cite index="22-1">from about KSh 40,000 for the simplest full deployment with software, computer, cash drawer and thermal printer</cite>, and the wider market spans <cite index="24-1">roughly KSh 20,000 to KSh 500,000+ depending on functionality and business size</cite>.

### Suggested pricing structure for your client

| Item | Suggested price (KES) | Notes |
|---|---|---|
| **Development fee (one-off, MVP)** | **KSh 45,000 – 80,000** | Covers: Android billing app + web back-office, thermal printing, stock, reports, profit/loss, one round of revisions, basic training. Price toward the top of this range if you're including offline sync, staff permissions, and barcode scanning from day one. |
| **Phase 2 add-ons** (M-Pesa integration, khata/credit tracking, multi-branch) | **KSh 10,000 – 25,000 each**, quoted separately once MVP is live | Don't bundle these into MVP — they inflate timeline and price before the client has even used the core system. |
| **Monthly maintenance/hosting** | **KSh 1,500 – 3,000/month** | This is your fee for bug fixes, minor updates, and monitoring — not the actual server bill (which is often KSh 0 on free tiers early on). Be transparent that this is a support retainer, not a pass-through cost. |
| **Domain renewal** | **KSh 1,000 – 1,500/year**, billed to client directly (pass-through, no markup, or a small 10–20% convenience markup if you manage renewal for them) | |
| **Play Store account** (one-time, if publishing properly) | **KSh 3,600 one-time**, client's account | |

**A note on pricing philosophy:** Since you're new to delivering this and building trust with the client, it's reasonable to price at the lower-middle of the range (~KSh 45,000–55,000) for the first version, explicitly scoped as an MVP, with clear written pricing for anything beyond that scope. Undercutting the market too much (e.g., KSh 15,000) signals low quality and sets a bad precedent for future work with this client.

---

## 7. Step-by-step: from "yes" to delivery

1. **Discovery call + requirements checklist** (Section 4) — get everything in writing. Don't start building on a verbal description.
2. **Written proposal/quote** — scope (exact feature list), price, timeline, payment terms (e.g., 50% upfront, 50% on delivery), and what's *not* included (to avoid scope creep).
3. **Contract/agreement** — even a simple one-page document signed by both parties: scope, price, timeline, ownership of code/accounts, revision limits, support terms after handover.
4. **Client sets up accounts** — domain registrar account, Firebase/Supabase project, Google Play Developer account (or you set these up under their email/ownership, per Section 5).
5. **Design/wireframe** — quick mockups of the billing screen, stock screen, and reports screen for the client to approve before you code (saves rework).
6. **Build MVP** — typically 4–8 weeks for one developer:
   - Week 1–2: Auth, product/stock module, database schema
   - Week 3–4: Billing/checkout flow + thermal printer integration
   - Week 5–6: Reports (daily/weekly/monthly), profit/loss
   - Week 7–8: Web back-office, offline sync, testing, bug fixes
7. **Testing with real data** — import the client's actual product list, test on their actual thermal printer and Android device(s), not just emulators.
8. **Staff training** — a short in-person or video walkthrough for whoever will use it daily at the till.
9. **Handover** — deliver source code (or at least document that you retain it under your agreement), login credentials, and a simple user guide.
10. **Go live + support window** — agree on a defined support period (e.g., 30 days of free bug fixes) before the monthly maintenance retainer kicks in.
11. **Collect feedback after 2–4 weeks of real use** — this is when you'll learn what Phase 2 features (M-Pesa, khata, multi-branch) are actually worth building.

---

### Quick summary
- **Feasible:** yes, this is a well-understood build, not R&D.
- **Best architecture for your case:** native Android app (till) + web dashboard (reports/back-office), backed by Firebase/Supabase.
- **Get a written requirements checklist from the client before quoting.**
- **Register domain/hosting/Play Store accounts in the client's name.**
- **Charge roughly KSh 45,000–80,000 for the MVP**, KSh 1,500–3,000/month for maintenance, and pass through ~KSh 1,000–1,500/year for domain renewal.
- **Deliver in phases** — MVP first, paid add-ons (M-Pesa, credit tracking, multi-branch) after the client has used the core system.
