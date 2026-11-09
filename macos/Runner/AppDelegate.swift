import Cocoa
import FlutterMacOS
import Sparkle

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

final class ProcessLamaAppUpdateBridge: NSObject, SPUUpdaterDelegate {
  static let shared = ProcessLamaAppUpdateBridge()

  private let channelName = "de.devmil.processlama/app_update"
  private var methodChannel: FlutterMethodChannel?
  private var userDriver: SPUStandardUserDriver?
  private var updater: SPUUpdater?
  private var feedURL: String?
  private var allowedChannels = Set<String>()

  func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: binaryMessenger)
    methodChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configure":
      guard let arguments = call.arguments as? [String: Any],
            let feedURL = arguments["feedUrl"] as? String,
            let releaseChannel = arguments["releaseChannel"] as? String,
            let interval = arguments["scheduledCheckIntervalSeconds"] as? Int else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "configure requires feedUrl, releaseChannel, and scheduledCheckIntervalSeconds.",
          details: nil))
        return
      }
      configure(
        feedURL: feedURL,
        releaseChannel: releaseChannel,
        scheduledCheckIntervalSeconds: interval)
      result(nil)
    case "checkForUpdates":
      updater?.checkForUpdates()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func configure(
    feedURL: String,
    releaseChannel: String,
    scheduledCheckIntervalSeconds: Int
  ) {
    self.feedURL = feedURL
    allowedChannels = releaseChannel == "beta" ? ["beta"] : []
    ensureUpdater()
    updater?.updateCheckInterval = TimeInterval(scheduledCheckIntervalSeconds)
    updater?.resetUpdateCycle()
  }

  private func ensureUpdater() {
    guard updater == nil else {
      return
    }

    let hostBundle = Bundle.main
    let userDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
    let updater = SPUUpdater(
      hostBundle: hostBundle,
      applicationBundle: hostBundle,
      userDriver: userDriver,
      delegate: self)
    updater.clearFeedURLFromUserDefaults()
    try? updater.start()

    self.userDriver = userDriver
    self.updater = updater
  }

  func allowedChannels(for updater: SPUUpdater) -> Set<String> {
    allowedChannels
  }

  func feedURLString(for updater: SPUUpdater) -> String? {
    feedURL
  }
}
