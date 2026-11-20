# Waterproofing Status Dashboard

Live dashboard for waterproofing progress — Towers 1–6, Club Area, WTP and STP.
It reads the site tracking Google Sheet directly, so **any change in the sheet shows up on the dashboard automatically** (every 60 seconds, or instantly with **↻ Refresh now**).

Data source: https://docs.google.com/spreadsheets/d/1MoE-MyuIGQ1BhWFnFTwjcWhcwcglkjkK4BR9wx3oBOo/edit

## Run on localhost (Windows)

1. Double-click **`start-dashboard.bat`**
2. The browser opens at **http://localhost:9375** (keep the black window open; close it to stop)

No installs needed — it uses Windows PowerShell. Alternatives if you prefer:

```
python -m http.server 9375        # then open http://localhost:9375
npx serve -l 9375 .               # Node.js
```

## What the dashboard shows

- **KPIs** — overall % of steps done, areas complete / in progress / not started, flats fully complete, remarks count
- **Stage-wise completion** — Cleaning → Repair → Gola → Primer → 1st/2nd Coat → Testing → Plaster → Khudda Testing → PCC
- **Progress by block** (click a tower to drill in) and **by area type** (toilets, kitchen, balconies, shafts, jacuzzi)
- **Floor-wise heatmap** — all towers by floor, or one tower by flat; click any cell for the full area × stage checklist
- **Remarks & hold-ups** — the REMARKS column plus any text typed in a stage cell (e.g. "wip", "pending due to scaffolding")
- **Report view** (button at the top) — pick Tower → Floor → Flat → Area (+ status) to get a report for exactly that selection; **Print / PDF** or **Excel** download. The report link in the address bar can be bookmarked or shared.
- **Area-wise detail table** — search and filter by status, floor and area type

## How the sheet is read

| In the sheet | On the dashboard |
|---|---|
| ☑ TRUE | ✓ Done |
| ☐ FALSE / blank | · Pending |
| `wip`, a date (e.g. `25-Oct`) or other text | ◐ In progress (text shown as a note) |
| text containing "pending" / "hold" / "due to" | · Pending (text shown as a note) |

- New towers/tabs, floors, flats, areas and stage columns are picked up automatically — keep the same layout (a header row with `FLOOR`, `FLAT`, `Areas`, stage columns, then `REMARKS`).
- The sheet must stay shared as **Anyone with the link → Viewer**.
- If the sheet can't be reached (no internet), the page shows the saved snapshot in `snapshot.js` with a yellow notice and keeps retrying.

## Files

| File | Purpose |
|---|---|
| `index.html` | The dashboard (single file — all logic inside) |
| `snapshot.js` | Offline fallback copy of the sheet (19 Nov 2026) |
| `server.ps1` / `start-dashboard.bat` | Local server for http://localhost:9375 |

## Host it online (optional, free)

GitHub → this repo → **Settings → Pages** → Source: *Deploy from a branch* → Branch: `main` / root → Save.
In a minute it's live at `https://veer670.github.io/water-proofing/` and still auto-updates from the sheet.

## Login and users

Start the dashboard with **start-dashboard.bat** (or the PowerShell command), then sign in.

- First login: **User ID `admin`**, **password `Homeland@2026`**. Change it straight away (sidebar -> *Change password*).
- **Users** page (admins only): *Add user* -> User ID, name, password, and access:
  - **Admin - edit access**: sees everything and can create, edit and delete users.
  - **Viewer - view only**: sees Dashboard and Remaining Work only.
- Users are saved in `users.json` in this folder (passwords only as salted hashes). `secret.key` signs the login sessions. Do not share these two files; deleting `users.json` resets to the default admin.
- If the page is opened without the server (double-clicking index.html), only the built-in admin login works and the Users page is disabled.
