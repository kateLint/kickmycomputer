// Elements Selection
const container = document.getElementById('avatar-container');
const avatar = document.getElementById('laptop-avatar');
const statusBadge = document.getElementById('system-status');
const lastActionHUD = document.getElementById('hud-last-action');
const sensoryLevelHUD = document.getElementById('hud-sensory-level');
const logFeed = document.getElementById('log-feed');
const waveCanvas = document.getElementById('wave-canvas');
const micSlider = document.getElementById('mic-threshold');
const petSlider = document.getElementById('pet-threshold');
const micValText = document.getElementById('mic-val');
const petValText = document.getElementById('pet-val');

// State tracking
let currentState = 'idle';
let stateTimeout = null;
let touchPetAccumulator = 0;
let lastTouchX = 0;
let lastTouchTime = Date.now();

// Canvas Initialization
const ctx = waveCanvas.getContext('2d');
let animationFrameId;
let currentAmplitude = 0;
let targetAmplitude = 0;

// Resize canvas properly
function resizeCanvas() {
    waveCanvas.width = waveCanvas.parentElement.clientWidth;
    waveCanvas.height = waveCanvas.parentElement.clientHeight;
}
window.addEventListener('resize', resizeCanvas);
resizeCanvas();

// --- Particle Emitter System ---
function spawnParticle(type) {
    const rect = avatar.getBoundingClientRect();
    const containerRect = container.getBoundingClientRect();
    
    const particle = document.createElement('div');
    particle.className = 'particle';
    
    // Random position starting from the laptop screen
    const x = (rect.left - containerRect.left) + (rect.width / 4) + (Math.random() * (rect.width / 2));
    const y = (rect.top - containerRect.top) + (rect.height / 3);
    
    particle.style.left = `${x}px`;
    particle.style.top = `${y}px`;
    
    if (type === 'heart') {
        particle.innerHTML = '🌸';
        particle.style.fontSize = `${12 + Math.random() * 12}px`;
    } else if (type === 'spark') {
        const sparks = ['⚡', '🔥', '💥', '💀'];
        particle.innerHTML = sparks[Math.floor(Math.random() * sparks.length)];
        particle.style.fontSize = `${14 + Math.random() * 16}px`;
    } else {
        particle.innerHTML = '✨';
    }
    
    container.appendChild(particle);
    
    // Remove after animation completes
    setTimeout(() => {
        particle.remove();
    }, 1200);
}

// --- Companion Avatar State Machine ---
function setInteractionState(state, forceSpeechText = '') {
    // Clear any pending state reversion
    if (stateTimeout) {
        clearTimeout(stateTimeout);
        stateTimeout = null;
    }
    
    currentState = state;
    
    // Reset classes
    container.className = 'avatar-container';
    
    let label = 'STANDBY';
    let sensory = '0%';
    
    if (state === 'petting') {
        container.classList.add('state-petting');
        label = '🌸 PETTED';
        sensory = '35%';
        
        // Spawn hearts
        for (let i = 0; i < 4; i++) {
            setTimeout(() => spawnParticle('heart'), i * 200);
        }
        
        // Revert to idle after 2.5s
        stateTimeout = setTimeout(() => revertToIdle(), 2500);
        
    } else if (state === 'hit') {
        container.classList.add('state-hit');
        label = '⚡ IMPACT (MEDIUM)';
        sensory = '68%';
        
        // Spark particles
        for (let i = 0; i < 5; i++) {
            spawnParticle('spark');
        }
        
        stateTimeout = setTimeout(() => revertToIdle(), 1800);
        
    } else if (state === 'hard-hit') {
        container.classList.add('state-hard-hit');
        label = '🔥 IMPACT (CRITICAL)';
        sensory = '100%';
        
        // High density spark particles
        for (let i = 0; i < 8; i++) {
            setTimeout(() => spawnParticle('spark'), i * 80);
        }
        
        stateTimeout = setTimeout(() => revertToIdle(), 2500);
    }
    
    // Update HUD
    lastActionHUD.textContent = label;
    sensoryLevelHUD.textContent = sensory;
    
    if (state !== 'idle') {
        // Pulse system status badge red or purple depending on state
        statusBadge.style.background = state === 'hard-hit' ? 'rgba(239, 68, 68, 0.15)' : 'rgba(139, 92, 246, 0.15)';
        statusBadge.style.borderColor = state === 'hard-hit' ? 'var(--crimson)' : 'var(--primary)';
        statusBadge.querySelector('.status-text').textContent = state === 'hard-hit' ? 'CRITICAL SHOCK' : 'INTERACTION INCOMING';
        statusBadge.querySelector('.status-dot').style.backgroundColor = state === 'hard-hit' ? 'var(--crimson)' : 'var(--primary)';
    }
}

