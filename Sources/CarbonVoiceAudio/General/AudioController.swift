//
//  AudioController.swift
//
//  Created by Manuel on 17/11/21.
//

import Foundation
import AVKit

// MARK: - Input (methods)

public protocol AudioControllerProtocol {
    var delegate: AudioControllerDelegate? { get set }
    func setSessionCategory(_ category: String, completion: (Result<Void, Error>) -> Void)
    func setSessionActive(_ active: Bool, completion: (Result<Void, Error>) -> Void)
    func getCurrentSessionCategoryName() -> String?
    func getCurrentInput() -> AVAudioSessionPortDescription?
    func getCurrentOutput() -> AVAudioSessionPortDescription?
}

// MARK: - Output (callbacks)

public protocol AudioControllerDelegate: AnyObject {
    func routeDidChange(inputPortName: String?, inputPortType: String?, outputPortName: String?, outputPortType: String?)
    func interruptionStarted()
    func interruptionEnded()
}

// MARK: - AudioController

public class AudioController {

    weak var delegate: AudioControllerDelegate?

    init() {
        setupNotifications()
    }

    deinit {
        removeNotifications()
    }

    private func removeNotifications() {
        NotificationCenter.default.removeObserver(self,
                                                  name: AVAudioSession.routeChangeNotification,
                                                  object: nil)

        NotificationCenter.default.removeObserver(self,
                                                  name: AVAudioSession.interruptionNotification,
                                                  object: AVAudioSession.sharedInstance)

        NotificationCenter.default.removeObserver(self,
                                                  name: AVAudioSession.silenceSecondaryAudioHintNotification,
                                                  object: AVAudioSession.sharedInstance)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleRouteChange),
                                               name: AVAudioSession.routeChangeNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleInterruption),
                                               name: AVAudioSession.interruptionNotification,
                                               object: AVAudioSession.sharedInstance)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleSecondaryAudio),
                                               name: AVAudioSession.silenceSecondaryAudioHintNotification,
                                               object: AVAudioSession.sharedInstance)
    }

    @objc private func handleRouteChange(notification: Notification) {
        let input = getCurrentInput()
        let output = getCurrentOutput()
        delegate?.routeDidChange(inputPortName: input?.portName,
                                 inputPortType: input?.portType.rawValue,
                                 outputPortName: output?.portName,
                                 outputPortType: output?.portType.rawValue)
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                  return
              }

        // Switch over the interruption type.
        switch type {

        case .began:
            // An interruption began. Update the UI as necessary.
            delegate?.interruptionStarted()
        case .ended:
            // An interruption ended. Resume playback, if appropriate.
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                delegate?.interruptionEnded()
                return
            }

            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            if options.contains(.shouldResume) {
                delegate?.interruptionEnded()
            } else {
                // An interruption ended. Don't resume playback.
            }
        default: ()
        }
    }

    @objc private func handleSecondaryAudio(notification: Notification) {
        // Determine hint type
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
              let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: typeValue) else {
                  return
              }

        if type == .begin {
            // Other app audio started playing - mute secondary audio.
            delegate?.interruptionStarted()
        } else {
            // Other app audio stopped playing - restart secondary audio.
            delegate?.interruptionEnded()
        }
    }
}

// MARK: - AudioControllerProtocol

extension AudioController: AudioControllerProtocol {
    func setSessionCategory(_ category: String, completion: (Result<Void, Error>) -> Void) {
        do {
            guard let category = getAudioSessionCategoryFromString(category) else {
                let error = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey : "Category does not exist"])
                completion(.failure(error))
                return
            }
            try AVAudioSession.sharedInstance().setCategory(category)
            completion(.success(Void()))
        } catch {
            completion(.failure(error))
        }
    }

    func setSessionActive(_ active: Bool, completion: (Result<Void, Error>) -> Void) {
        do {
            try AVAudioSession.sharedInstance().setActive(active)
            completion(.success(Void()))
        } catch {
            completion(.failure(error))
        }
    }

    func getCurrentSessionCategoryName() -> String? {
        return getAudioSessionCategoryName(AVAudioSession.sharedInstance().category)
    }

    func getCurrentInput() -> AVAudioSessionPortDescription? {
        var currentInput: AVAudioSessionPortDescription?

        let inputs = AVAudioSession.sharedInstance().currentRoute.inputs

        for input in inputs {
            for port in getAllAudioPorts() {
                if input.portType == port {
                    currentInput = input
                }
            }
        }

        return currentInput
    }

    func getCurrentOutput() -> AVAudioSessionPortDescription? {
        var currentOutput: AVAudioSessionPortDescription?

        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs

        for output in outputs {
            for port in getAllAudioPorts() {
                if output.portType == port {
                    currentOutput = output
                }
            }
        }

        return currentOutput
    }
}

// MARK: - Helpers

extension AudioController {
    private func getAllAudioPorts() -> [AVAudioSession.Port] {
        var allPorts: [AVAudioSession.Port] = [
            AVAudioSession.Port.lineIn,
            AVAudioSession.Port.builtInMic,
            AVAudioSession.Port.headsetMic,
            AVAudioSession.Port.lineOut,
            AVAudioSession.Port.headphones,
            AVAudioSession.Port.bluetoothA2DP,
            AVAudioSession.Port.builtInReceiver,
            AVAudioSession.Port.builtInSpeaker,
            AVAudioSession.Port.HDMI,
            AVAudioSession.Port.airPlay,
            AVAudioSession.Port.bluetoothLE,
            AVAudioSession.Port.bluetoothHFP,
            AVAudioSession.Port.usbAudio,
            AVAudioSession.Port.carAudio,
            AVAudioSession.Port.carAudio
        ]

        if #available(iOS 14.0, *) {
            allPorts.append(contentsOf: [
                AVAudioSession.Port.PCI,
                AVAudioSession.Port.fireWire,
                AVAudioSession.Port.displayPort,
                AVAudioSession.Port.AVB,
                AVAudioSession.Port.thunderbolt
            ])
        }

        return allPorts
    }

    private func getAllAudioSessionCategories() -> [AVAudioSession.Category] {
        let categories: [AVAudioSession.Category] = [
            AVAudioSession.Category.playAndRecord,
            AVAudioSession.Category.ambient,
            AVAudioSession.Category.playAndRecord,
            AVAudioSession.Category.playback,
            AVAudioSession.Category.multiRoute,
            AVAudioSession.Category.record,
            AVAudioSession.Category.soloAmbient,
        ]

        return categories
    }

    private func getAudioSessionCategoryFromString(_ string: String) -> AVAudioSession.Category? {
        switch string {
        case "playAndRecord":
            return .playAndRecord
        case "ambient":
            return .ambient
        case "playback":
            return .playback
        case "multiRoute":
            return .multiRoute
        case "record":
            return .record
        case "soloAmbient":
            return .soloAmbient
        default:
            return nil
        }
    }

    private func getAudioSessionCategoryName(_ category: AVAudioSession.Category) -> String? {
        switch category {
        case .playAndRecord:
            return "playAndRecord"
        case .ambient:
            return "ambient"
        case .playback:
            return "playback"
        case .multiRoute:
            return "multiRoute"
        case .record:
            return "record"
        case .soloAmbient:
            return "soloAmbient"
        default:
            return nil
        }
    }
}
