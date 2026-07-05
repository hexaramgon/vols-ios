//
//  LeaseOptionsSheet.swift
//  Volspire
//
//  "Lease" — shows the track's license tiers (free / creator / pro / exclusive)
//  with their price and perks, mirroring the web app's licensing UI. Display only;
//  checkout stays on the web.
//

import DesignSystem
import Services
import SwiftUI

struct LeaseOptionsSheet: View {
    let trackId: String

    @State private var licenses: [ApiTrackLicense] = []
    @State private var isLoading = true

    private let service = SupabaseService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .sheetBackground()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("License this track")
                .font(.appTitle2)
            Text("Leasing options for this track")
                .font(.appFootnote)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .tint(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if licenses.isEmpty {
            Text("No licenses available for this track.")
                .font(.appSubheadline)
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 60)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(licenses) { license in
                        licenseCard(license)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
    }

    private func licenseCard(_ license: ApiTrackLicense) -> some View {
        let display = LicenseDisplay.forType(license.licenseType)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("License")
                    .font(.appMicroSemibold)
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                if let badge = display.badge {
                    Text(badge)
                        .font(.appNanoBold)
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(display.label)
                    .font(.appCalloutSemibold)
                Text(priceString(license))
                    .font(.appTitleXXL)
                    .monospacedDigit()
            }

            if let terms = license.terms, !terms.isEmpty {
                Text(terms)
                    .font(.appCaption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            if !display.perks.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(display.perks, id: \.self) { perk in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.top, 1)
                            Text(perk)
                                .font(.appFootnote)
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(display.isExclusive ? Color.orange.opacity(0.35) : Color.white.opacity(0.08))
        )
    }

    private func priceString(_ license: ApiTrackLicense) -> String {
        guard license.price > 0 else { return "Free" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = license.currency ?? "USD"
        return formatter.string(from: NSNumber(value: license.price)) ?? "$\(license.price)"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let fetched = (try? await service.getTrackLicenses(trackId: trackId)) ?? []
        licenses = fetched.sorted { $0.price < $1.price }
    }
}

// MARK: - Tier display (mirrors the web's LICENSE_DISPLAY)

private struct LicenseDisplay {
    let label: String
    let badge: String?
    let perks: [String]
    let isExclusive: Bool

    static func forType(_ type: String) -> LicenseDisplay {
        switch type.lowercased() {
        case "free":
            return .init(label: "Free / Stream", badge: nil, perks: [
                "Stream the track on Volspire",
                "Free download of the master",
                "Add to your workspace",
            ], isExclusive: false)
        case "creator":
            return .init(label: "Creator", badge: nil, perks: [
                "Non-exclusive commercial use",
                "MP3 or WAV download",
                "Monetization allowed",
                "Best for indie artists & small projects",
            ], isExclusive: false)
        case "pro":
            return .init(label: "Pro", badge: nil, perks: [
                "Non-exclusive commercial use",
                "WAV + stems included",
                "Monetization allowed",
                "Better for remixes & collaboration",
            ], isExclusive: false)
        case "exclusive":
            return .init(label: "Exclusive", badge: "Exclusive", perks: [
                "Full ownership transfer",
                "WAV + stems (plus MP3 if uploaded)",
                "Track is removed from the marketplace",
                "No future licenses can be sold",
            ], isExclusive: true)
        default:
            return .init(label: type.capitalized, badge: nil, perks: [], isExclusive: false)
        }
    }
}