function revertToIdle() {
    container.className = 'avatar-container';
    currentState = 'idle';
    lastActionHUD.textContent = 'STANDBY';
    sensoryLevelHUD.textContent = '0%';
    
    // Reset status badge
    statusBadge.style.background = 'rgba(6, 182, 212, 0.08)';
    statusBadge.style.borderColor = 'rgba(6, 182, 212, 0.2)';
    statusBadge.querySelector('.status-text').textContent = 'MONITORS ONLINE';
    statusBadge.querySelector('.status-dot').style.backgroundColor = 'var(--cyan)';
}

// --- Live Oscilloscope Visualizer ---
let wavePhase = 0;
function drawWave() {
    ctx.clearRect(0, 0, waveCanvas.width, waveCanvas.height);
    
    // Interpolate current amplitude for smoothness
    currentAmplitude += (targetAmplitude - currentAmplitude) * 0.15;
    
    const width = waveCanvas.width;
    const height = waveCanvas.height;
    const midY = height / 2;
    
    ctx.beginPath();
    ctx.lineWidth = 2.5;
    
    // Color changes based on the amplitude severity
    if (currentState === 'hard-hit') {
        ctx.strokeStyle = '#ef4444';
        ctx.shadowColor = '#ef4444';
    } else if (currentState === 'hit') {
        ctx.strokeStyle = '#8b5cf6';
        ctx.shadowColor = '#8b5cf6';
    } else if (currentState === 'petting') {
        ctx.strokeStyle = '#ec4899';
        ctx.shadowColor = '#ec4899';
    } else {
        ctx.strokeStyle = '#06b6d4';
        ctx.shadowColor = '#06b6d4';
    }
    
    ctx.shadowBlur = 6;
    
    // Draw oscilloscope sine-like wave
    for (let x = 0; x < width; x++) {
        // Form a wave shape that tapers at the screen edges
        const edgeTaper = Math.sin((x / width) * Math.PI);
        const baseSine = Math.sin((x * 0.035) + wavePhase);
        const noise = (Math.sin(x * 0.1 + wavePhase * 2) * 0.3);
        
        // Final amplitude calculated from native microphone feedback + ambient organic micro-noise
        const amp = (currentAmplitude * 28 + 2.5) * edgeTaper;
        const y = midY + (baseSine + noise) * amp;
        
        if (x === 0) {
            ctx.moveTo(x, y);
        } else {
            ctx.lineTo(x, y);
        }
    }
    
    ctx.stroke();
    ctx.shadowBlur = 0; // Reset glow
    
    // Update phase
    wavePhase += 0.08 + (currentAmplitude * 0.2);
    
    // Fade amplitude down slowly if no active sound updates are received
    targetAmplitude *= 0.92;
    
    animationFrameId = requestAnimationFrame(drawWave);
}
drawWave();

// --- Live Telemetry Feed Logger ---
function addLog(text, type = '') {
    const entry = document.createElement('div');
    entry.className = 'log-entry';
    
    if (type === 'pet') {
        entry.classList.add('log-entry-pet');
    } else if (type === 'hit') {
        entry.classList.add('log-entry-hit');
    } else if (type === 'hard-hit') {
        entry.classList.add('log-entry-hard');
    }
    
    const timestamp = new Date().toLocaleTimeString();
    entry.textContent = `[${timestamp}] ${text}`;
    
    logFeed.appendChild(entry);
    
    // Auto-scroll
    logFeed.scrollTop = logFeed.scrollHeight;
    
    // Keep feed clean (limit to 100 entries)
    while (logFeed.children.length > 100) {
        logFeed.children[0].remove();
    }
}

// --- Bidirectional WebKit Swift Native Bridge API ---

// 1. Receives raw physical interactions triggered by native sensors
window.onPhysicalInteraction = function(type, amplitude) {
    const ampVal = parseFloat(amplitude);
    
    if (type === 'pet') {
        addLog(`PET DETECTED (RMS: ${ampVal.toFixed(4)}) - Laptop feeling appreciated.`, 'pet');
        setInteractionState('petting');
    } else if (type === 'hit') {
        addLog(`SHOCK DETECTED: Tap/Hit (Level: ${(ampVal * 100).toFixed(0)}%)`, 'hit');
        setInteractionState('hit');
    } else if (type === 'hard_hit') {
        addLog(`CRITICAL SHOCK DETECTED: Hard Hit! (Level: ${(ampVal * 100).toFixed(0)}%)`, 'hard-hit');
        setInteractionState('hard-hit');
    }
};

