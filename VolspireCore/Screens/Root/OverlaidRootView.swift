//
//  OverlaidRootView.swift
//  Volspire
//
//

import DesignSystem
import Foundation
import Kingfisher
import SwiftUI

struct OverlaidRootView: View {
    @State private var expandSheet: Bool = false
    @State private var conversationState = ConversationState()
    @State private var avatarPreview = AvatarPreviewState()
    /// Post-publish confirmation card ("Track uploaded") — flashed over the
    /// whole app AFTER the create form's sheet has slid away.
    @State private var uploadConfirmation: UploadConfirmation?
    /// Full-resolution image for the attachment preview's pinch-zoom viewer —
    /// fetched when the preview opens, cleared when it closes.
    @State private var attachmentImage: UIImage?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(PlayerController.self) var playerController

    private struct UploadConfirmation: Equatable {
        let title: String
        var subtitle: String?
        /// Set for a new post — once the card dismisses, the app opens the
        /// posted content (track → expanded player, listing → detail page).
        var trackId: String?
        var listingId: String?
    }

    private var showMiniPlayer: Bool {
        playerController.display.title.isEmpty == false
    }

    private var isConversationActive: Bool {
        conversationState.activeConversation != nil
    }

    private var collapsedFrame: CGRect {
        // Position the collapsed mini-player above the tab bar
        let tabBarHeight: CGFloat = 49
        let bottomPadding: CGFloat = 8
        let horizontalPadding: CGFloat = 8
        let height = ViewConst.compactNowPlayingHeight
        let screenWidth = UIScreen.size.width
        let screenHeight = UIScreen.size.height
        let safeAreaBottom = ViewConst.safeAreaInsets.bottom

        return CGRect(
            x: horizontalPadding,
            y: screenHeight - safeAreaBottom - tabBarHeight - bottomPadding - height,
            width: screenWidth - (horizontalPadding * 2),
            height: height
        )
    }

    var body: some View {
        RootTabView()
            .animation(.easeInOut(duration: 0.2), value: showMiniPlayer)
            .overlay {
                // Wrapper + scoped animation so the mini player's insert/remove
                // (when a track starts / clears) actually animates — the
                // `.animation` on RootTabView above doesn't reach into the overlay.
                ZStack {
                    if showMiniPlayer {
                        ExpandableNowPlaying(
                            show: .constant(true),
                            expanded: $expandSheet,
                            collapsedFrame: collapsedFrame
                        )
                        // Clear the mini-player inside a conversation — the chat is
                        // full-screen and its input bar owns the bottom.
                        .offset(y: isConversationActive ? 140 : 0)
                        .opacity(isConversationActive ? 0 : 1)
                        .allowsHitTesting(!isConversationActive)
                        // Same curve as the tab bar's hide in RootTabView so the two
                        // move as one piece.
                        .animation(.smooth(duration: 0.35), value: isConversationActive)
                        .toolbarColorScheme(colorScheme, for: .navigationBar)
                        // Slide up + fade in when a track starts (reverse on clear)
                        // instead of popping in/out.
                        .transition(.offset(y: 70).combined(with: .opacity))
                    }
                }
                .animation(.smooth(duration: 0.4), value: showMiniPlayer)
            }
            // In-hierarchy so its glass material can blur the player beneath
            // (a fullScreenCover's material can't see through the presentation).
            .overlay { aboutModalOverlay }
            // Above the mini-player + tab bar so the avatar zoom covers everything.
            .overlay { avatarPreviewOverlay }
            .overlay { uploadConfirmationOverlay }
            .environment(conversationState)
            .environment(avatarPreview)
            .onReceive(NotificationCenter.default.publisher(for: .ownContentPosted)) { note in
                guard let title = note.userInfo?["confirmationTitle"] as? String else { return }
                let subtitle = note.userInfo?["confirmationSubtitle"] as? String
                // Let the form's sheet finish sliding down, then flash the card.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    let confirmation = UploadConfirmation(
                        title: title,
                        subtitle: subtitle,
                        trackId: note.userInfo?["trackId"] as? String,
                        listingId: note.userInfo?["listingId"] as? String
                    )
                    withAnimation(.easeOut(duration: 0.22)) { uploadConfirmation = confirmation }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        // Don't clear a newer card that replaced this one mid-flight.
                        guard uploadConfirmation == confirmation else { return }
                        dismissConfirmation(confirmation)
                    }
                }
            }
            // Playback fully cleared (blocking the playing artist, sign-out)
            // while the sheet was expanded: the overlay unmounts on its own,
            // but the flag must drop too or the next track would mount
            // straight into the expanded state.
            .onChange(of: showMiniPlayer) { _, showing in
                if !showing { expandSheet = false }
            }
            .onChange(of: playerController.pendingProfileNavigation) { _, userId in
                guard let userId else { return }
                // Collapse the player
                withAnimation(.playerExpandAnimation) {
                    expandSheet = false
                }
                // Post notification so the active tab can navigate
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(
                        name: .navigateToProfile,
                        object: nil,
                        userInfo: ["userId": userId]
                    )
                    playerController.pendingProfileNavigation = nil
                }
            }
            .onChange(of: playerController.pendingExpand) { _, expand in
                guard expand else { return }
                // Tapping a workspace file opens straight into the (comments) player.
                withAnimation(.playerExpandAnimation) { expandSheet = true }
                playerController.pendingExpand = false
            }
    }
}

