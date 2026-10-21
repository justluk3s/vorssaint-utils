// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The plan limit the menu bar shows: one window of one agent, as chosen in
/// Settings. A window the agent does not report right now hides the reading
/// rather than showing another window's figure in its place.
enum AgentMenuBarSupport {
    static func provider(in defaults: UserDefaults = .standard) -> AgentProvider {
        AgentProvider(rawValue: defaults.string(forKey: DefaultsKey.menuBarAgentUsageProvider) ?? "") ?? .claude
    }

    /// The window chosen in Settings; nil until one is, and again once
    /// another agent is chosen, so the reading follows what is reported.
    static func windowChoice(in defaults: UserDefaults = .standard) -> String? {
        let id = defaults.string(forKey: DefaultsKey.menuBarAgentUsageWindow) ?? ""
        return id.isEmpty ? nil : id
    }

    /// Agents reporting at least one window, in their usual order. OpenCode
    /// and GitHub Copilot report none.
    static func providers(_ snapshot: AgentUsageSnapshot) -> [AgentProvider] {
        AgentProvider.allCases.filter { !windows(snapshot, provider: $0).isEmpty }
    }

    /// The windows an agent reports right now, shortest first.
    static func windows(_ snapshot: AgentUsageSnapshot, provider: AgentProvider) -> [AgentLimitWindow] {
        (snapshot.limits[provider]?.windows ?? []).sorted { ($0.minutes ?? .max) < ($1.minutes ?? .max) }
    }

    /// The window the menu bar reads as of `now`: the chosen one, or while
    /// none is chosen, the one the agent reports first. A chosen window the
    /// agent does not report reads nothing.
    static func window(_ snapshot: AgentUsageSnapshot, provider: AgentProvider, choice: String?,
                       now: Date) -> AgentLimitWindow? {
        guard let id = choice ?? automaticWindowID(snapshot, provider: provider) else { return nil }
        return snapshot.limits[provider]?.windows.first { $0.id == id }.map { AgentLimitSupport.current($0, at: now) }
    }

    /// While no window is chosen: the plan's session, else its week. Without
    /// Claude Code, the Claude app's saved session can age out and leave the
    /// week alone, which still shows rather than an empty item.
    static func automaticWindowID(_ snapshot: AgentUsageSnapshot, provider: AgentProvider) -> String? {
        let all = snapshot.limits[provider]?.windows ?? []
        return (all.first { $0.kind == .session && $0.scope == nil }
            ?? all.first { $0.kind == .weekly && $0.scope == nil })?.id
    }

    /// The figure beside the mark, as the island shows limits: left or used.
    static func reading(_ window: AgentLimitWindow, display: NotchAgentLimitDisplay,
                        locale: Locale = .autoupdatingCurrent) -> String {
        AgentFormat.percent(display == .remaining ? window.remainingFraction : window.usedFraction, locale: locale)
    }

    /// What a window covers: its length, or the model it is kept for.
    static func label(_ window: AgentLimitWindow, text: NotchAgentStrings, locale: Locale) -> String {
        switch window.kind {
        case .session: return text.session
        case .weekly: return window.scope.map { "\(text.weekly) · \($0)" } ?? text.weekly
        case .other:
            guard let minutes = window.minutes else { return window.scope ?? text.readoutLimit }
            return AgentFormat.duration(TimeInterval(minutes) * 60, locale: locale, units: 1)
        }
    }

    /// A saved window the agent does not report right now, rebuilt from its
    /// id so Settings can still name it. Nil for an id no source makes.
    static func knownWindow(id: String) -> AgentLimitWindow? {
        func window(_ kind: AgentLimitWindow.Kind, minutes: Int?, scope: String?) -> AgentLimitWindow {
            AgentLimitWindow(id: id, kind: kind, minutes: minutes, scope: scope, usedPercent: 0, resetsAt: nil)
        }
        if let claude = AgentClaudeAppUsage.windows.first(where: { "claude.\($0.key)" == id }) {
            return window(claude.kind, minutes: claude.minutes, scope: claude.scope)
        }
        guard id.hasPrefix("codex.") else { return nil }
        let slot = String(id.dropFirst("codex.".count))
        if slot == "individual" { return window(.other, minutes: nil, scope: nil) }
        guard let minutes = Int(slot) else { return nil }
        return window(AgentLogParser.kind(minutes: minutes), minutes: minutes, scope: nil)
    }
}
