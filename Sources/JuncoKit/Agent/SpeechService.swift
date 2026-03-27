// SpeechService.swift — On-device speech transcription for /speak command
//
// Uses SFSpeechRecognizer for on-device speech recognition.
// Listens for a configurable duration, then returns the transcript.

#if canImport(Speech)
import Foundation
import Speech

/// On-device speech transcription service.
public actor SpeechService {
  private let recognizer: SFSpeechRecognizer?

  public init(locale: Locale = Locale(identifier: "en-US")) {
    self.recognizer = SFSpeechRecognizer(locale: locale)
  }

  /// Whether speech recognition is available on this device.
  public var isAvailable: Bool {
    recognizer?.isAvailable ?? false
  }

  /// Request authorization for speech recognition.
  /// Must be called before transcribe().
  public func requestAuthorization() async -> Bool {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
  }

  /// Transcribe from the default audio input for `duration` seconds.
  /// Returns the transcribed text.
  public func transcribe(duration: TimeInterval = 10) async throws -> String {
    guard let recognizer, recognizer.isAvailable else {
      throw SpeechError.unavailable
    }

    guard await requestAuthorization() else {
      throw SpeechError.notAuthorized
    }

    let audioEngine = AVAudioEngine()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = false
    request.requiresOnDeviceRecognition = true  // Force on-device

    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)

    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      request.append(buffer)
    }

    audioEngine.prepare()
    try audioEngine.start()

    // Record for duration
    try await Task.sleep(for: .seconds(duration))

    audioEngine.stop()
    inputNode.removeTap(onBus: 0)
    request.endAudio()

    // Get final transcription
    let rec = recognizer  // capture for Sendable
    let transcript: String = try await withCheckedThrowingContinuation { continuation in
      rec.recognitionTask(with: request) { result, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let result, result.isFinal {
          continuation.resume(returning: result.bestTranscription.formattedString)
        }
      }
    }
    return transcript
  }
}

public enum SpeechError: Error, Sendable {
  case unavailable
  case notAuthorized
  case transcriptionFailed(String)
}
#endif
