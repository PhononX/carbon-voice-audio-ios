//
//  RecorderController.swift
//
//  Created by Manuel on 19/10/21.
//

import Foundation
import AVKit
import AVFoundation

#if canImport(Speech)
import Speech
#endif

// MARK: - Input (methods)

@available(watchOS 7.3, *)
public protocol RecorderControllerProtocol {
    var delegate: RecorderControllerDelegate? { get set }
    var isRecording: Bool { get }
    func requestRecordPermission(completion: @escaping (Bool) -> Void)
    func getRecordPermissionState() -> String
    func startOrResumeRecording() throws
    func pauseRecording()
    func endRecordingSession(completion: @escaping (RecorderController.AudioRecordingResult?) -> Void)
    func setSubscriptionFrequency(seconds: Int)
}

// MARK: - Output (callbacks)

public protocol RecorderControllerDelegate: AnyObject {
    func recordedTimeDidChange(secondsRecorded: Int)
    func recordingInfoUpdate(decibels: Float?, duration: Int)
}

// MARK: - RecorderController

@available(watchOS 7.3, *)
public class RecorderController {

    public struct AudioRecordingResult {
        public let url: URL
        public let transcription: String?
        public let recordedTimeInMilliseconds: Int
    }

    public enum Error: Swift.Error, LocalizedError {
        case deniedRecordPermissionRequest

        public var errorDescription: String? {
            switch self {
            case .deniedRecordPermissionRequest:
                return "Failed to find permission to access the microphone, go to settings and turn it on from there"
            }
        }
    }

    private var audioRecorder: AVAudioRecorder?

    private var recordedTimeInSeconds: Int = 0

    private var timer: Timer?

    private var customTimer: Timer?

    #if canImport(Speech)
    private lazy var speechRecognizer: SFSpeechRecognizer? = {
        let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        return speechRecognizer
    }()
    #endif

    public weak var delegate: RecorderControllerDelegate?

    deinit {
        invalidateTimer()

        customTimer?.invalidate()
        customTimer = nil
    }

    public init() {}

    private func startTimer() {
        invalidateTimer()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { [weak self] _ in
            guard let self = self else { return }
            if self.audioRecorder?.isRecording == true {
                self.recordedTimeInSeconds += 1
                self.delegate?.recordedTimeDidChange(secondsRecorded: self.recordedTimeInSeconds)
            }
        })

        timer?.fire()
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
    }

    public func setSubscriptionFrequency(seconds: Int) {
        customTimer?.invalidate()
        customTimer = nil

        customTimer = Timer.scheduledTimer(withTimeInterval: Double(seconds), repeats: true, block: { [weak self] _ in
            guard let self = self else { return }
            let decibels = self.audioRecorder?.averagePower(forChannel: 0)
            self.delegate?.recordingInfoUpdate(decibels: decibels, duration: self.recordedTimeInSeconds)
        })

        customTimer?.fire()
    }

    private func setPrefersNoInterruptionsFromSystemAlerts(_ inValue: Bool) {
        if #available(iOS 14.5, *) {
            do {
                try AVAudioSession.sharedInstance().setPrefersNoInterruptionsFromSystemAlerts(inValue)
            } catch {
                print("Failed to call setPrefersNoInterruptionsFromSystemAlerts, error: ", error.localizedDescription)
            }
        }
    }
}

@available(watchOS 7.3, *)
extension RecorderController: RecorderControllerProtocol {
    public var isRecording: Bool {
        audioRecorder?.isRecording == true
    }

    public func requestRecordPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            completion(granted)
        }
    }

    public func getRecordPermissionState() -> String {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .undetermined:
            return "undetermined"
        case .denied:
            return "denied"
        case .granted:
            return "granted"
        default:
            return ""
        }
    }

    public func startOrResumeRecording() throws {
        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            throw Error.deniedRecordPermissionRequest
        }

        if AVAudioSession.sharedInstance().category != .record ||
            AVAudioSession.sharedInstance().categoryOptions != .interruptSpokenAudioAndMixWithOthers {
            try AVAudioSession.sharedInstance().setCategory(.record, options: .interruptSpokenAudioAndMixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        }

        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording.m4a")

        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        if audioRecorder == nil {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
        }

        startTimer()
        setPrefersNoInterruptionsFromSystemAlerts(true)
        audioRecorder?.record()
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.updateMeters()
    }

    public func pauseRecording() {
        guard audioRecorder != nil else {
            return
        }

        audioRecorder?.pause()
    }

    public func endRecordingSession(completion: @escaping (AudioRecordingResult?) -> Void) {
        guard audioRecorder != nil, let url = audioRecorder?.url else {
            completion(nil)
            return
        }

        invalidateTimer()

        let recordedTimeInMilliseconds = recordedTimeInSeconds * 1000

        recordedTimeInSeconds = 0
        delegate?.recordedTimeDidChange(secondsRecorded: recordedTimeInSeconds)

        audioRecorder?.stop()

        setPrefersNoInterruptionsFromSystemAlerts(false)

        #if canImport(Speech)

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        if speechRecognizer?.isAvailable == true {
            speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                if let error = error {
                    print("Speech recognition task failed, error: \(error.localizedDescription)")
                    completion(AudioRecordingResult(url: url,
                                                    transcription: nil,
                                                    recordedTimeInMilliseconds: recordedTimeInMilliseconds))
                } else if let transcription = result?.bestTranscription.formattedString {
                    print("Speech recognition task succeeded, transcription: \(transcription)")
                    completion(AudioRecordingResult(url: url,
                                                    transcription: transcription,
                                                    recordedTimeInMilliseconds: recordedTimeInMilliseconds))
                } else {
                    print("Speech recognition failed without an error")
                    completion(AudioRecordingResult(url: url,
                                                    transcription: nil,
                                                    recordedTimeInMilliseconds: recordedTimeInMilliseconds))
                }
                self?.audioRecorder = nil
            }
        } else {
            print("Device doesn't support speech recognition")
            completion(AudioRecordingResult(url: url, transcription: nil, recordedTimeInMilliseconds: recordedTimeInMilliseconds))
            audioRecorder = nil
        }

        #else
        completion(AudioRecordingResult(url: url, transcription: nil, recordedTimeInMilliseconds: recordedTimeInMilliseconds))
        audioRecorder = nil

        #endif
    }

    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}
