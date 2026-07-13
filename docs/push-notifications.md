# Push Notifications — how they work with Supabase

The iOS app delivers lock-screen push notifications (likes, saves, comments,
follows, credits, DMs) through Apple's APNs, driven end-to-end by Supabase:
database triggers detect events, edge functions deliver them. This doc maps
the whole pipeline, where each piece lives, and how to debug it.

## The pipeline at a glance

```
 someone likes your track                    you send a DM
          │                                        │
          ▼                                        ▼
   user_likes INSERT                       convo_messages INSERT
          │  (DB trigger)                          │  (DB trigger)
          ▼                                        │
   activity_log INSERT                             │
          │  (DB trigger → supabase_functions.http_request)
          ▼                                        ▼
 edge fn: send-activity-notification   edge fn: send-message-notification
          │                                        │
          ├─ preference gate (user_notification_preferences)
          ├─ look up recipient's active iOS tokens (user_push_tokens)
          ├─ badge = get_unread_badge_count(recipient)
          ▼                                        ▼
     APNs (api.push.apple.com, sandbox fallback) — ES256 JWT from secrets
          │
          ▼
   🔔 lock-screen banner + custom sound + icon badge
```

## 1. Device registration (iOS → Supabase)

**Code: `Services/Sources/Services/PushNotificationManager.swift`**

1. When a session becomes active (launch restore or fresh sign-in), `AppView`
   calls `PushNotificationManager.enable()` — this shows the system permission
   prompt (first time only) and calls `registerForRemoteNotifications()`.
2. Apple hands back a device token via the AppDelegate callback
   (`VolspireCore/Main/AppDelegate.swift`), which forwards it to
   `didRegister(deviceToken:)` — the token is hex-encoded and upserted via the
   **`register_push_token`** RPC into **`user_push_tokens`**
   (user_id, push_token, platform `ios`, is_active).
3. One owner per device token: registering a token that belonged to a
   different account (account switch on the same phone) deletes the old row —
   the previous account stops receiving pushes on that device.
4. **Sign-out** calls the **`deactivate_push_token`** RPC *before* the local
   session is dropped (the RPC needs auth), marking the token inactive.

Tokens rotate — Apple may issue a new one at any time, which is why
registration re-runs on every launch.

## 2. Event detection (database triggers)

Events are born in the database, so pushes work no matter which client (iOS
or web) caused them:

- Engagement triggers (`user_likes`, `user_saves`, `comments`,
  `user_relationships`, `track_credits`, `listing_*`) insert rows into
  **`activity_log`** — the same table the in-app Notifications screen reads.
- `activity_log` has an AFTER INSERT trigger (`activity_notification`) that
  calls `supabase_functions.http_request(...)` → POSTs the new row to the
  **send-activity-notification** edge function, authorized with the service
  role key.
- `convo_messages` has the analogous `message_notification` trigger →
  **send-message-notification**.

Note: nothing fires on *track upload* — followers aren't notified of new
tracks (tracked separately in `todolist.md`).

## 3. Delivery (edge functions → APNs)

**Code: deployed on Supabase (edit via dashboard or `deploy_edge_function`);
both functions are self-contained Deno scripts.**

Each function:

1. **Preference gate** (activity only): maps the activity to a
   `user_notification_preferences` column (`liked`→`likes`,
   `followed`→`new_followers`, etc.) and skips the push if the recipient
   turned that category off in Settings → Notifications.
2. Fetches the recipient's **active iOS tokens** from `user_push_tokens`
   (messages: one lookup per receiver, everyone in the convo except the
   sender).
