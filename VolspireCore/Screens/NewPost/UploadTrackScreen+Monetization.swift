//
//  UploadTrackScreen+Monetization.swift
//  Volspire
//
//  Buyer downloads, distribution tiers, the collaboration flag, and privacy.
//

import CoreTransferable
import DesignSystem
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension UploadTrackScreen {
    // MARK: - Buyer downloads (per-tier assets, uploaded once)

    var buyerDownloadsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Buyer Downloads")

            Text("Files paying buyers get after they purchase. Upload each format once — the paid tiers below decide who gets what.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)
            Text("All optional. Skip if you only enable Free / Stream.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText3)

            assetRow(
                kind: "mp3",
                label: "MP3",
                hint: "Lossy audio. Included with Creator and Exclusive.",
                fileName: viewModel.mp3FileName,
                bytes: viewModel.mp3Data?.count
            )
            assetRow(
                kind: "wav",
                label: "WAV",
                hint: "Lossless, production-grade. Included with Creator, Pro, and Exclusive.",
                fileName: viewModel.wavFileName,
                bytes: viewModel.wavData?.count
            )
            assetRow(
                kind: "stems",
                label: "Stems (zip)",
                hint: "Multitrack zip for remixing. Included with Pro and Exclusive.",
                fileName: viewModel.stemsFileName,
                bytes: viewModel.stemsData?.count
            )
        }
    }

    func assetRow(
        kind: String, label: String, hint: String, fileName: String?, bytes: Int?
    ) -> some View {
        let attached = bytes != nil
        return Button {
            guard !attached else { return }
            pickingAssetKind = kind
            showAssetPicker = true
        } label: {
            HStack(spacing: 12) {
                iconBox(.fileAudio)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(label)
                            .font(.appBodyMedium)
                            .foregroundStyle(attached ? .white : Color.vText2)
                        if !attached {
                            Text("· optional")
                                .font(.appFootnote)
                                .foregroundStyle(Color.vText3)
                        }
                    }
                    if let fileName, let bytes {
                        Text("\(fileName) · \(UploadClipRows.formatBytes(bytes))")
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(hint)
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                if attached {
                    Button {
                        viewModel.clearAsset(kind: kind)
                    } label: {
                        LucideIcon(.trash2, .sm)
                            .foregroundStyle(Color.vText3)
                            .frame(width: 40, height: 40)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                } else {
                    LucideIcon(.upload, .sm)
                        .foregroundStyle(Color.vText3)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(attached ? UploadTheme.fieldFill : Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        UploadTheme.border,
                        style: attached ? StrokeStyle(lineWidth: 1) : UploadTheme.dashed
                    )
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Distribution & Monetization (tiers)

    var distributionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider(FeatureFlags.marketplace ? "Distribution & Monetization" : "Distribution")

            Text(FeatureFlags.marketplace
                ? "Free stream and download are always on. Toggle paid tiers to sell format-specific bundles on top."
                : "Every track is free to stream and download.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)

            // Only the free tier while monetization is gated off (matches the web).
            ForEach(FeatureFlags.marketplace ? Array(TrackTier.allCases) : [.free], id: \.self) { tier in
                tierCard(tier)
            }

            if let tierValidation = viewModel.tierValidation {
                HStack(spacing: 8) {
                    LucideIcon(.triangleAlert, .xs)
                    Text(tierValidation)
                        .font(.appFootnote)
                }
                .foregroundStyle(UploadTheme.warningText)
            }
        }
    }

    func tierCard(_ tier: TrackTier) -> some View {
        let enabled = viewModel.tierEnabled[tier] == true
        let isFree = tier == .free
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                guard !isFree else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    viewModel.setTier(tier, enabled: !enabled)
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tier.label)
                            .font(.appBodyMedium)
                            .foregroundStyle(enabled ? .white : Color.vText2)
                        Text(tier.blurb)
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    UploadSwitch(isOn: enabled)
                        .opacity(isFree ? 0.3 : 1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isFree)

            if enabled, !isFree {
                HStack(spacing: 6) {
                    Text("$")
                        .font(.appBody)
                        .foregroundStyle(Color.vText3)
                    TextField(
                        "",
                        text: Binding(
                            get: { viewModel.tierPrice[tier] ?? "" },
                            set: { viewModel.tierPrice[tier] = $0.filter { "0123456789.".contains($0) } }
                        ),
                        prompt: Text("0.00").foregroundStyle(Color.vText3)
                    )
                    .font(.appBody)
                    .foregroundStyle(.white)
                    .keyboardType(.decimalPad)
                    .focused($priceFieldFocused)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                priceFieldFocused = false
                            }
                            .font(.appCallout)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .uploadFieldShell()

                let included = viewModel.includedAssets(for: tier)
                if included.isEmpty {
                    Text("Missing required files")
                        .font(.appFootnote)
                        .foregroundStyle(UploadTheme.warningText)
                } else {
                    ChipFlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(included, id: \.self) { kind in
                            Text(kind.uppercased())
                                .font(.appLabel)
                                .foregroundStyle(Color.vText2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                                .overlay(Capsule().strokeBorder(Color.vBorder, lineWidth: 1))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(enabled ? UploadTheme.fieldFill : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(enabled ? Color.white.opacity(0.25) : Color.vBorder, lineWidth: 1)
        )
    }

    // MARK: - Collaboration flag

    var collaborationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            UploadSectionDivider("Collaboration")

            UploadToggleRow(
                label: "Looking for collaborators on this track",
                hint: "Your track shows in the Looking for Collab feed. Other artists can DM you to offer.",
                isOn: $viewModel.lookingForCollab
            )
        }
    }

    // MARK: - Privacy

    var privacySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            UploadSectionDivider("Privacy & Release")

            HStack(spacing: 8) {
                UploadPill("Public", icon: .globe, expands: true, selected: viewModel.visibility == "public") {
                    viewModel.visibility = "public"
                }
                UploadPill("Private", icon: .lock, expands: true, selected: viewModel.visibility == "private") {
                    viewModel.visibility = "private"
                }
            }
        }
    }
}
