//
//  UploadTrackScreen+Steps.swift
//  Volspire
//
//  Step machinery (header, navigation) and the Back / Continue / Publish bottom bar.
//

import CoreTransferable
import DesignSystem
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension UploadTrackScreen {
    // MARK: - Header + step machinery

    var header: some View {
        UploadFlowHeader(icon: .music, title: "Upload Track") { dismiss() }
    }

    func goTo(_ newStep: Int) {
        stepDirection = newStep > step ? .trailing : .leading
        withAnimation(.smooth(duration: 0.35)) { step = newStep }
    }

    /// Shared scroll shell for each step's sections.
    func stepScroll(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28, content: content)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        // Tap on inert space drops the keyboard (fields/buttons still win the tap).
        .tapToDismissKeyboard()
    }

    // MARK: - Bottom bar (Back / Continue / Publish + per-step status)

    /// Whether the current step's requirements are met (gates Continue/Publish).
    var stepComplete: Bool {
        switch step {
        case 0: viewModel.mediaAttached && !viewModel.isProcessingVideo
        case 1: detailsComplete
        default: viewModel.canUpload
        }
    }

    var detailsComplete: Bool {
        !viewModel.title.trimmingCharacters(in: .whitespaces).isEmpty
            && !viewModel.genre.isEmpty
            && viewModel.coverData != nil
    }

    var stepHint: String? {
        switch step {
        case 0: viewModel.mediaAttached ? nil : "Add an audio or video file to continue"
        case 1: detailsComplete ? nil : "Add a cover, title, and genre to continue"
        default: viewModel.tierValidation
        }
    }

    var bottomBar: some View {
        VStack(spacing: 10) {
            if case .error(let message) = viewModel.uploadState {
                statusRow(message, color: UploadTheme.errorText)
            } else if let hint = stepHint {
                statusRow(hint, color: Color.vText3)
            }

            HStack(spacing: 10) {
                if step > 0 {
                    Button {
                        goTo(step - 1)
                    } label: {
                        Text("Back")
                            .font(.appHeadline)
                            .foregroundStyle(.white)
                            .frame(width: 92)
                            .frame(height: 54)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploading)
                }

                if step < 2 {
                    // Plain white while stepping through — the gradient is
                    // saved for the actual publish moment.
                    Button {
                        goTo(step + 1)
                    } label: {
                        Text("Continue")
                            .font(.appHeadline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!stepComplete)
                    .opacity(stepComplete ? 1 : 0.3)
                } else {
                    // Publish gets the gradient CTA (same as the auth pages).
                    AuthCTA(
                        title: "Publish Track",
                        loadingTitle: "Uploading…",
                        isLoading: isUploading,
                        isDisabled: !stepComplete
                    ) {
                        Task { await viewModel.upload() }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            Color.vBar
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.vBorder)
                        .frame(height: 1)
                }
                .ignoresSafeArea()
        }
    }

    func statusRow(_ message: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            LucideIcon(.triangleAlert, .sm)
                .foregroundStyle(color)
            Text(message)
                .font(.appFootnote)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}
