# WorkTrack — Deployable Web App

A multi-user business ledger app with a **User Panel** (customers, work
orders, payments, expenses, reports) and a separate **Admin Panel**
(manage every user/business on the platform), backed by Supabase.

## Files

| File | Purpose |
|---|---|
| `supabase-schema.sql` | Database tables, roles, and security rules — run once in Supabase |
| `config.js` | Your Supabase project URL + anon key |
| `supabaseClient.js` | Shared Supabase client + auth/session helpers |
| `styles.css` | Shared stylesheet used by all pages |
| `index.html` | Login / signup page — routes users to the right panel |
| `user.html` | User panel — the ledger app (per-business data) |
| `admin.html` | Admin panel — manage all users/businesses |

## 1. Set up Supabase (5 minutes)

1. Create a free project at [supabase.com](https://supabase.com).
2. Go to **SQL Editor → New query**, paste the entire contents of
   `supabase-schema.sql`, and click **Run**. This creates all tables,
   the `is_admin()` helper, the auto-profile trigger, and Row Level
   Security policies (every user can only see their own data; admins
   can see everyone's).
3. Go to **Project Settings → API** and copy:
   - **Project URL**
   - **anon public** key
4. Paste both into `config.js`:
   ```js
   export const SUPABASE_URL = "https://xxxxx.supabase.co";
   export const SUPABASE_ANON_KEY = "eyJ....";
   ```
5. (Recommended) In **Authentication → Providers → Email**, you can
   turn off "Confirm email" while testing so new signups can log in
   immediately — turn it back on before going live.

## 2. Create your first admin

By default **every new signup is a regular user** (their own
business's user panel only). To make an account an admin:

1. Sign up normally through `index.html` (as yourself).
2. In Supabase, go to **SQL Editor** and run:
   ```sql
   update public.profiles set role = 'admin' where email = 'you@example.com';
   ```
3. Log out and log back in — you'll land on `admin.html`.

From then on, admins can promote/demote other users straight from the
Admin Panel's **Users** tab — no SQL needed.

## 3. Deploy (static hosting — no build step needed)

This app is plain HTML/CSS/JS (ES modules), so any static host works.

**Netlify / Vercel (drag & drop):**
1. Zip or drag the whole `worktrack-app` folder onto
   [app.netlify.com/drop](https://app.netlify.com/drop) (or `vercel deploy` from this folder).
2. Done — you'll get a live URL immediately.

**GitHub Pages:**
1. Push this folder to a GitHub repo.
2. Repo → Settings → Pages → Deploy from branch → `/` (root).

**Any other static host** (S3, Cloudflare Pages, Firebase Hosting,
your own server): just upload these files as-is — `index.html` is the
entry point.

> ⚠️ Supabase's **anon key** is safe to expose in frontend code — it's
> designed for this. Actual data protection comes from the Row Level
> Security policies in `supabase-schema.sql`, not from hiding the key.

## How it works

- **Auth**: real Supabase Auth (email + password), not local/demo auth.
- **Data isolation**: every table has a `user_id` column and an RLS
  policy `user_id = auth.uid() OR is_admin()` — regular users can only
  ever read/write their own rows; admins can read/write everyone's.
- **Roles**: stored in `public.profiles.role` (`'user'` or `'admin'`).
  `index.html` checks this after login and redirects to `user.html`
  or `admin.html` accordingly. Each panel also re-checks the role on
  load and bounces you to the correct one if you land on the wrong URL.
- **Suspension**: admins can suspend a user from the Admin Panel; a
  suspended user is signed out immediately on their next login attempt.

## Customizing

- Branding/colors: edit the `:root` CSS variables at the top of `styles.css`.
- Work order statuses, priorities, expense categories: edit the arrays
  inside the relevant `open...Modal()` functions in `user.html`.
- Currency: the `inr()` helper formats amounts as ₹ — change the
  symbol/locale there if needed.
