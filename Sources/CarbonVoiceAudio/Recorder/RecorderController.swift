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
        let url: URL
        let transcription: String?
        let recordedTimeInMilliseconds: Int
    }

    public enum Error: Swift.Error, LocalizedError {
        case deniedRecordPermissionRequest
        case failedToInstantiateAVAudioRecorder

        public var errorDescription: String? {
            switch self {
            case .deniedRecordPermissionRequest:
                return "Failed to find permission to access the microphone, go to settings and turn it on from there"
            case .failedToInstantiateAVAudioRecorder:
                return "Failed to instantiate AVAudioRecorder"
            }
        }
    }

    private let localURLToStoreAudioRecordings: URL = {
        let documentsDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let url = NSURL.fileURL(withPath: documentsDirectory).appendingPathComponent("audio_recording.wav")
        return url
    }()

    private var audioRecorder: AVAudioRecorder?

    private var recordedTimeInSeconds: Int = 0

    private var timer: Timer?

    public var isSessionActive: Bool = false

    public weak var delegate: RecorderControllerDelegate?

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

        if audioRecorder == nil {
            do {
                self.audioRecorder = try AVAudioRecorder(url: localURLToStoreAudioRecordings, settings: [:])
            } catch {
                throw Error.failedToInstantiateAVAudioRecorder
            }
        }

        startTimer()
        audioRecorder?.record()
        isSessionActive = true
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
    }
}
