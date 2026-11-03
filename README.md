# Spin the Wheel — Employee Event Game

## Shared Supabase project configuration (November 2026)
Both games use the **same Supabase project** (project ref `jlwgzopkdlsgwcaxvfnn`). Their `config.js` public URL and publishable key are configured. The database **is not installed by simply editing config.js**.

**Run the combined installer once:** open [supabase/install-both-games.sql](https://github.com/vijaysaini7713-web/Spin-the-Wheel/blob/main/supabase/install-both-games.sql), copy its complete contents, then run them in your Supabase project's **SQL Editor**. This provisions shared admin/employee tables, separate settings tables, games, security policies and RPC functions. Do not run separate outdated SQL installers instead.

**Admin setup:** Supabase Dashboard > Authentication > Users > Add user (set email and password). Copy UUID and run `insert into public.admins(user_id) values ('UUID_FROM_AUTH_USERS') on conflict do nothing;`. No default admin password exists. Never share your admin password, database password or service-role key. GitHub Pages must also be enabled separately if you need a public URL.


Responsive static web game with **one spin per Employee ID**, server-side weighted prize selection, and an authenticated admin dashboard.

## Setup
1. Create a Supabase project and run [supabase/schema.sql](supabase/schema.sql) in the SQL Editor.
2. Create an admin in Supabase **Authentication → Users**; add that user's UUID: `insert into public.admins(user_id) values ('YOUR_AUTH_UUID');`
3. Update `config.js` with Supabase project URL and **publishable/anon** key. Never use the service-role key here.
4. Open `index.html` with a static local server, or enable GitHub Pages (Settings → Pages → Deploy from branch → main → root).
5. The admin button allows changing the event title, accepting/closing spins, adding/editing prize names, colors, weights and enabled state, exporting CSV, and resetting a game.

## Security
The database enforces a single spin per normalized Employee ID using a unique primary key and transaction advisory locks. An Employee ID alone is not identity verification: for valuable prizes, validate against HR records or SSO/OTP. Admin sign-in uses Supabase Auth; no hardcoded admin password. Do not expose personal data in a public repository. Reset permanently clears spin history. Test before using with employees.

## Files
- `index.html`: complete UI
- `config.js`: Supabase public client configuration
- `supabase/schema.sql`: PostgreSQL schema, row-level security, and server RPCs.
