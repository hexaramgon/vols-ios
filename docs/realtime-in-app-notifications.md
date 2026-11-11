# In-app notifications: Realtime (and how to go back)

How the iOS app learns about new DMs and activity **while it is open**:
banner, unread dots, conversation list. Lock-screen and background
notifications are separate. They're covered in
[push-notifications.md](push-notifications.md).

Written 2026-11-08, when this replaced a short-lived 10-second polling loop.

---

## The model (industry standard)

| App state | Channel | What happens |
|---|---|---|
| Closed / backgrounded | **APNs push** (FCM on Android) | Lock-screen alert + badge |
| Open (foreground) | **Supabase Realtime WebSocket** | Server pushes an event the moment something happens → banner + dots + list update |
| Returning to foreground | **One catch-up fetch** | Covers anything missed while the socket was closed |

Polling was rejected. It was wasteful: at 10,000 open apps a 10-second poll is
about 1,000 Postgres queries a second, almost all of them answering "nothing new".

---

## How it works

```
 DM inserted (convo_messages)            activity row inserted (activity_log)
          │ AFTER INSERT trigger                    │ AFTER INSERT trigger
          ▼                                         ▼
 broadcast_new_message()                 broadcast_new_activity()
   one event per other participant        one event to user_id (skips self-actions)
          │                                         │
          └──── realtime.send(payload, event, 'user:<uid>', private => true)
                                │
                                ▼
          Supabase Realtime: private topic  user:<uid lowercase>
          (RLS on realtime.messages: you may only receive your own topic;
           no INSERT policy, so clients can't broadcast into anyone's topic)
                                │  WebSocket (only while the app is foreground)
                                ▼
 iOS  LiveEvents.swift   SupabaseService.openLiveEvents() → AsyncStream<LiveEvent>
                                │
                                ▼
 iOS  InboxStore.handle(_:)
   .message(convoId) → refreshUnread(force) + refreshConversations
                       → PushBannerCenter.show (unless that convo is on screen,
                         already read, mine, or archived)
   .activity         → refreshUnread(force) + newest unread notification
                       → PushBannerCenter.show + post .pushReceived
                         (an open Notifications page reloads)
```

**Payloads carry ids only, never message text**:
`new_message` → `{convo_id, message_id, sender_id}`;
`new_activity` → `{activity_id, action, object_type, object_id}`.
The client always refetches through the normal RPCs (`get_unread_counts`,
`get_user_conversations`, `get_user_notifications`), so blocks, archives and
every other read rule still apply. Realtime only says *"go look"*.

### Pieces and where they live

| Piece | Location |
|---|---|
| Migration: triggers, functions, RLS policy | `volspire-ui-v2/supabase/migrations/20261108120000_realtime_user_channel.sql` (applied to prod 2026-11-08 as `realtime_user_channel`) |
| Subscription (join private topic, decode events) | `Services/Sources/Services/LiveEvents.swift` |
| Lifecycle + reactions | `VolspireCore/Stores/InboxStore.swift`: `startLiveUpdates` / `stopLiveUpdates` / `runLiveEvents` / `handle` |
| Start / stop with app state | `VolspireCore/Screens/Root/RootTabView.swift`: `.task` + `scenePhase` (`.active` → start + `appBecameActive()`, `.background` → stop) |
| Sign-out | `InboxStore.resetForSignOut()` → `stopLiveUpdates()` |
| In-app banner UI | `VolspireCore/UI/Views/ToastCenter.swift`: `PushBannerCenter` / `PushBannerHost` (mounted top-aligned in `OverlaidRootView`) |
| APNs arriving while open | `AppDelegate.willPresent` → shows the same in-app banner, returns `[.list, .badge]` (no system banner) and posts `.pushReceived` |

**Dedupe:** while the app is open, the same DM can arrive twice, once over
Realtime and once as APNs. `PushBannerCenter` shows one banner per
conversation (or per activity object) within 12 seconds.

**Reconnects:** supabase-swift re-joins channels after a dropped socket by
itself. If the initial join fails, `runLiveEvents` retries with backoff
(2 s up to 60 s). Anything missed while disconnected is picked up by
`appBecameActive()` on the next foreground.

---

## Scale and limits

These are Supabase Realtime limits per project (see
supabase.com/docs/guides/realtime/limits). The project is on **Pro**.

| | Pro (spend cap on) | Pro (spend cap off) / Team | Enterprise |
|---|---|---|---|
| Concurrent connections | 500 | 10,000 | 10,000+ (custom) |
| Messages / second | 500 | 2,500 | custom |

- **Connections** count only users with the app **open in the foreground**.
  Each one holds a single socket with one channel.
- **Messages** means one event per DM recipient or activity row.
- When a limit is hit, joins are refused (`too_many_connections`) or sockets
  dropped (`tenant_events`). The app still works then: push and the
  catch-up on foreground keep everything correct. Only the instant in-app
  update is lost. Check the Realtime logs in the dashboard.
