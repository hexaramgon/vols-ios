//
//  ProfileMarketTab.swift
//  Volspire
//
//  Merged "Market" tab — the artist's collab listings, sample/preset packs, and
//  services in one grid. Tapping any card opens its marketplace/listing detail.
//

import DesignSystem
import Kingfisher
import Services
import SwiftUI

struct ProfileMarketTab: View {
    @Environment(Router.self) private var router
    let viewModel: ProfileScreenViewModel
    let isOwnProfile: Bool

    var body: some View {
        // For now this tab surfaces collab listings only — packs/services are
        // hidden until they're wired up (the card builders below stay ready).
        if viewModel.listings.isEmpty {
            ProfileEmptyState(
                icon: .handshake,
                title: "No collab listings yet",
                subtitle: isOwnProfile ? "Your open collab listings show up here." : nil
            )
        } else {
            LazyVStack(spacing: 0) {
                // A full-width hairline after every row (the tab bar's border closes
                // the top), so each listing sits in its own cleanly divided band.
                // NB: use an explicit white opacity — `Color.vBorder` is `.clear`
                // app-wide, so it renders nothing.
                ForEach(viewModel.listings) { listing in
                    listingRow(listing)
                    Rectangle().fill(Color.white.opacity(0.1)).frame(height: 0.5)
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Collab listing row (feed-style, separated by a full-width hairline)

private extension ProfileMarketTab {
    func listingRow(_ listing: ApiListing) -> some View {
        Button {
            router.navigateToCollabListing(listing)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Title on the left, category pill on the far right.
                HStack(alignment: .top, spacing: 10) {
                    Text(listing.title)
                        // Same style as the home feed's listing titles.
                        .font(.appFont.trackTitle)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    categoryPill(listing)
                }

                if let desc = listing.description, !desc.isEmpty {
                    Text(desc)
                        .font(.appFootnote)
                        .foregroundStyle(Color.vText2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if let tags = listing.tags, !tags.isEmpty {
                    tagRow(tags)
                }

                // Engagement on the left, status · time on the bottom right.
                HStack(spacing: 8) {
                    engagement(listing)
                    Spacer(minLength: 8)
                    statusBadge(listing)
                    Text("· \(MessageTime.ago(MessageTime.parse(listing.createdAt)))")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.vertical, 16)
            .contentShape(.rect)
        }
        .buttonStyle(RowHighlightButtonStyle(cornerRadius: 0))
    }

    /// The brand category chip — same treatment as the home feed rows and the
    /// listing detail (accent gradient, white label).
    func categoryPill(_ listing: ApiListing) -> some View {
        Text(categoryLabel(listing.category))
            .font(.appCaption2Semibold)
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(LinearGradient.sendAccent, in: Capsule())
    }

    func statusBadge(_ listing: ApiListing) -> some View {
        let isOpen = (listing.status ?? "open") == "open"
        let tint = isOpen ? Color.green : Color.vText3
        return HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(isOpen ? "Open" : "Closed")
                .font(.appCaption2Semibold)
                .foregroundStyle(tint)
                .fixedSize()
        }
    }

    func tagRow(_ tags: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(tags.prefix(3), id: \.self) { tag in
                Text("#\(tag)")
                    .font(.appCaptionMedium)
                    .foregroundStyle(Color.vText3)
                    .lineLimit(1)
            }
        }
    }

    func engagement(_ listing: ApiListing) -> some View {
        HStack(spacing: 20) {
            stat(.users, listing.responseCount)        // responders
            stat(.messageCircle, listing.commentCount) // comments
            stat(.bookmark, listing.saveCount)         // saves
        }
    }

    func stat(_ icon: LucideIcon.Name, _ count: Int?) -> some View {
        HStack(spacing: 5) {
            LucideIcon(icon, .sm)
            Text("\(count ?? 0)")
                .font(.appCaptionMedium)
                .monospacedDigit()
                // Never compress the counts — sharing a line with the spacer +
                // status + time squeezed them into clipped glyph slivers.
                .fixedSize()
        }
        .foregroundStyle(Color.vText3)
    }

    func categoryLabel(_ id: String) -> String {
        listingCategories.first { $0.id == id }?.label ?? id.capitalized
    }
}

// MARK: - Pack card

private extension ProfileMarketTab {
    func packCard(_ pack: UserPack) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                if let url = pack.coverURL {
                    KFImage(url).downsampled(to: 220).resizable().aspectRatio(contentMode: .fill)
                        .frame(height: 92).frame(maxWidth: .infinity).clipped()
                } else {
                    ZStack {
                        LinearGradient(colors: [Color(white: 0.16), .vBase],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        LucideIcon(.library, .xl).foregroundStyle(.white.opacity(0.4))
                    }
                    .frame(height: 92).frame(maxWidth: .infinity)
                }

                HStack(alignment: .top) {
                    Text(pack.packType.uppercased())
                        .font(.appMicroBold).foregroundStyle(.white.opacity(0.85)).tracking(0.7)
                    Spacer()
                    Text(pack.priceLabel)
                        .font(.appSubheadlineBold).foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                .padding(12)

                if !pack.isPublished {
                    VStack { Spacer()
                        HStack {
                            Text("DRAFT")
                                .font(.appMicroBold).foregroundStyle(.white.opacity(0.6)).tracking(0.7)
                                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                            Spacer()
                        }
                    }
                    .padding(12)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(pack.name)
                    .font(.appSubheadlineSemibold).foregroundStyle(.white)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                HStack(spacing: 5) {
                    LucideIcon(.download, .xs)
                    Text("\(pack.downloads.compactCount) downloads").font(.appCaption2)
                    if let files = pack.fileCount {
                        Text("· \(files) files").font(.appCaption2).foregroundStyle(Color.vText3.opacity(0.8))
                    }
                }
                .foregroundStyle(Color.vText3)
            }
            .padding(12)
        }
        .background(Color.vSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Service card

private extension ProfileMarketTab {
    func serviceCard(_ service: ProfileService) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                if let url = service.coverURL {
                    KFImage(url).downsampled(to: 220).resizable().aspectRatio(contentMode: .fill)
                        .frame(height: 92).frame(maxWidth: .infinity).clipped()
                        .opacity(service.isActive ? 1 : 0.6)
                } else {
                    ZStack {
                        LinearGradient(colors: ServiceStyle.colors(for: service.serviceType),
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        LucideIcon(ServiceStyle.icon(for: service.serviceType), .xl)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .frame(height: 92).frame(maxWidth: .infinity)
                }

                HStack(alignment: .top) {
                    Text(service.serviceType.uppercased())
                        .font(.appMicroBold).foregroundStyle(.white.opacity(0.85)).tracking(0.7)
                    Spacer()
                    if service.isActive {
                        Text(service.price).font(.appSubheadlineBold).foregroundStyle(.white)
                    } else {
                        Text("PRIVATE")
                            .font(.appMicroBold).foregroundStyle(.white.opacity(0.6)).tracking(0.7)
                    }
                }
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                .padding(12)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(service.title)
                    .font(.appSubheadlineSemibold).foregroundStyle(.white)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                if let days = service.deliveryTimeDays {
                    Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                    HStack(spacing: 5) {
                        LucideIcon(.clock, .xs)
                        Text("\(days)d delivery").font(.appCaption2)
                    }
                    .foregroundStyle(Color.vText3)
                }
            }
            .padding(12)
        }
        .background(Color.vSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
