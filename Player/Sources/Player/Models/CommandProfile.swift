//
//  CommandProfile.swift
//  Volspire
//
//

public struct CommandProfile: Equatable {
    public let isLiveStream: Bool
    public let isSwitchTrackEnabled: Bool

    public init(isLiveStream: Bool, isSwitchTrackEnabled: Bool) {
        self.isLiveStream = isLiveStream
        self.isSwitchTrackEnabled = isSwitchTrackEnabled
    }
}
