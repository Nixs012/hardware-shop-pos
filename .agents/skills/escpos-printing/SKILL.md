---
name: escpos-printing
description: How to integrate ESC/POS thermal receipt printers (58mm and 80mm, Bluetooth or USB) into the Android POS app, including the exact receipt layout template for this hardware shop. ALWAYS use this skill when writing or debugging any code related to receipt printing, printer pairing/connection, ESC/POS commands, print formatting, or when the user mentions "printer," "receipt," "Bluetooth print," or "thermal."
---

# ESC/POS Thermal Printer Integration

## 1. What ESC/POS is (context for any new contributor)

ESC/POS is a command language most thermal receipt printers understand, regardless of brand. It's just a stream of bytes: mostly plain text plus special escape sequences for bold, alignment, cut, barcode, etc. You do not need brand-specific SDKs for standard thermal printers — one ESC/POS implementation works across nearly all of them.

## 2. Recommended library (Flutter)

Use `esc_pos_bluetooth` (Bluetooth) paired with `esc_pos_utils` (formatting/rendering) for Flutter. For USB printers, use `esc_pos_printer` or a USB-serial bridge package depending on the target Android device's USB host support.

- Support **both 58mm and 80mm paper widths** — this is a connection setting, not a code branch; the library takes a `PaperSize` enum (`mm58` / `mm80`) and adjusts character-per-line automatically (58mm ≈ 32 chars/line, 80mm ≈ 48 chars/line at default font).
- Pairing flow: scan for Bluetooth devices → let the user select and pair once → persist the printer's MAC address in local settings so it reconnects automatically on every future sale without re-pairing.

## 3. Receipt Template (this shop's default layout)

Structure every receipt in this order — treat this as the default template, adjustable by client for wording only:

```
        [SHOP NAME]              <- bold, centered, large
     [Shop address / phone]      <- centered, normal
   ------------------------------
   Receipt #: 000123
   Date: 26/08/2026  14:32
   Cashier: [Staff Name]
   ------------------------------
   Item              Qty   Total
   ------------------------------
   PVC Pipe 2"         3   450.00
   Cement 50kg          1  750.00
   ------------------------------
   Subtotal:              1,200.00
   Discount:                   0.00
   TOTAL:                 1,200.00
   ------------------------------
   Paid via: Cash / M-Pesa
   ------------------------------
     [Footer message from client
      e.g. "Goods sold are not
      returnable. Thank you!"]
```

- Item names longer than the line width must wrap or truncate cleanly — never let a long product name push the price off the printable area. Truncate to fit, don't crash the print job.
- Always print the total in bold and a larger font than line items so it's the visual focal point.
- Include a paper cut command (`printer.cut()`) at the end of every receipt job so it doesn't need to be torn manually.

## 4. Error Handling (critical for a real shop counter)

A cashier mid-sale cannot tolerate a silent print failure. Handle these explicitly:
- **Printer not connected**: show a clear retry/reconnect prompt immediately, and still record the sale in the database regardless of print success — printing must never block the sale from being saved.
- **Printer out of paper / offline mid-print**: catch the write failure, show an alert, and offer a "Reprint last receipt" button that pulls from the last completed sale record rather than requiring the cashier to reconstruct it.
- **Bluetooth disconnected between sales**: attempt silent auto-reconnect using the persisted MAC address before falling back to prompting the user.

## 5. Testing without a physical printer

When a physical thermal printer isn't available during development, use a Bluetooth printer simulator/emulator app or log the raw ESC/POS byte output to console for visual review of the command structure — don't skip formatting logic just because hardware isn't on hand.
