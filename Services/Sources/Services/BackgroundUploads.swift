//
//  BackgroundUploads.swift
//  Services
//
//  Big uploads that survive the app leaving the foreground. Each file goes
//  up on a background URLSession from a copy the job owns, so the system
//  keeps transferring while the app is suspended or even terminated; the
//  job's RPC (e.g. `create_track_v2`) runs once the last file lands —
//  in-process if the caller is still waiting, on the background wake, or at
//  the next launch. A force-quit cancels the transfers; `resume` restarts
//  them on the next activation.
//

import Foundation
import SharedUtilities
import Synchronization

/// What the uploader needs from the API layer (SupabaseService conforms).
public protocol BackgroundUploadBackend: Sendable {
    /// A signed PUT URL for `path` in `bucket` (minted with the user's session).
    func signedUploadURL(bucket: String, path: String) async throws -> URL
    /// Runs the job's closing RPC with its pre-serialized params.
    func runUploadRPC(_ name: String, params: Data) async throws -> Data
    /// The signed-in user (lowercased) — a job only closes as its owner.
    var currentUserId: String? { get }
}

public extension Notification.Name {
    /// A job finished with no caller waiting (it completed after a relaunch).
    /// userInfo: "label" (String), "succeeded" (Bool — the content was
    /// created), "followUpFailed" (Bool — created, but e.g. not added to
    /// its release).
    static let backgroundUploadEnded = Notification.Name("BackgroundUploadEnded")
}

