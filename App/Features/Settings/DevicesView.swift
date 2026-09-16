// DevicesView
//
// Settings ▸ Applications (work-consolidation.md G17, GitHub issue #56) — the
// machines registered under this app's key and the settings documents they
// share and pin.
//
// Every action `/help/app-settings` documents lives here: set as main
// workstation, rename, remove, view the shared and per-machine settings, copy a
// machine's settings to shared, and delete the shared settings.
//
// Each confirmation states the *actual* consequence rather than a generic "are
// you sure": removal takes the machine's own settings with it, and copy-to-
// shared replaces rather than merges. Both are irreversible, and neither is
// obvious from the button name.
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
    @State private var pendingCopyToShared: AppDevice?
    @State private var confirmingSharedDelete = false

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
                    currentDeviceID: DeviceIdentity.current(),
                    currentDeviceName: DeviceIdentity.suggestedName
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
                title: "Applications unavailable",
                message: "This build has no app-settings key configured, so this Mac cannot sync settings or appear in the device list."
            )
        } else {
            Form {
                if let error = viewModel.error {
                    Section { SettingsErrorRow(error: error) }
                }
                sharedSettingsSection(viewModel)
                devicesSection(viewModel)
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
                "Remove this machine?",
                isPresented: Binding(
                    get: { pendingDeregister != nil },
                    set: { if !$0 { pendingDeregister = nil } }
                ),
                presenting: pendingDeregister
            ) { device in
                Button("Remove", role: .destructive) {
                    Task { await viewModel.deregister(device); pendingDeregister = nil }
                }
                Button("Cancel", role: .cancel) { pendingDeregister = nil }
            } message: { device in
                // Naming both halves matters: users hesitate to remove an old
                // machine for fear of losing the settings they share with it.
                Text(
                    device.isMainWorkstation
                    ? "\(device.name) will lose the settings saved just for it. Shared settings are not affected. Another machine will become the main workstation."
                    : "\(device.name) will lose the settings saved just for it. Shared settings are not affected."
                )
            }
            .confirmationDialog(
                "Replace shared settings?",
                isPresented: Binding(
                    get: { pendingCopyToShared != nil },
                    set: { if !$0 { pendingCopyToShared = nil } }
                ),
                presenting: pendingCopyToShared
            ) { device in
                Button("Replace", role: .destructive) {
                    Task { await viewModel.copySettingsToShared(from: device); pendingCopyToShared = nil }
                }
                Button("Cancel", role: .cancel) { pendingCopyToShared = nil }
            } message: { device in
                Text("The shared settings will be replaced with the settings from \(device.name). This is not a merge — shared settings that \(device.name) does not have will be removed.")
            }
            .confirmationDialog(
                "Delete shared settings?",
                isPresented: $confirmingSharedDelete
            ) {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.deleteSharedSettings() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every machine loses the settings shared across this account. Settings saved for individual machines are not affected.")
            }
            .sheet(isPresented: Binding(
                get: { viewModel.inspection != nil },
                set: { if !$0 { viewModel.dismissInspection() } }
            )) {
                if let inspection = viewModel.inspection {
                    DeviceSettingsInspector(inspection: inspection) {
                        viewModel.dismissInspection()
                    }
                }
            }
        }
    }

    // MARK: - Shared settings

    @ViewBuilder
    private func sharedSettingsSection(_ viewModel: DevicesViewModel) -> some View {
        Section("Shared settings") {
            if let document = viewModel.sharedDocument {
                SettingsDocumentSummary(document: document)
                HStack {
                    Spacer()
                    if viewModel.busyID == DevicesViewModel.sharedSettingsRowID {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Delete Shared Settings…", role: .destructive) {
                            confirmingSharedDelete = true
                        }
                        .disabled(viewModel.busyID != nil)
                    }
                }
            } else if viewModel.isLoading {
                ProgressView()
            } else {
                // Nothing stored is the ordinary first-run state, not an error.
                Text("No settings are shared across this account yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Devices

    @ViewBuilder
    private func devicesSection(_ viewModel: DevicesViewModel) -> some View {
        Section("Registered machines") {
            if viewModel.mainWorkstationIsUnknown {
                Label(
                    "Another machine became the main workstation. Reopen this pane to see which.",
                    systemImage: "questionmark.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            if viewModel.isLoading && viewModel.devices.isEmpty {
                ProgressView()
            } else if viewModel.devices.isEmpty {
                Text("No machines registered yet.").foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.devices) { device in
                    row(device, viewModel: viewModel)
                }
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
                    // Suppressed while the holder is unknown: a stale badge
                    // asserts something this client can no longer vouch for.
                    if device.isMainWorkstation && !viewModel.mainWorkstationIsUnknown {
                        Label("Main", systemImage: "star.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(subtitle(for: device))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.busyID == device.id {
                ProgressView().controlSize(.small)
            } else {
                Menu {
                    Button("Rename…") { renaming = device; draftName = device.name }
                    if !device.isMainWorkstation {
                        Button("Make Main Workstation") {
                            Task { await viewModel.makeMainWorkstation(device) }
                        }
                    }
                    Divider()
                    Button("View Settings…") { Task { await viewModel.inspect(device) } }
                    // `hasDeviceSettings == nil` means the server did not say,
                    // so the action stays available rather than being hidden on
                    // an assumption; the service refuses an empty copy.
                    if device.hasDeviceSettings != false {
                        Button("Copy Settings to Shared…") { pendingCopyToShared = device }
                    }
                    Divider()
                    Button("Remove…", role: .destructive) { pendingDeregister = device }
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
            device.isMainWorkstation && !viewModel.mainWorkstationIsUnknown
            ? "\(device.name), main workstation"
            : device.name
        )
    }

    private func subtitle(for device: AppDevice) -> String {
        var parts: [String] = []
        if let lastSeen = device.lastSeenAt {
            parts.append("Last seen \(lastSeen.formatted(.relative(presentation: .named)))")
        }
        if device.hasDeviceSettings == true {
            parts.append("has its own settings")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Settings document presentation

/// Last-updated and size for one settings document.
///
/// Size is shown because the payload is opaque to this app as well as to the
/// server — there is nothing else truthful to say about its contents at a
/// glance, and the server enforces a size cap.
struct SettingsDocumentSummary: View {
    let document: AppSettingsDocument

    var body: some View {
        LabeledContent("Last updated") {
            if let updatedAt = document.updatedAt {
                Text(updatedAt.formatted(date: .abbreviated, time: .shortened))
            } else {
                Text("Unknown").foregroundStyle(.secondary)
            }
        }
        LabeledContent("Size") {
            Text(document.byteSize.formatted(.byteCount(style: .file)))
        }
        LabeledContent("Entries") {
            Text("\(document.bag.count)")
        }
    }
}

/// One machine's settings, shown on demand.
struct DeviceSettingsInspector: View {
    let inspection: DevicesViewModel.Inspection
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(inspection.device.name).font(.headline)

            if inspection.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let error = inspection.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).font(.callout)
            } else if let document = inspection.document {
                Form {
                    Section("Settings saved for this machine") {
                        SettingsDocumentSummary(document: document)
                    }
                    Section("Keys") {
                        if document.bag.isEmpty {
                            Text("None").foregroundStyle(.secondary)
                        } else {
                            // Keys only, never values: the payload can hold a
                            // sync folder path and other machine-local detail,
                            // and this pane is about accounting for settings,
                            // not displaying them.
                            ForEach(document.bag.keys, id: \.self) { key in
                                Text(key).font(.callout.monospaced())
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            } else {
                Text("This machine has no settings of its own. It uses the shared settings.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420, height: 380)
    }
}
