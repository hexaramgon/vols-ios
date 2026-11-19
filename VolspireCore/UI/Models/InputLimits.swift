//
//  InputLimits.swift
//  Volspire
//
//  Every user-text cap in one place. The numbers mirror the database's CHECK
//  constraints (and the web's `lib/input-limits.ts` / Android's
//  `InputLimits`), so a client never lets through text the server rejects.
//
//  Counts are Unicode scalars, matching Postgres `char_length` (code points).
//  `String.count` counts graphemes — a family emoji is 1 grapheme but 7
//  scalars — so always measure with `limitCount` and clamp with `capped(at:)`.
//

import Foundation

enum InputLimits {
    // Profile
    static let usernameMin = 3
    static let usernameMax = 30
    static let bio = 300
    static let location = 100

    // Tags (track, pack, service, listing)
    static let maxTags = 10
    static let tag = 30

    // Tracks
    static let trackTitle = 100
    static let trackDescription = 500
    static let genre = 50
    static let creditRole = 50
    static let licenseTerms = 2000

    // Packs
    static let packName = 80
    static let packDescription = 600

    // Services
    static let serviceTitle = 80
    static let serviceDescription = 1000
    /// A package feature / deliverable item.
    static let serviceListItem = 100
    /// Max rows in any one service list (features, deliverables, steps, FAQs).
    static let serviceMaxItems = 20
    static let processStepTitle = 80
    static let processStepDetail = 300
    static let faqQuestion = 150
    static let faqAnswer = 1000

    // Clips (listing + service portfolio)
    static let clipTitle = 80

    // Listings
    static let listingTitle = 50
    static let listingDescription = 500
    static let listingMaxClips = 5

    // Conversation-style text
    static let comment = 1000
    static let message = 2000
    static let collabPitch = 2000
    /// Listing response / service inquiry.
    static let response = 2000
    static let review = 2000
    static let reportDetails = 1000

    // Collections
    static let playlistTitle = 50
    static let playlistDescription = 300
    static let folderName = 50
    static let folderDescription = 300
    static let releaseTitle = 100
    static let releaseDescription = 1000

    /// Stored file names (pack files, workspace uploads, attachments).
    static let fileName = 255
}

extension String {
    /// Length as the database counts it (Unicode scalars / code points).
    var limitCount: Int { unicodeScalars.count }

    /// The longest prefix whose scalar count fits `limit`, cut on a grapheme
    /// boundary so an emoji is never left half-built.
    func capped(at limit: Int) -> String {
        guard unicodeScalars.count > limit else { return self }
        var used = 0
        var end = startIndex
        for character in self {
            let size = character.unicodeScalars.count
            if used + size > limit { break }
            used += size
            end = index(after: end)
        }
        return String(self[..<end])
    }

    /// Newlines and other control characters folded out — for single-line
    /// fields (titles, names, tags, list items). Newlines become spaces so
    /// pasted lines don't run together.
    var singleLined: String {
        var scalars = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            if CharacterSet.newlines.contains(scalar) {
                scalars.append(" ")
            } else if !CharacterSet.controlCharacters.contains(scalar) || scalar == "\t" {
                scalars.append(scalar == "\t" ? " " : scalar)
            }
        }
        return String(scalars)
    }

    /// Trimmed of surrounding whitespace and newlines.
    var trimmedForSubmit: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Trimmed, or nil when nothing's left — for optional fields.
    var trimmedOrNil: String? {
        let t = trimmedForSubmit
        return t.isEmpty ? nil : t
    }

    /// File name capped at `InputLimits.fileName`, keeping the extension.
    var cappedFileName: String {
        guard limitCount > InputLimits.fileName else { return self }
        let ns = self as NSString
        let ext = ns.pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        let base = ns.deletingPathExtension.capped(at: max(1, InputLimits.fileName - suffix.limitCount))
        return base + suffix
    }
}