- Broadcast was chosen over "Postgres Changes" on purpose. Postgres Changes
  checks every change against every subscriber's RLS, which is Realtime's
  known bottleneck. Broadcast sends straight to one topic.

---

## Testing it

1. On the sim, sign in as the demo account. To prove the banner isn't coming
   from APNs, set that account's iOS tokens `is_active = false` in
   `user_push_tokens`. The next app launch reactivates the current one;
   reactivate the rest afterwards.
2. As another account, call the `send_message` RPC into a shared DM (the
   sim-qa session used psyknick → lowkeyloops). A banner should appear within
   about 1 second, the Messages and Explore dots should light up, and the row
   should get its unread dot.
3. Activity: have the other account call `post_comment` on one of the demo
   account's tracks. Expect a bell banner reading "commented on your track".
   Delete the comment afterwards.
4. Background the app (open Settings), come back, and send again. It should
   still be instant.
5. Authorization check (SQL; it rolls back). As user A, `realtime.messages`
   rows for topic `user:<B>` must be invisible and inserts must fail:

   ```sql
   begin;
   insert into realtime.messages (topic, extension, payload, event, private)
     values ('user:<B>','broadcast','{}','probe',true),
            ('user:<A>','broadcast','{}','probe',true);
   select set_config('request.jwt.claims','{"sub":"<A>","role":"authenticated"}',true);
   set local role authenticated;
   select set_config('realtime.topic','user:<B>',true);
   select count(*) from realtime.messages where event='probe';  -- expect 0
   select set_config('realtime.topic','user:<A>',true);
   select count(*) from realtime.messages where event='probe';  -- expect > 0
   rollback;
   ```

---

## Going back

### A. Turn Realtime off server-side (keeps the app working)

Run the following against the project. It's also at the bottom of the
migration file:

```sql
drop trigger if exists trg_broadcast_new_message on public.convo_messages;
drop trigger if exists trg_broadcast_new_activity on public.activity_log;
drop function if exists public.broadcast_new_message();
drop function if exists public.broadcast_new_activity();
drop policy if exists "user channel: receive own broadcasts" on realtime.messages;
```

The app degrades gracefully. The channel join is refused or simply never
receives anything. In-app banners then come only from APNs arriving while
the app is open, and dots refresh on foreground, on tab switch and on push.
Nothing crashes, and the retry loop backs off to one attempt a minute.

### B. Remove it from the app

- Delete `Services/Sources/Services/LiveEvents.swift`. Optionally put
  `SupabaseService.client` back to `private` (it was made internal for
  that file).
- In `InboxStore`, delete `liveTask`, `liveSubscription`,
  `startLiveUpdates`, `stopLiveUpdates`, `runLiveEvents`, `handle` and
  `announceMessage`. Keep `announceNewActivity` / `activityText` only if
  something else uses them.
- In `RootTabView`, drop the `startLiveUpdates()` / `stopLiveUpdates()` calls.

### C. Fall back to polling (the 2026-11-08 interim version)

Use this only if Realtime is unavailable and push-independent in-app alerts
are still required. Expect about 1 RPC per open app every 10 seconds.

```swift
// InboxStore
private var hasUnreadBaseline = false          // set true in refreshUnread()
private var liveTask: Task<Void, Never>?
static let liveInterval: Duration = .seconds(10)

func startLiveUpdates() {
    guard liveTask == nil else { return }
    liveTask = Task { [weak self] in
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.liveInterval)
            guard !Task.isCancelled else { return }
            await self?.liveTick()
        }
    }
}

private func liveTick() async {
    let hadBaseline = hasUnreadBaseline
    let messagesBefore = unreadMessages, notificationsBefore = unreadNotifications
    await refreshUnread(force: true)
    guard hadBaseline else { return }
    if unreadMessages > messagesBefore {
        await refreshConversations()
        // banner the newest row with hasUnread && !lastMessageFromMe && not on screen
    }
    if unreadNotifications > notificationsBefore { await announceNewActivity() }
}
```

---

## Related history (2026-11-08)

Same day, same bug report ("push arrives but no red dot / no in-app banner"):

- The tab-bar unread dot sat on **Workspace** after Messages and the bell
  moved to Explore's header. It now sits on **Explore**. The header's
  Messages icon shows DMs only; the bell shows activity only.
- A push arriving in the foreground didn't refresh anything. It now posts
  `.pushReceived`, which InboxStore and an open Notifications page react to.
  Foregrounding calls `InboxStore.appBecameActive()`, and opening Messages
  revalidates the list.
- The system's foreground banner was replaced by the app's own
  `PushBannerHost`. iOS hides its foreground banners under Focus modes and
  banner-style settings.
- The original "no banner on my phone" report was a test install with
  **no registered push token** (psyknick, none since 2026-11-06), so APNs
  never reached it. To diagnose, check `user_push_tokens.updated_at`: it
  bumps on every launch when notification permission is granted.