// 2. Receives real-time microphone stream amplitude updates
window.onAudioStream = function(amplitude) {
    const val = parseFloat(amplitude);
    targetAmplitude = val;
};

// Helper: Safely post message to native AppKit context
function postToNative(action, payload = {}) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.interaction) {
        window.webkit.messageHandlers.interaction.postMessage({
            action: action,
            ...payload
        });
    }
}

// --- UI Interaction Handlers ---

// Slider adjustments
micSlider.addEventListener('input', (e) => {
    const val = e.target.value;
    micValText.textContent = `${val}%`;
    postToNative('setMicThreshold', { value: parseInt(val) });
});

petSlider.addEventListener('input', (e) => {
    const val = e.target.value;
    petValText.textContent = `${val}%`;
    postToNative('setPetThreshold', { value: parseInt(val) });
});

// Clear Feed
document.getElementById('btn-clear-logs').addEventListener('click', () => {
    logFeed.innerHTML = '';
    addLog('Telemetry feed cleared.', '');
});

// Manual simulations
document.getElementById('btn-simulate-pet').addEventListener('click', () => {
    window.onPhysicalInteraction('pet', 0.12);
    postToNative('simulate', { type: 'pet' });
});

document.getElementById('btn-simulate-hit').addEventListener('click', () => {
    window.onPhysicalInteraction('hit', 0.65);
    postToNative('simulate', { type: 'hit' });
});

document.getElementById('btn-simulate-hard').addEventListener('click', () => {
    window.onPhysicalInteraction('hard_hit', 0.98);
    postToNative('simulate', { type: 'hard_hit' });
});

// --- Mouse / Touch gesture directly on Screen/Trackpad UI for petting ---
let isDragging = false;

function handlePetGesture(clientX) {
    if (!isDragging) return;
    
    const now = Date.now();
    const diffTime = now - lastTouchTime;
    
    if (diffTime > 0) {
        const diffX = Math.abs(clientX - lastTouchX);
        const velocity = diffX / diffTime;
        
        // Gentle moves only
        if (velocity > 0.05 && velocity < 1.5) {
            touchPetAccumulator += diffX;
            
            // Reached pet threshold
            if (touchPetAccumulator > 300) {
                touchPetAccumulator = 0;
                window.onPhysicalInteraction('pet', 0.08);
                postToNative('simulate', { type: 'pet' });
            }
        }
    }
    
    lastTouchX = clientX;
    lastTouchTime = now;
}

container.addEventListener('mousedown', (e) => {
    isDragging = true;
    lastTouchX = e.clientX;
    lastTouchTime = Date.now();
    touchPetAccumulator = 0;
});

container.addEventListener('mousemove', (e) => {
    handlePetGesture(e.clientX);
});

window.addEventListener('mouseup', () => {
    isDragging = false;
});

// Touch devices (Trackpad taps inside web view)
container.addEventListener('touchstart', (e) => {
    isDragging = true;
    if (e.touches.length > 0) {
        lastTouchX = e.touches[0].clientX;
        lastTouchTime = Date.now();
        touchPetAccumulator = 0;
    }
});

container.addEventListener('touchmove', (e) => {
    if (e.touches.length > 0) {
        handlePetGesture(e.touches[0].clientX);
    }
});

container.addEventListener('touchend', () => {
    isDragging = false;
});

// Capture two-finger trackpad scrolling (wheel event) on the dashboard avatar as petting
let wheelAccumulator = 0;
let lastWheelEventTime = Date.now();

container.addEventListener('wheel', (e) => {
    e.preventDefault(); // Prevent standard page scroll behavior
    
    const now = Date.now();
    // If it's been more than 1 second since last scroll, reset accumulator
    if (now - lastWheelEventTime > 1000) {
        wheelAccumulator = 0;
    }
    
    const delta = Math.abs(e.deltaX) + Math.abs(e.deltaY);
    
    // Gentle scroll speeds only (avoiding aggressive heavy swipes)
    if (delta > 0.1 && delta < 50) {
        wheelAccumulator += delta;
        lastWheelEventTime = now;
        
        // Threshold reached for a pet stroke
        if (wheelAccumulator > 120) {
            wheelAccumulator = 0;
            window.onPhysicalInteraction('pet', 0.10);
            postToNative('simulate', { type: 'pet' });
        }
    }
}, { passive: false });
