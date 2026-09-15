# Optional account sync

ThaiTalk works offline without Supabase. To enable accounts:

1. Create a Supabase project and enable email/password authentication.
2. Apply `migrations/202609150001_learning_progress.sql` in the SQL editor.
3. Build with `--dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co`
   and `--dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_ANON_KEY`.
4. Enable email confirmation for production. The signup screen asks users to
   confirm their email before signing in when this is enabled.

Use the public anon key in the app; never embed a service-role key. Row-level
policies isolate each user's learning progress. The SQL function also runs under
the caller's permissions and uses revision checks to prevent lost concurrent
updates. Auth credentials are managed by the Supabase Flutter SDK.

The app stores progress locally first, then automatically syncs while signed in.
Saved/unsaved state and review schedules use the newest per-item timestamp. Best
scores and learned items merge monotonically. Per-device daily activity counters
merge by maximum so repeat synchronization does not award additional XP.
Guest and account snapshots are stored separately on the device.

Reference: [Supabase Flutter authentication](https://supabase.com/docs/reference/dart/auth-signinwithpassword)
and [row-level security](https://supabase.com/docs/guides/database/postgres/row-level-security).
