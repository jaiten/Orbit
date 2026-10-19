# Email confirmation

In Orbit's Supabase project, Authentication → URL Configuration → Redirect URLs
must include `orbit://auth`. Signup and resend requests explicitly use that URL.
The standard Supabase confirmation template can remain unchanged.

Create an account, open the newest confirmation email, follow the confirmation
link, then sign in with the same email/password on each device. Orbit handles the
return link on iOS and packaged Windows. It ignores session tokens in external
links and asks for password sign-in. The portable Windows executable registers
its current path when launched; open the new executable after moving it.

Old emails with localhost redirects retain the old URL. Expired or already-used
links cannot be reused. Use **Settings → Email confirmation → Resend confirmation
email**, then open the newest message. The app also supports entering an email OTP
if a custom template provides one; it does not require OTP templates by default.

New free Supabase projects cannot customize templates while using the default
mailer (policy effective June 3, 2026). Custom SMTP is needed to customize those
templates. Supabase's built-in mailer only sends to organization team addresses
and currently permits two messages per hour; broad tester signup requires custom
SMTP. Do not disable email verification to work around delivery limits.

References:
- https://supabase.com/docs/guides/auth/native-mobile-deep-linking
- https://supabase.com/changelog/46599-changes-to-email-template-customisation-on-free-tier
- https://supabase.com/docs/guides/auth/auth-smtp
