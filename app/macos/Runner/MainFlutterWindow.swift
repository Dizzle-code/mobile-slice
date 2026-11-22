import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // A slicer wants room: plates, 3D view and settings side by side, as large as the screen allows.
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 1440, height: 900)
    if let visible = NSScreen.main?.visibleFrame {
      windowFrame.size.width = min(windowFrame.size.width, visible.width)
      windowFrame.size.height = min(windowFrame.size.height, visible.height)
      windowFrame.origin.x = visible.midX - windowFrame.size.width / 2
      windowFrame.origin.y = visible.midY - windowFrame.size.height / 2
    }
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // Narrower windows fall back to the phone layout.
    self.contentMinSize = NSSize(width: 420, height: 600)
    self.title = "Mobile Slice"
    self.setFrameAutosaveName("MobileSliceMain")

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
