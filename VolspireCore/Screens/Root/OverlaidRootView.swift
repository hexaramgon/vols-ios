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
    /// The viewer's Save button: nil idle, true saved (✓), false failed (!).
    @State private var attachmentSaved: Bool?
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
        playerController.hasMedia
    }

    private var isConversationActive: Bool {
        conversationState.activeConversation != nil
    }

    /// Slide the mini player away for a full-screen conversation or under
    /// Explore's search.
    private var hideBottomChrome: Bool {
        isConversationActive || conversationState.searchOpen
    }

    // A bottom composer's keyboard (listing comments) changes NOTHING here: the
    // mini player doesn't slide, fade or hide — it stays exactly where it is,
    // fully visible, and the keyboard simply rises over it (Hector, 2026-11-07).

    private var collapsedFrame: CGRect {
        // Position the collapsed mini-player above the tab bar (measured —
        // the bar's height varies with Dynamic Type).
        let tabBarHeight = playerController.tabBarHeight
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
                            expanded: $expandSheet,
                            collapsedFrame: collapsedFrame
                        )
                        // Clear the mini-player inside a conversation (its input bar
                        // owns the bottom) or under search.
                        .offset(y: hideBottomChrome ? 140 : 0)
                        .opacity(hideBottomChrome ? 0 : 1)
                        .allowsHitTesting(!hideBottomChrome)
                        // Conversation hide keeps its tuned spring.
                        .animation(.smooth(duration: 0.35), value: isConversationActive)
                        .animation(.easeInOut(duration: 0.25), value: conversationState.searchOpen)
                        // Slide up + fade in when a track starts (reverse on clear)
                        // instead of popping in/out.
                        .transition(.offset(y: 70).combined(with: .opacity))
                    }
                }
                .animation(.smooth(duration: 0.4), value: showMiniPlayer)
                // Like the tab bar (RootTabView), the player stays put when a
                // keyboard opens — it slides under it instead of riding up
                // over the page. (Composers that own the bottom hide it via
                // hideBottomChrome.)
                .ignoresSafeArea(.keyboard)
            }
            // In-hierarchy so its glass material can blur the player beneath
            // (a fullScreenCover's material can't see through the presentation).
            .overlay { aboutModalOverlay }
            // Above the mini-player + tab bar so the avatar zoom covers everything.
            .overlay { avatarPreviewOverlay }
            .overlay { uploadConfirmationOverlay }
            // Action toasts ("Track deleted", "Blocked @user") — just above the
            // tab bar / mini-player. The overlay already sits inside the safe
            // area, so no window inset here: reading UIKit's safeAreaInsets in
            // this body made a cold launch from a stored session re-enter the
            // graph (an AttributeGraph cycle) and froze every overlay below —
            // intro tips showed their dim with no content.
            .overlay(alignment: .bottom) {
                ToastHost()
                    .padding(.bottom, playerController.tabBarHeight + playerController.miniPlayerAllowance + 10)
            }
            // Pushes that arrive while the app is open — the app's own banner
            // (top, inside the safe area), not the system's.
            .overlay(alignment: .top) { PushBannerHost() }
            // First-visit section explainers (IntroModal.swift), over everything.
            .overlay { IntroModalHost() }
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
                    Haptics.success()
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

    /// Message photos, Photos-app style: always on black (light mode too),
    /// with floating glass Close / Save. The photo grows out of its bubble
    /// (rounded corners easing square) to fit the screen, then hands over to
    /// the pinch / double-tap zoom viewer; tap or swipe down to dismiss, and it
    /// shrinks back into the bubble. The bubble's decoded thumbnail stands in
    /// until the full image lands, so the hero never starts empty.
    private func imageAttachmentPreview(_ url: URL) -> some View {
        let thumbKey = attachmentCacheKey(url)
        let thumb = Self.cachedThumbnail(forKey: thumbKey)
        let shown = attachmentImage ?? thumb
        let screen = UIScreen.size
        // No pixels yet → the photo's remembered aspect (the bubble's frame is
        // clamped/cropped, so growing to it would snap when the image lands).
        let fallback = ChatImageAspects.get(thumbKey).map { CGSize(width: $0, height: 1) }
            ?? avatarPreview.sourceFrame.size
        let fitted = Self.fittedRect(for: shown?.size, in: screen, fallback: fallback)
        let dragFade = min(abs(avatarPreview.dragY) / 420, 0.7)

        return ZStack {
            Color.black
                .opacity(avatarPreview.zoomed ? 1 - dragFade : 0)
                .ignoresSafeArea()

            if avatarPreview.settled, let shown {
                ZoomableAttachmentViewer(
                    image: shown,
                    onSingleTap: { avatarPreview.dismiss() },
                    onDrag: { avatarPreview.dragY = $0 },
                    onDragEnd: { dy, velocity in
                        if abs(dy) > 110 || abs(velocity) > 900 {
                            avatarPreview.dismiss()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { avatarPreview.dragY = 0 }
                        }
                    }
                )
                // The full image swaps into this same viewer in place (no
                // rebuild — rebuilding flashed / reset the zoom on first open).
                .offset(y: avatarPreview.dragY)
                .ignoresSafeArea()
            } else {
                attachmentHero(shown, fitted: fitted)
            }

            attachmentControls(shown)
                .opacity(avatarPreview.settled && avatarPreview.dragY == 0 ? 1 : 0)
                .animation(.easeOut(duration: 0.18), value: avatarPreview.settled)
                .animation(.easeOut(duration: 0.18), value: avatarPreview.dragY == 0)
        }
        // Immersive: the status bar would be dark-on-black in light mode.
        .statusBarHidden(avatarPreview.zoomed)
        .task(id: url) { attachmentImage = await loadAttachmentImage(url, cacheKey: thumbKey) }
        .onDisappear { attachmentImage = nil; attachmentSaved = nil }
    }

    /// The animating copy: at the bubble's frame (rounded like the bubble)
    /// when closed, the screen-fitted rect (square corners) when open — plus
    /// the live drag, so a swipe-dismiss shrinks home from where you let go.
    private func attachmentHero(_ image: UIImage?, fitted: CGRect) -> some View {
        let f = avatarPreview.sourceFrame
        let open = avatarPreview.zoomed
        let rect = open ? fitted.offsetBy(dx: 0, dy: avatarPreview.dragY) : f
        return Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.vSkeleton
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(RoundedRectangle(cornerRadius: open ? 0 : 18, style: .continuous))
        .position(x: rect.midX, y: rect.midY)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { avatarPreview.dismiss() }
    }

    /// Floating glass Close (top-left), Save (top-right), always
    /// light-on-dark. Save appears once the full-quality image is in.
    private func attachmentControls(_ image: UIImage?) -> some View {
        VStack {
            HStack(spacing: 10) {
                glassButton(.x, label: "Close") { avatarPreview.dismiss() }
                Spacer(minLength: 0)
                if let full = attachmentImage {
                    glassButton(
                        attachmentSaved == true ? .check : (attachmentSaved == false ? .triangleAlert : .download),
                        label: attachmentSaved == true ? "Saved to Photos" : "Save to Photos"
                    ) {
                        guard attachmentSaved != true else { return }
                        Task {
                            let ok = await AttachmentDownloads.saveToPhotos(full, name: avatarPreview.name)
                            if ok {
                                Haptics.success()
                                ToastCenter.shared.show("Saved to Photos")
                            } else {
                                ToastCenter.shared.show("Couldn't save the photo. Check Volspire's Photos access in Settings.", style: .error)
                            }
                            withAnimation(.smooth(duration: 0.2)) { attachmentSaved = ok }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, ViewConst.safeAreaInsets.top + 4)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    private func glassButton(_ icon: LucideIcon.Name, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LucideIcon(icon, .lg)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The bubble's already-decoded thumbnail (its downsample size, then any
    /// size) so the hero has pixels on frame 0.
    private static func cachedThumbnail(forKey key: String) -> UIImage? {
        for side in [480.0, 220.0] {
            let px = side * UIScreen.displayScale
            if let img = ImageCache.default.retrieveImageInMemoryCache(
                forKey: key,
                options: [.processor(DownsamplingImageProcessor(size: CGSize(width: px, height: px)))]
            ) { return img }
        }
        return ImageCache.default.retrieveImageInMemoryCache(forKey: key)
    }

    /// Aspect-fit rect for an image of `size` centred on the screen — matches
    /// the zoom viewer's rest position, so the hand-over doesn't jump.
    private static func fittedRect(for size: CGSize?, in screen: CGSize, fallback: CGSize) -> CGRect {
        let s = (size?.width ?? 0) > 0 && (size?.height ?? 0) > 0 ? size! : fallback
        guard s.width > 0, s.height > 0 else { return CGRect(origin: .zero, size: screen) }
        let k = min(screen.width / s.width, screen.height / s.height)
        let w = s.width * k, h = s.height * k
        return CGRect(x: (screen.width - w) / 2, y: (screen.height - h) / 2, width: w, height: h)
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
    /// Called on a plain tap (dismiss) — double-taps zoom instead.
    let onSingleTap: () -> Void
    /// Swipe-down-to-dismiss (only at rest zoom): live vertical offset, then
    /// the release (offset, vertical velocity).
    var onDrag: (CGFloat) -> Void = { _ in }
    var onDragEnd: (CGFloat, CGFloat) -> Void = { _, _ in }

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
        context.coordinator.onDrag = onDrag
        context.coordinator.onDragEnd = onDragEnd

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
        let pan = UIPanGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        scrollView.addGestureRecognizer(pan)

        scrollView.onLayout = { [weak scrollView] in
            guard let scrollView else { return }
            context.coordinator.fitIfNeeded(scrollView)
        }
        return scrollView
    }

    func updateUIView(_ scrollView: ZoomScrollView, context: Context) {
        context.coordinator.swapImage(image, in: scrollView)
        context.coordinator.fitIfNeeded(scrollView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        weak var imageView: UIImageView?
        var onSingleTap: () -> Void = {}
        var onDrag: (CGFloat) -> Void = { _ in }
        var onDragEnd: (CGFloat, CGFloat) -> Void = { _, _ in }
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

        /// Thumbnail → full image: same photo, so keep the image view's frame
        /// and zoom and just swap the pixels (a sharpness upgrade, no motion).
        /// Only re-fit if the aspect genuinely differs.
        func swapImage(_ image: UIImage, in scrollView: UIScrollView) {
            guard let imageView, imageView.image !== image else { return }
            let old = imageView.image?.size ?? .zero
            imageView.image = image
            let new = image.size
            guard old.height > 0, new.height > 0,
                  abs(old.width / old.height - new.width / new.height) > 0.01 else { return }
            fittedBounds = .zero
            fitIfNeeded(scrollView)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage(scrollView) }

        /// Keeps the image centred while it's smaller than the viewport — by
        /// moving the image view's frame (the PhotoScroller pattern), which is
        /// deterministic; inset-based centring drifts because the rest offset
        /// doesn't track late-set insets.
        private func centerImage(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let box = scrollView.bounds.size
            var frame = imageView.frame
            frame.origin.x = frame.width < box.width ? (box.width - frame.width) / 2 : 0
            frame.origin.y = frame.height < box.height ? (box.height - frame.height) / 2 : 0
            imageView.frame = frame
        }

        @objc func handleSingleTap() { onSingleTap() }

        /// Swipe-to-dismiss: only at rest zoom and only for a mostly vertical pull.
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer,
                  let scrollView = pan.view as? UIScrollView else { return true }
            guard scrollView.zoomScale <= scrollView.minimumZoomScale * 1.01 else { return false }
            let v = pan.velocity(in: scrollView)
            return abs(v.y) > abs(v.x)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            let dy = pan.translation(in: pan.view).y
            switch pan.state {
            case .changed: onDrag(dy)
            case .ended, .cancelled: onDragEnd(dy, pan.velocity(in: pan.view).y)
            default: break
            }
        }

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
    /// Opens a New post create flow; `object` is its id (RootTabView).
    static let openNewPost = Notification.Name("openNewPost")
    /// The signed-in user saved Edit Profile — own-profile screens refetch.
    static let ownProfileUpdated = Notification.Name("ownProfileUpdated")
    /// Posted after the signed-in user publishes content (track upload, collab
    /// listing). Two listeners: the kept-alive own-profile tab refreshes in
    /// place (so the new post shows without a relaunch), and OverlaidRootView
    /// flashes the confirmation card from `confirmationTitle`/`-Subtitle`
    /// userInfo once the form's sheet has slid away.
    static let ownContentPosted = Notification.Name("ownContentPosted")
    /// A pack was created or edited (its cached responses are already
    /// dropped) — the Marketplace tab, saved packs and profiles refetch.
    static let packsChanged = Notification.Name("packsChanged")
    /// Posted by the confirmation card's dismissal when the post carries an id —
    /// RootTabView opens the content (userInfo: "trackId" or "listingId").
    static let openOwnPost = Notification.Name("openOwnPost")
    /// Posted by AppDelegate when a push notification is tapped — RootTabView
    /// drains `PushInbox.pending` and deep-links to the referenced entity.
    static let openPushNotification = Notification.Name("openPushNotification")
    /// Posted by AppDelegate when a push ARRIVES while the app is in the
    /// foreground (userInfo: the payload's string fields — "convo_id" for a
    /// message). InboxStore refreshes the dots/list; an open Notifications
    /// screen reloads.
    static let pushReceived = Notification.Name("pushReceived")
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
        .environment(dependencies.libraryStore)
        .environment(dependencies.workspaceStore)
        .environment(dependencies.socialStore)
        .environment(dependencies.inboxStore)
        .environment(dependencies.listingsStore)
        .environment(dependencies.feedStore)
        .environment(dependencies.packsStore)
}
