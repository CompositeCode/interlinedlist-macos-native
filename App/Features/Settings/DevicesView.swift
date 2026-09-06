// DevicesView
//
// Settings ▸ Devices (work-consolidation.md G17) — the machines registered under
// this app's key. Rename a machine, promote one to main workstation (its config
// seeds a brand-new device on first sign-in), or deregister one.
//
// SwiftUI-only (no AppKit). Consumes only `InterlinedDomain` per Decision 0003.

import SwiftUI
import InterlinedDomain

struct DevicesView: View {

    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: DevicesViewModel?
    @State private var renaming: AppDevice?
    @State private var draftName: String = ""
    @State private var pendingDeregister: AppDevice?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if viewModel == nil {
                let model = DevicesViewModel(
                    service: environment?.appSettings,
                    currentDeviceID: DeviceIdentity.current()
                )
                viewModel = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: DevicesViewModel) -> some View {
        if viewModel.isUnavailable {
            SettingsUnavailableView(
                title: "Devices unavailable",
                message: "Synced settings need an app key registered with InterlinedList before this Mac can appear here."
            )
        } else {
            Form {
                if let error = viewModel.error {
                    Section { SettingsErrorRow(error: error) }
                }
                Section("Registered devices") {
                    if viewModel.isLoading && viewModel.devices.isEmpty {
                        ProgressView()
                    } else if viewModel.devices.isEmpty {
                        Text("No devices registered yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.devices) { device in
                            row(device, viewModel: viewModel)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .alert("Rename device", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Name", text: $draftName)
                Button("Rename") {
                    if let device = renaming {
                        Task { await viewModel.rename(device, to: draftName); renaming = nil }
                    }
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .confirmationDialog(
                "Deregister this device?",
                isPresented: Binding(
                    get: { pendingDeregister != nil },
                    set: { if !$0 { pendingDeregister = nil } }
                ),
                presenting: pendingDeregister
            ) { device in
                Button("Deregister", role: .destructive) {
                    Task { await viewModel.deregister(device); pendingDeregister = nil }
                }
                Button("Cancel", role: .cancel) { pendingDeregister = nil }
            } message: { device in
                Text("\(device.name) will lose its per-machine settings. Shared settings are unaffected.")
            }
        }
    }

    @ViewBuilder
    private func row(_ device: AppDevice, viewModel: DevicesViewModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name)
                    if viewModel.isCurrentDevice(device) {
                        Text("This Mac")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                    if device.isMainWorkstation {
                        Label("Main", systemImage: "star.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let lastSeen = device.lastSeenAt {
                    Text("Last seen \(lastSeen.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if viewModel.busyID == device.id {
                ProgressView().controlSize(.small)
            } else {
                Menu {
                    Button("Rename…") { renaming = device; draftName = device.name }
                    if !device.isMainWorkstation {
                        Button("Make main workstation") {
                            Task { await viewModel.makeMainWorkstation(device) }
                        }
                    }
                    Divider()
                    Button("Deregister…", role: .destructive) { pendingDeregister = device }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(viewModel.busyID != nil)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            device.isMainWorkstation ? "\(device.name), main workstation" : device.name
        )
    }
}
