# Plain-English style rules for these documents

These documents are read by ordinary users, not lawyers. Every rule below exists to keep them that way.

## The no em dash rule

Never use an em dash (—) or en dash (–) anywhere in the output. Not for asides, not for ranges, not for list items. Rewrite instead:

- Aside: use a comma, a period and a new sentence, or parentheses. "Payments are processed by Paystack, and we never see your full card number." not "Payments are processed by Paystack — we never see your full card number."
- Range: spell it out. "12 to 24 months" not "12–24 months."
- List lead-in: use a colon, not a dash.

Before finishing, search your own draft for `—`, `–`, and `--` and rewrite every hit. This is a hard rule, not a style preference to weigh against other goals.

## Plain English rules

- Short sentences. If a sentence needs a semicolon to hold together, split it into two.
- Active voice: "We collect your email address," not "Your email address is collected by us."
- Say "you" and "we," not "the user" and "the Company," except in the defined-terms section of a Terms of Service where a formal party name is genuinely needed.
- Name the actual thing. "Paystack" and "Supabase," not "our payment partners" and "our infrastructure providers," unless the list is long enough that naming every vendor would bury the point (then name the categories and list vendors once, in one place).
- One idea per sentence. Don't stack three clauses about three different topics into one sentence because they're all "data" related.
- Avoid Latin and legalese where an English word works: "for example" not "e.g.," "that is" not "i.e.," "before" not "prior to," "use" not "utilize."
- Define a term only if it's used more than once and isn't obvious from context (e.g., "personal data" if the policy leans on it repeatedly). Don't build a wall-of-definitions section just because that's a common template habit.

## Structure to aim for

MTN Ghana's public privacy policy (the largest, most established privacy notice in the Ghanaian market) uses this shape. Use it as the default, and adapt section names to what the product actually does:

1. **Who we are / what this covers** — one short paragraph.
2. **Information we collect** — grouped by source (account/signup, usage, payment, support, optional/analytics), each with a one-line reason.
3. **How we use it** — a short bullet list, one line each.
4. **Legal basis / is this allowed** — tie each use back to a ground under s20 of Act 843 (contract, consent, legitimate interest, legal duty). Skip this as a separate section for a small consumer product if it would just repeat "how we use it" in legal language; fold it into that section as a phrase instead ("...to run your order, which we need to do to fulfil the contract you make with us at checkout").
5. **Where your data is stored / who we share it with** — name the vendors, say if any are outside Ghana, say plainly "we do not sell your personal data."
6. **How long we keep it** — tie to the account lifecycle or a stated period; mention deletion.
7. **Your rights** — access, correction, objection, withdrawing consent, stopping direct marketing, and how to reach the business to exercise them; mention the right to complain to the Data Protection Commission.
8. **Children** — state the real policy; see the Act reference doc for why "under 13" alone may understate Act 843's rule.
9. **Security** — one paragraph on the real measures in place (encryption in transit, access control, provider security) grounded in what the codebase scan found, not boilerplate.
10. **Changes to this policy** — how updates are communicated.
11. **Contact us** — email, and DPC registration number if the user confirms one exists.

For a Terms of Service, adapt to: who can use the service, account responsibilities, acceptable use, payment/refunds (if commerce), intellectual property, service availability/liability limits, termination, governing law, and how to contact the business. For a Cookie Policy: what cookies/local storage are used, which are essential vs. optional, how to control them (link to an in-app preferences control if the scan found one), and third-party cookies from ad/analytics pixels.

## Formatting

Match the target file's format:

- If updating a `.tsx`/`.jsx` page, keep using the project's existing components and Tailwind classes; only change the copy inside the sections data structure.
- If updating markdown or a CMS fallback string, use `**bold**` for sub-headings and `-` for bullets (a hyphen, not an em dash), matching whatever fallback-content pattern the project already uses.
- Keep a "Last updated" date at the top, and update it whenever the content changes materially.
