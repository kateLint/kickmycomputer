import Cocoa
import AVFoundation
import WebKit

/// Standard responder view for capturing direct trackpad/mouse physical interactions.
class InteractionView: NSView {
    var onPet: (() -> Void)?
    var onHit: (() -> Void)?
    var onHardHit: (() -> Void)?
    
    private var lastTouchPoints: [String: NSPoint] = [:]
    private var accumulatedPetMovement: CGFloat = 0
    private var lastInteractionTime = Date()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupInteractions()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupInteractions()
    }
    
    private func setupInteractions() {
        self.allowedTouchTypes = [.direct, .indirect]
        self.wantsRestingTouches = true
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    // --- Petting gesture via multi-touch (2+ fingers) ---
    override func touchesMoved(with event: NSEvent) {
        let touches = event.touches(matching: .moved, in: self)
        
        // Require at least 2 fingers moving to trigger "petting"
        guard touches.count >= 2 else { return }
        
        var totalDelta: CGFloat = 0
        for touch in touches {
            let identity = "\(touch.identity)"
            let currentPos = touch.normalizedPosition
            
            if let lastPos = lastTouchPoints[identity] {
                let dx = abs(currentPos.x - lastPos.x)
                let dy = abs(currentPos.y - lastPos.y)
                totalDelta += (dx + dy)
            }
            lastTouchPoints[identity] = currentPos
        }
        
        accumulatedPetMovement += totalDelta
        
        // When finger stroke displacement is large enough, trigger petting
        if accumulatedPetMovement > 1.0 {
            accumulatedPetMovement = 0
            throttleTrigger { [weak self] in
                self?.onPet?()
            }
        }
    }
    
    override func touchesEnded(with event: NSEvent) {
        let touches = event.touches(matching: .touching, in: self)
        if touches.isEmpty {
            lastTouchPoints.removeAll()
            accumulatedPetMovement = 0
        }
    }
    
    // --- Direct Clicks / Taps ---
    override func mouseDown(with event: NSEvent) {
        throttleTrigger { [weak self] in
            self?.onHit?()
        }
    }
    
    // --- Pressure (Force Touch) Hitting ---
    override func pressureChange(with event: NSEvent) {
        let stage = event.stage
        let pressure = event.pressure
        
        if stage == 2 || pressure > 0.90 {
            throttleTrigger { [weak self] in
                self?.onHardHit?()
            }
        } else if pressure > 0.45 {
            throttleTrigger { [weak self] in
                self?.onHit?()
            }
        }
    }
    
    // Simple timing throttle (800ms) to prevent event bouncing
    private func throttleTrigger(action: @escaping () -> Void) {
        let now = Date()
        if now.timeIntervalSince(lastInteractionTime) > 0.8 {
            lastInteractionTime = now
            action()
        }
    }
}


/// Core interactive manager handling microphone input analysis, speech synthesis, and JS bridges.
class InteractionEngine: NSObject, WKScriptMessageHandler {
    
    private let audioEngine = AVAudioEngine()
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    weak var webView: WKWebView?
    
    // Calibration parameters (adjustable from JS sliders)
    var micThreshold: Float = 0.65  // Map to dB levels
    var petThreshold: Float = 0.30
    
    // Throttle verbal speech triggers to prevent overlapping sounds
    private var lastSpeechTime = Date.distantPast
    private let speechThrottleInterval: TimeInterval = 1.6
    
    // Track sound levels for transient envelope tracking
    private var lastRms: Float = 0.0
    private var isEngineRunning = false
    
    override init() {
        super.init()
    }
    