public actor BackgroundUploads {
    public static let shared = BackgroundUploads()

    /// One file of a job: where it goes, and whether it has landed.
    public struct File: Codable, Sendable {
        public let bucket: String
        public let path: String
        public let contentType: String
        var localName = ""
        var done = false
        /// Failed transfers of this file (a force-quit's cancel isn't one).
        var failures = 0

        public init(bucket: StorageBucket, path: String, contentType: String) {
            self.bucket = bucket.rawValue
            self.path = path
            self.contentType = contentType
        }
    }

    /// A second RPC that runs after the job's own one, fed an id from its
    /// result — e.g. adding the new track to its release. Part of the job,
    /// so it also completes after a relaunch.
    public struct FollowUp: Codable, Sendable {
        public let rpc: String
        /// A JSON object of the fixed params.
        public let params: Data
        /// The param that receives `[id]`.
        public let idParam: String
        /// The key in the first RPC's JSON result holding that id.
        public let resultKey: String

        public init(rpc: String, params: Data, idParam: String, resultKey: String) {
            self.rpc = rpc
            self.params = params
            self.idParam = idParam
            self.resultKey = resultKey
        }
    }

    /// The job's own RPC succeeded but its follow-up didn't. `result` is the
    /// first RPC's response (the content exists — only the follow-up is
    /// left for the caller to retry).
    public struct FollowUpFailed: Error {
        public let result: Data
        public let underlying: Error
    }

    struct Job: Codable, Sendable {
        let id: UUID
        let userId: String
        let label: String
        let rpc: String
        let params: Data
        var files: [File]
        /// Failed runs of the closing RPC (files count their own failures).
        var attempts = 0
        var followUp: FollowUp?
        /// The first RPC's response, once it ran (a relaunch then only
        /// retries the follow-up).
        var result: Data?
    }

    private static let maxAttempts = 3
    private static let sessionId = "com.volspire.app.uploads"

    private static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "BackgroundUploads", directoryHint: .isDirectory)
    }()
    private static var index: URL { root.appending(path: "jobs.json") }

    /// Created with the actor — touching `shared` at launch (`activate`)
    /// reconnects the session, so a relaunch receives its events.
    private nonisolated let session: URLSession
    private nonisolated let events = SessionEvents()

    /// Set synchronously at launch (`configure`), so a background wake's
    /// events can close a job straight away.
    private nonisolated let backendBox = Mutex<BackgroundUploadBackend?>(nil)
    private var backend: BackgroundUploadBackend? { backendBox.withLock { $0 } }
    private var jobs: [UUID: Job]
    /// Files between "start" and their transfer existing (signing the URL is
    /// an await) — a concurrent resume / retry must not start them twice.
    private var starting: Set<String> = []
    private var waiters: [UUID: CheckedContinuation<Data, Error>] = [:]
    private var finishing: [UUID: Task<Void, Never>] = [:]

    private init() {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionId)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: events, delegateQueue: nil)
        jobs = Self.load()
    }

    // MARK: - App hooks

    /// Call at launch, before anything else can wake the session.
    public nonisolated func activate() { _ = session }

    public nonisolated func configure(_ backend: BackgroundUploadBackend) {
        backendBox.withLock { $0 = backend }
    }

    /// `application(_:handleEventsForBackgroundURLSession:completionHandler:)`:
    /// the handler runs once every delivered event (and any RPC it set off)
    /// has been processed.
    public nonisolated func handleEvents(identifier: String, completion: @escaping @Sendable () -> Void) {
        guard identifier == Self.sessionId else { return completion() }
        events.setCompletion(completion)
    }

    /// Foreground / sign-in: restart files whose transfer is gone (force-quit,
    /// failed while suspended) and close jobs whose files all landed. Jobs
    /// of another account (left by a sign-out) are dropped.
    public func resume(userId: String) async {
        let uid = userId.lowercased()
        let live = Set(await session.allTasks.compactMap(\.taskDescription))
        for (id, job) in jobs where waiters[id] == nil && finishing[id] == nil {
            guard job.userId == uid else {
                end(id, .failure(CancellationError()))
                continue
            }
            if job.files.allSatisfy(\.done) {
                await closeJob(id)
                continue
            }
            // A restart isn't a failure (a force-quit cancels transfers) —
            // only failed transfers count toward giving up.
            for i in job.files.indices where !job.files[i].done && !live.contains(Self.describe(id, i)) {
                await startFile(id, i)
            }
        }
    }

    // MARK: - Running a job

    /// Uploads `files` (each from its local URL), then runs `rpc` with
    /// `params`; returns the RPC's response. Keeps going if the app leaves
    /// the foreground — the await then resolves when the app is next running.
    public func run(
        userId: String,
        label: String,
        rpc: String,
        params: Data,
        files: [(File, URL)],
        then followUp: FollowUp? = nil
    ) async throws -> Data {
        let id = UUID()
        let dir = Self.root.appending(path: id.uuidString, directoryHint: .isDirectory)
        var staged: [File] = []
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var noBackup = URLResourceValues()
            noBackup.isExcludedFromBackup = true
            var rootURL = Self.root
            try? rootURL.setResourceValues(noBackup)
            for (i, (file, source)) in files.enumerated() {
                var file = file
                file.localName = "\(i)"
                let dest = dir.appending(path: file.localName)
                // A hard link is instant and costs no space (same volume);
                // the caller can delete its staged copy right after.
                do { try FileManager.default.linkItem(at: source, to: dest) }
                catch { try FileManager.default.copyItem(at: source, to: dest) }
                staged.append(file)
            }
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
        jobs[id] = Job(id: id, userId: userId.lowercased(), label: label, rpc: rpc, params: params,
                       files: staged, followUp: followUp)
        save()
        return try await withCheckedThrowingContinuation { continuation in
            waiters[id] = continuation
            Task { await self.startAll(id) }
        }
    }

    private func startAll(_ id: UUID) async {
        guard let job = jobs[id] else { return }
        if job.files.isEmpty { return await closeJob(id) }
        for i in job.files.indices where !job.files[i].done {
            await startFile(id, i)
        }
    }

    private func startFile(_ id: UUID, _ i: Int) async {
        let key = Self.describe(id, i)
        guard let file = jobs[id]?.files[i], !file.done, let backend, !starting.contains(key) else { return }
        starting.insert(key)
        defer { starting.remove(key) }
        // Already transferring (started by a call that finished meanwhile).
        let live = await session.allTasks.contains {
            $0.taskDescription == key && ($0.state == .running || $0.state == .suspended)
        }
        guard !live else { return }
        do {
            let url = try await backend.signedUploadURL(bucket: file.bucket, path: file.path)
            guard jobs[id] != nil else { return }   // ended meanwhile
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue(file.contentType, forHTTPHeaderField: "Content-Type")
            // Paths are unique per job; upsert lets a retry replace a
            // half-known earlier attempt instead of failing "Duplicate".
            request.setValue("true", forHTTPHeaderField: "x-upsert")
            request.setValue("3600", forHTTPHeaderField: "cache-control")
            request.setValue(SupabaseConfig.apiKey, forHTTPHeaderField: "apikey")
            let local = Self.root.appending(path: id.uuidString).appending(path: file.localName)
            let task = session.uploadTask(with: request, fromFile: local)
            task.taskDescription = Self.describe(id, i)
            task.resume()
        } catch {
            debugLog("[BackgroundUploads] sign \(file.path): \(error)")
            // A waiting caller shows the error. In the background (offline,
            // say) it's a failed attempt — the next activation tries again.
            if waiters[id] != nil { return end(id, .failure(error)) }
            countFailure(id, i, error)
        }
    }

    /// One more failure for file `i`; the job ends at `maxAttempts`.
    /// Returns whether it may be retried.
    @discardableResult
    private func countFailure(_ id: UUID, _ i: Int, _ error: Error) -> Bool {
        guard let failures = jobs[id]?.files[i].failures else { return false }
        guard failures + 1 < Self.maxAttempts else {
            end(id, .failure(error))
            return false
        }
        jobs[id]?.files[i].failures = failures + 1
        save()
        return true
    }

    /// Delegate: one file's transfer ended.
    fileprivate func transferEnded(_ description: String?, status: Int, error: Error?, body: Data) async {
        guard let (id, i) = Self.parse(description), let job = jobs[id], job.files.indices.contains(i),
              !job.files[i].done else { return }
        if error == nil, (200..<300).contains(status) {
            jobs[id]?.files[i].done = true
            save()
            if jobs[id]?.files.allSatisfy(\.done) == true { await closeJob(id) }
            return
        }
        debugLog("[BackgroundUploads] \(job.files[i].path) status \(status) error \(String(describing: error)): \(String(decoding: body.prefix(500), as: UTF8.self))")
        // Cancelled: we ended the job, or the app was force-quit — `resume`
        // restarts it on the next activation.
        if (error as? URLError)?.code == .cancelled { return }
        if status == 413 {
            let max = StorageBucket(rawValue: job.files[i].bucket)?.maxUploadBytes ?? 0
            return end(id, .failure(SupabaseError.fileTooLarge(maxBytes: max)))
        }
        guard countFailure(id, i, error ?? SupabaseError.serverError("storage upload \(status)")) else { return }
        await startFile(id, i)
    }

    /// Every file landed — run the RPC once (a second caller awaits the first).
    private func closeJob(_ id: UUID) async {
        if let running = finishing[id] { return await running.value }
        let task = Task { await self.runRPC(id) }
        finishing[id] = task
        await task.value
        finishing[id] = nil
    }

    private func runRPC(_ id: UUID) async {
        guard let job = jobs[id] else { return }
        // Signed out / another account (or not configured): a waiting caller
        // is told now — it'd otherwise wait forever; a background close
        // waits for `resume` as the owner.
        guard let backend, backend.currentUserId == job.userId else {
            if waiters[id] != nil { end(id, .failure(CancellationError())) }
            return
        }
        do {
            let data: Data
            if let done = job.result {
                data = done
            } else {
                data = try await backend.runUploadRPC(job.rpc, params: job.params)
                jobs[id]?.result = data
                save()
            }
            if let followUp = job.followUp {
                do {
                    _ = try await backend.runUploadRPC(followUp.rpc, params: Self.followUpParams(followUp, result: data))
                } catch {
                    debugLog("[BackgroundUploads] \(followUp.rpc): \(error)")
                    throw FollowUpFailed(result: data, underlying: error)
                }
            }
            end(id, .success(data))
        } catch {
            debugLog("[BackgroundUploads] \(job.rpc): \(error)")
            // A waiting caller shows the error now; a background close
            // tries again at the next activation, a few times.
            if waiters[id] != nil || job.attempts + 1 >= Self.maxAttempts {
                end(id, .failure(error))
            } else {
                jobs[id]?.attempts += 1
                save()
            }
        }
    }

    private func end(_ id: UUID, _ result: Result<Data, Error>) {
        guard let job = jobs.removeValue(forKey: id) else { return }
        save()
        try? FileManager.default.removeItem(at: Self.root.appending(path: id.uuidString))
        let prefix = id.uuidString + "|"
        let session = session
        Task {
            for task in await session.allTasks where task.taskDescription?.hasPrefix(prefix) == true {
                task.cancel()
            }
        }
        if let waiter = waiters.removeValue(forKey: id) {
            waiter.resume(with: result)
        } else if !(result.failureError is CancellationError) {
            let followUpFailed = result.failureError is FollowUpFailed
            let label = job.label, succeeded = result.isSuccess || followUpFailed
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .backgroundUploadEnded, object: nil, userInfo: [
                    "label": label, "succeeded": succeeded, "followUpFailed": followUpFailed,
                ])
            }
        }
    }

    // MARK: - Persistence

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
            try JSONEncoder().encode(Array(jobs.values)).write(to: Self.index, options: .atomic)
        } catch {
            debugLog("[BackgroundUploads] save: \(error)")
        }
    }

    private static func load() -> [UUID: Job] {
        guard let data = try? Data(contentsOf: index),
              let list = try? JSONDecoder().decode([Job].self, from: data) else { return [:] }
        return Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// The follow-up's params with `[id]` (from the first RPC's result) added.
    private static func followUpParams(_ followUp: FollowUp, result: Data) throws -> Data {
        guard var params = try JSONSerialization.jsonObject(with: followUp.params) as? [String: Any],
              let response = try JSONSerialization.jsonObject(with: result) as? [String: Any],
              let id = response[followUp.resultKey] as? String
        else { throw SupabaseError.serverError("follow-up: no \(followUp.resultKey) in result") }
        params[followUp.idParam] = [id]
        return try JSONSerialization.data(withJSONObject: params)
    }

    private static func describe(_ id: UUID, _ i: Int) -> String { "\(id.uuidString)|\(i)" }

    private static func parse(_ description: String?) -> (UUID, Int)? {
        guard let parts = description?.split(separator: "|"), parts.count == 2,
              let id = UUID(uuidString: String(parts[0])), let i = Int(parts[1]) else { return nil }
        return (id, i)
    }

    /// Waits out every forwarded delegate event (see `SessionEvents`).
    fileprivate func drain() async {
        for task in finishing.values { await task.value }
    }
}

