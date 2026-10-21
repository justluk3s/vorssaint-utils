// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Starts and pauses the usage reading for the menu bar while the Dynamic
/// Island, which otherwise does both, is off. It pauses on the island's own
/// rule, so a locked or sleeping Mac reads nothing either way. Main thread.
final class AgentUsageMenuBarRunner {
    static let shared = AgentUsageMenuBarRunner()

    private var session = NotchSessionState()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var quitting = false

    private init() {}

    func syncWithPreferences() {
        guard !quitting else { return }
        let islandOn = NotchSupport.isEnabled()
        let readout = NotchAgentSupport.menuBarReadoutEnabled()
        // Read before the first decision: the Mac may already be locked.
        if !islandOn, readout, !observing { installObservers() }
        switch NotchAgentSupport.menuBarReading(islandOn: islandOn, readout: readout,
                                                canPresent: session.canPresent) {
        case .island: removeObservers()
        case .run: AgentUsageService.shared.syncWithPreferences()
        case .pause: AgentUsageService.shared.pause()
        case .stop:
            removeObservers()
            AgentUsageService.shared.stop()
        }
    }

    /// Saves what was read as the app quits. The island stops after this and
    /// would hand the reading back, so nothing starts it again.
    func quit() {
        quitting = true
        removeObservers()
        AgentUsageService.shared.stop()
    }

    private var observing: Bool { !observers.isEmpty }

    private func update(_ change: (inout NotchSessionState) -> Void) {
        let couldPresent = session.canPresent
        change(&session)
        guard couldPresent != session.canPresent else { return }
        syncWithPreferences()
    }

    private func installObservers() {
        session = NotchSessionState()
        session.locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.sleeping = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.sleeping = false }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displaysSleeping = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displaysSleeping = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.onConsole = false }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.onConsole = true }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         change: @escaping (inout NotchSessionState) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.update(change)
        }
        observers.append((center, token))
    }

    private func removeObservers() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
    }
}
