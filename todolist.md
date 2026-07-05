# To-Do

## Native Google Sign-In — console setup (code is already done & merged)

The iOS code is fully wired (GoogleSignIn SDK + `signInWithIdToken(.google)` in
`AuthManager`). It won't work until these external steps + the two Info.plist
values are filled in.

- [ ] **Google Cloud Console — create an iOS OAuth client**
  - Same Google project that backs the web sign-in:
    APIs & Services → Credentials → Create Credentials → OAuth client ID →
    Application type: **iOS**
  - Bundle ID: `com.anonymous.volspire-mobile`
  - Save the two outputs:
    - **Client ID:** `NNNN-xxxx.apps.googleusercontent.com`
    - **iOS URL scheme (reversed):** `com.googleusercontent.apps.NNNN-xxxx`

- [ ] **Supabase — trust the iOS client**
  - Authentication → Providers → Google → add the new **iOS client ID** to
    **Authorized Client IDs** (keep the existing web one). Save.
  - If sign-in returns a "nonce" error, enable **Skip nonce checks** (our native
    flow doesn't send one).

- [ ] **Fill in `VolspireCore/Info.plist`** (placeholders marked `YOUR_IOS_CLIENT_ID`)
  - `GIDClientID` → the Client ID
  - **Uncomment** the Google Sign-In `CFBundleURLTypes` block (it's currently commented
    out so the placeholder scheme doesn't fail App Store validation) and replace the
    reversed-client-id scheme with the real one.

- [ ] **Test:** Sign in with Google → native account sheet appears (no Safari) →
  lands back in the app authenticated.

### Notes / gotchas
- Bundle ID is currently `com.anonymous.volspire-mobile` (template default). If you'll
  change it before shipping, do that **first** and register the real one in
  Google Cloud — otherwise the iOS OAuth client has to be redone. (See the
  "App bundle identifier" section below.)
- The old web-redirect Google flow (and `volspire://auth/callback`) is no longer
  used for sign-in; the `volspire` URL scheme is left in place and is harmless.

## App bundle identifier — choose a real one before public App Store release

The app still ships under the Expo/template default prefix.

- **Current app bundle id:** `com.anonymous.volspire-mobile` (`project.pbxproj`, app target — Debug & Release)
- **Test target:** `com.anonymous.volspire-mobile.VolspireTests` (derives from the app id; TestFlight never builds or uploads it)

- [ ] **Pick the permanent id** (e.g. `com.volspire.app`) and set `PRODUCT_BUNDLE_IDENTIFIER`
  for the **app target** in `Volspire.xcodeproj/project.pbxproj` (both Debug & Release), and
  update the test target to `<new-id>.VolspireTests` to match.
- [ ] **Register the App ID** (Apple Developer → Identifiers) and create / align the App Store
  Connect app record to it.
- [ ] **Redo the iOS Google OAuth client** for the new id (the OAuth client + Supabase
  *Authorized Client IDs* are keyed to the bundle id — see the Google Sign-In section above).

### Why it can't wait
- **A bundle id can't be changed once the App Store Connect app record exists** — switching then
  means a new app record, a fresh upload, and re-inviting TestFlight testers. Lock it in **before**
  any public App Store submission.
- Existing TestFlight builds under `com.anonymous.volspire-mobile` are fine — do the rename for the
  public release, not as a fix.
- Do this **before** the Google Cloud iOS OAuth client setup above, or that client has to be redone.

## Export compliance / encryption

- `ITSAppUsesNonExemptEncryption` is set to `false` in `VolspireCore/Info.plist`.
  The app uses only standard HTTPS/TLS + auth (exempt), so this skips the App Store
  Connect encryption questionnaire on every upload.
- **Revisit only if** you add custom/non-standard encryption — then remove the key
  (or set it `true`) and complete the export-compliance questionnaire.

## Analytics — events still to wire on iOS

The analytics framework (`Services/Sources/Services/Analytics/`) is live, and these
events already fire: `track_play`, `track_ended`, `stream_counted`,
`track_liked`/`track_unliked`, `track_saved`/`track_unsaved`, `page_view`,
`search_performed`, `audio_settings_changed`, `share_clicked`,
`user_followed`/`user_unfollowed`, `comment_posted`.

To add any below, call `AnalyticsService.shared?.log(.eventType, trackId:, metadata:)`
at the right handler — the case already exists in `AnalyticsEventType`.

- [ ] **`download_clicked` / `download_modal_opened`** — wire when the iOS download/lease
  flow is settled. Candidate sites: `LeaseOptionsSheet` (modal opened) and the
  `TrackOptionsSheet` download action in `MediaCollectionScreen.mediaActions`.
- [ ] **`tier_impression`** — when lease/license tiers are shown (`LeaseOptionsSheet`).
- [ ] **`pack_liked` / `pack_saved`** — pack like/save isn't implemented on iOS yet
  (no `likePack`/`savePack` in `SupabaseService`). Wire alongside that feature.
- [ ] **`playback_error`** — hook the player's error path (`URLAudioPlayer` / `MediaPlayer`)
  and log with the failing `track_id` + error info.
- [ ] **Stripe purchase funnel** — `purchase_clicked`, `purchase_initiated`,
  `purchase_completed`, `purchase_abandoned`, `refund_completed`. Wire when iOS gets a
  checkout flow. Note: on web, `purchase_abandoned` / `refund_completed` are fired
  **server-side** (Stripe webhooks) — those may never be iOS-client events.
- [ ] **Stripe Connect onboarding** — `connect_modal_opened`,
  `connect_onboarding_started`, `connect_onboarding_completed`. Seller-onboarding flow,
  not present on iOS yet (and *completed* is webhook-fired on web).
- [ ] **`visualizer_toggled`** — N/A: the audio visualizer/spectrum was removed from iOS.
  Skip unless the visualizer returns.

### Parity notes / deltas vs web
- `page_view` uses logical screen names (`home`, `track`, `profile`, `media_list`, …),
  not URL paths, and logs `to` (+ entity `id`) — no `from` (iOS keeps a nav stack per
  tab, so a single "previous path" isn't meaningful).
- Listen events send `source: null` — iOS has no per-play surface tag yet (web sets
  `library`/`profile`/`playlist`/…). Threading a play `source` is a separate task.
- Every iOS event carries `metadata.env.platform = "ios"`; filter native-app rows with
  `metadata->'env'->>'platform' = 'ios'`.

## Payments / Stripe — deferred (shelved 2026-06-29)

Decided not to build Stripe on iOS for now — the App Store classification is a
headache and the overall scope (marketplace Connect + a new backend endpoint) is large.
No iOS code was written; this is a research summary so we don't have to re-derive it.

### Where things stand
- **iOS:** no Stripe at all. `LeaseOptionsSheet` is display-only (license tiers + prices,
  no buy button).
- **Web (the thing to mirror):** a Stripe **marketplace** — hosted **Checkout Sessions**
  + **Connect destination charges** (`transfer_data.destination` = seller,
  `application_fee_amount` = platform cut). Sellers onboard via `accounts.create` +
  hosted `accountLinks`. Plus a webhook (records orders) and refund / portal / release
  (escrow-then-release for services). Routes: `volspire-ui-v2/app/api/stripe/**`.

### The App Store wrinkle (why it's a headache)
- **Real-world services** (mixing, a feature, collab — a person delivers work) → Apple
  exempts these from IAP and *requires* external payment → **Stripe is fine** (the Fiverr
  model). Apple Pay *via Stripe* is NOT IAP and avoids the 30%.
- **Digital packs / track licenses** → digital goods → Apple wants **In-App Purchase**
  (15–30%, and IAP can't cleanly Connect-split to sellers). Selling these via Stripe
  in-app is what gets the app rejected.
- **Seller payouts** (Connect onboarding) → not a purchase; always fine.
- US-only lever: the 2025 *Epic v. Apple* injunction lets US apps link out to web Stripe
  checkout without commission — US-only and still settling. Not for v1.

### If/when we revisit — recommended slice
1. **Connect seller onboarding** (no IAP issue) + **services checkout via Stripe**
   (App-Store-safe) — both shippable.
2. Keep **packs/licenses browse-only on iOS** (buy on web) to dodge the IAP fight.
3. **Backend gap:** the web's `/api/stripe/checkout` is cookie-authed Next.js; iOS uses
   bearer tokens, so we'd need a bearer-authed **Supabase edge function** to mint Checkout
   Sessions / account links (no edge functions exist yet).
4. App Review notes: frame as "marketplace for real-world creative services (à la Fiverr);
   service payments use external processing per Guidelines 3.1.3/3.1.5" + a test account.

## Video/audio drift — optional safety net (foreground re-sync already shipped)

The now-playing video shows through a separate muted `AVPlayer` while audio runs
through AudioKit; they only re-sync on play/pause/seek. A `willEnterForeground`
re-sync (`URLAudioPlayer.resyncVideoToAudio()`) already fixes the background→foreground
desync/stutter. If drift ever shows up *during normal playback* (not just after
backgrounding), add a conservative drift check:

- [ ] In the existing progress timer (~0.5s tick, no new timer), when `isVideoMode`
      and playing, compare `videoPlayer.currentTime` vs `akPlayer.currentTime`.
- [ ] If |drift| > ~0.3–0.4s, call `resyncVideoToAudio()` to re-seek the video.
- [ ] Add a short cooldown (e.g. don't re-seek more than once every ~2s) so a tight
      threshold can't cause repeated seeks → micro-stutter.
- [ ] Cost is negligible (two time reads + compare per tick); only the occasional
      seek has any cost, and it's gated on real drift. Only worth doing if the
      foreground re-sync proves insufficient.

## Player transport toggles — RESOLVED 2026-07-04 (unified with the action-row icons)

The premise was off: the save/like buttons were never "instant" — they declare their own
fast tint animation, `.animation(.easeInOut(duration: 0.18), value: isActive)`
(`RegularNowPlaying.interactionButton` / `FillIcon`). That value-scoped declaration is
*why* they're immune to ambient transactions: it owns the animation whenever its value
changes, so nothing can leak in.

Shuffle/repeat (`PlayerButtons.swift`) keep `.animation(nil, value:)` — but it's now
understood as the same idiom, not a hack: every stateful icon *declares* its own
value-scoped animation (like/save declare a 0.18s ease; shuffle/repeat declare instant
— a deliberate feel choice, tried the 0.18s ease and preferred the snap). Declaring it
is what makes them immune to ambient transactions.

Also intentionally instant: the play/pause glyph swap (`.animation(nil)` +
`.contentTransition(.identity)`) — an instant swap is standard transport behavior.

Still true: do NOT use a blanket `.transaction { $0.animation = nil }` on these — it also
kills the icons' layout/movement animation (tried and reverted).

Note: `isShuffled` / `repeatMode` are local `@State` — the buttons don't drive actual
playback behavior yet. See the "Wire shuffle / repeat into playback" section below.

## Wire shuffle / repeat into actual playback (buttons are visual-only today)

`PlayerButtons.swift` holds `isShuffled` / `repeatMode` as local `@State` — tapping them
changes tint only. Nothing in the stack implements the behavior.

How the stack works today (for whoever picks this up):
- `MediaPlayer` (Player package) owns the queue: `items: [MediaID]`. `forward()` /
  `backward()` walk it **linearly with wraparound**, and `urlAudioPlayerDidFinishPlaying`
  (MediaPlayer.swift:341) auto-advances the same way — i.e. today's behavior is
  effectively **repeat-all, always**. "Repeat off" is therefore a behavior *change*
  (stop at end of queue), not just a no-op default.
- `PlayerController.onForward/onBackward` just delegate to `MediaPlayer`.
- `MediaLibrary/MediaState/MediaPlaybackMode.swift` is an unused stub type (id + title
  only) — either build on it or delete it when doing this.

- [ ] Move `isShuffled` / `repeatMode` state up out of `PlayerButtons` (PlayerController,
      forwarded to MediaPlayer — same pattern as `applyEffects`). Local state also
      currently resets whenever the button view is rebuilt.
- [ ] **Shuffle:** on enable, build a shuffled play order over `items` (keep the original
      order around so un-shuffle restores it; keep the current track first so playback
      doesn't jump). `forward()`/`backward()`/auto-advance walk the active order.
- [ ] **Repeat:** in `urlAudioPlayerDidFinishPlaying` — `one`: replay current (seek 0 +
      play); `all`: wrap (today's behavior); `off`: advance until the end of the queue,
      then stop (pause + reset). Explicit `forward()` taps should probably still wrap
      even with repeat off (matches Apple Music / Spotify).
- [ ] Check the web app's player for intended semantics/parity before implementing.
- [ ] Optional polish: report shuffle/repeat to the lock screen via
      `MPRemoteCommandCenter` change-shuffle/repeat commands (`SystemMediaInterface`).

## Reply-to-a-reply (nested comments) — deferred

Today comment threads are **one level deep**: you can reply to a top-level comment, but
replies have no Reply button (gated behind `!isReply` in `NowPlayingCommentsPanel`). This
matches the web app (its comment component gates the reply button the same way).

Backend check (2026-07-04): the `comments` table has a self-referential `parent_id`, and
`post_comment` accepts **any** `p_parent_id` (no top-level check), so a nested reply would
be *inserted and stored*. BUT `get_track_comments` only assembles **two tiers** (top-level
`parent_id IS NULL` + their direct children), so a reply-to-a-reply would be **stored but
never returned** — an orphaned, invisible comment. So it's not usable end-to-end as-is.

Recommended if we ever want it — **flatten** (what IG/YouTube do, zero backend change):
- [ ] Drop the `!isReply` guard so replies also show a "Reply" button.
- [ ] When replying to a reply, set `replyingTo` (→ the sent `parentId`) to the **top-level
      ancestor**, not the reply itself — so `get_track_comments` still returns it as a
      direct child and it shows.
- [ ] Prepend an `@username` mention of the reply's author so it's clear who's addressed.
- [ ] Fix the optimistic insert in `NowPlayingCommentsModel.send` — it currently finds the
      parent only among top-level `comments`; with flattening that still works, but verify.

True arbitrary nesting (recursive-CTE `get_track_comments` + nested rendering) is a bigger
lift and diverges from the web — only if the product wants deep threads.

## Comments-button count — removed, re-add later

The "Comments" pill in the player transport (`PlayerControls.commentsButton`) used to show a
count next to the label. Removed it because it wouldn't animate in with the rest of the page
cleanly and the attempts to fix it got fussy. The count itself is available at
`model.trackDetail?.comments`.

- [ ] Re-add the count on the "Comments" pill (e.g. "Comments · 12").
- [ ] Make it appear **with** the page's entrance, not pop in after — the trick is to have the
      value present *at insertion* (read `trackDetail?.comments` directly in the label rather
      than seeding a `@State` in `.onAppear`, which is too late for the entrance transition).
- [ ] Keep a last-known fallback so it doesn't blank for a frame during a track switch (when
      `trackDetail` briefly goes nil). The removed code used a `displayedComments` @State
      updated via `.onChange` for exactly this — restore that pattern.
- [ ] There was also a `commentCountLabel` helper (999 / 1.2K / 3.4M formatting) worth reusing.
