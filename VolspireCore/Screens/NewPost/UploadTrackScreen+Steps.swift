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
        // Swapping steps while a field is focused tears the keyboard down via
        // view-removal (the focused field vanishes with the outgoing step),
        // which collapses the keyboard safe-area WITHOUT a coordinated
        // animation — the pinned bottom bar teleported instead of gliding.
        // Resign focus FIRST so the keyboard runs its normal animated
        // dismissal alongside the step slide. (Title/description have no
        // FocusState binding, so this goes through the responder chain.)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
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
        UploadBottomBar(error: viewModel.uploadState.errorMessage, hint: stepHint) {
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

                // ONE persistent CTA across every step. Continue and Publish
                // used to be two separate views (Button vs AuthCTA), so each
                // step change removed one and inserted the other — the bar
                // visibly cross-faded between "different sections". With a
                // single identity, the fill (white → gradient), label, and
                // width all morph inside the step transition instead.
                Button {
                    if step < 2 {
                        goTo(step + 1)
                    } else {
                        Task { await viewModel.upload() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isUploading {
                            ProgressView().tint(.white).controlSize(.small)
                        }
                        Text(step < 2 ? "Continue" : (isUploading ? "Uploading…" : "Publish Track"))
                            .font(.appHeadline)
                    }
                    .foregroundStyle(ctaForeground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(ctaFill)
                    }
                }
                .buttonStyle(AuthPress())
                .disabled(!stepComplete || isUploading)
                .animation(.easeInOut(duration: 0.2), value: stepComplete)
                .animation(.easeInOut(duration: 0.2), value: isUploading)
            }
        }
    }

    /// Disabled reads the same on every step (AuthCTA's dim treatment);
    /// enabled is white/black while stepping and the gradient at publish.
    private var ctaForeground: Color {
        if !stepComplete, !isUploading { return Color.vText3 }
        return step < 2 ? .black : .white
    }

    private var ctaFill: AnyShapeStyle {
        if !stepComplete, !isUploading { return AnyShapeStyle(Color.white.opacity(0.06)) }
        return step < 2 ? AnyShapeStyle(Color.white) : AnyShapeStyle(LinearGradient.sendAccent)
    }

}
