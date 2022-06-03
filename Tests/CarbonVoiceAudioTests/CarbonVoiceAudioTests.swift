import XCTest
import AVKit
import AVFoundation

@testable import CarbonVoiceAudio

@available(watchOS 7.3, *)
final class CarbonVoiceAudioTests: XCTestCase {

    let audioController: AudioControllerProtocol = AudioController()

    let playerController: PlayerControllerProtocol = PlayerController()

    let recorderController: RecorderControllerProtocol = RecorderController()

    let sampleAudioSoundURL: URL = URL(string: "https://www.kozco.com/tech/piano2.wav")!
}

// MARK: - AudioControllerProtocol

@available(watchOS 7.3, *)
extension CarbonVoiceAudioTests {
    func testGetCurrentSessionCategoryName() {
        let result = audioController.getCurrentSessionCategoryName()
        XCTAssertNotNil(result)
    }

    func testGetCurrentInput() {
        let result = audioController.getCurrentInput()
        XCTAssertNil(result)
    }

    func testGetCurrentOutput() {
        let result = audioController.getCurrentOutput()
        XCTAssertNotNil(result)
    }
}

// MARK: - PlayerControllerProtocol

@available(watchOS 7.3, *)
extension CarbonVoiceAudioTests {
    func testPlay() throws {
        let expectation = self.expectation(description: "testPlay")
        var errorResult: Error?

        playerController.play(url: sampleAudioSoundURL, rate: 0.8, position: 0.0) { result in
            switch result {
            case .success:
                errorResult = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    expectation.fulfill()
                }
            case .failure(let error):
                errorResult = error
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5, handler: nil)

        XCTAssertNil(errorResult)

        let isPlaying = try XCTUnwrap(playerController.playerInfo.isPlaying)
        XCTAssertTrue(isPlaying)

        XCTAssertEqual(0.8, playerController.playerInfo.playbackSpeed)
    }

    func testPause() throws {
        let expectation = self.expectation(description: "testPause")
        var errorResult: Error?

        playerController.play(url: sampleAudioSoundURL, rate: 1.0, position: 0.0) { [weak self] result in
            switch result {
            case .success:
                errorResult = nil
                self?.playerController.pause()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    expectation.fulfill()
                }
            case .failure(let error):
                errorResult = error
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5, handler: nil)

        XCTAssertNil(errorResult)

        let isPlaying = try XCTUnwrap(playerController.playerInfo.isPlaying)
        XCTAssertFalse(isPlaying)
    }

    func testResume() throws {
        let expectation = self.expectation(description: "testResume")
        var errorResult: Error?

        playerController.play(url: sampleAudioSoundURL, rate: 1.0, position: 0.0) { [weak self] result in
            switch result {
            case .success:
                errorResult = nil
                self?.playerController.pause()
                self?.playerController.resume()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    expectation.fulfill()
                }
            case .failure(let error):
                errorResult = error
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 10, handler: nil)

        XCTAssertNil(errorResult)

        let isPlaying = try XCTUnwrap(playerController.playerInfo.isPlaying)
        XCTAssertTrue(isPlaying)
    }

    func testSeek() throws {
        let expectation = self.expectation(description: "testSeek")
        var errorResult: Error?

        playerController.play(url: sampleAudioSoundURL, rate: 1.0, position: 0.0) { [weak self] result in
            switch result {
            case .success:
                errorResult = nil
                self?.playerController.pause()
                self?.playerController.seek(to: 0.50)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    expectation.fulfill()
                }
            case .failure(let error):
                errorResult = error
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 10, handler: nil)

        XCTAssertNil(errorResult)

        let percentage = try XCTUnwrap(playerController.playerInfo.percentage)

        // Allow room for + - 1
        XCTAssertEqual(percentage, 0.50, accuracy: 0.01)
    }

    func testSetPlaybackSpeed() {
        let expectation = self.expectation(description: "testSetPlaybackSpeed")
        var errorResult: Error?

        playerController.play(url: sampleAudioSoundURL, rate: 1.5, position: 0.0) { [weak self] result in
            switch result {
            case .success:
                errorResult = nil
                // Weird state, setting playback speed needs to be done at "play" method for the most optimal experience
                // Otherwise it can only be set after half a second (or more) of calling "play" method
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.playerController.setPlaybackSpeed(0.9)
                    expectation.fulfill()
                }
            case .failure(let error):
                errorResult = error
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 10, handler: nil)

        XCTAssertNil(errorResult)

        XCTAssertEqual(0.9, playerController.playerInfo.playbackSpeed)
    }

    func testGetCurrentTimeInSeconds() {
        let expectation = self.expectation(description: "testGetCurrentTimeInSeconds")
        var errorResult: Error?

        playerController.play(url: sampleAudioSoundURL, rate: 1.0, position: 0.0) { [weak self] result in
            switch result {
            case .success:
                errorResult = nil
                self?.playerController.pause()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    expectation.fulfill()
                }
            case .failure(let error):
                errorResult = error
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 10, handler: nil)

        XCTAssertNil(errorResult)

        XCTAssertNotNil(playerController.getCurrentTimeInSeconds())
    }
}

// MARK: - RecorderControllerProtocol

@available(watchOS 7.3, *)
extension CarbonVoiceAudioTests {
    func testRequestRecordPermission() {
        let expectation = self.expectation(description: "testRequestRecordPermission")

        var recordPermissionState: Bool?

        recorderController.requestRecordPermission { state in
            recordPermissionState = state
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)

        XCTAssertNotNil(recordPermissionState)
    }

    func testGetRecordPermissionState() {
        XCTAssertNotNil(recorderController.getRecordPermissionState())
    }

    // TODO: - Test these functions when Swift Packages support UI Testing
//    func testStartOrResumeRecording() throws {
//        try recorderController.startOrResumeRecording()
//    }
//
//    func testPauseRecording() {
//
//    }
//
//    func testEndRecordingSession() {
//
//    }
}
