import XCTest
@testable import CarbonVoiceAudio

final class CarbonVoiceAudioTests: XCTestCase {

    let audioController: AudioControllerProtocol = AudioController()

    let playerController: PlayerControllerProtocol = PlayerController()

    let recorderController: RecorderControllerProtocol = RecorderController()

    func testInitializeAudio() throws {
        var errorResult: Error?
        let result = audioController.initializeAudioController()
        switch result {
        case .success:
            errorResult = nil
        case .failure(let error):
            errorResult = error
        }
        XCTAssertNil(errorResult)
    }

    func testCurrentCategoryName() throws {
        let result = audioController.getCurrentSessionCategoryName()
        XCTAssertNotNil(result)
    }

    func testPlay() throws {
        let expectation = self.expectation(description: "Prepare player to play")
        var errorResult: Error?

        playerController.play(url: URL(string: "https://www.kozco.com/tech/piano2.wav")!, rate: 1.0, position: 0.0) { result in
            switch result {
            case .success:
                errorResult = nil
            case .failure(let error):
                errorResult = error
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5, handler: nil)

        XCTAssertNil(errorResult)
    }

}
