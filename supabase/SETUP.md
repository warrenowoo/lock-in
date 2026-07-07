# Lock-In — Backend setup (Supabase)

This creates the free cloud backend that powers accounts, friends, the leaderboard, and the activity feed. Takes about 5 minutes. No Docker or command line needed.

## 1. Create the project
1. Go to <https://supabase.com> and sign in (use "Continue with GitHub" — you already have GitHub).
2. Click **New project**.
   - **Name:** `lock-in`
   - **Database password:** click *Generate*, then save it somewhere (you rarely need it, but keep it).
   - **Region:** pick the one closest to you.
   - **Plan:** Free.
3. Wait ~2 minutes for it to finish provisioning.

## 2. Create the database tables
1. In the left sidebar, open **SQL Editor** → **New query**.
2. Open the file `schema.sql` (in this folder), copy everything, paste it in.
3. Click **Run**. You should see "Success. No rows returned." That's correct — it built the tables and security rules.

## 3. Give Claude the connection info
Two values, both safe to share (the anon key is designed to be public and is protected by the security rules we just installed):
1. Left sidebar → **Project Settings** (gear) → **API**.
2. Copy these and paste them back to Claude:
   - **Project URL** (looks like `https://abcdefgh.supabase.co`)
   - **anon public** key (a long `eyJ...` string)

That's all I need to wire the app to your backend and start building the friends features. (The *service_role* / secret key — never share that one; we won't need it.)

## 4. Later — Sign in with Apple
Once your Apple Developer account is approved, we'll enable "Sign in with Apple" in Supabase (Authentication → Providers) and connect it to your Apple app. I'll walk you through it then. For now, while building and testing, we can use email sign-in.

---

### What's stored where
- **On the server (Supabase):** your username, your daily summary numbers (so friends can see them), your workout/meal feed items, and friend connections.
- **Still on your device:** the full detail continues to live locally too; the cloud copy is what enables sharing with friends. You approve every friend, and only approved friends can see your data (enforced by the row-level security rules in `schema.sql`).
