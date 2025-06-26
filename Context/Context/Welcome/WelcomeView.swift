import ComposableArchitecture
import SwiftUI

struct WelcomeView: View {
  let store: StoreOf<WelcomeFeature>
  @State private var isImportHovered = false
  @State private var isAddHovered = false
  @State private var isDefaultHovered = false

  var body: some View {
    WithViewStore(self.store, observe: { $0 }) { viewStore in
      ZStack {
        VStack(spacing: 0) {
          // Header with app icon and title
          VStack(spacing: 16) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName)!)
              .resizable()
              .frame(width: 128, height: 128)
              .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 2)

            VStack(spacing: 8) {
              Text("Welcome to Context")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)

              Text("Get started by importing existing MCP servers or adding a new one")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .padding(.top, 48)
          .padding(.horizontal, 40)
          .padding(.bottom, 40)

          Divider()

          // Action buttons
          HStack(spacing: 24) {
            // Import Servers option
            Button(action: { viewStore.send(.importServersButtonTapped) }) {
              VStack(spacing: 16) {
                ZStack {
                  RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(isImportHovered ? 0.15 : 0.1))
                    .frame(width: 80, height: 80)
                    .overlay(
                      RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                          Color.accentColor.opacity(isImportHovered ? 0.4 : 0.2), lineWidth: 1)
                    )
                    .scaleEffect(isImportHovered ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isImportHovered)

                  Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(isImportHovered ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isImportHovered)
                }

                VStack(spacing: 6) {
                  Text("Import Servers")
                    .font(.headline)

                  Text("Import from Cursor, Claude,\nWindsurf, or VS Code")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
            }
            .buttonStyle(.plain)
            .frame(width: 160)
            .onHover { hovering in
              isImportHovered = hovering
            }

            // Divider
            Divider()
              .frame(height: 160)

            // Add Reference Servers option
            Button(action: { viewStore.send(.addReferenceServersButtonTapped) }) {
              VStack(spacing: 16) {
                ZStack {
                  RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(isDefaultHovered ? 0.15 : 0.1))
                    .frame(width: 80, height: 80)
                    .overlay(
                      RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                          Color.accentColor.opacity(isDefaultHovered ? 0.4 : 0.2), lineWidth: 1)
                    )
                    .scaleEffect(isDefaultHovered ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isDefaultHovered)

                  Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(isDefaultHovered ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isDefaultHovered)
                }

                VStack(spacing: 6) {
                  Text("Add Reference Servers")
                    .font(.headline)

                  Text("Add servers from\nmodelcontextprotocol/servers")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
            }
            .buttonStyle(.plain)
            .frame(width: 160)
            .onHover { hovering in
              isDefaultHovered = hovering
            }

            // Divider
            Divider()
              .frame(height: 160)

            // Add Server option
            Button(action: { viewStore.send(.addServerButtonTapped) }) {
              VStack(spacing: 16) {
                ZStack {
                  RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(isAddHovered ? 0.15 : 0.1))
                    .frame(width: 80, height: 80)
                    .overlay(
                      RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                          Color.accentColor.opacity(isAddHovered ? 0.4 : 0.2), lineWidth: 1)
                    )
                    .scaleEffect(isAddHovered ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isAddHovered)

                  Image(systemName: "plus.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(isAddHovered ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isAddHovered)
                }

                VStack(spacing: 6) {
                  Text("Add Server")
                    .font(.headline)

                  Text("Manually configure a\nnew MCP server")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
            }
            .buttonStyle(.plain)
            .frame(width: 160)
            .onHover { hovering in
              isAddHovered = hovering
            }
          }
          .padding(.vertical, 40)
          .padding(.horizontal, 40)

          Spacer(minLength: 0)
        }
        .frame(width: 700, height: 520)
        .background(.background)

        // Close button in top-left corner
        VStack {
          HStack {
            Button(action: { viewStore.send(.dismiss) }) {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .background(Circle().fill(.background))
            }
            .buttonStyle(.plain)
            .padding(12)

            Spacer()
          }

          Spacer()
        }
      }
    }
  }
}

#Preview {
  WelcomeView(
    store: Store(initialState: WelcomeFeature.State()) {
      WelcomeFeature()
    }
  )
}
