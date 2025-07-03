// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import ComposableArchitecture
import ContextCore
import SwiftUI
import UniformTypeIdentifiers

struct DXTConfigView: View {
  let store: StoreOf<DXTConfigFeature>
  @State private var isDragOver = false
  @State private var showingFilePicker = false
  @State private var showingManifest = false
  @State private var showingUserConfig = false

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in

      VStack(alignment: .leading, spacing: 16) {
        // DXT Package
        VStack(alignment: .leading, spacing: 8) {
          Text("DXT Package")
            .font(.headline)

          if viewStore.manifest == nil {
            // Drop zone
            dropZone
          } else {
            // Preview of selected DXT
            dxtPreview
          }

          if let error = viewStore.error {
            Text(error)
              .font(.caption)
              .foregroundColor(.red)
              .padding(.top, 4)
          }
        }
      }
      .fileImporter(
        isPresented: $showingFilePicker,
        allowedContentTypes: [UTType(filenameExtension: "dxt") ?? .data],
        allowsMultipleSelection: false
      ) { result in
        if case .success(let urls) = result, let url = urls.first {
          store.send(.fileSelected(url))
        }
      }
      .sheet(isPresented: $showingManifest) {
        if let manifestData = viewStore.manifestData {
          DXTManifestView(manifestData: manifestData)
        }
      }
      .sheet(isPresented: $showingUserConfig) {
        if let manifest = viewStore.manifest {
          DXTUserConfigurationView(
            manifest: manifest,
            userConfig: viewStore.binding(
              get: \.userConfig, send: DXTConfigFeature.Action.userConfigChanged),
            icon: {
              guard let iconPath = manifest.icon,
                let tempDir = viewStore.tempDirectory
              else {
                return nil
              }
              let iconURL = tempDir.appendingPathComponent(iconPath)
              return NSImage(contentsOf: iconURL)
            }()
          )
        }
      }
    }
  }

  private var dropZone: some View {
    VStack(spacing: 12) {
      Image(systemName: "arrow.down.doc.fill")
        .font(.system(size: 48))
        .foregroundColor(isDragOver ? .accentColor : .secondary.opacity(0.5))

      Text("Drop a .dxt file here")
        .font(.body)
        .foregroundColor(.secondary)

      Text("or")
        .font(.caption)
        .foregroundColor(.secondary.opacity(0.7))

      Button("Choose File...") {
        showingFilePicker = true
      }
      .buttonStyle(.bordered)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 200)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(NSColor.controlBackgroundColor))
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
              isDragOver ? Color.accentColor : Color.secondary.opacity(0.3),
              style: StrokeStyle(lineWidth: 2, dash: isDragOver ? [] : [5])
            )
        )
    )
    .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
      guard let provider = providers.first else { return false }

      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        if let url = url, url.pathExtension.lowercased() == "dxt" {
          DispatchQueue.main.async {
            store.send(.fileSelected(url))
          }
        }
      }
      return true
    }
  }

  private var dxtPreview: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      Group {
        if let manifest = viewStore.manifest {
          DXTPackagePreview(
            manifest: manifest,
            icon: {
              guard let iconPath = manifest.icon,
                let tempDir = viewStore.tempDirectory
              else {
                return nil
              }
              let iconURL = tempDir.appendingPathComponent(iconPath)
              return NSImage(contentsOf: iconURL)
            }(),
            missingRequiredFields: viewStore.missingRequiredFields
          )
          .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
              Button(action: {
                showingManifest = true
              }) {
                Label("Info", systemImage: "info.circle")
                  .labelStyle(.iconOnly)
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
              .help("View manifest")

              if let userConfig = manifest.userConfig,
                !userConfig.isEmpty
              {
                Button(action: {
                  showingUserConfig = true
                }) {
                  Text("Configure")
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Configure user settings")
              }

              Button(action: {
                showingFilePicker = true
              }) {
                Text("Change")
                  .font(.caption)
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
            .padding(8)
          }
        }
      }
    }
  }
}

struct DXTPackagePreview: View {
  let manifest: DXTManifest
  let icon: NSImage?
  let missingRequiredFields: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        // Icon
        if let icon = icon {
          Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 60, height: 60)
            .cornerRadius(12)
        } else {
          Image(systemName: "puzzlepiece.extension.fill")
            .font(.system(size: 32))
            .foregroundColor(.accentColor)
            .frame(width: 60, height: 60)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(12)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text(manifest.displayName ?? manifest.name)
            .font(.headline)

          HStack(spacing: 8) {
            Text("Version \(manifest.version)")
              .font(.caption)
              .foregroundColor(.secondary)

            Text(serverTypeDisplay(manifest.server.type))
              .font(.caption)
              .foregroundColor(.secondary)
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(Color.secondary.opacity(0.15))
              .cornerRadius(8)
          }

          if !manifest.author.name.isEmpty {
            Text("by \(manifest.author.name)")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        Spacer()
      }

      Text(manifest.description)
        .font(.body)
        .foregroundColor(.secondary)
        .lineLimit(3)

      // Show warning if there are required fields not configured
      if !missingRequiredFields.isEmpty {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundColor(.orange)
          Text(
            "\(missingRequiredFields.count) required field\(missingRequiredFields.count == 1 ? "" : "s") need\(missingRequiredFields.count == 1 ? "s" : "") configuration"
          )
          .font(.caption)
          .foregroundColor(.orange)
        }
        .padding(.top, 4)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color(NSColor.controlBackgroundColor))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    )
  }

  private func serverTypeDisplay(_ type: DXTManifest.Server.ServerType) -> String {
    switch type {
    case .node:
      return "node"
    case .python:
      return "python"
    case .binary:
      return "binary"
    }
  }
}
