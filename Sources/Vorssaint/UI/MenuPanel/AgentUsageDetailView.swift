// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The AI plan limits behind the menu bar reading: every agent reporting
/// them, each window with what is left or used and when it renews.
struct AgentUsageDetailView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var usage = AgentUsageService.shared
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var limitDisplay = NotchAgentLimitDisplay.remaining.rawValue
    @State private var claudeApp: URL?

    private var text: NotchAgentStrings { FeatureStrings.notchAgents(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }
    private var display: NotchAgentLimitDisplay { NotchAgentLimitDisplay(rawValue: limitDisplay) ?? .remaining }

    var body: some View {
        // Countdowns in minutes and a window renewing need the clock, not
        // only new readings.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let providers = AgentMenuBarSupport.providers(usage.snapshot)
            VStack(alignment: .leading, spacing: 10) {
                if providers.isEmpty {
                    Text(text.waitingForLimits)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panelCard()
                }
                ForEach(providers) { card($0, now: context.date) }
            }
        }
        // Asks Claude Code for fresh limits while the panel shows them.
        .onAppear {
            usage.pageDidAppear()
            claudeApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AgentClaudeAppUsage.bundleIdentifier)
        }
        .onDisappear { usage.pageDidDisappear() }
    }

    private func card(_ provider: AgentProvider, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                NotchAgentMark(provider: provider, size: 12)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                if let plan = usage.snapshot.plans[provider] {
                    Text(plan.name)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ForEach(AgentMenuBarSupport.windows(usage.snapshot, provider: provider)) { window in
                row(AgentLimitSupport.current(window, at: now), provider: provider, now: now)
            }
            if provider == .claude { claudeChecked(now: now) }
        }
        .panelCard()
    }

    /// When Claude's limits were last checked, worded as in Settings. Without
    /// Claude Code, an old reading offers to open the Claude app, which
    /// checks them again itself while it runs.
    @ViewBuilder private func claudeChecked(now: Date) -> some View {
        let limits = usage.snapshot.limits[.claude]
        if let limits, limits.source == .account {
            caption("Claude Code · " + text.updated(relative(limits.observedAt, now: now)))
        } else if let checked = usage.claudeAppChecked {
            let when = relative(checked, now: now)
            if now.timeIntervalSince(checked) < AgentClaudeAppUsage.freshness {
                caption(text.claudeLimitsCurrent(when))
            } else {
                caption(text.claudeLimitsStale(when))
                if usage.claudeAccountFailure == .missing {
                    caption(text.claudeCodeMissing)
                    if let claudeApp {
                        Button(text.openClaude) {
                            NSWorkspace.shared.openApplication(at: claudeApp, configuration: NSWorkspace.OpenConfiguration())
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func caption(_ string: String) -> some View {
        Text(string)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func relative(_ date: Date, now: Date) -> String {
        min(date, now).formatted(.relative(presentation: .named).locale(locale))
    }

    private func row(_ window: AgentLimitWindow, provider: AgentProvider, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(AgentMenuBarSupport.label(window, text: text, locale: locale))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if let resets = AgentLimitSupport.displayedReset(window, now: now) {
                    Label((window.estimatedResetsAt == nil ? "" : "≈ ")
                          + AgentFormat.duration(resets.timeIntervalSince(now), locale: locale),
                          systemImage: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(AgentMenuBarSupport.reading(window, display: display, locale: locale))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            UsageBar(fraction: display == .remaining ? window.remainingFraction : window.usedFraction,
                     tint: agentLimitTint(provider, usedFraction: window.usedFraction))
        }
        .accessibilityElement(children: .combine)
    }
}
