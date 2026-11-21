import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var privateCloud: BookWormICloud?
  private var speechRenderer: BookWormSpeechRenderer?
  private var audioTransition: BookWormAudioTransition?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BookWormAudioTransition") {
      audioTransition = BookWormAudioTransition(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BookWormSpeechRenderer") {
      speechRenderer = BookWormSpeechRenderer(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BookWormICloud") {
      privateCloud = BookWormICloud(messenger: registrar.messenger())
    }
  }
}

// A finite assertion protects the brief gap between real audio files. It is
// released as soon as playback resumes, never used as a permanent background loop.
final class BookWormAudioTransition {
  private let channel: FlutterMethodChannel
  private var task: UIBackgroundTaskIdentifier = .invalid
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "bookworm/audio_transition", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "begin":
        if self.task == .invalid {
          self.task = UIApplication.shared.beginBackgroundTask(withName: "BookWorm audio handoff") { [weak self] in
            NSLog("BookWorm audio handoff expired; next audio was not ready")
            self?.end()
          }
        }
        result(nil)
      case "end": self.end(); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  private func end() {
    if task != .invalid {
      UIApplication.shared.endBackgroundTask(task)
      task = .invalid
    }
  }
}

// Complete a PCM16 WAV only after AVSpeechSynthesizer has delivered its final
// buffer. The media player never sees an open/unfinalized speech file.
final class BookWormSpeechRenderer: NSObject, AVSpeechSynthesizerDelegate {
  private let channel: FlutterMethodChannel
  private let synth = AVSpeechSynthesizer()
  private var result: FlutterResult?
  private var samples = Data()
  private var sampleRate: Double = 22050
  private var destination: String = ""
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "bookworm/system_speech", binaryMessenger: messenger)
    super.init()
    synth.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      guard call.method == "render", let args = call.arguments as? [String: Any],
        let text = args["text"] as? String, let path = args["path"] as? String else {
        result(FlutterMethodNotImplemented); return
      }
      guard self.result == nil else { result(FlutterError(code: "busy", message: "语音正在准备中", details: nil)); return }
      let url = URL(fileURLWithPath: path).standardizedFileURL
      let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.standardizedFileURL.path
      guard url.path.hasPrefix(caches + "/") || url.path.hasPrefix(NSTemporaryDirectory()) else {
        result(FlutterError(code: "path", message: "语音缓存位置无效", details: nil)); return
      }
      self.result = result; self.destination = path; self.samples = Data()
      let voice = args["voice"] as? [String: String]
      let utterance = AVSpeechUtterance(string: text)
      if let identifier = voice?["identifier"] { utterance.voice = AVSpeechSynthesisVoice(identifier: identifier) }
      if utterance.voice == nil, let name = voice?["name"] {
        utterance.voice = AVSpeechSynthesisVoice.speechVoices().first { $0.name == name && (voice?["locale"] == nil || $0.language == voice?["locale"]) }
      }
      if utterance.voice == nil { utterance.voice = AVSpeechSynthesisVoice(language: voice?["locale"] ?? "zh-CN") }
      utterance.rate = AVSpeechUtteranceDefaultSpeechRate
      self.synth.write(utterance) { [weak self] buffer in
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if Thread.isMainThread { self?.consume(pcm) }
        else { DispatchQueue.main.sync { self?.consume(pcm) } }
      }
    }
  }
  private func consume(_ buffer: AVAudioPCMBuffer) {
    guard result != nil else { return }
    if buffer.frameLength == 0 { finish(); return }
    sampleRate = buffer.format.sampleRate
    let channels = Int(buffer.format.channelCount)
    let frames = Int(buffer.frameLength)
    let interleaved = buffer.format.isInterleaved
    for frame in 0..<frames {
      var value: Float = 0
      for channel in 0..<channels {
        let index = interleaved ? frame * channels + channel : frame
        let bank = interleaved ? 0 : channel
        if let data = buffer.floatChannelData { value += data[bank][index] }
        else if let data = buffer.int16ChannelData { value += Float(data[bank][index]) / 32768 }
        else if let data = buffer.int32ChannelData { value += Float(data[bank][index]) / 2147483648 }
      }
      let average = value / Float(max(1, channels))
      var sample = Int16(max(-32768, min(32767, Int(average * 32767)))).littleEndian
      withUnsafeBytes(of: &sample) { samples.append(contentsOf: $0) }
    }
  }
  private func finish() {
    guard let callback = result else { return }
    defer { result = nil; samples = Data() }
    guard !samples.isEmpty else { callback(FlutterError(code: "empty", message: "此系统音色未生成音频，请更换音色", details: nil)); return }
    var wav = Data()
    func tag(_ value: String) { wav.append(value.data(using: .ascii)!) }
    func number<T: FixedWidthInteger>(_ value: T) {
      var number = value.littleEndian; withUnsafeBytes(of: &number) { wav.append(contentsOf: $0) }
    }
    tag("RIFF"); number(UInt32(36 + samples.count)); tag("WAVEfmt "); number(UInt32(16))
    number(UInt16(1)); number(UInt16(1)); number(UInt32(sampleRate)); number(UInt32(sampleRate) * 2)
    number(UInt16(2)); number(UInt16(16)); tag("data"); number(UInt32(samples.count)); wav.append(samples)
    do { try wav.write(to: URL(fileURLWithPath: destination), options: .atomic); callback(1) }
    catch { callback(FlutterError(code: "write", message: "无法保存语音缓存", details: nil)) }
  }
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    result?(FlutterError(code: "cancelled", message: "语音生成已取消", details: nil)); result = nil; samples = Data()
  }
}

