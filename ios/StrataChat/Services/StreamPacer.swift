import Foundation

/// Adaptive elastic token pacer for streaming chat responses.
/// Prevents sentence/chunk popping over cellular/proxies while maintaining
/// minimal time-to-first-word and eliminating backlog lag.
@MainActor
public final class StreamPacer {
    private var queue: [String] = []
    private var timer: Timer?
    private let onEmit: (String) -> Void
    private var isDone: Bool = false
    private var onDone: (() -> Void)?
    
    public init(onEmit: @escaping (String) -> Void, onDone: (() -> Void)? = nil) {
        self.onEmit = onEmit
        self.onDone = onDone
    }
    
    deinit {
        timer?.invalidate()
    }
    
    /// Enqueue incoming raw text from a network SSE chunk.
    public func feed(_ text: String) {
        guard !text.isEmpty else { return }
        
        let pieces = Self.tokenize(text)
        queue.append(contentsOf: pieces)
        
        if timer == nil {
            scheduleNextTick()
        }
    }
    
    /// Mark that the server is done generating tokens.
    public func finish() {
        isDone = true
        if !queue.isEmpty {
            scheduleNextTick()
        } else {
            stop()
            onDone?()
        }
    }
    
    /// Immediately flush everything remaining in the queue and stop.
    public func flushAll() {
        timer?.invalidate()
        timer = nil
        if !queue.isEmpty {
            let remaining = queue.joined()
            queue.removeAll()
            onEmit(remaining)
        }
        isDone = true
        onDone?()
    }
    
    /// Cancel the pacer immediately without emitting further tokens.
    public func stop() {
        timer?.invalidate()
        timer = nil
        queue.removeAll()
        isDone = false
    }
    
    private func scheduleNextTick() {
        guard timer == nil else { return }
        guard !queue.isEmpty else {
            if isDone {
                stop()
                onDone?()
            }
            return
        }
        
        // Elastic pacing: adapt delay based on queue depth.
        //
        // Every tick republishes the message array, which re-renders the whole transcript and
        // re-lays out the streaming bubble, so a tick every 5-16ms was burning CPU on long
        // replies and made typing feel laggy. Publishing in batches keeps the typewriter feel
        // at a fraction of the renders.
        let interval: TimeInterval
        if isDone {
            interval = 0.02 // drain what is left when the model is finished
        } else {
            let count = queue.count
            if count <= 2 {
                interval = 0.06
            } else if count <= 6 {
                interval = 0.05
            } else if count <= 12 {
                interval = 0.04
            } else {
                interval = 0.03 // catch-up so backlogs from lag spikes dissolve smoothly
            }
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }
    
    private func tick() {
        timer = nil
        guard !queue.isEmpty else {
            if isDone {
                stop()
                onDone?()
            }
            return
        }
        
        // Batch several tokens per publish. One token per tick looked smooth but re-rendered
        // the transcript 100+ times a second; this keeps a similar reading cadence at a small
        // fraction of the layout passes.
        let batchSize: Int
        if isDone {
            batchSize = max(2, queue.count / 4)
        } else {
            batchSize = max(1, min(queue.count, 2 + queue.count / 3))
        }
        var emitted = ""
        for _ in 0..<min(batchSize, queue.count) {
            emitted += queue.removeFirst()
        }
        
        onEmit(emitted)
        
        if !queue.isEmpty {
            scheduleNextTick()
        } else if isDone {
            stop()
            onDone?()
        }
    }
    
    /// Splits raw text into natural word/whitespace tokens while preserving 100% of characters.
    public static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        
        for char in text {
            current.append(char)
            if char.isWhitespace || char == "\n" {
                tokens.append(current)
                current = ""
            } else if current.count >= 6 {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
