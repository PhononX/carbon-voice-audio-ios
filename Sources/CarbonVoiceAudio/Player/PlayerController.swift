//
//  PlayerController.swift
//
//  Created by Manuel on 04/10/21.
//

import Foundation
import AVKit

// MARK: - Input (methods)

public protocol PlayerControllerProtocol {
    var delegate: PlayerControllerDelegate? { get set }
    var isPlaying: Bool { get }
    func play(url: URL, rate: Double, position: Double, readyToPlay: @escaping (Result<Void, Error>) -> Void)
    func pause()
    func resume()
    func seek(to percentage: Double)
    func rewind(seconds: Double)
    func setPlaybackSpeed(_ playbackSpeed: Double)
    func getCurrentTimeInSeconds() -> Double?
}

// MARK: - Output (callbacks)

public protocol PlayerControllerDelegate: AnyObject {
    func timelineDidChange(timePlayed: String, timeRemaining: String, percentage: Double)
    func millisecondsHeardDidChange(milliseconds: Int, percentage: Double)
    func playerDidFinishPlaying()
}

// MARK: - PlayerController

public class PlayerController {
    private var playerController: AVPlayerViewController?

    private var millisecondTimeObserverToken: Any?

    private var fiveSecondTimeObserverToken: Any?

    private var playerItemStatusObserver: NSKeyValueObservation?

    weak var delegate: PlayerControllerDelegate?

    deinit {
        if let millisecondTimeObserverToken = millisecondTimeObserverToken {
            if let player = playerController?.player {
                player.removeTimeObserver(millisecondTimeObserverToken)
            }
            self.millisecondTimeObserverToken = nil
        }

        if let secondTimeObserverToken = fiveSecondTimeObserverToken {
            if let player = playerController?.player {
                player.removeTimeObserver(secondTimeObserverToken)
            }
            self.fiveSecondTimeObserverToken = nil
        }
    }

    @objc private func handlePlayerDidFinishPlaying() {
        self.delegate?.playerDidFinishPlaying()
    }
}

extension PlayerController: PlayerControllerProtocol {
    var isPlaying: Bool {
        playerController?.player?.timeControlStatus == .playing
    }

    func play(url: URL, rate: Double, position: Double, readyToPlay: @escaping (Result<Void, Error>) -> Void) {
        // Pause current player if needed
        playerController?.player?.pause()

        // Set new player
        playerController = AVPlayerViewController()
        playerController?.player = AVPlayer(url: url)

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
        millisecondTimeObserverToken = playerController?.player?.addPeriodicTimeObserver(forInterval: millisecond, queue: .main) { [weak self] time in
            guard let self = self,
                  let player = self.playerController?.player,
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
        fiveSecondTimeObserverToken = playerController?.player?.addPeriodicTimeObserver(forInterval: fiveSeconds, queue: .main) { [weak self] time in
            guard let self = self,
                  let player = self.playerController?.player,
                  player.timeControlStatus == .playing,
                  let item = player.currentItem
            else { return }

            let milliseconds = Int(player.currentTime().seconds * 1000)

            let percentage = Double(player.currentTime().seconds / item.asset.duration.seconds)

            guard percentage > 0 && percentage <= 100 else { return }

            self.delegate?.millisecondsHeardDidChange(milliseconds: milliseconds, percentage: percentage)
        }

        // Register as an observer of the player item's status property
        self.playerItemStatusObserver = playerController?.player?.currentItem?.observe(\.status, options:  [.new, .old], changeHandler: { [weak self] (playerItem, change) in
            guard let self = self else { return }
            if playerItem.status == .readyToPlay {
                self.seek(to: position)
                self.playerController?.player?.play()
                self.playerController?.player?.rate = Float(rate)
                readyToPlay(.success(Void()))
            }
        })
    }

    func pause() {
        playerController?.player?.pause()
    }

    func resume() {
        playerController?.player?.play()
    }

    func seek(to percentage: Double) {
        guard let player = playerController?.player,
              let currentReplyDuration = player.currentItem?.duration.seconds,
              !currentReplyDuration.isNaN,
              !currentReplyDuration.isInfinite
        else { return }
        let newTimeMS = Int64(percentage * Double(currentReplyDuration * 1000))
        let newTime = CMTimeMake(value: newTimeMS, timescale: 1000)
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func rewind(seconds: Double) {
        guard let player = playerController?.player else { return }
        let currentTime = player.currentTime()
        var newTime = currentTime - CMTime(seconds: seconds, preferredTimescale: 60000)
        if (newTime < CMTime.zero) { newTime = CMTime.zero }
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func getCurrentTimeInSeconds() -> Double? {
        return playerController?.player?.currentTime().seconds
    }

    func setPlaybackSpeed(_ playbackSpeed: Double) {
        let isPlaying = playerController?.player?.timeControlStatus == .playing

        if isPlaying {
            playerController?.player?.play()
            playerController?.player?.rate = Float(playbackSpeed)
        } else {
            playerController?.player?.rate = Float(playbackSpeed)
            playerController?.player?.pause()
        }
    }
}

// MARK: - CMTime helper

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
