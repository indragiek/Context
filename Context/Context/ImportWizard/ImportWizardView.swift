// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct ImportWizardView: View {
  @Bindable var store: StoreOf<ImportWizardFeature>

  var body: some View {
    VStack(spacing: 0) {
      // Content
      Group {
        switch store.screen {
        case .directorySelection, .loadingSources:
          DirectorySelectionView(store: store)
        case .sourceSelection:
          SourceSelectionView(store: store)
        case .importing:
          ImportingView()
        case let .complete(importedCount, updatedCount):
          CompleteView(importedCount: importedCount, updatedCount: updatedCount)
        case let .error(message):
          ErrorView(message: message)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      Divider()

      // Bottom Bar
      HStack {
        Button("Cancel") {
          store.send(.cancelButtonTapped)
        }
        .keyboardShortcut(.cancelAction)

        Spacer()

        switch store.screen {
        case .directorySelection:
          Button("Next") {
            store.send(.directorySelectionNextTapped)
          }
          .keyboardShortcut(.defaultAction)
          .disabled(!store.canProceedFromDirectorySelection)

        case .loadingSources:
          HStack(spacing: 6) {
            ProgressView()
              .scaleEffect(0.5)
            Text("Loading...")
              .font(.caption)
              .foregroundColor(.secondary)
          }
          .padding(.trailing, 8)

          Button("Next") {
            // Disabled during loading
          }
          .keyboardShortcut(.defaultAction)
          .disabled(true)

        case .sourceSelection:
          Button("Back") {
            store.send(.backToDirectorySelection)
          }

          Button("Next") {
            store.send(.nextButtonTapped)
          }
          .keyboardShortcut(.defaultAction)
          .disabled(!store.hasValidSelection)

        case .importing:
          EmptyView()

        case .complete:
          Button("Done") {
            store.send(.doneButtonTapped)
          }
          .keyboardShortcut(.defaultAction)

        case .error:
          Button("Back") {
            store.send(.backToDirectorySelection)
          }

          Button("Done") {
            store.send(.doneButtonTapped)
          }
          .keyboardShortcut(.defaultAction)
        }
      }
      .padding()
    }
    .frame(width: 800, height: 500)
    .onAppear {
      store.send(.onAppear)
    }
  }
}

struct DirectorySelectionView: View {
  @Bindable var store: StoreOf<ImportWizardFeature>
  @State private var showingProjectPicker: Bool = false
  @State private var showingHomePicker: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      // Introduction
      VStack(alignment: .leading, spacing: 8) {
        Text("Select Directories to Scan")
          .font(.title2)
          .fontWeight(.semibold)

        Text(
          "To import MCP server configurations, we need access to directories where configuration files might be located."
        )
        .font(.body)
        .foregroundColor(.secondary)
      }
      .padding(.horizontal)
      .padding(.top)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          // Home Folder Access
          homeFolderSection

          // Project Directories
          projectDirectoriesSection
        }
        .padding(.horizontal)
      }
    }
  }

  @ViewBuilder
  private var homeFolderSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "house.fill")
          .font(.title2)
          .foregroundColor(store.hasHomeAccess ? .green : .accentColor)

        VStack(alignment: .leading, spacing: 4) {
          Text("Home Folder Access")
            .font(.headline)
          Text("Required for user-scoped configurations")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Spacer()

        if store.hasHomeAccess {
          Label("Access Granted", systemImage: "checkmark.circle.fill")
            .foregroundColor(.green)
            .font(.system(size: 13, weight: .medium))
        } else {
          Button("Select Home Folder") {
            showingHomePicker = true
          }
          .fileImporter(
            isPresented: $showingHomePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
          ) { result in
            if case .success(let urls) = result, let url = urls.first {
              store.send(.homeFolderSelected(url))
            }
          }
          .fileDialogDefaultDirectory(showingHomePicker ? store.homeURL : nil)
          .fileDialogConfirmationLabel(showingHomePicker ? Text("Select") : Text("Open"))
          .fileDialogMessage(
            showingHomePicker
              ? Text("Select your home folder to allow access to user-scoped MCP configurations")
              : Text(""))
        }
      }
      .padding()
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.secondary.opacity(0.05))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(
            store.hasHomeAccess ? Color.green.opacity(0.3) : Color.secondary.opacity(0.1),
            lineWidth: 1
          )
      )

      if !store.hasHomeAccess {
        Text(
          "Grant access to your home folder to discover user-scoped MCP configurations from apps like Claude Desktop, VS Code, and others."
        )
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 4)
      }
    }
  }

  @ViewBuilder
  private var projectDirectoriesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Project Directories")
          .font(.headline)

        Spacer()

        Button(action: {
          showingProjectPicker = true
        }) {
          Label("Add Directory", systemImage: "plus.circle")
            .font(.system(size: 13))
        }
        .fileImporter(
          isPresented: $showingProjectPicker,
          allowedContentTypes: [.folder],
          allowsMultipleSelection: false
        ) { result in
          if case .success(let urls) = result, let url = urls.first {
            store.send(.projectDirectorySelected(url))
          }
        }
      }

      Text("Add project directories to scan for workspace-specific MCP configurations.")
        .font(.caption)
        .foregroundColor(.secondary)

      if store.projectDirectories.isEmpty {
        HStack {
          Image(systemName: "folder.badge.plus")
            .font(.largeTitle)
            .foregroundColor(.secondary)

          VStack(alignment: .leading) {
            Text("No project directories added")
              .font(.subheadline)
              .foregroundColor(.secondary)
            Text("Click \"Add Directory\" to add project directories")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.05))
        )
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(store.projectDirectories, id: \.self) { directory in
            HStack {
              Image(systemName: "folder.fill")
                .foregroundColor(.accentColor)

              Text(directory.lastPathComponent)
                .font(.system(size: 13))

              Text(directory.path)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

              Spacer()

              Button(action: { store.send(.removeProjectDirectory(directory)) }) {
                Image(systemName: "xmark.circle.fill")
                  .foregroundColor(.secondary)
                  .imageScale(.medium)
              }
              .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
              RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.05))
            )
          }
        }
      }
    }
  }
}

