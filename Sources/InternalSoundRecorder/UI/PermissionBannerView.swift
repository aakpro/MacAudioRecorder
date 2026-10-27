import SwiftUI
import InternalSoundRecorderCore

public struct PermissionBannerView: View {
    @ObservedObject var permissionManager: PermissionManager

    public init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Permission Required")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("macOS requires 'Screen & System Audio Recording' permission to capture internal audio without virtual drivers.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button(action: {
                    permissionManager.openSystemSettings()
                }) {
                    Label("Open System Settings", systemImage: "gearshape")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)

                Button(action: {
                    permissionManager.checkPermission()
                }) {
                    Text("Check Again")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}
