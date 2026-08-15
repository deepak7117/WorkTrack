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

## 2. Deploy the Edge Function (needed for delete-user and set-password)

Deleting a user or forcibly setting their password requires Supabase's
privileged Admin API, which needs the `service_role` key. That key must
never be shipped to the browser, so it lives in a small server-side
function instead (`supabase/functions/admin-actions`).

1. Install the Supabase CLI: `npm install -g supabase`
2. From this folder, log in and link your project:
   ```bash
   supabase login
   supabase link --project-ref YOUR-PROJECT-REF
   ```
   (find your project ref in the Supabase dashboard URL, or under Project Settings → General)
3. Deploy the function:
   ```bash
   supabase functions deploy admin-actions
   ```

That's it — `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected
automatically by Supabase into every Edge Function, so there's no key to
copy or paste. Everything else in the admin panel (suspend, promote,
edit info, send reset email) works with just the anon key and doesn't
need this function.

## 3. Create your first admin

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

## 4. Deploy the frontend (static hosting — no build step needed)

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

## Already have the app deployed and just want the new admin features?

Run `supabase-admin-upgrade.sql` in the SQL Editor instead of the full
`supabase-schema.sql` — it only adds what's new (audit log table,
`last_sign_in_at`, `admin_notes`) without touching your existing data.
Then deploy the Edge Function as in step 2, and re-upload the updated
`admin.html`, `index.html`, and `styles.css`.

## What the Admin Panel can do

- **View every business** — customers, work orders, revenue, and
  expenses across all users, plus a platform-wide overview.
- **Edit any user's info** — name, business name, mobile, email, and a
  private admin-notes field only admins can see.
- **Suspend / reactivate** accounts — a suspended user is signed out
  immediately and blocked from logging back in until reactivated.
- **Promote / demote admins** — grant or revoke admin access for any
  user (except themselves, to prevent accidental lockout).
- **Reset a user's password** two ways: send them a normal password
  reset email, or set a temporary password directly for support
  situations — never by viewing their actual password, which isn't
  technically possible (see below).
- **Email a user** — opens a pre-addressed message in the admin's own
  email client. For automated, server-sent email (e.g. on signup or
  suspension) you'd add an Edge Function using a provider like Resend
  or SendGrid — not included here since it needs your own API key.
- **Delete a user permanently** — removes their login and cascades to
  all their business data. Requires typing "DELETE" to confirm, and
  can't be undone.
- **Audit log** — every admin action (who did what, to whom, when) is
  recorded and viewable in its own tab, for accountability.

**On viewing passwords:** this is intentionally not possible anywhere.
Supabase stores passwords as one-way hashes — even Supabase itself
can't recover the plaintext. This isn't a limitation of this app
specifically; it's how secure authentication works everywhere. The
legitimate admin equivalent is resetting or setting a new password,
both of which are built in.

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
- **Privileged actions** (delete user, set password): handled by the
  `admin-actions` Edge Function, which independently re-verifies the
  caller is an admin server-side before touching anything — the
  browser can't forge this even if someone tampers with the frontend
  code.

## Customizing

- Branding/colors: edit the `:root` CSS variables at the top of `styles.css`.
- Work order statuses, priorities, expense categories: edit the arrays
  inside the relevant `open...Modal()` functions in `user.html`.
- Currency: the `inr()` helper formats amounts as ₹ — change the
  symbol/locale there if needed.