struct SourceSelectionView: View {
  @Bindable var store: StoreOf<ImportWizardFeature>

  var body: some View {
    VStack(spacing: 0) {
      HSplitView {
        // Left: Source List
        List(
          store.sources,
          selection: Binding(
            get: { store.selectedSource?.id },
            set: { id in
              if let id {
                store.send(.sourceSelected(id))
              }
            }
          )
        ) { source in
          HStack(spacing: 12) {
            Toggle(
              "",
              isOn: .init(
                get: { source.isSelected },
                set: { _ in store.send(.toggleSourceSelection(source.id)) }
              )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(nsImage: appIcon(for: source.importerType.bundleIdentifiers))
              .resizable()
              .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
              Text(source.name)
                .font(.system(size: 13))

              Text(
                "\(source.servers.count) \(source.servers.count == 1 ? "server" : "servers") found"
              )
              .font(.caption)
              .foregroundColor(.secondary)
            }

            Spacer()
          }
          .padding(.vertical, 4)
          .padding(.horizontal, 8)
          .tag(source.id)
        }
        .listStyle(.inset)
        .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)

        // Right: Server List
        if let selectedSourceID = store.selectedSource?.id,
          let selectedSource = store.sources[id: selectedSourceID]
        {
          VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
              Text(selectedSource.name)
                .font(.headline)
              Spacer()
              if selectedSource.isLoading {
                ProgressView()
                  .scaleEffect(0.7)
              }
            }
            .padding()

            Divider()

            // Server List
            if let error = selectedSource.loadError {
              VStack {
                Image(systemName: "exclamationmark.triangle")
                  .font(.largeTitle)
                  .foregroundColor(.secondary)
                Text("Failed to load servers")
                  .font(.headline)
                Text(error)
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .multilineTextAlignment(.center)
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .padding()
            } else if selectedSource.servers.isEmpty && !selectedSource.isLoading {
              VStack {
                Image(systemName: "server.rack")
                  .font(.largeTitle)
                  .foregroundColor(.secondary)
                Text("No servers found")
                  .font(.headline)
                  .foregroundColor(.secondary)
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
              ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                  ForEach(selectedSource.servers) { serverSelection in
                    ServerRow(
                      server: serverSelection.server,
                      isSelected: serverSelection.isSelected,
                      isEnabled: selectedSource.isSelected,
                      onToggle: {
                        store.send(
                          .toggleServerSelection(
                            sourceID: selectedSource.id,
                            serverID: serverSelection.id))
                      }
                    )
                  }
                }
                .padding()
              }
            }
          }
        } else {
          VStack {
            Image(systemName: "arrow.left")
              .font(.largeTitle)
              .foregroundColor(.secondary)
            Text("Select a source to view servers")
              .font(.headline)
              .foregroundColor(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
  }
}

struct ServerRow: View {
  let server: MCPServer
  let isSelected: Bool
  let isEnabled: Bool
  let onToggle: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Toggle(
        "",
        isOn: .init(
          get: { isSelected },
          set: { _ in onToggle() }
        )
      )
      .toggleStyle(.checkbox)
      .labelsHidden()
      .disabled(!isEnabled)

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(server.name)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isEnabled ? .primary : .secondary)

          // Transport type badge
          Text(server.transport.rawValue.uppercased())
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(isEnabled ? .white : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
              RoundedRectangle(cornerRadius: 4)
                .fill(transportColor(for: server.transport).opacity(isEnabled ? 1 : 0.5))
            )
        }