// MARK: - Session delegate

/// Forwards transfer events into the actor, and holds the system's
/// background-wake completion handler until they've all been handled.
private final class SessionEvents: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var bodies: [Int: Data] = [:]
        /// Forwarded events still being handled, by task id (each removes
        /// itself when done, so the foreground doesn't accumulate them).
        var forwarded: [Int: Task<Void, Never>] = [:]
        var completion: (@Sendable () -> Void)?
        /// The session finished its events before UIKit handed over the
        /// completion handler — call it as soon as it arrives.
        var finishedWithoutHandler = false
    }
    private let state = Mutex(State())

    func setCompletion(_ completion: @escaping @Sendable () -> Void) {
        let callNow = state.withLock { s in
            if s.finishedWithoutHandler {
                s.finishedWithoutHandler = false
                return true
            }
            s.completion = completion
            return false
        }
        if callNow { DispatchQueue.main.async { completion() } }
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Only error bodies are small JSON; cap it either way.
        state.withLock { s in
            var body = s.bodies[dataTask.taskIdentifier, default: Data()]
            if body.count < 2048 { body.append(data.prefix(2048 - body.count)) }
            s.bodies[dataTask.taskIdentifier] = body
        }
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let key = task.taskIdentifier
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        let description = task.taskDescription
        // Under the lock: the task can't remove its entry before it's stored.
        state.withLock { s in
            let body = s.bodies.removeValue(forKey: key) ?? Data()
            s.forwarded[key] = Task {
                await BackgroundUploads.shared.transferEnded(description, status: status, error: error, body: body)
                self.state.withLock { _ = $0.forwarded.removeValue(forKey: key) }
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession _: URLSession) {
        let tasks = state.withLock { Array($0.forwarded.values) }
        Task {
            for task in tasks { await task.value }
            await BackgroundUploads.shared.drain()
            let completion = self.state.withLock { s -> (@Sendable () -> Void)? in
                guard let c = s.completion else {
                    s.finishedWithoutHandler = true
                    return nil
                }
                s.completion = nil
                return c
            }
            if let completion { DispatchQueue.main.async { completion() } }
        }
    }
}

private extension Result {
    var isSuccess: Bool { if case .success = self { true } else { false } }
    var failureError: Failure? { if case .failure(let e) = self { e } else { nil } }
}
