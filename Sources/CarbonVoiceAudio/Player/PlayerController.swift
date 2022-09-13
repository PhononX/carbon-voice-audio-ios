//
//  PlayerController.swift
//
//  Created by Manuel on 04/10/21.
//

import Foundation
import AVFoundation
import AVKit

// MARK: - Input (methods)

@available(watchOS 7.3, *)
public protocol PlayerControllerProtocol {
    var delegate: PlayerControllerDelegate? { get set }
    var isPlaying: Bool { get }
    var playerInfo: PlayerInfo { get }
    func play(url: URL, pxtoken: String, rate: Double, position: Double, readyToPlay: @escaping (Result<Void, Error>) -> Void)
    func pause()
    func resume()
    func seek(to percentage: Double)
    func rewind(seconds: Double)
    func setPlaybackSpeed(_ playbackSpeed: Double)
    func getCurrentTimeInSeconds() -> Double?
    func setSubscriptionFrequency(seconds: Int)
}

// MARK: - Output (callbacks)

@available(watchOS 7.3, *)
public protocol PlayerControllerDelegate: AnyObject {
    func timelineDidChange(timePlayed: String, timeRemaining: String, percentage: Double)
    func millisecondsHeardDidChange(milliseconds: Int, percentage: Double)
    func playerDidFinishPlaying()
    func playerInfoDidUpdate(_ playerInfo: PlayerInfo)
}

// MARK: - PlayerController

@available(watchOS 7.3, *)
public class PlayerController {

    private var avPlayer: AVPlayer?

    private var millisecondTimeObserverToken: Any?

    private var fiveSecondTimeObserverToken: Any?

    private var customTimeObserverToken: Any?

    private var playerItemStatusObserver: NSKeyValueObservation?

    public weak var delegate: PlayerControllerDelegate?

    public init() {}

    deinit {
        if let millisecondTimeObserverToken = millisecondTimeObserverToken {
            if let player = avPlayer {
                player.removeTimeObserver(millisecondTimeObserverToken)
            }
            self.millisecondTimeObserverToken = nil
        }

        if let secondTimeObserverToken = fiveSecondTimeObserverToken {
            if let player = avPlayer {
                player.removeTimeObserver(secondTimeObserverToken)
            }
            self.fiveSecondTimeObserverToken = nil
        }

        if let customTimeObserverToken = customTimeObserverToken {
            if let player = avPlayer {
                player.removeTimeObserver(customTimeObserverToken)
            }
            self.customTimeObserverToken = nil
        }
    }

    @objc private func handlePlayerDidFinishPlaying() {
        self.delegate?.playerDidFinishPlaying()
    }
}

@available(watchOS 7.3, *)
extension PlayerController: PlayerControllerProtocol {
    public var isPlaying: Bool {
        avPlayer?.timeControlStatus == .playing
    }

    public var playerInfo: PlayerInfo {
        guard let player = self.avPlayer,
              let item = player.currentItem
        else {
            return PlayerInfo(percentage: nil, duration: nil, isPlaying: nil, playbackSpeed: nil)
        }

        let percentage = Double(player.currentTime().seconds / item.asset.duration.seconds)

        guard percentage > 0 && percentage <= 100 else {
            return PlayerInfo(percentage: nil,
                              duration: Int(item.asset.duration.seconds),
                              isPlaying: player.timeControlStatus == .playing,
                              playbackSpeed: Double(player.rate))
        }

        return PlayerInfo(percentage: percentage,
                          duration: Int(item.asset.duration.seconds),
                          isPlaying: player.timeControlStatus == .playing,
                          playbackSpeed: Double(player.rate))
    }

