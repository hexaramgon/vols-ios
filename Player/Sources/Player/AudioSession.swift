//
//  AudioSession.swift
//  Volspire
//
//

import AVFAudio
import SharedUtilities

@MainActor
protocol AudioSessionDelegate: AnyObject {
    func audioSessionInterruptionBegan()
    func audioSessionInterruptionEnded(shouldResume: Bool)
    /// The output in use went away (headphones unplugged, Bluetooth dropped).
    func audioSessionOutputLost()
    /// The audio engine was reconfigured (route / hardware format change),
    /// which stops it — playback has to be restarted to be heard.
    func audioEngineConfigurationChanged()
    /// The media server restarted: every audio object is dead.
    func audioSessionMediaServicesReset()
}

@MainActor
class AudioSession {
    private var interruptionTask: Task<Void, Never>?
    private var routeTasks: [Task<Void, Never>] = []
    weak var delegate: AudioSessionDelegate?

    init() {
        setupAudioSession()
        setupAudioInterruptionObserver()
        setupRouteObservers()
    }

    func setActive(_ active: Bool) {
        do {
            try AVAudioSession.sharedInstance().setActive(active)
        } catch {
            debugLog("AVAudioSession setActive Error: \(error.localizedDescription)")
        }
    }

    deinit {
        interruptionTask?.cancel()
        routeTasks.forEach { $0.cancel() }
    }
}

private extension AudioSession {
    func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
        } catch {
            debugLog("AVAudioSession configuring Error: \(error.localizedDescription)")
        }
    }

    func setupAudioInterruptionObserver() {
        interruptionTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification
            )

            for await notification in notifications {
                self?.handleAudioSessionInterruption(notification: notification)
            }
        }
    }

    /// Nothing else handles these: AudioKit doesn't, and without them an
    /// unplug / Bluetooth drop left the state "playing" over silence.
    func setupRouteObservers() {
        routeTasks.append(Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
                let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                // Apple's rule: the old output became unavailable → pause.
                if raw.flatMap(AVAudioSession.RouteChangeReason.init) == .oldDeviceUnavailable {
                    self?.delegate?.audioSessionOutputLost()
                }
            }
        })
        routeTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .AVAudioEngineConfigurationChange) {
                self?.delegate?.audioEngineConfigurationChanged()
            }
        })
        routeTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.mediaServicesWereResetNotification) {
                // Apple: reconfigure the session after a reset.
                self?.setupAudioSession()
                self?.delegate?.audioSessionMediaServicesReset()
            }
        })
    }

    private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let interruptionTypeRaw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let interruptionType = AVAudioSession.InterruptionType(rawValue: interruptionTypeRaw)
        else {
            return
        }

        switch interruptionType {
        case .began:
            delegate?.audioSessionInterruptionBegan()
        case .ended:
            if let optionsRaw = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                delegate?.audioSessionInterruptionEnded(shouldResume: options.contains(.shouldResume))
            }
        @unknown default:
            break
        }
    }
}
