import Foundation
import UIKit
import BackgroundTasks

public final class BackgroundTaskManager: @unchecked Sendable {
    public static let shared = BackgroundTaskManager()
    
    public static let backgroundTaskIdentifier = "com.noir.stratachat.jobrefresh"
    
    private let lock = NSLock()
    private var activeTasks: [UIBackgroundTaskIdentifier: String] = [:]
    
    private init() {}
    
    /// Starts a background execution task assertion with iOS.
    /// This gives the app execution time (typically ~30s) after moving to the background.
    public func beginTask(name: String) -> UIBackgroundTaskIdentifier {
        var taskId: UIBackgroundTaskIdentifier = .invalid
        
        let start = {
            taskId = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
                guard let self = self else { return }
                self.lock.lock()
                let taskName = self.activeTasks.removeValue(forKey: taskId) ?? name
                self.lock.unlock()
                print("[BackgroundTaskManager] Background task expired by iOS: \(taskName) (\(taskId.rawValue))")
                UIApplication.shared.endBackgroundTask(taskId)
            }
        }
        
        if Thread.isMainThread {
            start()
        } else {
            DispatchQueue.main.sync {
                start()
            }
        }
        
        if taskId != .invalid {
            lock.lock()
            activeTasks[taskId] = name
            lock.unlock()
            print("[BackgroundTaskManager] Started background task: \(name) (\(taskId.rawValue))")
        }
        
        return taskId
    }
    
    /// Ends an active background task assertion.
    public func endTask(_ id: UIBackgroundTaskIdentifier) {
        guard id != .invalid else { return }
        
        lock.lock()
        guard let name = activeTasks.removeValue(forKey: id) else {
            lock.unlock()
            return
        }
        lock.unlock()
        
        let finish = {
            UIApplication.shared.endBackgroundTask(id)
            print("[BackgroundTaskManager] Ended background task: \(name) (\(id.rawValue))")
        }
        
        if Thread.isMainThread {
            finish()
        } else {
            DispatchQueue.main.async {
                finish()
            }
        }
    }
    
    /// Cleanly ends all currently tracked background tasks.
    public func endAllTasks() {
        lock.lock()
        let tasks = activeTasks
        activeTasks.removeAll()
        lock.unlock()
        
        let finishAll = {
            for (id, name) in tasks {
                UIApplication.shared.endBackgroundTask(id)
                print("[BackgroundTaskManager] Cleaned up background task: \(name) (\(id.rawValue))")
            }
        }
        
        if Thread.isMainThread {
            finishAll()
        } else {
            DispatchQueue.main.async {
                finishAll()
            }
        }
    }
    
    // MARK: - BGTaskScheduler Support
    public func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else { return }
            self.handleAppRefresh(appRefreshTask)
        }
    }
    
    public func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BackgroundTaskManager] Scheduled BGAppRefresh successfully")
        } catch {
            print("[BackgroundTaskManager] Could not schedule BGAppRefresh: \(error)")
        }
    }
    
    private func handleAppRefresh(_ task: BGAppRefreshTask) {
        scheduleAppRefresh()
        
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        
        task.expirationHandler = {
            queue.cancelAllOperations()
        }
        
        let operation = BlockOperation {
            let sema = DispatchSemaphore(value: 0)
            Task {
                _ = try? await APIClient.shared.getStatus()
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 25)
        }
        
        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }
        
        queue.addOperation(operation)
    }
}
