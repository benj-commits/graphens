# Graphen Bags - Supabase setup (about 15 minutes)

## What you copy where

| What | From | To |
| --- | --- | --- |
| Project URL + publishable key | Supabase > Project Settings > API | `config.js` AND `lib/config.dart` |
| `full_setup.sql` (whole file) | this folder | Supabase > SQL Editor > New query > Run |
| One admin SQL line (step 5) | below | Supabase > SQL Editor |

NEVER copy the `service_role` key anywhere. Never share your database password.

## Steps

1. supabase.com > New project. Save the database password in a password manager. Pick the nearest region.
2. SQL Editor > New query > paste ALL of `full_setup.sql` > Run. You should see "Success".
3. Authentication settings:
   - Sign In / Providers > Email: on. Minimum password length: 10.
   - Confirm email: ON for real customers (turn OFF only while testing).
   - URL Configuration: Site URL = your admin website address; add `http://localhost:8080` and your site to Redirect URLs (needed for "Forgot password").
   - Multi-factor: TOTP on (default).
4. Project Settings > API: copy Project URL and publishable key into the two config files.
5. Authentication > Users > Add user > Create new user (your email + strong password, tick Auto Confirm). Then SQL Editor:
   update profiles set role = 'admin' where id = (select id from auth.users where email = 'YOUR_EMAIL');
6. Open the admin website, sign in, go to Settings and turn on two-factor.
7. Run the app (`flutter create .`, `flutter pub get`, `flutter run`), register as a customer.

## Quick test

Add a product with a photo on the website -> it shows in the app. Order it in the app -> it appears in Orders on the website with the real server-calculated total. Change the status -> the customer sees it. Chat both ways. Check Activity on the website.

## If something goes wrong

- "new row violates row-level security": the SQL did not run fully, or the account is not admin (step 5).
- Photos don't show: bucket `media` must exist and be public (created by the SQL).
- Lost your phone with 2FA: SQL Editor: delete from auth.mfa_factors where user_id = (select id from auth.users where email = 'YOUR_EMAIL');
- Reset emails not arriving: Supabase's built-in email is limited to a few per hour. Add SMTP in Authentication > SMTP Settings.
- Emergency lockout of a stolen admin: update profiles set role = 'customer' where id = '...';

