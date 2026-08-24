# Scanning a codebase for what it actually does with personal data

Goal: don't guess what the product collects — find it in the code, so the policy describes reality. A privacy policy that lists things the app doesn't do (or, worse, omits things it does do) is worse than no policy: it's a false statement to users and to the Data Protection Commission.

## 1. Find the dependency manifest and grep for known providers

Read `package.json` (or `requirements.txt`, `Gemfile`, `composer.json`, `pubspec.yaml`) and grep the source tree for these signal categories. Note each hit with the file path — you'll cite it when asking the user to confirm.

| Category | What to grep for | What it means for the policy |
|---|---|---|
| Auth | `supabase`, `firebase/auth`, `next-auth`, `auth0`, `clerk`, `@react-oauth/google`, `passport` | Which identity fields come from the provider (name, email, avatar) vs. the app's own signup form |
| Database / storage | `supabase`, `postgres`, `mongodb`, `prisma`, `mysql2`, `firestore` | Where records live; check `supabase/migrations` or `prisma/schema.prisma` for column names that are personal data (email, phone, address, dob, national id) |
| Payments | `paystack`, `flutterwave`, `stripe`, `hubtel` | Payments are handled by the processor, not stored by the app — say so; note the app never sees full card/MoMo numbers |
| Analytics / product usage | `posthog`, `google-analytics`, `gtag`, `mixpanel`, `amplitude`, `segment` | Usage tracking, whether it's opt-in/opt-out, whether it's masked (check for `mask`, `exclude`, `sanitize` near the analytics init) |
| Advertising pixels | `fbevents`, `meta-pixel`, `tiktok-pixel`, `gclid`, `fbclid` | Needs a cookie policy and, per the Act's consent-based lawful basis (s20), should be opt-in, not silently on |
| Error/performance monitoring | `sentry`, `bugsnag`, `logrocket` | Diagnostic data, may include IP address, device info, and (if not scrubbed) request payloads |
| Email/SMS | `resend`, `sendgrid`, `nodemailer`, `twilio`, `africas talking`, `hubtel sms` | Transactional vs. marketing sends — marketing needs the s40 written-consent rule |
| Push notifications | `firebase/messaging`, `onesignal`, `expo-notifications` | Device tokens are personal data |
| File/image storage | `supabase storage`, `cloudinary`, `s3`, `uploadthing` | Uploaded content (profile photos, ID scans) — check if any upload flow accepts ID documents (Ghana Card, passport) |
| Location | `navigator.geolocation`, `expo-location`, `react-native-geolocation` | Precise location is sensitive even though it isn't listed as "special personal data" in Act 843 — call it out |
| Cookies / local storage | `cookie`, `js-cookie`, `localStorage`, `next/headers` `cookies()` | Session cookies (essential) vs. preference/analytics cookies (need consent UI) |
| Server region | `vercel.json`, deployment config, Supabase project region, AWS region env vars | Whether data is stored/processed outside Ghana |

## 2. Read the actual forms and schema, not just the libraries

- Grep signup/checkout/profile forms for `name=`, form field labels, and Zod/Yup schemas — this is the real list of "information we collect," more accurate than guessing from the product description.
- Check the database schema/migrations for columns holding personal data: names, emails, phone numbers, addresses, date of birth, national ID or Ghana Card numbers, biometric fields, health fields. Any of these last few make the product a processor of **special personal data** under s37 — flag this prominently, it changes what the policy must say.
- Check for a "delete account" or "delete my data" feature (route, button, or admin action). If one exists, the retention section can promise self-service deletion; if not, say so honestly and give the request-by-email path instead.
- Check for an account-free / guest flow (cart or preferences stored only in `localStorage`). If one exists, state it plainly, e.g. "we don't require an account to shop; your cart and wishlist are stored in your own browser, not on our servers." This is a genuine privacy positive worth calling out when it's true.
- Check whether under-18 users are addressed anywhere (age gate, parental consent flow, school/education context). If the product is plainly for adults only, say so; if it can be used by minors, this triggers the special-personal-data rule in s37(1)(a) — see the Act reference doc.

## 3. Ask the user for what code can't tell you

Code shows *mechanism*, not *policy*. Always confirm with the user before publishing:

- Legal entity name, business address, and contact email/phone for the notices the Act requires (s23, s27(2)).
- Whether the business is registered with the Data Protection Commission, and the registration number if so (see act-843-reference.md's Registration section — never invent this).
- Whether any of the third parties found in the scan have a signed data-processing agreement (s30(2) requires one in writing).
- Governing law / dispute venue for the Terms of Service, and any Ghana-specific consumer or e-commerce rules relevant to the business (e.g. returns/refunds for a store).

## 4. Match the project's existing publishing convention

Before writing new content, check how the project already ships legal pages:

- A framework page component (e.g. a `privacy/page.tsx` route) with sections as data plus JSX — update the sections array/content in place, keep the existing visual design, just fix the copy.
- Markdown/rich-text content pulled from a database or CMS, often with a hardcoded fallback string for when the CMS row is missing — update both the CMS-seeding migration/script and the fallback string so they stay in sync.
- No existing page at all — ask the user where it should live before creating new files.

Reuse whatever heading/section style the project already has rather than imposing a different structure.
