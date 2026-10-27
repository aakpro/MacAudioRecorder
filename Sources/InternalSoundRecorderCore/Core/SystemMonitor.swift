import Foundation
import AppKit

public protocol SystemMonitorDelegate: AnyObject, Sendable {
    func systemWillSleep()
    func systemDidWake()
    func lowDiskSpaceDetected(availableBytes: Int64)
}

public final class SystemMonitor: @unchecked Sendable {
    public weak var delegate: SystemMonitorDelegate?

    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var diskTimer: DispatchSourceTimer?
    private let monitorQueue = DispatchQueue(label: "com.internalsoundrecorder.systemmonitor")

    private let minDiskSpaceBytes: Int64 = 200 * 1024 * 1024 // 200 MB safe threshold

    public init() {
        setupSleepWakeObservers()
    }

    deinit {
        stopMonitoring()
    }

    public func startDiskMonitoring(for targetDirectory: URL) {
        stopDiskMonitoring()

        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now() + 5.0, repeating: 5.0)
        timer.setEventHandler { [weak self] in
            self?.checkDiskSpace(at: targetDirectory)
        }
        timer.resume()
        self.diskTimer = timer
    }

    public func stopDiskMonitoring() {
        diskTimer?.cancel()
        diskTimer = nil
    }

    public func stopMonitoring() {
        stopDiskMonitoring()
        if let obs = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            sleepObserver = nil
        }
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            wakeObserver = nil
        }
    }

    private func setupSleepWakeObservers() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.delegate?.systemWillSleep()
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.delegate?.systemDidWake()
        }
    }

    private func checkDiskSpace(at url: URL) {
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let available = values.volumeAvailableCapacityForImportantUsage {
                if available < minDiskSpaceBytes {
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.lowDiskSpaceDetected(availableBytes: available)
                    }
                }
            }
        } catch {
            // Ignore if unable to check
        }
    }
}