        // Command or URL
        if server.command != nil {
          HStack(spacing: 4) {
            Image(systemName: "terminal")
              .font(.caption)
              .foregroundColor(.secondary)

            Text(fullCommand(for: server))
              .font(.system(size: 11, design: .monospaced))
              .foregroundColor(isEnabled ? .secondary : .secondary.opacity(0.6))
              .lineLimit(1)
              .truncationMode(.tail)
          }
        } else if let url = server.url {
          HStack(spacing: 4) {
            Image(systemName: "link")
              .font(.caption)
              .foregroundColor(.secondary)

            Text(url)
              .font(.system(size: 11))
              .foregroundColor(isEnabled ? .secondary : .secondary.opacity(0.6))
              .lineLimit(1)
              .truncationMode(.tail)
          }
        }
      }

      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(Color.secondary.opacity(0.05))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
    )
  }

  private func fullCommand(for server: MCPServer) -> String {
    var parts: [String] = []
    if let command = server.command {
      parts.append(command)
    }
    if let args = server.args {
      parts.append(contentsOf: args)
    }
    return parts.joined(separator: " ")
  }

  private func transportColor(for transport: TransportType) -> Color {
    switch transport {
    case .stdio:
      return .blue
    case .sse:
      return .green
    case .streamableHTTP:
      return .orange
    }
  }
}

struct ImportingView: View {
  var body: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.5)
      Text("Importing servers...")
        .font(.headline)
      Text("Please wait while we add the selected servers to your database.")
        .font(.caption)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct CompleteView: View {
  let importedCount: Int
  let updatedCount: Int

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 64))
        .foregroundColor(.green)

      Text("Import Complete")
        .font(.title2)
        .fontWeight(.semibold)

      Group {
        if importedCount > 0 && updatedCount > 0 {
          Text(
            "\(importedCount) \(importedCount == 1 ? "server" : "servers") imported, \(updatedCount) \(updatedCount == 1 ? "server" : "servers") updated"
          )
          .font(.body)
          .foregroundColor(.secondary)
        } else if importedCount > 0 {
          Text("\(importedCount) \(importedCount == 1 ? "server" : "servers") imported")
            .font(.body)
            .foregroundColor(.secondary)
        } else if updatedCount > 0 {
          Text("\(updatedCount) \(updatedCount == 1 ? "server" : "servers") updated")
            .font(.body)
            .foregroundColor(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct ErrorView: View {
  let message: String

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 64))
        .foregroundColor(.red)

      Text("Import Failed")
        .font(.title2)
        .fontWeight(.semibold)

      Text(message)
        .font(.body)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 400)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}

private func appIcon(for bundleIdentifiers: [String]) -> NSImage {
  // Try to find app URL for any of the bundle identifiers
  for bundleID in bundleIdentifiers {
    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
      // Get the app icon
      return NSWorkspace.shared.icon(forFile: appURL.path)
    }
  }

  // Default to binary executable icon if no app found
  return NSWorkspace.shared.icon(for: .unixExecutable)
}