// Uses only the app's entitled iCloud Drive container and the system Apple account.
// No file picker, shared STG container, password, or app-server storage.
final class BookWormICloud {
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "bookworm.icloud", qos: .utility)
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "bookworm/icloud", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }
  private func valid(_ key: String) -> Bool {
    key.range(of: "^(book-[a-f0-9]{64}(-[0-9]+\\.part|\\.manifest)|position-[a-f0-9]{64}-[a-f0-9]+\\.json)$", options: .regularExpression) != nil
  }
  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    guard let identifier = args["container"] as? String, identifier.hasPrefix("iCloud.") else {
      result(FlutterError(code: "configuration", message: "iCloud container is not configured", details: nil)); return
    }
    queue.async {
      func finish(_ value: Any?) { DispatchQueue.main.async { result(value) } }
      let files = FileManager.default
      guard files.ubiquityIdentityToken != nil else {
        finish(FlutterError(code: "account", message: "Sign in to iCloud Drive in system settings", details: nil)); return
      }
      guard let container = files.url(forUbiquityContainerIdentifier: identifier) else {
        finish(FlutterError(code: "configuration", message: "The app's iCloud container is unavailable", details: nil)); return
      }
      let folder = container.appendingPathComponent("Documents/BookWorm", isDirectory: true)
      do {
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        if call.method == "connect" { finish(nil); return }
        if call.method == "list" {
          var coordinationError: NSError?
          var outcome: Result<[String], Error>?
          NSFileCoordinator().coordinate(readingItemAt: folder, options: [], error: &coordinationError) { url in
            outcome = Result {
              try files.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                .filter {
                  let values = try $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                  return values.isRegularFile == true && values.isSymbolicLink != true
                }.compactMap { item -> String? in
                  let name = item.lastPathComponent
                  if self.valid(name) { return name }
                  if name.hasPrefix("."), name.hasSuffix(".icloud") {
                    let key = String(name.dropFirst().dropLast(7))
                    return self.valid(key) ? key : nil
                  }
                  return nil
                }
            }
          }
          if let error = coordinationError { throw error }
          guard let value = outcome else { throw CocoaError(.fileReadUnknown) }
          finish(try value.get()); return
        }
        guard let key = args["key"] as? String, self.valid(key) else { throw CocoaError(.fileReadInvalidFileName) }
        let target = folder.appendingPathComponent(key)
        if call.method == "read" {
          let placeholder = folder.appendingPathComponent("." + key + ".icloud")
          if !files.fileExists(atPath: target.path), files.fileExists(atPath: placeholder.path) {
            try files.startDownloadingUbiquitousItem(at: target)
            finish(FlutterError(code: "downloading", message: "iCloud download is in progress", details: nil)); return
          }
          let values = try target.resourceValues(forKeys: [.isSymbolicLinkKey, .ubiquitousItemDownloadingStatusKey, .fileSizeKey])
          guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 2 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
          if let status = values.ubiquitousItemDownloadingStatus, status == .notDownloaded {
            try files.startDownloadingUbiquitousItem(at: target)
            finish(FlutterError(code: "downloading", message: "iCloud download is in progress", details: nil)); return
          }
          var coordinationError: NSError?
          var outcome: Result<Data, Error>?
          NSFileCoordinator().coordinate(readingItemAt: target, options: [], error: &coordinationError) { url in
            outcome = Result { try Data(contentsOf: url) }
          }
          if let error = coordinationError { throw error }
          guard let value = outcome else { throw CocoaError(.fileReadUnknown) }
          let data = try value.get()
          guard data.count <= 2 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
          finish(FlutterStandardTypedData(bytes: data)); return
        }
        if call.method == "write" {
          guard let bytes = args["bytes"] as? FlutterStandardTypedData, bytes.data.count <= 2 * 1024 * 1024 else { throw CocoaError(.fileWriteUnknown) }
          if files.fileExists(atPath: target.path), try target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw CocoaError(.fileWriteNoPermission) }
          var coordinationError: NSError?
          var outcome: Result<Void, Error>?
          NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { url in
            outcome = Result { try bytes.data.write(to: url, options: .atomic) }
          }
          if let error = coordinationError { throw error }
          guard let value = outcome else { throw CocoaError(.fileWriteUnknown) }
          try value.get(); finish(nil); return
        }
        finish(FlutterMethodNotImplemented)
      } catch {
        // Do not expose local paths or account identifiers in errors.
        finish(FlutterError(code: "io", message: "iCloud operation failed", details: nil))
      }
    }
  }
}
