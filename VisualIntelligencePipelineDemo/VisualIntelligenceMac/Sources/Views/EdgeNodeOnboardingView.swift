//
//  EdgeNodeOnboardingView.swift
//  VisualIntelligenceMac
//
//  First-launch sheet asking the user to install the Visual Intelligence Node
//  as a background Login Item. Shown once; choice persisted in UserDefaults.
//

import SwiftUI

struct EdgeNodeOnboardingView: View {
    @Bindable var installer: EdgeNodeInstallService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {

            // ── Hero ──────────────────────────────────────────────────────
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: "brain.filled.head.profile")
                        .font(.system(size: 36))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text("Enable Visual Intelligence Node?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("A lightweight background helper will start automatically when you log in, so your iPhone can offload AI to this Mac — even when the app is closed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            .padding(.top, 32)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)

            Divider()

            // ── Feature bullets ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 12) {
                OnboardingBullet(
                    icon: "brain.head.profile",
                    color: .purple,
                    title: "Larger AI Models",
                    description: "CLaRa 7B and FastVLM 1.5B run here, delivering richer summaries than the on-device models."
                )
                OnboardingBullet(
                    icon: "rotate.3d",
                    color: .orange,
                    title: "3D Scene Generation",
                    description: "Convert any capture into a 3D Gaussian Splat viewable in AR on your iPhone."
                )
                OnboardingBullet(
                    icon: "lock.shield.fill",
                    color: .green,
                    title: "Stays on Your Network",
                    description: "All traffic uses TLS 1.3. Nothing leaves your home. No accounts, no cloud."
                )
                OnboardingBullet(
                    icon: "gearshape.fill",
                    color: .gray,
                    title: "Fully in Your Control",
                    description: "Appears in System Settings › Login Items. Disable it anytime in one click."
                )
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)

            Divider()

            // ── Status / Error ────────────────────────────────────────────
            if let error = installer.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.top, 12)
            }

            if installer.installStatus == .requiresApproval {
                HStack {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.orange)
                    Text("macOS requires your approval in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        installer.openSystemSettings()
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 32)
                .padding(.top, 12)
            }

            // ── Buttons ───────────────────────────────────────────────────
            HStack(spacing: 12) {
                Button("Not Now") {
                    installer.hasPromptedUser = true
                    dismiss()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)

                Button {
                    installer.hasPromptedUser = true
                    installer.install()
                    if installer.installStatus == .running {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if installer.installStatus == .installing {
                            ProgressView().controlSize(.small)
                        }
                        Text(installer.installStatus == .installing
                             ? "Installing…"
                             : "Enable Edge Node")
                    }
                    .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .disabled(installer.installStatus == .installing)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
        }
        .frame(width: 480)
        .fixedSize()
    }
}

// MARK: - Bullet

private struct OnboardingBullet: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    EdgeNodeOnboardingView(installer: EdgeNodeInstallService())
}
