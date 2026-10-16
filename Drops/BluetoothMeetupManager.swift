import CoreBluetooth
import Foundation
import Combine

// MARK: - BluetoothMeetupManager
//
// Automatische Treffen-Bestätigung über BLE-Proximity.
//
// Anti-Abuse-Schutz (3 Schichten):
//   1. Mindestzeit im Drop: BLE-Bestätigung erst nach 5 Min aktiver Drop-Teilnahme möglich.
//      → Wer sofort daneben sitzt und beitritt, bekommt noch nichts bestätigt.
//   2. Partner-Cooldown: Dieselben zwei Personen können sich nur einmal pro 6 Stunden
//      gegenseitig bestätigen. Verhindert, dass Freunde permanent nebeneinander sitzen
//      und wiederholt Score aufbauen.
//   3. Tages-Cap: Max. 4 BLE-Bestätigungen pro Kalendertag. Verhindert massenhaftes
//      Farmen mit mehreren Freunden.
//
// Normaler Ablauf:
//   1. Nutzer tritt einem Drop bei → start(userToken:dropID:joinedAt:)
//   2. BLE advertised Drop-spezifische Service-UUID + kurzen User-Token
//   3. Anderen Teilnehmer desselben Drops werden erkannt
//   4. Nach 5 Min Drop-Zeit + 20 Sek. Proximity → onMeetupConfirmed(partnerToken)
//
// iOS-Voraussetzungen:
//   • Info.plist: NSBluetoothAlwaysUsageDescription
//   • Background Modes: bluetooth-central, bluetooth-peripheral

final class BluetoothMeetupManager: NSObject, ObservableObject {

    // MARK: - Konfiguration

    static let tokenCharUUID     = CBUUID(string: "D50F4E0B-5B3C-4A8D-9F2E-1C7B6A3E8D5F")

    /// RSSI-Schwelle: "in der Nähe" (~5-10 m)
    static let proximityRSSI: Int        = -72
    /// Wie lange muss der Partner in Reichweite sein, um zu bestätigen
    static let proximityDuration: TimeInterval = 20
    /// Mindestzeit im Drop, bevor eine BLE-Bestätigung möglich ist.
    /// Vorher 5 Min — fühlte sich träge an („jemand ist da aber nix passiert
    /// in der UI"). 20 s fühlen sich live an: Joiner trifft ein → kurz drauf
    /// „Vor Ort". Die anderen zwei Abuse-Schichten (Partner-Cooldown 6h,
    /// Tages-Cap 4) bleiben scharf und verhindern Farming.
    static let minDropDuration: TimeInterval   = 20
    /// Cooldown zwischen zwei Bestätigungen desselben Partner-Paares
    static let partnerCooldown: TimeInterval   = 6 * 60 * 60  // 6 Stunden
    /// Maximale BLE-Bestätigungen pro Kalendertag
    static let dailyCap: Int = 4

    // MARK: - Persistenter State (überlebt App-Starts)

