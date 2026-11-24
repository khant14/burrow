import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Keep the sidebar, tabs and a usable terminal on screen.
    self.minSize = NSSize(width: 760, height: 480)
    self.title = "Burrow"
    self.tabbingMode = .disallowed

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
