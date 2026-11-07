//
//  ProfileMarketTab.swift
//  Volspire
//
//  The profile's "Listings" tab — the artist's collab listings as the shared
//  post cards. Pack/service cards stay ready for when the marketplace ships.
//

import DesignSystem
import Kingfisher
import Services
import SwiftUI

struct ProfileMarketTab: View {
    @Environment(Router.self) private var router
    let viewModel: ProfileScreenViewModel

    var body: some View {
        // For now this tab surfaces collab listings only — packs/services are
        // hidden until the marketplace ships (the card builders below stay ready).
        Group {
            if viewModel.listings.isEmpty && !viewModel.listingsLoaded {
                ListingPostCardSkeleton().padding(.horizontal, -8).padding(.top, 4)
            } else if viewModel.listings.isEmpty {
                ProfileEmptyState(icon: ProfileTab.market.icon, title: "No listings yet")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(viewModel.listings.enumerated()), id: \.element.id) { i, listing in
                        ListingPostCard(listing: listing, horizontalInset: 14)
                            .staggeredAppear(i, in: "profile.listings-\(ObjectIdentifier(viewModel).hashValue)")
                    }
                }
                // Cards run wider than the page's text column (as on Home).
                .padding(.horizontal, -8)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: 672)
        // The cards' 4pt top inset lives on the cards only, so the empty
        // state sits exactly where Tracks' and Featured On's do.
        .padding(.horizontal, ViewConst.screenPaddings)
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
                    // The pack's name mesh, like its Marketplace card.
                    PlaylistCoverFallback(name: pack.name, icon: nil)
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
                    .font(.appSubheadlineSemibold).foregroundStyle(Color.vText)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Color.vDivider).frame(height: 1)
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
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
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
                    .font(.appSubheadlineSemibold).foregroundStyle(Color.vText)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                if let days = service.deliveryTimeDays {
                    Rectangle().fill(Color.vDivider).frame(height: 1)
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
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
    }
}