    /// token → letztes Bestätigungsdatum (partnerCooldown-Check)
    private(set) var lastConfirmedPerPartner: [String: Date] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "ble_partner_confirm"),
                  let dict = try? JSONDecoder().decode([String: Date].self, from: data)
            else { return [:] }
            return dict
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: "ble_partner_confirm")
        }
    }

    /// Bestätigungs-Timestamps des heutigen Tages (dailyCap-Check)
    private(set) var todayConfirmations: [Date] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "ble_daily_confirms"),
                  let arr = try? JSONDecoder().decode([Date].self, from: data)
            else { return [] }
            // Nur heutige Einträge zurückgeben
            let startOfDay = Calendar.current.startOfDay(for: Date())
            return arr.filter { $0 >= startOfDay }
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: "ble_daily_confirms")
        }
    }

    // MARK: - Öffentlicher State

    @Published var nearbyTokens: Set<String>   = []
    @Published var confirmedTokens: Set<String> = []

    // MARK: - Callbacks

    /// Wird auf dem Main-Thread aufgerufen, wenn ein Treffen bestätigt wurde.
    var onMeetupConfirmed: ((String) -> Void)?

    /// Wird aufgerufen wenn eine Bestätigung abgelehnt wurde (für UI-Feedback).
    /// Parameter: Grund als String
    var onConfirmationBlocked: ((String) -> Void)?

    /// Wird sofort aufgerufen wenn ein Token mit gutem RSSI erkannt wird —
    /// ohne Anti-Abuse-Delays. Wird vom Host genutzt um die Live Activity zu aktualisieren.
    var onParticipantNearby: ((String) -> Void)?

    // MARK: - Private

    private var central: CBCentralManager!
    private var peripheral: CBPeripheralManager!
    private var myToken: String = ""
    private var dropServiceUUID: CBUUID?
    private var joinedAt: Date = Date()
    private var firstSeenAt: [String: Date] = [:]
    private var peripheralTokens: [UUID: String] = [:]
    private let bleQueue = DispatchQueue(label: "de.drops.ble", qos: .background)

    // MARK: - Init

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self, queue: bleQueue,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "de.drops.central"]
        )
        peripheral = CBPeripheralManager(
            delegate: self, queue: bleQueue,
            options: [CBPeripheralManagerOptionRestoreIdentifierKey: "de.drops.peripheral"]
        )
    }

    // MARK: - Public API

    /// Trigger für den iOS-Bluetooth-Permission-Prompt im Onboarding.
    /// Macht nichts außer den Manager initialisieren (passiert im `init`
    /// implizit beim ersten Touch der lazy `store.bluetoothMeetup`-
    /// Property). iOS zeigt dann automatisch den BLE-Permission-Dialog
    /// mit dem `NSBluetoothAlwaysUsageDescription`-Text aus Info.plist.
    /// Idempotent — kann mehrfach aufgerufen werden ohne Side-Effects.
    func warmUpForPermissionPrompt() {
        // Touching `central.state` reicht iOS-intern aus, um den
        // Permission-Check zu triggern, wenn noch nicht entschieden.
        _ = central.state
        _ = peripheral.state
    }

    /// Startet BLE-Session für einen Drop.
    /// - Parameters:
    ///   - userToken: Kurzer Identifier des eigenen Nutzers (8 Zeichen)
    ///   - dropID: UUID des Drops
    ///   - joinedAt: Zeitpunkt des Beitritts (für Mindestzeit-Prüfung)
    func start(userToken: String, dropID: UUID, joinedAt: Date = Date()) {
        guard !userToken.isEmpty else { return }
        myToken  = String(userToken.prefix(8))
        self.joinedAt = joinedAt
        dropServiceUUID = CBUUID(string: derivedServiceUUID(from: dropID))

        firstSeenAt     = [:]
        confirmedTokens = []
        nearbyTokens    = []
        peripheralTokens = [:]

        if central.state    == .poweredOn { beginScanning() }
        if peripheral.state == .poweredOn { beginAdvertising() }
    }

    func stop() {
        peripheral.stopAdvertising()
        peripheral.removeAllServices()
        central.stopScan()
        myToken = ""
        dropServiceUUID = nil
        firstSeenAt     = [:]
        nearbyTokens    = []
        peripheralTokens = [:]
    }

    // MARK: - Anti-Abuse Checks

    /// Prüft alle drei Schutzschichten. Gibt nil zurück wenn erlaubt, sonst einen Ablehnungsgrund.
    private func abuseCheckReason(for partnerToken: String) -> String? {
        // 1. Mindestzeit im Drop
        let timeInDrop = Date().timeIntervalSince(joinedAt)
        if timeInDrop < Self.minDropDuration {
            let remaining = Int((Self.minDropDuration - timeInDrop) / 60) + 1
            return tr("ble.stay_longer").replacingOccurrences(of: "{mins}", with: "\(remaining)")
        }

        // 2. Partner-Cooldown
        if let lastConfirm = lastConfirmedPerPartner[partnerToken] {
            let elapsed = Date().timeIntervalSince(lastConfirm)
            if elapsed < Self.partnerCooldown {
                let hoursLeft = Int((Self.partnerCooldown - elapsed) / 3600) + 1
                return tr("ble.recently_confirmed").replacingOccurrences(of: "{hours}", with: "\(hoursLeft)")
            }
        }

        // 3. Tages-Cap
        if todayConfirmations.count >= Self.dailyCap {
            return tr("ble.daily_limit").replacingOccurrences(of: "{cap}", with: "\(Self.dailyCap)")
        }

        return nil  // Alles okay
    }

    private func recordConfirmation(for partnerToken: String) {
        var dict = lastConfirmedPerPartner
        dict[partnerToken] = Date()
        lastConfirmedPerPartner = dict

        var today = todayConfirmations
        today.append(Date())
        todayConfirmations = today
    }

    // MARK: - Discovery Handler

    private func handleDiscovery(token: String, rssi: Int) {
        guard rssi >= Self.proximityRSSI else {
            DispatchQueue.main.async { self.nearbyTokens.remove(token) }
            return
        }
        guard token != myToken, !confirmedTokens.contains(token) else { return }

        DispatchQueue.main.async {
            self.nearbyTokens.insert(token)
            // Sofort-Callback für Live Activity (kein Anti-Abuse-Delay nötig)
            self.onParticipantNearby?(token)
        }

        // Proximity-Timer erst starten, wenn Mindestzeit im Drop erfüllt
        // (Schicht 1: frühzeitig filtern, spart CPU wenn eh blockiert)
        let timeInDrop = Date().timeIntervalSince(joinedAt)
        guard timeInDrop >= Self.minDropDuration else { return }

        let now = Date()
        if let firstSeen = firstSeenAt[token] {
            if now.timeIntervalSince(firstSeen) >= Self.proximityDuration {
                firstSeenAt.removeValue(forKey: token)

                // Alle Abuse-Checks
                if let reason = abuseCheckReason(for: token) {
                    DispatchQueue.main.async {
                        self.onConfirmationBlocked?(reason)
                    }
                    return
                }

                // ✓ Treffen bestätigen
                recordConfirmation(for: token)
                DispatchQueue.main.async {
                    self.confirmedTokens.insert(token)
                    self.nearbyTokens.remove(token)
                    self.onMeetupConfirmed?(token)
                }
            }
        } else {
            firstSeenAt[token] = now
        }
    }

    // MARK: - UUID Ableitung

    /// Drop-spezifische Service-UUID: nur Teilnehmer desselben Drops finden sich.
    private func derivedServiceUUID(from dropID: UUID) -> String {
        let bytes = dropID.uuid
        let base  = UUID(uuidString: "D50F4E0A-5B3C-4A8D-9F2E-1C7B6A3E8D5F")!.uuid
        let b0 = bytes.0 ^ base.0
        let b1 = bytes.1 ^ base.1
        let b2 = bytes.2 ^ base.2
        let b3 = bytes.3 ^ base.3
        return String(format: "%02X%02X%02X%02X-5B3C-4A8D-9F2E-1C7B6A3E8D5F", b0, b1, b2, b3)
    }

    // MARK: - BLE Setup

    private func beginAdvertising() {
        guard let svcUUID = dropServiceUUID, !myToken.isEmpty else { return }
        let char = CBMutableCharacteristic(
            type: Self.tokenCharUUID,
            properties: [.read], value: Data(myToken.utf8), permissions: .readable
        )
        let service = CBMutableService(type: svcUUID, primary: true)
        service.characteristics = [char]
        peripheral.removeAllServices()
        peripheral.add(service)
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [svcUUID],
            CBAdvertisementDataLocalNameKey: "drp-\(myToken)"
        ])
    }

    private func beginScanning() {
        guard let svcUUID = dropServiceUUID else { return }
        central.scanForPeripherals(
            withServices: [svcUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothMeetupManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, dropServiceUUID != nil { beginScanning() }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           name.hasPrefix("drp-") {
            handleDiscovery(token: String(name.dropFirst(4).prefix(8)), rssi: RSSI.intValue)
            return
        }
        if RSSI.intValue >= Self.proximityRSSI,
           peripheralTokens[peripheral.identifier] == nil {
            peripheralTokens[peripheral.identifier] = "__pending__"
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        if let svcUUID = dropServiceUUID { peripheral.discoverServices([svcUUID]) }
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        peripheralTokens.removeValue(forKey: peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        peripheralTokens.removeValue(forKey: peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if dropServiceUUID != nil { beginScanning() }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothMeetupManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for s in services { peripheral.discoverCharacteristics([Self.tokenCharUUID], for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let chars = service.characteristics else { return }
        for c in chars where c.uuid == Self.tokenCharUUID { peripheral.readValue(for: c) }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              let data = characteristic.value,
              let token = String(data: data, encoding: .utf8) else { return }
        peripheralTokens[peripheral.identifier] = token
        central.cancelPeripheralConnection(peripheral)
        handleDiscovery(token: String(token.prefix(8)), rssi: Self.proximityRSSI)
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BluetoothMeetupManager: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn, dropServiceUUID != nil { beginAdvertising() }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {}

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           willRestoreState dict: [String: Any]) {
        if dropServiceUUID != nil { beginAdvertising() }
    }
}
