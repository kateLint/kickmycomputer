import Cocoa
import WebKit
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate {
    
    var window: NSWindow!
    var webView: WKWebView!
    var statusItem: NSStatusItem!
    
    let engine = InteractionEngine()
    private var localEventMonitor: Any?
    private var accumulatedScrollPet: CGFloat = 0.0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Initialize macOS System Menu Bar Status Item
        setupStatusItem()
        
        // 2. Setup the stunning dashboard window
        setupWindow()
        
        // 3. Setup WebKit browser instance
        setupWebView()
        
        // 4. Connect Swift engine to WKWebView
        engine.webView = webView
        
        // 5. Load the local static HTML frontend assets
        loadDashboard()
        
        // 6. Setup local window event listeners for taps & pressure spikes
        setupLocalEventMonitors()
        
        // 7. Request physical microphone usage permissions on first run
        requestMicrophoneAccess()
        
        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // --- Window Architecture ---
    private func setupWindow() {
        let mask = NSWindow.StyleMask([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: mask,
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.title = "KickMyComputer Dashboard"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1.0)
        
        // Make background vibrant with backdrop blur
        let visualEffect = NSVisualEffectView(frame: window.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.state = .active
        visualEffect.material = .underWindowBackground
        visualEffect.blendingMode = .behindWindow
        
        window.contentView?.addSubview(visualEffect)
        window.makeKeyAndOrderFront(nil)
    }
    
    // --- WebKit Architecture ---
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        
        // Hook up Swift callback bridge under the identifier 'interaction'
        userContent.add(engine, name: "interaction")
        configuration.userContentController = userContent
        
        // Enable local file permissions for sandbox assets loading
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        
        let webViewFrame = window.contentView!.bounds
        webView = WKWebView(frame: webViewFrame, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        // Transparent WebView base
        webView.setValue(false, forKey: "drawsBackground")
        
        window.contentView?.addSubview(webView)
    }
    
    private func loadDashboard() {
        // Hybrid resolver: standard macOS bundle resource locator, with local CLI fallback
        if let resPath = Bundle.main.resourcePath, FileManager.default.fileExists(atPath: "\(resPath)/web/index.html") {
            let htmlPath = "\(resPath)/web/index.html"
            let fileURL = URL(fileURLWithPath: htmlPath)
            let directoryURL = URL(fileURLWithPath: "\(resPath)/web")
            webView.loadFileURL(fileURL, allowingReadAccessTo: directoryURL)
            print("[INFO] Loading Web UI from app bundle resources: \(htmlPath)")
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            let htmlPath = "\(currentDir)/web/index.html"
            let fileURL = URL(fileURLWithPath: htmlPath)
            let directoryURL = URL(fileURLWithPath: "\(currentDir)/web")
            webView.loadFileURL(fileURL, allowingReadAccessTo: directoryURL)
            print("[INFO] Loading Web UI from current directory CLI fallback: \(htmlPath)")
        }
    }
    
    // --- System Status Bar Menu Tray ---
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "KickMyComputer")
                button.image?.isTemplate = true
            } else {
                button.title = "💻"
            }
            button.action = #selector(statusBarClicked(_:))
            button.target = self
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Dashboard", action: #selector(showWindow), keyEquivalent: "d"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Mute Sensors", action: #selector(muteEngine), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: "Unmute Sensors", action: #selector(unmuteEngine), keyEquivalent: "u"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Exit Engine", action: #selector(exitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc func statusBarClicked(_ sender: Any?) {
        // standard status click
    }
    
    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func muteEngine() {
        engine.stopMicMonitoring()
        webView.evaluateJavaScript("addLog('[SYSTEM] Sensory systems muted.', '')", completionHandler: nil)
    }
    
    @objc func unmuteEngine() {
        engine.startMicMonitoring()
        webView.evaluateJavaScript("addLog('[SYSTEM] Sensory systems active.', '')", completionHandler: nil)
    }
    
    @objc func exitApp() {
        engine.stopMicMonitoring()
        NSApplication.shared.terminate(nil)
    }
    
    // --- Window Local Input Event Monitor ---
    private func setupLocalEventMonitors() {
        // Listens to Force Touch pressure changes, clicks, and scroll wheel gestures inside the app window
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .pressure, .scrollWheel]) { [weak self] event in
            guard let self = self else { return event }
            
            if event.type == .pressure {
                let stage = event.stage
                let pressure = event.pressure
                
                if stage == 2 || pressure > 0.92 {
                    self.engine.triggerInteraction(type: "hard_hit", amplitude: Float(pressure))
                } else if pressure > 0.50 && pressure < 0.85 {
                    self.engine.triggerInteraction(type: "hit", amplitude: Float(pressure))
                }
            } else if event.type == .leftMouseDown {
                // If it is a double click or rapid press, treat as moderate hit
                if event.clickCount >= 2 {
                    self.engine.triggerInteraction(type: "hit", amplitude: 0.6)
                }
            } else if event.type == .scrollWheel {
                let dy = abs(event.scrollingDeltaY)
                let dx = abs(event.scrollingDeltaX)
                
                if dy > 0.05 || dx > 0.05 {
                    self.accumulatedScrollPet += (dx + dy)
                    if self.accumulatedScrollPet > 8.0 {
                        self.accumulatedScrollPet = 0
                        self.engine.triggerInteraction(type: "pet", amplitude: 0.08)
                    }
                }
            }
            return event
        }
    }
    
    // --- Audio Permissions Request ---
    private func requestMicrophoneAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            self.engine.startMicMonitoring()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.engine.startMicMonitoring()
                    }
                }
            }
        case .denied, .restricted:
            print("[WARNING] Microphone permission is denied/restricted.")
        @unknown default:
            break
        }
    }
    
    // --- Navigation Delegates ---
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[INFO] Dashboard Web interface loaded successfully.")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        engine.stopMicMonitoring()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// --- Entry point ---
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
