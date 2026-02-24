//
//  MacInstallerView.swift
//  VisualIntelligenceMac
//
//  First-launch installer that provisions AI models before the app's main UI appears.
//  Shows once, persisted via UserDefaults. Each step downloads in sequence with progress.
//  The user can "Continue in Background" to defer to a background task.
//

import SwiftUI
import DiverKit

struct MacInstallerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phase: InstallerPhase = .welcome
    @State private var stepIndex = 0
    @State private var stepStatus: [InstallerStep.ID: StepStatus] = [:]
    @State private var isRunning = false
    @State private var didSendToBackground = false
    @State private var fastVLMWasAlreadyReady = false

    static var needsInstall: Bool {
        !UserDefaults.standard.bool(forKey: "vi.mac.installed")
    }

    private static func markInstalled() {
        UserDefaults.standard.set(true, forKey: "vi.mac.installed")
    }

    enum InstallerPhase { case welcome, installing, done }

    struct InstallerStep: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let title: String
        let detail: String
        let sizeLabel: String
        /// If true, this step runs in-app. If false, it's delegated to EdgeDaemon.
        var downloadable: Bool = true
    }

    enum StepStatus { case waiting, running, done, delegated, skipped }

    private let steps: [InstallerStep] = [
        InstallerStep(
            id: "fastvlm",
            icon: "eye.fill", color: .blue,
            title: "FastVLM 1.5B Vision Model",
            detail: "On-device vision-language model for image analysis.",
            sizeLabel: "~3 GB · downloads now",
            downloadable: true
        ),
        InstallerStep(
            id: "clara",
            icon: "brain.head.profile", color: .purple,
            title: "CLaRa 7B Language Model",
            detail: "Context-aware summarization. Set up automatically by the Edge Node.",
            sizeLabel: "~14 GB · via Edge Node",
            downloadable: false
        ),
        InstallerStep(
            id: "mlsharp",
            icon: "rotate.3d", color: .orange,
            title: "ML-Sharp 3D Engine",
            detail: "Apple's Gaussian Splat generator. Set up automatically by the Edge Node.",
            sizeLabel: "~500 MB · via Edge Node",
            downloadable: false
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .welcome: welcomeView
            case .installing: installingView
            case .done: doneView
            }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(spacing: 24) {
            // Hero
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.2), .purple.opacity(0.15)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 88, height: 88)
                Image(systemName: "brain.filled.head.profile")
                    .font(.system(size: 42))
                    .foregroundStyle(LinearGradient(colors: [.blue, .purple],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .padding(.top, 32)

            VStack(spacing: 8) {
                Text("Set Up Visual Intelligence")
                    .font(.title2.bold())
                Text("Your Mac will download and configure AI models that power intelligent image analysis, context summarization, and 3D scene generation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            // Model list
            VStack(alignment: .leading, spacing: 12) {
                ForEach(steps) { step in
                    HStack(spacing: 12) {
                        Image(systemName: step.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(step.color)
                            .frame(width: 30, height: 30)
                            .background(step.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(step.title).font(.subheadline.weight(.semibold))
                                Text(step.sizeLabel)
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.secondary.opacity(0.1), in: Capsule())
                            }
                            Text(step.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 32)

            Text("FastVLM downloads now (~3 GB). CLaRa and ML-Sharp are set up automatically by the Edge Node on first launch.")
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            // Actions
            VStack(spacing: 10) {
                Button {
                    phase = .installing
                    startInstall()
                } label: {
                    Text("Set Up Now")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    // Defer all to background, mark installed
                    Self.markInstalled()
                    Task.detached(priority: .utility) { await EdgeModelProvisioner.shared.provisionAll() }
                    dismiss()
                } label: {
                    Text("Skip — Set Up Later")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Installing

    private var installingView: some View {
        VStack(spacing: 20) {
            Text("Setting Up AI Models")
                .font(.title3.bold())
                .padding(.top, 28)

            Text(isRunning
                 ? "This may take 20–40 minutes depending on your internet speed."
                 : "Completed.")
                .font(.caption).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(steps) { step in
                    HStack(spacing: 12) {
                        stepIcon(for: step.id)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).font(.subheadline.weight(.semibold))
                            Text(step.sizeLabel).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        stepLabel(for: step.id)
                    }
                }
            }
            .padding()
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 32)

            if isRunning && !didSendToBackground {
                Button("Continue in Background") {
                    didSendToBackground = true
                    Self.markInstalled()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .padding(.top, 28)

            Text(fastVLMWasAlreadyReady ? "Visual Intelligence Is Ready" : "FastVLM Downloaded")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                doneRow(icon: "eye.fill", color: .blue, title: "FastVLM 1.5B",
                        status: "Ready", statusColor: .green)
                doneRow(icon: "brain.head.profile", color: .purple, title: "CLaRa 7B",
                        status: "Pending Edge Node", statusColor: .orange)
                doneRow(icon: "rotate.3d", color: .orange, title: "ML-Sharp 3D Engine",
                        status: "Pending Edge Node", statusColor: .orange)
            }
            .padding()
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 32)

            Text("CLaRa and ML-Sharp are set up by the Edge Node in the background. Track progress in Settings → On-Device AI.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Open Visual Intelligence") {
                Self.markInstalled()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 24)
        }
    }

    private func doneRow(icon: String, color: Color, title: String, status: String, statusColor: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(status).font(.caption).foregroundStyle(statusColor)
        }
    }

    // MARK: - Step Icons

    @ViewBuilder
    private func stepIcon(for id: String) -> some View {
        let status = stepStatus[id] ?? .waiting
        switch status {
        case .waiting:
            Image(systemName: "circle").foregroundStyle(.secondary).font(.system(size: 18))
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 18))
        case .delegated:
            Image(systemName: "arrow.right.circle.fill").foregroundStyle(.blue).font(.system(size: 18))
        case .skipped:
            Image(systemName: "arrow.right.circle").foregroundStyle(.secondary).font(.system(size: 18))
        }
    }

    @ViewBuilder
    private func stepLabel(for id: String) -> some View {
        let status = stepStatus[id] ?? .waiting
        switch status {
        case .waiting:   Text("Waiting").font(.caption).foregroundStyle(.secondary)
        case .running:   Text("Downloading…").font(.caption).foregroundStyle(.blue)
        case .done:      Text("Ready").font(.caption).foregroundStyle(.green)
        case .delegated: Text("Edge Node").font(.caption).foregroundStyle(.blue)
        case .skipped:   Text("Skipped").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Install Logic

    private func startInstall() {
        isRunning = true
        stepStatus["clara"] = .delegated
        stepStatus["mlsharp"] = .delegated
        fastVLMWasAlreadyReady = FastVLMEnrichmentService.isModelCached

        if fastVLMWasAlreadyReady {
            // Model already on disk — skip download, mark done immediately
            stepStatus["fastvlm"] = .done
            FastVLMEnrichmentService.setEnabled(true)
            isRunning = false
            phase = .done
        } else {
            Task.detached(priority: .utility) {
                await runStep("fastvlm") {
                    let svc = FastVLMEnrichmentService()
                    try? await svc.downloadOptimalModel(progress: { _ in })
                    FastVLMEnrichmentService.setEnabled(true)
                }
                await MainActor.run {
                    isRunning = false
                    phase = .done
                }
            }
        }
    }

    private func runStep(_ id: String, action: @Sendable () async -> Void) async {
        await MainActor.run { stepStatus[id] = .running }
        await action()
        await MainActor.run { stepStatus[id] = .done }
    }
}

// MARK: - Preview

#Preview {
    MacInstallerView()
}
