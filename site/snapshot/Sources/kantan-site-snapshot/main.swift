// Renders a web page to a PNG with WebKit.
//
//   kantan-site-snapshot <page> <width> <height> <scale> <out.png>
//
// The page is a file path or an http(s) URL, either with a query string.
// The page is drawn at `width` by `height` points, `scale` pixels to the point.
// Its transparent areas stay transparent.
import AppKit
import WebKit

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("kantan-site-snapshot: \(message)\n".utf8))
  exit(1)
}

struct Options {
  let page: URL
  let size: NSSize
  let scale: Double
  let output: URL

  init(_ args: [String]) {
    guard args.count == 6, let width = Double(args[2]), let height = Double(args[3]),
      let scale = Double(args[4])
    else {
      fail("usage: kantan-site-snapshot <page> <width> <height> <scale> <out.png>")
    }
    if args[1].hasPrefix("http://") || args[1].hasPrefix("https://"), let url = URL(string: args[1])
    {
      self.page = url
    } else {
      // A file path with an optional query string
      let parts = args[1].split(separator: "?", maxSplits: 1).map(String.init)
      var page = URLComponents(url: URL(fileURLWithPath: parts[0]), resolvingAgainstBaseURL: false)!
      page.percentEncodedQuery = parts.count > 1 ? parts[1] : nil
      self.page = page.url!
    }
    self.size = NSSize(width: width, height: height)
    self.scale = scale
    self.output = URL(fileURLWithPath: args[5])
  }
}

@MainActor
final class Snapshotter: NSObject, WKNavigationDelegate {
  let options: Options
  let window: NSWindow
  let webView: WKWebView

  init(_ options: Options) {
    self.options = options
    let frame = NSRect(origin: .zero, size: options.size)
    webView = WKWebView(frame: frame)
    webView.setValue(false, forKey: "drawsBackground")
    // An offscreen window, so WebKit lays out and paints the page.
    window = NSWindow(
      contentRect: frame.offsetBy(dx: -20000, dy: -20000), styleMask: .borderless,
      backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.contentView = webView
    super.init()
    webView.navigationDelegate = self
  }

  func load() {
    window.orderFrontRegardless()
    if options.page.isFileURL {
      // Pages link files in the folders above them, as the docs do.
      webView.loadFileURL(options.page, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    } else {
      webView.load(URLRequest(url: options.page))
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    Task { @MainActor in
      // Waits for the fonts, then a moment for React to paint with them.
      _ = try? await webView.callAsyncJavaScript(
        "await document.fonts.ready; await new Promise(r => setTimeout(r, 300));",
        contentWorld: .page)
      let config = WKSnapshotConfiguration()
      config.rect = webView.bounds
      config.afterScreenUpdates = true
      config.snapshotWidth = NSNumber(value: options.size.width * options.scale)
      guard let image = try? await webView.takeSnapshot(configuration: config) else {
        fail("WebKit couldn't snapshot \(options.page)")
      }
      save(image)
      exit(0)
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    fail(error.localizedDescription)
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    fail(error.localizedDescription)
  }

  func save(_ image: NSImage) {
    let pixels = (
      width: Int(options.size.width * options.scale),
      height: Int(options.size.height * options.scale)
    )
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels.width, pixelsHigh: pixels.height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { fail("can't make a \(pixels.width)x\(pixels.height) image") }
    bitmap.size = options.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(origin: .zero, size: options.size))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
      fail("can't encode the PNG")
    }
    do { try png.write(to: options.output) } catch { fail(error.localizedDescription) }
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let snapshotter = Snapshotter(Options(CommandLine.arguments))
snapshotter.load()
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { fail("timed out loading the page") }
app.run()
