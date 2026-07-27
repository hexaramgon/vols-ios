# Age Policy — 13+ (decision record)

**Status: Volspire is 13+.** Decided July 25, 2026, to match the App Store age rating Apple's questionnaire computed (13+ in 171 countries; 16+ in 2, A16 Brazil, 15+ Korea as regional overlays; legacy 12+ shown to pre-iOS-26 devices). No manual override was set in App Store Connect — the computed rating is the intended one.

This doc covers **both repos** (iOS `banana` + web `volspire-ui-v2`). If the policy ever changes, every touchpoint below changes together.

## Where the age language lives

| Surface | Location | Wording |
|---|---|---|
| iOS Terms §2 + Privacy §2 | `VolspireCore/Screens/Settings/SettingsInfoScreens.swift` | 13 minimum; under-13 banned outright; 13–17 need parent/guardian consent-and-involvement |
| Web Terms §2 + Privacy §2 | `app/(marketing)/terms/page.tsx`, `app/(marketing)/privacy/page.tsx` | identical copy |
| iOS signup checkbox | `RegisterScreen.termsString` | "I'm 13 or older and agree to Volspire's Terms of Service" |
| Web signup checkboxes | `components/authentication/register.tsx` (step 2 — gates both email and OAuth paths) | same two checkboxes as iOS |
| Acceptance record | `create_user` RPC stamps `users.terms_accepted_at = now()` | both clients gate signup on the checkboxes first |
| App Store Connect | Age Ratings | computed 13+, no override |

## The tradeoff: 13+ vs 18+

### Why 13 is the line at all
US federal children's-privacy law (COPPA) applies only **under 13**. At 13+ there are no COPPA obligations as long as under-13s are excluded and we never gain "actual knowledge" of one (if we do: terminate + delete, exactly as Privacy §2 promises). This is why the entire social internet (Instagram, TikTok, BandLab) standardized on 13.

### What 13+ buys us
- **The teen-producer audience** — a core slice of beat culture (the FL Studio / BandLab demographic). An 18+ rating blocks under-18 Apple accounts from even downloading the app.
- **Consistency with the computed rating** — Apple's own questionnaire produced 13+ from our answers (UGC + messaging set a 13+ floor). No override fight, no metadata mismatch.
- **Discoverability** — 18+ apps are excluded from some App Store featuring surfaces and placements.

### What 13+ costs us
- **Minor contract capacity.** Minors can't reliably form binding contracts, so Terms §2 carries the standard parental consent-and-involvement representation. Industry-standard, not bulletproof.
- **State teen-social-media laws** (Texas, Utah, Florida, etc.) impose parental-consent and design duties on paper. Mitigations: most target large platforms or are enjoined in the NetChoice litigation, and the newer **app-store accountability laws push age verification and parental consent onto Apple**, which shares age signals with developers. Our job is to keep the rating questionnaire honest and adopt Apple's age-range signals if/when required.
- **UK/EU paper exposure** (we ship to 171 storefronts): once minors are officially welcome, regimes like the UK's children's design code apply to us in principle. Enforcement targets platforms orders of magnitude larger, but it is the posture we've accepted.
- **A moderation bar we can't let slip.** Stranger DMs are what forced Discord from 12+ to 17+. Our mitigations already exist (built for App Store Guideline 1.2): report on every surface, block, 24-hour review, zero-tolerance terms language. **These must not regress while we're 13+.**

### What 18+ would have bought (the road not taken)
- Near-zero teen-regulation surface, with the "we don't serve minors" line enforced *by the store itself* (under-18 Apple accounts can't download 18+ apps).
- The simplest liability posture for a solo unincorporated operator (pre-LLC).
- Costs: loses the teen audience entirely, reduced featuring eligibility, and the docs/signup rewrites — 18+ was the original posture precisely because it was the low-liability default.

## If we ever flip back to 18+
1. App Store Connect → Age Ratings → Edit → declare an 18+ minimum (override upward; regional badges map automatically).
2. Terms §2 + Privacy §2 in **both** repos → restore the 18-or-older representation and "we don't knowingly collect from under-18s" wording.
3. iOS `RegisterScreen.termsString` and web `register.tsx` checkbox labels → "I'm 18 or older…".
4. Google Play rating equivalent when the Android port ships (see `ANDROID_PORT_PLAN.md`).

## Revisit triggers
- **Marketplace/monetization launch** — payments + minors adds real obligations (and Stripe's own age terms); revisit before flipping `FEATURES.marketplace` on.
- Any regulator/App Review inquiry touching minors.
- Apple questionnaire changes that recompute the rating.
- LLC formation — a bigger compliance appetite may change the calculus in either direction.