    public func setSubscriptionFrequency(seconds: Int) {
        // Remove observer if needed
        if let customTimeObserverToken = customTimeObserverToken {
            if let player = avPlayer {
                player.removeTimeObserver(customTimeObserverToken)
            }
            self.customTimeObserverToken = nil
        }

        // Add a new observer
        let cmTime = CMTime(seconds: Double(seconds), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        customTimeObserverToken = avPlayer?.addPeriodicTimeObserver(forInterval: cmTime, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.delegate?.playerInfoDidUpdate(self.playerInfo)
        }
    }

    public func play(url: URL, pxtoken:String, rate: Double, position: Double, readyToPlay: @escaping (Result<Void, Error>) -> Void) {
        #if os(watchOS)
        if AVAudioSession.sharedInstance().category != .playback ||
            AVAudioSession.sharedInstance().routeSharingPolicy != .longFormAudio ||
            AVAudioSession.sharedInstance().categoryOptions != .interruptSpokenAudioAndMixWithOthers {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio, options: .interruptSpokenAudioAndMixWithOthers)
            } catch {
                readyToPlay(.failure(error))
            }
        }
        #else
        if AVAudioSession.sharedInstance().category != .playback ||
            AVAudioSession.sharedInstance().categoryOptions != .interruptSpokenAudioAndMixWithOthers {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, options: .interruptSpokenAudioAndMixWithOthers)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                readyToPlay(.failure(error))
            }
        }
        #endif

        avPlayer?.pause()

        let headers: [String: String] = [ "pxtoken": pxtoken ]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let playerItem = AVPlayerItem(asset: asset)
                
        avPlayer = AVPlayer(playerItem: playerItem)

        // Remove old notification observer
        NotificationCenter.default.removeObserver(self,
                                                  name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                                  object: nil)

        // Add new notification observer
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handlePlayerDidFinishPlaying),
                                               name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                               object: nil)

        // Handle millisecond(Time) UI Updates like the timeline (slider)
        let millisecond = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        millisecondTimeObserverToken = avPlayer?.addPeriodicTimeObserver(forInterval: millisecond, queue: .main) { [weak self] time in
            guard let self = self,
                  let player = self.avPlayer,
                  let item = player.currentItem
            else { return }

            let percentage = Double(player.currentTime().seconds / item.asset.duration.seconds)

            // Update Timeline
            let remaining = item.asset.duration - player.currentTime()
            self.delegate?.timelineDidChange(timePlayed: player.currentTime().positionalTime(),
                                             timeRemaining: "-" + remaining.positionalTime(),
                                             percentage: percentage)
        }

        // Handle five seconds(Time) UI Updates like the "updateHeard" API call
        let fiveSeconds = CMTime(seconds: 5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        fiveSecondTimeObserverToken = avPlayer?.addPeriodicTimeObserver(forInterval: fiveSeconds, queue: .main) { [weak self] time in
            guard let self = self,
                  let player = self.avPlayer,
                  player.timeControlStatus == .playing,
                  let item = player.currentItem
            else { return }

            let milliseconds = Int(player.currentTime().seconds * 1000)

            let percentage = Double(player.currentTime().seconds / item.asset.duration.seconds)

            guard percentage > 0 && percentage <= 100 else { return }

            self.delegate?.millisecondsHeardDidChange(milliseconds: milliseconds, percentage: percentage)
        }

        // Register as an observer of the player item's status property
        self.playerItemStatusObserver = avPlayer?.currentItem?.observe(\.status, options:  [.new, .old], changeHandler: { [weak self] (playerItem, change) in
            guard let self = self else { return }
            if playerItem.status == .readyToPlay {
                self.seek(to: position)
                self.avPlayer?.playImmediately(atRate: Float(rate))
                readyToPlay(.success(Void()))
            }
        })
    }

    public func pause() {
        avPlayer?.pause()
    }

    public func resume() {
        avPlayer?.play()
    }

    public func seek(to percentage: Double) {
        guard let player = avPlayer,
              let currentReplyDuration = player.currentItem?.duration.seconds,
              !currentReplyDuration.isNaN,
              !currentReplyDuration.isInfinite
        else { return }
        let newTimeMS = Int64(percentage * Double(currentReplyDuration * 1000))
        let newTime = CMTimeMake(value: newTimeMS, timescale: 1000)
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func rewind(seconds: Double) {
        guard let player = avPlayer else { return }
        let currentTime = player.currentTime()
        var newTime = currentTime - CMTime(seconds: seconds, preferredTimescale: 60000)
        if (newTime < CMTime.zero) { newTime = CMTime.zero }
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func getCurrentTimeInSeconds() -> Double? {
        return avPlayer?.currentTime().seconds
    }

    public func setPlaybackSpeed(_ playbackSpeed: Double) {
        let isPlaying = avPlayer?.timeControlStatus == .playing

        if isPlaying {
            avPlayer?.play()
            avPlayer?.rate = Float(playbackSpeed)
        } else {
            avPlayer?.rate = Float(playbackSpeed)
            avPlayer?.pause()
        }
    }
}

// MARK: - CMTime helper
@available(watchOS 7.3, *)
fileprivate extension CMTime {
    private var roundedSeconds: TimeInterval {
        return seconds.rounded()
    }

    private var hours:  Int { return Int(roundedSeconds / 3600) }
    private var minute: Int { return Int(roundedSeconds.truncatingRemainder(dividingBy: 3600) / 60) }
    private var second: Int { return Int(roundedSeconds.truncatingRemainder(dividingBy: 60)) }

    func positionalTime() -> String {
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minute, second)
        } else {
            if minute >= 0 && second >= 0 {
                return String(format: "%02d:%02d", minute, second)
            } else {
                return "00:00"
            }
        }
    }
}
