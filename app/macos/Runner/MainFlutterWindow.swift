import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // The layout is made for phones, so the window starts upright.
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 480, height: 900)
    if let visible = NSScreen.main?.visibleFrame {
      windowFrame.size.height = min(windowFrame.size.height, visible.height)
      windowFrame.origin.y = visible.maxY - windowFrame.size.height
    }
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.contentMinSize = NSSize(width: 380, height: 560)
    self.title = "Mobile Slice"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
