---
name: ghana-data-protection-policies
description: Use when writing or updating a privacy policy, terms of service, or cookie policy for a Ghana-based product or a product processing data from Ghana, when the user asks for one to "comply with the Data Protection Act" or "Act 843," or when reviewing/auditing an existing privacy policy for gaps against Ghanaian data protection law.
---

# Ghana data protection policies

## Overview

Writes a privacy policy, terms of service, and/or cookie policy that reflects what a specific codebase actually does with personal data, and that complies with Ghana's Data Protection Act, 2012 (Act 843). The output is only as good as the scan behind it: read the code before drafting a single sentence.

**REQUIRED READING before drafting:** `reference/act-843-reference.md` (what the law actually requires, distilled and section-cited) and `reference/style-guide.md` (plain English, structure, and the no-em-dash rule). Load `reference/codebase-scan-guide.md` before starting the scan step below.

## The rule that matters most

**Never state a fact you didn't confirm.** A DPC registration number, a security measure, a data-sharing partner, a retention period: if the codebase scan didn't show it and the user didn't confirm it, don't put it in the document. A privacy policy is a legal representation to users and to the Data Protection Commission. A plausible-sounding invented detail is worse than an honest gap flagged to the user. If something is unconfirmed, write `[confirm: ...]` in your draft output to the user rather than guessing, and ask before it goes into a published file.

## Workflow

1. **Scan the codebase.** Follow `reference/codebase-scan-guide.md`: dependency manifest, forms, database schema, existing legal pages, deployment region. Build a concrete list of data categories, purposes, and third parties, each tied to a file you read.
2. **Check what's unconfirmed.** Legal entity name and address, contact email, DPC registration status, whether third-party processors have written agreements, governing law/venue for the ToS. Ask the user directly (AskUserQuestion or a plain question) rather than guessing or leaving generic placeholders in the final output.
3. **Map findings to the Act.** For each data category and use, note which principle or right in `reference/act-843-reference.md` it touches: lawful basis (s20), special personal data (s37, including that a child under parental control is special personal data, not just "under 13"), retention (s24), security and breach notification (s28, s31), direct marketing consent (s40), rights (s32–s44). If the product processes special personal data or is used by minors, say so explicitly to the user before drafting, since it changes what the policy must promise.
4. **Match the project's existing convention.** Look for an existing privacy/terms page or CMS-backed legal content and reuse its format and location (see the end of the scan guide). If none exists, ask the user where it should live before creating files.
5. **Draft using the templates in `templates/`** as a starting skeleton, replacing every bracketed placeholder with a confirmed fact, deleting sections that don't apply, and writing in the style from `reference/style-guide.md`. Only draft a cookie policy if the scan actually found cookies, local storage tracking, or analytics/ad pixels; only draft terms of service sections like payments/refunds if the product actually has them.
6. **Check for em dashes and en dashes** (`—`, `–`, `--`) in your draft and rewrite every instance before presenting it. This is a hard rule, not a preference.
7. **Report gaps, not just the document.** Tell the user what you found that's a compliance gap (no DPC registration, no written processor agreement, no consent UI for analytics, a "children" clause that understates Act 843's protection) separately from the drafted text, so they can decide what to fix versus what to accept as a known risk.

## Common mistakes

| Mistake | Fix |
|---|---|
| Copy-pasting a generic/GDPR privacy policy template | Ground every claim in the actual codebase scan; Act 843 has different rights, timelines (40-day access response, not 30), and definitions than GDPR |
| Listing "under 13" as the children's-data cutoff without comment | Act 843 treats any child under parental control as special personal data; flag the gap, see act-843-reference.md |
| Inventing a DPC registration number or exact security stack | Ask the user; write `[confirm: ...]` until they answer |
| Using an em dash for asides or ranges | Rewrite with a comma, period, or spelled-out range; grep your own draft for `—`/`–` before finishing |
| Writing one document type when the user needs three | Ask whether they want privacy policy only, or also terms of service and a cookie policy, based on what the scan found (e.g. ad pixels present → cookie policy is needed even if not asked for) |
| Overwriting an existing page's visual design to insert new copy | Keep the project's existing component/CMS structure; change only the content |
