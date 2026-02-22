import Foundation
import Combine

/// A queued speech item with all associated data
struct SpeechItem {
    let speech: String?
    let expression: String?
    let motion: String?
    let gesture: String?
    let audioBase64: String?
    let speechDuration: Double?
    let interrupt: Bool
}

/// Manages a FIFO queue of speech items, processing them sequentially.
/// Notifies via callbacks when items complete and when the queue empties.
class SpeechQueueManager: ObservableObject {
    @MainActor @Published var queueCount: Int = 0
    @MainActor @Published var isProcessing: Bool = false
    
    private var queue: [SpeechItem] = []
    private let lock = NSLock()
    
    /// Called to process each item (set by ContentView)
    @MainActor var onProcessItem: ((SpeechItem) -> Void)?
    /// Called when an item finishes (for broadcasting events)
    @MainActor var onItemDone: ((Int) -> Void)?  // remaining count
    /// Called when queue becomes empty
    @MainActor var onQueueEmpty: (() -> Void)?
    
    /// Enqueue a speech item. If interrupt is true, clear the queue first.
    @MainActor
    func enqueue(_ item: SpeechItem) {
        if item.interrupt {
            lock.lock()
            queue.removeAll()
            lock.unlock()
            queueCount = 0
        }
        
        lock.lock()
        queue.append(item)
        lock.unlock()
        queueCount = queue.count + (isProcessing ? 1 : 0)
        
        if !isProcessing {
            processNext()
        }
    }
    
    /// Called when current item playback is done
    @MainActor
    func currentItemDone() {
        let remaining: Int
        lock.lock()
        remaining = queue.count
        lock.unlock()
        
        onItemDone?(remaining)
        
        if remaining > 0 {
            processNext()
        } else {
            isProcessing = false
            queueCount = 0
            onQueueEmpty?()
        }
    }
    
    /// Process the next item in the queue
    @MainActor
    private func processNext() {
        lock.lock()
        guard !queue.isEmpty else {
            lock.unlock()
            isProcessing = false
            queueCount = 0
            return
        }
        let item = queue.removeFirst()
        let remaining = queue.count
        lock.unlock()
        
        isProcessing = true
        queueCount = remaining + 1  // +1 for currently processing
        onProcessItem?(item)
    }
    
    /// Get current queue status
    @MainActor
    func getStatus() -> (queueLength: Int, isProcessing: Bool) {
        lock.lock()
        let count = queue.count
        lock.unlock()
        return (count + (isProcessing ? 1 : 0), isProcessing)
    }
    
    /// Clear the queue (but don't stop current playback)
    @MainActor
    func clearQueue() {
        lock.lock()
        queue.removeAll()
        lock.unlock()
        queueCount = isProcessing ? 1 : 0
    }
}
