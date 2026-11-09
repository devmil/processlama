import Cocoa
import FlutterMacOS
import QuartzCore

class MainFlutterWindow: NSWindow {
  private let minimumLaunchScreenDuration: TimeInterval = 1.2
  private let launchScreenFadeDuration: TimeInterval = 0.2
  private var launchScreen: NativeLaunchScreen?
  private var launchScreenChannel: FlutterMethodChannel?
  private var launchScreenInstalledAt: TimeInterval?
  private var launchScreenDismissalScheduled = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Keep process-tree hover ordering stable while another app is frontmost.
    flutterViewController.mouseTrackingMode = .always
    backgroundColor = .windowBackgroundColor
    flutterViewController.backgroundColor = .windowBackgroundColor

    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    configureUnifiedTitleBar()
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    ProcessLamaAppUpdateBridge.shared.register(
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    installLaunchScreen(on: flutterViewController)

    super.awakeFromNib()
  }

  /// An empty unified toolbar makes the transparent title bar 52 pt tall and
  /// centres the traffic lights in it, level with Flutter's Meridian toolbar
  /// (`MeridianSize.toolbar`), which draws beneath it and receives the
  /// clicks. The lights then span x 19-79 pt; the Flutter title starts after
  /// them (`_WindowToolbarState._macOSTitleInset`).
  private func configureUnifiedTitleBar() {
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    toolbar = NSToolbar(identifier: "ProcessLamaWindowToolbar")
    if #available(macOS 11.0, *) {
      toolbarStyle = .unified
      titlebarSeparatorStyle = .none
    }
  }

  private func installLaunchScreen(on flutterViewController: FlutterViewController) {
    let launchScreen = NativeLaunchScreen()
    // Cover Flutter before it can submit its first frame. Fading the overlay in
    // exposed the already-built process list for a frame during relaunch.
    launchScreen.alphaValue = 1
    launchScreen.translatesAutoresizingMaskIntoConstraints = false
    flutterViewController.view.addSubview(launchScreen)
    NSLayoutConstraint.activate([
      launchScreen.leadingAnchor.constraint(equalTo: flutterViewController.view.leadingAnchor),
      launchScreen.trailingAnchor.constraint(equalTo: flutterViewController.view.trailingAnchor),
      launchScreen.topAnchor.constraint(equalTo: flutterViewController.view.topAnchor),
      launchScreen.bottomAnchor.constraint(equalTo: flutterViewController.view.bottomAnchor),
    ])
    self.launchScreen = launchScreen
    launchScreenInstalledAt = ProcessInfo.processInfo.systemUptime

    let channel = FlutterMethodChannel(
      name: "de.devmil.processlama/native_launch_screen",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "ready" else {
        result(FlutterMethodNotImplemented)
        return
      }

      self?.dismissLaunchScreen()
      result(nil)
    }
    launchScreenChannel = channel
  }

  private func dismissLaunchScreen() {
    guard let launchScreen, !launchScreenDismissalScheduled else {
      return
    }
    launchScreenDismissalScheduled = true

    let elapsed = ProcessInfo.processInfo.systemUptime - (launchScreenInstalledAt ?? 0)
    let delay = max(0, minimumLaunchScreenDuration - elapsed)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak launchScreen] in
      guard let self, let launchScreen, self.launchScreen === launchScreen else {
        return
      }
      NSAnimationContext.runAnimationGroup { context in
        context.duration = self.launchScreenFadeDuration
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        launchScreen.animator().alphaValue = 0
      } completionHandler: { [weak self, weak launchScreen] in
        launchScreen?.removeFromSuperview()
        self?.launchScreen = nil
        self?.launchScreenChannel = nil
        self?.launchScreenInstalledAt = nil
      }
    }
  }
}

private final class NativeLaunchScreen: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    dirtyRect.fill()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  private func configure() {
    let logoView = NSImageView(image: NSApplication.shared.applicationIconImage)
    logoView.imageScaling = .scaleProportionallyUpOrDown
    logoView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(logoView)

    NSLayoutConstraint.activate([
      logoView.centerXAnchor.constraint(equalTo: centerXAnchor),
      logoView.centerYAnchor.constraint(equalTo: centerYAnchor),
      logoView.widthAnchor.constraint(equalToConstant: 128),
      logoView.heightAnchor.constraint(equalToConstant: 128),
    ])
  }
}
