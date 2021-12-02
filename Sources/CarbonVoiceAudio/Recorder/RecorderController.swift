//
//  RecorderController.swift
//
//  Created by Manuel on 19/10/21.
//

import Foundation
import Speech
import AVKit

// MARK: - Input (methods)

public protocol RecorderControllerProtocol {
    var delegate: RecorderControllerDelegate? { get set }
    var isSessionActive: Bool { get }
    var isRecording: Bool { get }
    func requestRecordPermission(completion: @escaping (Bool) -> Void)
    func getRecordPermissionState() -> String
    func startRecordingSession() throws
    func pauseRecording()
    func resumeRecording()
    func endRecordingSession(completion: @escaping (RecorderController.AudioRecordingResult?) -> Void)
    func deleteRecordingSession()
}

// MARK: - Output (callbacks)

public protocol RecorderControllerDelegate: AnyObject {
    func recordedTimeDidChange(secondsRecorded: Int)
}

// MARK: - RecorderController

public class RecorderController {

    public struct AudioRecordingResult {
        public let url: URL
        public let transcription: String?
        public let recordedTimeInMilliseconds: Int
    }

    public enum Error: Swift.Error, LocalizedError {
        case deniedRecordPermissionRequest
        case audioSessionIsAlreadyInProgress

        public var errorDescription: String? {
            switch self {
            case .deniedRecordPermissionRequest:
                return "Failed to find permission to access the microphone, go to settings and turn it on from there"
            case .audioSessionIsAlreadyInProgress:
                return "End the current audio session before starting a new one"
            }
        }
    }

    private var audioRecorder: AVAudioRecorder?

    private var recordedTimeInSeconds: Int = 0

    private var timer: Timer?

    public var isSessionActive: Bool = false

    public weak var delegate: RecorderControllerDelegate?

    public init() {}

    private func startTimer() {
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

    public func startRecordingSession() throws {
        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            throw Error.deniedRecordPermissionRequest
        }

        guard isSessionActive == false, audioRecorder == nil else {
            throw Error.audioSessionIsAlreadyInProgress
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
        audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
        startTimer()
        isSessionActive = true
        setPrefersNoInterruptionsFromSystemAlerts(true)
        audioRecorder?.record()
    }

    public func resumeRecording() {
        guard audioRecorder != nil else {
            return
        }

        audioRecorder?.record()
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

        isSessionActive = false

        setPrefersNoInterruptionsFromSystemAlerts(false)

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        if recognizer?.isAvailable == true {
            recognizer?.recognitionTask(with: request) { result, _ in
                let transcription = result?.bestTranscription.formattedString
                completion(AudioRecordingResult(url: url, transcription: transcription, recordedTimeInMilliseconds: recordedTimeInMilliseconds))
            }
        } else {
            print("Device doesn't support speech recognition")
            completion(AudioRecordingResult(url: url, transcription: nil, recordedTimeInMilliseconds: recordedTimeInMilliseconds))
        }
    }

    public func deleteRecordingSession() {
        guard audioRecorder != nil else {
            return
        }

        invalidateTimer()

        recordedTimeInSeconds = 0
        delegate?.recordedTimeDidChange(secondsRecorded: recordedTimeInSeconds)

        audioRecorder?.stop()
        audioRecorder?.deleteRecording()

        isSessionActive = false

        setPrefersNoInterruptionsFromSystemAlerts(false)
    }

    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}