3. Computes the **badge** via the `get_unread_badge_count(user_id)` SQL
   function: unread `activity_log` rows + unread DMs (messages newer than
   each convo's `last_read_at`, excluding archived convos and own messages).
4. Signs an **ES256 JWT** with the APNs auth key (cached ~45 min) and POSTs
   to APNs with headers `apns-topic: com.volspire.app`,
   `apns-push-type: alert`, `apns-priority: 10`.
5. **Environment fallback**: tries `api.push.apple.com` first; on
   `BadDeviceToken` retries `api.sandbox.push.apple.com`. Dev builds from
   Xcode register *sandbox* tokens; TestFlight/App Store builds are
   *production* — the fallback makes both work with zero config.

The payload:

```json
{
  "aps": {
    "alert": { "title": "<actor username>", "body": "liked your track" },
    "sound": "notif.caf",
    "badge": 3
  },
  "type": "activity | message",
  "object_id": "…", "convo_id": "…"
}
```

## 4. Presentation on the phone

- **Custom sound**: `notif.caf` ships in the app bundle
  (`VolspireCore/Resources/notif.caf` — IMA4-encoded CAF, must stay under
  30 s or iOS falls back to the default). Installs without the file also get
  the default sound, so changing it is never a breaking change. To replace:
  `afconvert new.wav VolspireCore/Resources/notif.caf -d ima4 -f caff`.
- **Foreground**: the AppDelegate is the `UNUserNotificationCenter` delegate
  and presents pushes as banners (`.banner, .badge`) even while the app is
  open.
- **Icon badge**: stamped by the server with the true unread count on every
  push; cleared to 0 whenever the app comes to the foreground
  (`AppView`'s `scenePhase` observer). The next push re-stamps the accurate
  number, so the badge self-corrects.
- **In-app dots**: the Inbox tab dot (unread DMs) and the notifications bell
  dot (unread activity) are driven by the `get_unread_counts` RPC (the same
  one the web uses) via `UnreadCounts` in `RootTabView.swift`, refreshed on
  launch/foreground/tab-switch/conversation-close and cleared optimistically
  when the relevant screen opens.

## 5. Secrets & Apple configuration

| Where | What |
|---|---|
| Apple portal → Identifiers | `com.volspire.app` App ID with **Push Notifications** enabled |
| Apple portal → Keys | APNs auth key (**Sandbox & Production**), Key ID `6V6BHN4GT4` |
| `Volspire.entitlements` | `aps-environment` (development; distribution signing flips it) |
| Supabase → Edge Functions → Secrets | `APNS_AUTH_KEY` (full .p8 contents), `APNS_KEY_ID`, `APPLE_TEAM_ID` (`9Q838CQ524`), optional `APNS_TOPIC` |

⚠️ The Team ID is the **membership** team (portal top-right), not whatever a
stale `DEVELOPMENT_TEAM` in the Xcode project says — a mismatch yields
`InvalidProviderToken` from APNs in both environments.

## 6. Debugging playbook

Work down the pipeline; each step has a concrete check:

1. **Did the device register?**
   `SELECT * FROM user_push_tokens;` — expect an active `ios` row after
   signing in on the device (permission must be granted).
2. **Did the event land?**
   `SELECT * FROM activity_log ORDER BY created_at DESC LIMIT 5;`
3. **Did the function run?** Supabase dashboard → Edge Functions → logs
   (invocations show as `POST | 200`). The response body includes
   `{ sent, of, badge, errors[] }` — `errors` carries the raw APNs rejection
   (e.g. `prod 403: {"reason":"InvalidProviderToken"}`), so a manual
   invocation with a copied `activity_log` row (service-role bearer) tells
   you exactly what APNs said.
4. **Apple's side**: the Push Notifications Console
   (icloud.developer.apple.com → Push Notifications → pick
   `com.volspire.app`) has a per-token **Delivery Log** and a **Send** tab
   for hand-fired test pushes.

Common APNs rejections:
- `InvalidProviderToken` — key/Key ID/Team ID mismatch (see §5 warning).
- `BadDeviceToken` — wrong environment for the token (dev build ↔ prod
  host); our fallback handles this automatically.
- `TopicDisallowed` / `DeviceTokenNotForTopic` — `apns-topic` doesn't match
  the app's bundle ID.
- Silent success but no banner: check phone's Focus mode, per-app
  notification settings, and that the recipient ≠ actor.

## 7. Adding a new notification type

1. Make the event write an `activity_log` row (trigger or RPC) with a
   descriptive `action` + `object_type` — delivery is then automatic.
2. If it should be user-mutable: add a preference column to
   `user_notification_preferences`, a case to `NotificationPref` (iOS
   Settings), and a mapping line in the edge function's `prefColumn()`.
3. Different sound/title formatting: adjust the edge function only — no app
   update needed unless the sound file itself is new.
