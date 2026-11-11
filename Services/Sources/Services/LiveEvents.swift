//
//  LiveEvents.swift
//  Services
//
//  In-app realtime: the signed-in user's PRIVATE Supabase Realtime broadcast
//  topic `user:<uid>`. Database triggers (migration
//  20261108120000_realtime_user_channel.sql in volspire-ui-v2) broadcast a
//  tiny ids-only event when a DM or an activity row is created for this user;
//  the app reacts by refetching through the normal RPCs. Used ONLY while the
//  app is in the foreground — closed/backgrounded = APNs pushes.
//  Design + rollback: docs/realtime-in-app-notifications.md.
//

import Foundation
import Supabase
import SharedUtilities

/// Something new for the signed-in user, from their realtime topic.
public enum LiveEvent: Sendable {
    case message(convoId: String, senderId: String?)
    case activity(objectType: String?, objectId: String?)
}

/// An open subscription to the user's topic. `close()` leaves the channel
/// (the WebSocket itself closes once no channels remain).
public final class LiveEventsSubscription: Sendable {
    public let events: AsyncStream<LiveEvent>
    private let channel: RealtimeChannelV2
    private let client: SupabaseClient

    init(events: AsyncStream<LiveEvent>, channel: RealtimeChannelV2, client: SupabaseClient) {
        self.events = events
        self.channel = channel
        self.client = client
    }

    public func close() async {
        await client.removeChannel(channel)
    }
}

extension SupabaseService {
    /// Joins `user:<uid>` (private — the realtime.messages RLS policy lets a
    /// user receive only their own topic). Nil when signed out.
    public func openLiveEvents() async throws -> LiveEventsSubscription? {
        guard let uid = currentUserId else { return nil }
        let channel = client.channel("user:\(uid)") { $0.isPrivate = true }
        let messages = channel.broadcastStream(event: "new_message")
        let activity = channel.broadcastStream(event: "new_activity")

        let (events, continuation) = AsyncStream<LiveEvent>.makeStream()
        let pump = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await raw in messages {
                        let p = Self.payload(raw)
                        guard let convoId = p["convo_id"]?.stringValue else { continue }
                        continuation.yield(.message(convoId: convoId, senderId: p["sender_id"]?.stringValue))
                    }
                }
                group.addTask {
                    for await raw in activity {
                        let p = Self.payload(raw)
                        continuation.yield(.activity(
                            objectType: p["object_type"]?.stringValue,
                            objectId: p["object_id"]?.stringValue
                        ))
                    }
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in pump.cancel() }

        try await channel.subscribeWithError()
        debugLog("[LiveEvents] joined user:\(uid)")
        return LiveEventsSubscription(events: events, channel: channel, client: client)
    }

    /// A DB-sent broadcast arrives as {event, payload: {...}, type}; unwrap it.
    private static func payload(_ raw: JSONObject) -> JSONObject {
        raw["payload"]?.objectValue ?? raw
    }
}
