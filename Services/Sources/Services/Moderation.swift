//
//  Moderation.swift
//  Services
//
//  API surface for UGC safety (App Store Guideline 1.2): the report/block
//  RPC parameter types and the blocked-user DTO. Backend: submit_report,
//  block_user / unblock_user, get_blocked_users.
//

import Foundation

/// What a report points at. Raw values match the DB `content_reports.target_type`
/// check constraint exactly — do not rename without a matching migration.
public enum ReportTargetType: String, Sendable {
    case track
    case trackComment = "track_comment"
    case fileComment = "file_comment"
    case listingComment = "listing_comment"
    case message
    case listing
    case user
    case pack
}

/// Why something is being reported. Raw values match the DB `content_reports.reason`
/// check constraint. `csam`, `sexual`, and `violence` auto-hide the target on the
/// first report; the rest hide once a report threshold is crossed.
public enum ReportReason: String, CaseIterable, Sendable {
    case sexual
    case csam
    case harassment
    case hate
    case violence
    case ip
    case spam
    case illegal
    case other

    /// User-facing row label in the report sheet.
    public var label: String {
        switch self {
        case .sexual:     return "Nudity or sexual content"
        case .csam:       return "Child sexual abuse / endangerment"
        case .harassment: return "Harassment or bullying"
        case .hate:       return "Hate speech or symbols"
        case .violence:   return "Violence or threats"
        case .ip:         return "Copyright or trademark infringement"
        case .spam:       return "Spam or a scam"
        case .illegal:    return "Illegal goods or activity"
        case .other:      return "Something else"
        }
    }
}

public extension Notification.Name {
    /// Posted after `block_user`/`unblock_user` succeed (cache already cleared).
    /// Keep-alive screens holding server content in memory (the Home feed)
    /// observe this and refetch, since the server now filters the blocked
    /// party out of every read.
    static let userBlockStateChanged = Notification.Name("userBlockStateChanged")
}