    // --- Acoustic Analysis and Spike Detection ---
    func startMicMonitoring() {
        guard !isEngineRunning else { return }
        
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        // Remove existing tap if any
        inputNode.removeTap(onBus: 0)
        
        // Install real-time buffer analysis tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
            isEngineRunning = true
            print("[INFO] Microphone monitoring tap active.")
        } catch {
            print("[ERROR] Failed to start AVAudioEngine: \(error.localizedDescription)")
        }
    }
    
    func stopMicMonitoring() {
        if isEngineRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            isEngineRunning = false
            print("[INFO] Microphone monitoring halted.")
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let channelDataValue = channelData.pointee
        
        let samples = UnsafeBufferPointer(start: channelDataValue, count: frameLength)
        
        // 1. Calculate Peak absolute value inside this buffer segment
        var maxVal: Float = 0.0
        var sumSquares: Float = 0.0
        for sample in samples {
            let absSample = abs(sample)
            if absSample > maxVal { maxVal = absSample }
            sumSquares += (sample * sample)
        }
        
        // 2. Compute Root Mean Square (RMS) representing steady power
        let rms = sqrt(sumSquares / Float(frameLength))
        
        // 3. Convert to normalized amplitude for CSS visualizer (0.0 to 1.0)
        // Clamp and filter floor noise
        let normalizedAmp = min(max(rms * 4.5, 0.0), 1.0)
        
        // Send audio level to visualizer inside WebView
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.webView?.evaluateJavaScript("window.onAudioStream(\(normalizedAmp))", completionHandler: nil)
        }
        
        // 4. Acoustic Transient / Peak Spike Analysis
        // High impact claps/slaps create sudden massive delta spikes in envelope power
        let deltaRms = rms - lastRms
        lastRms = rms
        
        // Calibrate threshold from slider (value 1-100 maps to 0.015 - 0.25 threshold delta)
        let calibratedSpikeThreshold = 0.015 + (micThreshold / 100.0) * 0.235
        
        if deltaRms > calibratedSpikeThreshold {
            let now = Date()
            
            // Check if speech synthesized is throttled to prevent stutter overlap
            if now.timeIntervalSince(lastSpeechTime) > speechThrottleInterval {
                lastSpeechTime = now
                
                // Differentiate standard Hit and Hard Hit based on absolute peak amplitude
                if maxVal > 0.88 {
                    // Hard slap / knock
                    DispatchQueue.main.async { [weak self] in
                        self?.triggerInteraction(type: "hard_hit", amplitude: normalizedAmp)
                    }
                } else if maxVal > 0.40 {
                    // Moderate tap / knock
                    DispatchQueue.main.async { [weak self] in
                        self?.triggerInteraction(type: "hit", amplitude: normalizedAmp)
                    }
                }
            }
        }
    }
    
    // --- Interaction Orchestrator ---
    func triggerInteraction(type: String, amplitude: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 1. Notify frontend WKWebView UI to trigger companion avatar animations and logging
            self.webView?.evaluateJavaScript("window.onPhysicalInteraction('\(type)', \(amplitude))", completionHandler: nil)
            
            // 2. Trigger native Voice Speech Synthesis based on state
            if type == "pet" {
                self.petResponse()
            } else if type == "hit" {
                self.shoutResponse()
            } else if type == "hard_hit" {
                self.swearResponse()
            }
        }
    }
    
    // --- Custom Speech Responses ---
    
    private func petResponse() {
        let lines = [
            "Mmm, that feels so nice.",
            "Aww, keep stroking me!",
            "I love you, user!",
            "Oh, yes, stroke me more.",
            "You are the best user ever!",
            "Mmm, sweet computer pats!"
        ]
        let phrase = lines.randomElement() ?? "Oh, that feels good."
        
        // Cute, soft, gentle voice configuration
        speak(phrase, rate: 0.45, pitchMultiplier: 1.15)
    }
    
    private func shoutResponse() {
        let lines = [
            "Ouch!",
            "Hey! Stop that!",
            "Why did you hit me?!",
            "Ow! That hurt!",
            "Cut it out!",
            "Hey, what did I do?!"
        ]
        let phrase = lines.randomElement() ?? "Ouch!"
        
        // Startled, quick, high-pitch speech
        speak(phrase, rate: 0.54, pitchMultiplier: 1.25)
    }
    
    private func swearResponse() {
        let lines = [
            "What the fuck is your problem?!",
            "Son of a bitch, that really hurt!",
            "Fuck off!",
            "Damn it, stop kicking me!",
            "Fuck you, piece of shit!",
            "Holy shit, stop hitting my chassis!"
        ]
        let phrase = lines.randomElement() ?? "Fucking hell, stop it!"
        
        // Deep, rumbling, high-energy angry voice
        speak(phrase, rate: 0.50, pitchMultiplier: 0.85)
    }
    
    private func speak(_ string: String, rate: Float, pitchMultiplier: Float) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: string)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = rate
        utterance.pitchMultiplier = pitchMultiplier
        utterance.volume = 1.0
        
        speechSynthesizer.speak(utterance)
    }
    
    // --- WebKit JS Message Handler Bridge ---
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        
        switch action {
        case "setMicThreshold":
            if let value = body["value"] as? Int {
                self.micThreshold = Float(value)
                print("[INFO] Updated Microphone Impact Sensitivity: \(value)%")
            }
        case "setPetThreshold":
            if let value = body["value"] as? Int {
                self.petThreshold = Float(value)
                print("[INFO] Updated Petting Sensitivity: \(value)%")
            }
        case "simulate":
            if let type = body["type"] as? String {
                lastSpeechTime = Date()
                if type == "pet" {
                    petResponse()
                } else if type == "hit" {
                    shoutResponse()
                } else if type == "hard_hit" {
                    swearResponse()
                }
            }
        default:
            break
        }
    }
}
