//
//  ArtistMapView.swift
//  Volspire
//
//  The Collab tab's artist map: a real (muted, flat) Apple map with each
//  city's artists pinned as an avatar and the viewer's own city pinging.
//  Static — no pan/zoom, so it never fights the page scroll; it's a picture
//  of who's around you. Centres on `center` (the viewer's city) at a
//  regional span; with no centre it fits every pin. Purely presentational:
//  the Collab tab owns the data and the selection.
//

import DesignSystem
import MapKit
import SwiftUI

struct MapCluster: Identifiable, Hashable {
    let city: String
    let coords: LatLng
    /// Biggest-first, so the lead avatar is the best-known face there.
    let artists: [ExploreArtistItem]
    var id: String { city }
}

private extension LatLng {
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }
}

/// Pins pop in the first time a map shows in a session only (tabs remount).
@MainActor private enum ArtistMapSession {
    static var pinsHaveAnimated = false
}

struct ArtistMapView<Overlay: View>: View {
    let clusters: [MapCluster]
    /// The viewer's own city, pinned as "you".
    let viewer: LatLng?
    /// What the frame centres on; nil fits every pin.
    let center: LatLng?
    let selected: String?
    let onSelect: (String?) -> Void
    @ViewBuilder let overlay: () -> Overlay

    @State private var animatePins = !ArtistMapSession.pinsHaveAnimated
    @State private var pinsIn = false
    /// Set from `region` on appear; glides to the new frame when the pins
    /// or the viewer's city change (a filter), instead of rebuilding the map.
    @State private var position: MapCameraPosition = .automatic

    /// Degrees of latitude shown around the viewer's city — regional, so
    /// nearby cities land on screen too.
    private static var nearbySpan: Double { 14 }

    /// The frame: the viewer's region, else every pin (padded), else the world.
    private var region: MKCoordinateRegion {
        if let center {
            return MKCoordinateRegion(center: center.coordinate,
                                      span: .init(latitudeDelta: Self.nearbySpan, longitudeDelta: Self.nearbySpan * 1.33))
        }
        let pts = clusters.map(\.coords)
        guard let minLat = pts.map(\.lat).min(), let maxLat = pts.map(\.lat).max(),
              let minLng = pts.map(\.lng).min(), let maxLng = pts.map(\.lng).max()
        else {
            return MKCoordinateRegion(center: .init(latitude: 25, longitude: 0),
                                      span: .init(latitudeDelta: 120, longitudeDelta: 160))
        }
        return MKCoordinateRegion(
            center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: .init(latitudeDelta: min(150, max(20, (maxLat - minLat) * 1.5)),
                        longitudeDelta: min(340, max(28, (maxLng - minLng) * 1.4)))
        )
    }

    /// Smaller pins once the frame is continent-wide.
    private var compact: Bool { region.span.latitudeDelta > 40 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $position, interactionModes: []) {
                if let viewer {
                    Annotation("You", coordinate: viewer.coordinate, anchor: .center) {
                        ViewerPin()
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(Array(clusters.enumerated()), id: \.element.id) { i, c in
                    Annotation(c.city, coordinate: c.coords.coordinate, anchor: .center) {
                        pin(c, index: i)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .onChange(of: RegionKey(center: center, cities: clusters.map(\.city))) {
                withAnimation(.smooth(duration: 0.5)) { position = .region(region) }
            }
            // Tapping open map clears the city selection.
            .onTapGesture { onSelect(nil) }

            overlay()
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .strokeBorder(Color.vDivider, lineWidth: 1)
        }
        .onAppear {
            position = .region(region)
            ArtistMapSession.pinsHaveAnimated = true
            if animatePins { pinsIn = true }
        }
    }

    private struct RegionKey: Hashable {
        let center: LatLng?
        let cities: [String]
    }

    private func pin(_ c: MapCluster, index: Int) -> some View {
        let isSelected = selected == c.city
        let lead = c.artists.first
        let shown = !animatePins || pinsIn
        return Button {
            onSelect(isSelected ? nil : c.city)
        } label: {
            AvatarView(url: lead?.avatarURL, name: lead?.username, size: compact ? 24 : 32)
                .padding(2)
                .background(isSelected ? Color.vAccent : Color.vCardSolid, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .overlay(alignment: .topTrailing) {
                    if c.artists.count > 1 {
                        Text("\(c.artists.count)")
                            .font(.appMicroBold)
                            .monospacedDigit()
                            .foregroundStyle(Color.vOnInverse)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.vInverse, in: Capsule())
                            .offset(x: 6, y: -4)
                    }
                }
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Text(c.city.split(separator: ",").first.map(String.init) ?? c.city)
                            .font(.appCaption)
                            .foregroundStyle(Color.vText)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.vSurface, in: Capsule())
                            .offset(y: 26)
                    }
                }
                .scaleEffect(shown ? (isSelected ? 1.15 : 1) : 0)
                .opacity(shown ? 1 : 0)
                .animation(.interpolatingSpring(stiffness: 400, damping: 24).delay(Double(min(index, 12)) * 0.03), value: pinsIn)
                .animation(.interpolatingSpring(stiffness: 400, damping: 24), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(c.city): \(c.artists.count) \(c.artists.count == 1 ? "artist" : "artists")")
    }
}

/// The viewer's own city: an ink dot with a soft ring and a ping.
private struct ViewerPin: View {
    @State private var ping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.ink(0.4))
                .frame(width: 12, height: 12)
                .scaleEffect(ping ? 2.2 : 1)
                .opacity(ping ? 0 : 1)
            Circle()
                .fill(Color.vInverse)
                .frame(width: 12, height: 12)
                .padding(4)
                .background(Color.ink(0.2), in: Circle())
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) { ping = true }
        }
    }
}
