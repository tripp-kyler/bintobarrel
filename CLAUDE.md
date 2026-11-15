# Working in this repo

## Branches and pull requests
- Name branches in plain, human-readable words that say what the change does, in kebab-case:
  `add-barrel-topping-report`, `fix-bin-tag-printing`. No ticket numbers, initials, dates or random suffixes.
- Write PR titles as a short plain-English sentence: "Add a barrel topping report", "Fix bin tags printing off the page".

## Layout
- `public/` is what DigitalOcean serves. `public/index.html` is generated: edit `src/bin-to-bottle.html`,
  then run `python3 build_index.py src/bin-to-bottle.html`.
- `public/config.js` holds only the Supabase URL and publishable key. Never commit a secret key.
- Database changes go in `supabase/schema.sql` (keep it safe to re-run) and are applied to the
  Supabase project `bintobarrel` (ref `gszlsbpikbsvdwbdomtv`).
- Edge functions `members` and `read-po` are deployed with JWT verification off; each checks the
  signed-in user in its own code.
