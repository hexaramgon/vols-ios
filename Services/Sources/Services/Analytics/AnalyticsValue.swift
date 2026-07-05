//
//  AnalyticsValue.swift
//  Volspire
//
//  A transport-neutral JSON value used for analytics event metadata. Keeping the
//  event model free of any vendor's JSON type is what lets the backend sink be
//  swapped (Supabase → PostHog/Segment/…) without touching a single call site.
//

import Foundation

public enum AnalyticsValue: Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([AnalyticsValue])
    case object([String: AnalyticsValue])
}

extension AnalyticsValue: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

// Ergonomic literals so call sites read like plain dictionaries:
//   ["source": "library", "duration": 217, "completion_pct": 84, "ok": true]
extension AnalyticsValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension AnalyticsValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension AnalyticsValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension AnalyticsValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension AnalyticsValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension AnalyticsValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: AnalyticsValue...) { self = .array(elements) }
}

extension AnalyticsValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, AnalyticsValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}
