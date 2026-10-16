import SwiftUI
import Network

// MARK: - NetworkMonitor

final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "drops.network")

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var justReconnected: Bool = false

    private var wasDisconnected = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                let connected = path.status == .satisfied
                if connected && self.wasDisconnected {
                    self.justReconnected = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        self.justReconnected = false
                    }
                }
                self.wasDisconnected = !connected
                self.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }
}

// MARK: - Offline Banner View

struct OfflineBanner: View {
    @ObservedObject private var network = NetworkMonitor.shared

    var body: some View {
        if !network.isConnected || network.justReconnected {
            HStack(spacing: 10) {
                DazuIcon(network.isConnected ? "wifi" : "wifi.slash", accent: false)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(network.isConnected ? "Wieder verbunden" : "Keine Verbindung")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(network.isConnected
                          ? Color.onlineGreen.opacity(0.94)
                          : Color(UIColor.systemRed).opacity(0.94))
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 3)
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: network.isConnected)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: network.justReconnected)
            .zIndex(999)
        }
    }
}
