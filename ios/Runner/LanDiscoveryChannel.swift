import Darwin
import Flutter

/// Browses for PCs advertising `_streamphonecam._tcp` on the LAN (see
/// HELP.md's "LAN discovery" section) via Bonjour (`NetServiceBrowser`).
/// This app never advertises itself — only browses — mirroring
/// `LanDiscoveryChannel.kt`'s NsdManager-discovery-only behavior on Android.
final class LanDiscoveryChannel: NSObject, FlutterStreamHandler, NetServiceBrowserDelegate, NetServiceDelegate {
    private static let serviceType = "_streamphonecam._tcp."
    private static let serviceDomain = "local."

    private var eventSink: FlutterEventSink?
    private var browser: NetServiceBrowser?
    /// Keeps a strong reference to in-flight/resolved services — NetService
    /// instances are dropped (and their delegate callbacks stop firing) if
    /// nothing retains them.
    private var resolvingServices: [NetService] = []
    private var knownByServiceName: [String: [String: Any]] = [:]

    func register(messenger: FlutterBinaryMessenger) {
        let methodChannel = FlutterMethodChannel(name: "com.streamphonecam/lan_discovery", binaryMessenger: messenger)
        methodChannel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "startBrowse":
                self?.startBrowse()
                result(nil)
            case "stopBrowse":
                self?.stopBrowse()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        let eventChannel = FlutterEventChannel(name: "com.streamphonecam/lan_discovery_events", binaryMessenger: messenger)
        eventChannel.setStreamHandler(self)
    }

    private func startBrowse() {
        guard browser == nil else { return }
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: Self.serviceType, inDomain: Self.serviceDomain)
        self.browser = browser
    }

    private func stopBrowse() {
        browser?.stop()
        browser = nil
        resolvingServices.forEach { $0.stop() }
        resolvingServices.removeAll()
        knownByServiceName.removeAll()
    }

    // MARK: - NetServiceBrowserDelegate

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        resolvingServices.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        resolvingServices.removeAll { $0 === service }
        guard let known = knownByServiceName.removeValue(forKey: service.name) else { return }
        var event = known
        event["type"] = "lost"
        eventSink?(event)
    }

    // MARK: - NetServiceDelegate

    func netServiceDidResolveAddress(_ service: NetService) {
        guard let txtData = service.txtRecordData() else { return }
        let txt = NetService.dictionary(fromTXTRecord: txtData)
        func value(_ key: String) -> String? {
            guard let data = txt[key] else { return nil }
            return String(data: data, encoding: .utf8)
        }

        guard let pcId = value("id") else { return }
        let event: [String: Any] = [
            "type": "found",
            "pcId": pcId,
            "pcName": value("name") ?? service.name,
            "host": Self.firstIPv4Address(service) ?? service.hostName ?? "",
            "port": service.port,
            "wsPath": value("path") ?? "/pair",
        ]
        knownByServiceName[service.name] = event
        eventSink?(event)
    }

    /// Prefers a resolved literal IPv4 address over `hostName` (a `.local`
    /// mDNS name) — a literal address is what the WebSocket signaling
    /// client actually needs to connect without depending on the phone's
    /// own mDNS resolver working for arbitrary hostnames.
    private static func firstIPv4Address(_ service: NetService) -> String? {
        guard let addresses = service.addresses else { return nil }
        for data in addresses {
            let result: String? = data.withUnsafeBytes { rawBuffer -> String? in
                guard let sockaddrPtr = rawBuffer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else {
                    return nil
                }
                guard sockaddrPtr.pointee.sa_family == sa_family_t(AF_INET) else { return nil }
                var addrIn = sockaddrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addrIn.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                return String(cString: buffer)
            }
            if let result { return result }
        }
        return nil
    }

    func netService(_ service: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolvingServices.removeAll { $0 === service }
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = eventSink
        // Replay everything already resolved, same race-cover pattern as
        // ScreencastChannel's onListen.
        knownByServiceName.values.forEach { eventSink($0) }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
