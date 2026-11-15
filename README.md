# bintobarrel

Winery software for the farm: Bin to Bottle tracks every bin from orchard to press to tank, through
fermentation, barrels and packaging, with custom crush, POs, BOLs, sales orders, work orders and TTB reports.

## What's here

| Path | What it is |
| --- | --- |
| `public/` | The app. DigitalOcean App Platform serves this folder as a static site. |
| `public/config.js` | Supabase project address and publishable key (public by design; no secrets). |
| `supabase/schema.sql` | Database tables, security rules and the private `photos` bucket. Safe to re-run. |
| `supabase/functions/members` | Edge function: owners and admins add crew, change access, reset passwords. |
| `supabase/functions/read-po` | Edge function: reads a photo or scan of a PO with Claude (needs the `ANTHROPIC_API_KEY` secret). |
| `src/bin-to-bottle.html` | The source the app is built from. |
| `build_index.py` | Rebuilds `public/index.html` from `src/bin-to-bottle.html`. |

## Updating the app

Replace `src/bin-to-bottle.html`, run `python3 build_index.py src/bin-to-bottle.html`, and push.
DigitalOcean redeploys automatically when `main` changes.

## How data is stored

Each ciderhouse's records live in one JSON document (`app_state`), saved with a version check.
If two people save at the same moment, the app merges their changes record by record. An hourly
snapshot is kept for 30 days in `app_state_history`. Photos go to the private `photos` bucket,
in a folder per ciderhouse.
