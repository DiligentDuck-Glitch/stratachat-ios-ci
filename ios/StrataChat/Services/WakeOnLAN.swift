import Foundation
import Network

public enum WakeOnLAN {
    public static let targetMAC = "2c:f0:5d:7a:5d:70"
    public static let subnetBroadcast = "192.168.1.255"
    public static let globalBroadcast = "255.255.255.255"
    
    public static func sendMagicPacket(mac: String = targetMAC, port: UInt16 = 9) {
        let cleanMac = mac.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        guard cleanMac.count == 12 else {
            print("WakeOnLAN: Invalid MAC address \(mac)")
            return
        }
        
        var macBytes = [UInt8]()
        for i in stride(from: 0, to: 12, by: 2) {
            let start = cleanMac.index(cleanMac.startIndex, offsetBy: i)
            let end = cleanMac.index(start, offsetBy: 2)
            if let byte = UInt8(cleanMac[start..<end], radix: 16) {
                macBytes.append(byte)
            }
        }
        guard macBytes.count == 6 else { return }
        
        // 6 bytes of 0xFF followed by 16 repetitions of the target MAC
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }
        
        let nwPort = NWEndpoint.Port(rawValue: port)!
        
        // Send over default interface AND force over Wi-Fi interface.
        // This guarantees that even if iOS detects "No Internet" (when AdGuard is offline)
        // and tries to route normal traffic via Cellular, the magic packet is still blasted over local Wi-Fi.
        let defaultParams = NWParameters.udp
        defaultParams.allowLocalEndpointReuse = true
        
        let wifiParams = NWParameters.udp
        wifiParams.allowLocalEndpointReuse = true
        wifiParams.requiredInterfaceType = .wifi
        
        let targets: [(String, NWParameters)] = [
            (subnetBroadcast, defaultParams),
            (globalBroadcast, defaultParams),
            (subnetBroadcast, wifiParams),
            (globalBroadcast, wifiParams)
        ]
        
        for (targetHost, params) in targets {
            let conn = NWConnection(host: NWEndpoint.Host(targetHost), port: nwPort, using: params)
            conn.stateUpdateHandler = { state in
                if case .ready = state {
                    conn.send(content: packet, completion: .contentProcessed({ _ in
                        // Send twice for UDP redundancy
                        conn.send(content: packet, completion: .contentProcessed({ _ in
                            conn.cancel()
                        }))
                    }))
                }
            }
            conn.start(queue: .global())
        }
        
        print("WakeOnLAN: Magic packet burst sent to \(mac) on port \(port)")
    }
}
