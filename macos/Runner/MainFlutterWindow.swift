import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var privateCloud: BookWormICloud?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    privateCloud = BookWormICloud(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
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