private extension OverlaidRootView {
    /// The track About dialog (glass card over the expanded player) — mounted
    /// here so the material genuinely blurs what's behind it.
    @ViewBuilder
    var aboutModalOverlay: some View {
        if let payload = playerController.aboutModal {
            PlayerAboutModal(payload: payload) {
                playerController.aboutModal = nil
            }
        }
    }

    /// The post-publish confirmation card — tap anywhere to dismiss early.
    @ViewBuilder
    var uploadConfirmationOverlay: some View {
        if let confirmation = uploadConfirmation {
            UploadSuccessOverlay(title: confirmation.title, subtitle: confirmation.subtitle)
                .onTapGesture { dismissConfirmation(confirmation) }
                .transition(.opacity)
        }
    }

    /// Hides the card, then — for a fresh post — hands off to RootTabView to
    /// open what was just posted (track → expanded player, listing → detail).
    /// The card always completes first, so the reveal never fights the sheet
    /// dismissal or the confirmation animation.
    private func dismissConfirmation(_ confirmation: UploadConfirmation) {
        withAnimation(.easeIn(duration: 0.25)) { uploadConfirmation = nil }
        var info: [String: Any] = [:]
        if let id = confirmation.trackId { info["trackId"] = id }
        if let id = confirmation.listingId { info["listingId"] = id }
        guard !info.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NotificationCenter.default.post(name: .openOwnPost, object: nil, userInfo: info)
        }
    }

    @ViewBuilder
    var avatarPreviewOverlay: some View {
        if avatarPreview.mounted, let url = avatarPreview.url {
            if avatarPreview.circular {
                circularAvatarZoom(url)
            } else {
                imageAttachmentPreview(url)
            }
        }
    }

    /// Profile avatars: one circular image grows from the tapped frame to a large
    /// centred circle over a dimmed app, and shrinks back (unchanged).
    private func circularAvatarZoom(_ url: URL) -> some View {
        let f = avatarPreview.sourceFrame
        let big = min(UIScreen.size.width - 56, 340)
        let w = avatarPreview.zoomed ? big : f.width
        let h = avatarPreview.zoomed ? big : f.height
        let cx = avatarPreview.zoomed ? UIScreen.size.width / 2 : f.midX
        let cy = avatarPreview.zoomed ? UIScreen.size.height / 2 : f.midY
        return ZStack {
            Color.black.opacity(avatarPreview.zoomed ? 0.92 : 0).ignoresSafeArea()

            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: w, height: h)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.5), radius: avatarPreview.zoomed ? 28 : 14, y: avatarPreview.zoomed ? 12 : 6)
                .position(x: cx, y: cy)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { avatarPreview.dismiss() }
    }

    /// Message image attachments: a centred full-screen viewer that fades in.
    /// Once the full image is in it's UIScrollView-backed — pinch or double-tap
    /// to zoom, pan while zoomed — and a single tap anywhere dismisses. The
    /// bubble's already-decoded thumbnail shows on frame 0 while the full image
    /// loads, so the black backdrop never out-races the picture.
    private func imageAttachmentPreview(_ url: URL) -> some View {
        let thumbKey = attachmentCacheKey(url)
        let px = 220 * UIScreen.main.scale
        let cached = ImageCache.default.retrieveImageInMemoryCache(
            forKey: thumbKey,
            options: [.processor(DownsamplingImageProcessor(size: CGSize(width: px, height: px)))]
        ) ?? ImageCache.default.retrieveImageInMemoryCache(forKey: thumbKey)

        return VStack(spacing: 0) {
            attachmentHeader

            // The image fits in the space UNDER the header — the zoom viewer
            // aspect-fits within these bounds, so nothing sits behind the bar.
            // The viewer area starts below the header, so plain centring within
            // it sits the photo headerHeight/2 BELOW the screen's centre — and
            // against the near-black chrome that reads as "not centred". Bias
            // the image up by half the header so its centre lands on the
            // screen's centre (clamped: tall photos still never go under the bar).
            let headerHeight = ViewConst.safeAreaInsets.top + 44
            ZStack {
                Color.black
                if let attachmentImage {
                    ZoomableAttachmentViewer(image: attachmentImage, verticalBias: headerHeight / 2) {
                        avatarPreview.dismiss()
                    }
                } else if let cached {
                    // Thumbnail stand-in until the full image lands — same
                    // aspect-fit placement as the zoom viewer's rest state.
                    Image(uiImage: cached).resizable().scaledToFit()
                        .offset(y: -headerHeight / 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { avatarPreview.dismiss() }
        }
        .opacity(avatarPreview.zoomed ? 1 : 0)
        .ignoresSafeArea()
        .task(id: url) { attachmentImage = await loadAttachmentImage(url, cacheKey: thumbKey) }
        .onDisappear { attachmentImage = nil }
    }

    /// Chrome bar over the attachment viewer — the app's bar tone, a centred
    /// title, and an "X" close on the right (cropper-style button).
    private var attachmentHeader: some View {
        ZStack {
            Text("Photo Attachment")
                .font(.appCalloutSemibold)
                .foregroundStyle(.white)

            HStack {
                Spacer(minLength: 0)
                Button { avatarPreview.dismiss() } label: {
                    LucideIcon(.x, .xxl)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
        }
        .frame(height: 44)
        .padding(.top, ViewConst.safeAreaInsets.top)
        .background(Color.vBar)
    }

    /// Fetches the full-resolution attachment through Kingfisher — same
    /// normalized cache key as the bubbles, so re-signed URLs reuse the cache.
    private func loadAttachmentImage(_ url: URL, cacheKey: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            KingfisherManager.shared.retrieveImage(
                with: KF.ImageResource(downloadURL: url, cacheKey: cacheKey)
            ) { result in
                continuation.resume(returning: try? result.get().image)
            }
        }
    }
}

// MARK: - Pinch-zoom attachment viewer

/// UIScrollView that reports layout passes so the zoom scales can be set once
/// real bounds exist (same trick as the cropper's CropScrollView).
private final class ZoomScrollView: UIScrollView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// Pinch-zoom viewer for the attachment preview — aspect-fit at rest, pinch or
/// double-tap to zoom, pan while zoomed. A UIScrollView owns the zoom/pan math
/// (same reasoning as the cropper: more reliable than SwiftUI gestures).
private struct ZoomableAttachmentViewer: UIViewRepresentable {
    let image: UIImage
    /// Shifts the at-rest image up so it centres on the SCREEN rather than in
    /// this view's own (below-the-header) bounds. Clamped in `centerImage`.
    var verticalBias: CGFloat = 0
    /// Called on a plain tap (dismiss) — double-taps zoom instead.
    let onSingleTap: () -> Void

    func makeUIView(context: Context) -> ZoomScrollView {
        let scrollView = ZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.verticalBias = verticalBias

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleSingleTap)
        )
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        scrollView.onLayout = { [weak scrollView] in
            guard let scrollView else { return }
            context.coordinator.fitIfNeeded(scrollView)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: ZoomScrollView, context: Context) {
        context.coordinator.fitIfNeeded(scrollView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var onSingleTap: () -> Void = {}
        var verticalBias: CGFloat = 0
        /// Bounds the zoom scales were computed for — recomputed if they change.
        private var fittedBounds: CGSize = .zero

        /// Aspect-fits the image once the scroll view has real bounds: fit is
        /// the min zoom, 4× fit the max, centred via `contentInset`.
        func fitIfNeeded(_ scrollView: UIScrollView) {
            guard let imageView, scrollView.bounds.width > 1, scrollView.bounds.height > 1 else { return }
            // Re-centre on every layout pass (cheap, self-healing); the full
            // zoom re-fit below only runs when the bounds actually change.
            defer { centerImage(scrollView) }
            guard scrollView.bounds.size != fittedBounds else { return }
            let imageSize = imageView.image?.size ?? .zero
            guard imageSize.width > 0, imageSize.height > 0 else { return }
            fittedBounds = scrollView.bounds.size

            imageView.frame = CGRect(origin: .zero, size: imageSize)
            scrollView.contentSize = imageSize
            let box = scrollView.bounds.size
            let fit = min(box.width / imageSize.width, box.height / imageSize.height)
            scrollView.minimumZoomScale = fit
            scrollView.maximumZoomScale = max(fit * 4, 1)
            scrollView.zoomScale = fit
            scrollView.contentOffset = .zero
            centerImage(scrollView)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage(scrollView) }

        /// Keeps the image centred while it's smaller than the viewport — by
        /// moving the image view's frame (the PhotoScroller pattern), which is
        /// deterministic; inset-based centring drifts because the rest offset
        /// doesn't track late-set insets. `verticalBias` lifts the rest position
        /// so the image centres on the screen, not this below-the-header box —
        /// clamped to 0 so it can never poke out of the top.
        private func centerImage(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let box = scrollView.bounds.size
            var frame = imageView.frame
            frame.origin.x = frame.width < box.width ? (box.width - frame.width) / 2 : 0
            frame.origin.y = frame.height < box.height
                ? max(0, (box.height - frame.height) / 2 - verticalBias)
                : 0
            imageView.frame = frame
        }

        @objc func handleSingleTap() { onSingleTap() }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView, let imageView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale * 1.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                // Zoom to ~2.5× around the tapped point.
                let scale = min(scrollView.minimumZoomScale * 2.5, scrollView.maximumZoomScale)
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
                scrollView.zoom(
                    to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                               width: size.width, height: size.height),
                    animated: true
                )
            }
        }
    }
}

extension Notification.Name {
    static let navigateToProfile = Notification.Name("navigateToProfile")
    /// Posted after the signed-in user publishes content (track upload, collab
    /// listing). Two listeners: the kept-alive own-profile tab refreshes in
    /// place (so the new post shows without a relaunch), and OverlaidRootView
    /// flashes the confirmation card from `confirmationTitle`/`-Subtitle`
    /// userInfo once the form's sheet has slid away.
    static let ownContentPosted = Notification.Name("ownContentPosted")
    /// Posted by the confirmation card's dismissal when the post carries an id —
    /// RootTabView opens the content (userInfo: "trackId" or "listingId").
    static let openOwnPost = Notification.Name("openOwnPost")
    /// Posted by AppDelegate when a push notification is tapped — RootTabView
    /// drains `PushInbox.pending` and deep-links to the referenced entity.
    static let openPushNotification = Notification.Name("openPushNotification")
}

/// A tapped push notification's data, buffered until the tab UI is ready to route
/// it — covers cold launch, where the tap arrives before RootTabView has mounted.
enum PushInbox {
    @MainActor static var pending: [String: String]?
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub

    OverlaidRootView()
        .environment(playerController)
        .environment(dependencies)
}
