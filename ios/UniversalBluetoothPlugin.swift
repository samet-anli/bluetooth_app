import Flutter
import UIKit
import CoreBluetooth
import CoreLocation
import ExternalAccessory

public class UniversalBluetoothPlugin: NSObject {
    private var channel: FlutterMethodChannel?
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var locationManager: CLLocationManager?
    
    // Classic Bluetooth simulation using BLE
    private var connectedPeripherals: [String: CBPeripheral] = [:]
    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    private var characteristics: [String: [String: CBCharacteristic]] = [:]
    private var dataReadServices: [String: CBService] = [:]
    
    // Connection management
    private var connectionStates: [String: Int] = [:]
    private var dataQueues: [String: [Data]] = [:]
    
    // Scanning states
    private var isScanning = false
    private var isBleScanning = false
    private var isBeaconScanning = false
    private var isAdvertising = false
    private var isDiscoverable = false
    
    // For async operations
    private var pendingResult: FlutterResult?
    private var pendingOperations: [String: FlutterResult] = [:]
    
    // Service UUID for Classic Bluetooth simulation
    private let classicServiceUUID = CBUUID(string: "00001101-0000-1000-8000-00805F9B34FB")
    private let dataCharacteristicUUID = CBUUID(string: "00002A3D-0000-1000-8000-00805F9B34FB")
    
    // Singleton instance
    static let shared = UniversalBluetoothPlugin()
    
    override init() {
        super.init()
        setupManagers()
    }
    
    // Initialize with Flutter binary messenger
    func initialize(with messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "universal_bluetooth", binaryMessenger: messenger)
        channel?.setMethodCallHandler(handle)
    }
    
    private func setupManagers() {
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        locationManager = CLLocationManager()
        locationManager?.delegate = self
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        NSLog("iOS: Received method call: \(call.method)")
        
        switch call.method {
        // Classic Bluetooth
        case "isBluetoothAvailable":
            result(true) // iOS always has Bluetooth capability
        case "isBluetoothEnabled":
            result(centralManager?.state == .poweredOn)
        case "getBluetoothAddress":
            getBluetoothAddress(result: result)
        case "requestBluetoothEnable":
            requestBluetoothEnable(result: result)
        case "startBluetoothScan":
            startBluetoothScan(result: result)
        case "stopBluetoothScan":
            stopBluetoothScan(result: result)
        case "startBluetoothDiscoverable":
            startBluetoothDiscoverable(call: call, result: result)
        case "stopBluetoothDiscoverable":
            stopBluetoothDiscoverable(result: result)
        case "connectToBluetoothDevice":
            connectToBluetoothDevice(call: call, result: result)
        case "disconnectBluetoothDevice":
            disconnectBluetoothDevice(call: call, result: result)
        case "sendBluetoothData":
            sendBluetoothData(call: call, result: result)
            
        // Debug methods
        case "getConnectedDevices":
            getConnectedDevices(result: result)
        case "testDataSend":
            testDataSend(call: call, result: result)
            
        // BLE
        case "isBleAvailable":
            result(true) // iOS always supports BLE
        case "startBleScan":
            startBleScan(call: call, result: result)
        case "stopBleScan":
            stopBleScan(result: result)
        case "connectToBleDevice":
            connectToBleDevice(call: call, result: result)
        case "disconnectBleDevice":
            disconnectBleDevice(call: call, result: result)
        case "discoverBleServices":
            discoverBleServices(call: call, result: result)
        case "getBleCharacteristics":
            getBleCharacteristics(call: call, result: result)
        case "readBleCharacteristic":
            readBleCharacteristic(call: call, result: result)
        case "writeBleCharacteristic":
            writeBleCharacteristic(call: call, result: result)
        case "subscribeBleCharacteristic":
            subscribeBleCharacteristic(call: call, result: result)
        case "unsubscribeBleCharacteristic":
            unsubscribeBleCharacteristic(call: call, result: result)
            
        // iBeacon
        case "isBeaconSupported":
            result(CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self))
        case "startBeaconAdvertising":
            startBeaconAdvertising(call: call, result: result)
        case "stopBeaconAdvertising":
            stopBeaconAdvertising(result: result)
        case "startBeaconScanning":
            startBeaconScanning(call: call, result: result)
        case "stopBeaconScanning":
            stopBeaconScanning(result: result)
        case "requestLocationPermission":
            requestLocationPermission(result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Debug Methods
    
    private func getConnectedDevices(result: @escaping FlutterResult) {
        let connectedList = Array(connectedPeripherals.keys)
        NSLog("iOS: Connected devices: \(connectedList)")
        result(connectedList)
    }
    
    private func testDataSend(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Device ID is required", details: nil))
            return
        }
        
        let testMessage = "test_message_from_ios"
        NSLog("iOS: 🧪 Test sending data to \(deviceId)")
        
        DispatchQueue.global(qos: .background).async {
            guard let peripheral = self.connectedPeripherals[deviceId],
                  let service = peripheral.services?.first(where: { $0.uuid == self.classicServiceUUID }),
                  let characteristic = service.characteristics?.first(where: { $0.uuid == self.dataCharacteristicUUID }) else {
                DispatchQueue.main.async {
                    NSLog("iOS: ❌ No connection or characteristic for \(deviceId)")
                    result(FlutterError(code: "NOT_CONNECTED", message: "Device not connected or characteristic not found", details: nil))
                }
                return
            }
            
            let data = testMessage.data(using: .utf8) ?? Data()
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            
            DispatchQueue.main.async {
                NSLog("iOS: ✅ Test data sent successfully: \(testMessage)")
                result("Test data sent: \(testMessage)")
            }
        }
    }
    
    // MARK: - Classic Bluetooth Methods
    
    private func getBluetoothAddress(result: @escaping FlutterResult) {
        // iOS doesn't provide access to the Bluetooth MAC address for privacy reasons
        // We'll generate a consistent identifier based on device
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "Unknown"
        let bluetoothId = "iOS-\(deviceId.prefix(8))"
        NSLog("iOS: My Bluetooth identifier: \(bluetoothId)")
        result(bluetoothId)
    }
    
    private func requestBluetoothEnable(result: @escaping FlutterResult) {
        if centralManager?.state == .poweredOn {
            result(true)
        } else {
            pendingResult = result
            // iOS doesn't allow programmatic Bluetooth enabling
            // User must enable it manually in Settings
            result(false)
        }
    }
    
    private func startBluetoothScan(result: @escaping FlutterResult) {
        NSLog("iOS: startBluetoothScan called")
        
        guard centralManager?.state == .poweredOn else {
            NSLog("iOS: Bluetooth is not enabled")
            result(FlutterError(code: "BLUETOOTH_DISABLED", message: "Bluetooth is not enabled", details: nil))
            return
        }
        
        if isScanning {
            NSLog("iOS: Already scanning, stopping previous scan")
            centralManager?.stopScan()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startActualScan(result: result)
            }
        } else {
            startActualScan(result: result)
        }
    }
    
    private func startActualScan(result: @escaping FlutterResult) {
        // Clear previous results
        discoveredPeripherals.removeAll()
        
        NSLog("iOS: Starting Bluetooth discovery (BLE scan)")
        isScanning = true
        
        // Scan for devices with Classic Bluetooth service UUID and general BLE devices
        let serviceUUIDs: [CBUUID]? = nil // Scan for all devices
        let options = [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        
        centralManager?.scanForPeripherals(withServices: serviceUUIDs, options: options)
        
        // Set timeout for scan completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            if self.isScanning {
                NSLog("iOS: Scan timeout reached, stopping discovery")
                self.centralManager?.stopScan()
                self.isScanning = false
                self.notifyBluetoothScanFinished()
            }
        }
        
        result(nil)
    }
    
    private func stopBluetoothScan(result: @escaping FlutterResult) {
        if isScanning {
            centralManager?.stopScan()
            isScanning = false
            notifyBluetoothScanFinished()
        }
        result(nil)
    }
    
    private func startBluetoothDiscoverable(call: FlutterMethodCall, result: @escaping FlutterResult) {
        NSLog("iOS: startBluetoothDiscoverable called")
        
        guard centralManager?.state == .poweredOn,
              peripheralManager?.state == .poweredOn else {
            result(FlutterError(code: "BLUETOOTH_DISABLED", message: "Bluetooth is not enabled", details: nil))
            return
        }
        
        let args = call.arguments as? [String: Any]
        let duration = args?["duration"] as? Int ?? 300
        NSLog("iOS: Discoverable duration: \(duration)")
        
        if !isDiscoverable {
            startBluetoothPeripheralMode(duration: duration, result: result)
        } else {
            result(true)
        }
    }
    
    private func startBluetoothPeripheralMode(duration: Int, result: @escaping FlutterResult) {
        // Create service for Classic Bluetooth simulation
        let service = CBMutableService(type: classicServiceUUID, primary: true)
        
        // Create characteristic for data exchange
        let dataCharacteristic = CBMutableCharacteristic(
            type: dataCharacteristicUUID,
            properties: [.read, .write, .notify, .writeWithoutResponse],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        service.characteristics = [dataCharacteristic]
        
        // Add service to peripheral manager
        peripheralManager?.add(service)
        
        // Start advertising
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [classicServiceUUID],
            CBAdvertisementDataLocalNameKey: "UniversalBluetooth-iOS"
        ]
        
        peripheralManager?.startAdvertising(advertisementData)
        isDiscoverable = true
        
        NSLog("iOS: ✅ Started peripheral mode and advertising")
        result(true)
        
        // Auto-stop after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(duration)) {
            if self.isDiscoverable {
                self.stopBluetoothDiscoverable { _ in }
            }
        }
    }
    
    private func stopBluetoothDiscoverable(result: @escaping FlutterResult) {
        if isDiscoverable {
            peripheralManager?.stopAdvertising()
            isDiscoverable = false
            NSLog("iOS: Stopped discoverable mode")
        }
        result(nil)
    }
    
    private func connectToBluetoothDevice(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Device ID is required", details: nil))
            return
        }
        
        guard let peripheral = discoveredPeripherals[deviceId] else {
            result(FlutterError(code: "DEVICE_NOT_FOUND", message: "Device not found", details: nil))
            return
        }
        
        NSLog("iOS: 🔗 Attempting to connect to device: \(peripheral.name ?? "Unknown") (\(peripheral.identifier.uuidString))")
        
        // Set connection state to connecting
        connectionStates[deviceId] = 1
        notifyConnectionStateChanged(deviceId: deviceId, state: 1)
        
        peripheral.delegate = self
        centralManager?.connect(peripheral, options: nil)
        result(nil)
    }
    
    private func disconnectBluetoothDevice(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String,
              let peripheral = connectedPeripherals[deviceId] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid device ID", details: nil))
            return
        }
        
        NSLog("iOS: Disconnecting from \(deviceId)")
        centralManager?.cancelPeripheralConnection(peripheral)
        result(nil)
    }
    
    private func sendBluetoothData(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String,
              let dataArray = args["data"] as? [Int] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Device ID and data are required", details: nil))
            return
        }
        
        let data = Data(dataArray.map { UInt8($0) })
        let message = String(data: data, encoding: .utf8) ?? "Binary Data"
        
        NSLog("iOS: 📤 Sending data to \(deviceId): '\(message)' (\(dataArray.count) bytes)")
        NSLog("iOS: 📤 Raw data: \(dataArray)")
        
        DispatchQueue.global(qos: .background).async {
            guard let peripheral = self.connectedPeripherals[deviceId] else {
                DispatchQueue.main.async {
                    NSLog("iOS: ❌ Device not connected: \(deviceId)")
                    result(FlutterError(code: "NOT_CONNECTED", message: "Device is not connected", details: nil))
                }
                return
            }
            
            // Find the data characteristic
            guard let service = peripheral.services?.first(where: { $0.uuid == self.classicServiceUUID }),
                  let characteristic = service.characteristics?.first(where: { $0.uuid == self.dataCharacteristicUUID }) else {
                DispatchQueue.main.async {
                    NSLog("iOS: ❌ Characteristic not found for \(deviceId)")
                    result(FlutterError(code: "CHARACTERISTIC_NOT_FOUND", message: "Data characteristic not found", details: nil))
                }
                return
            }
            
            // Write data
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            
            DispatchQueue.main.async {
                NSLog("iOS: ✅ Data sent successfully to \(deviceId)")
                result(nil)
            }
        }
    }
    
    private func notifyBluetoothScanFinished() {
        DispatchQueue.main.async {
            NSLog("iOS: Sending scan finished event to Flutter")
            self.channel?.invokeMethod("onBluetoothScanFinished", arguments: nil)
        }
    }
    
    private func notifyConnectionStateChanged(deviceId: String, state: Int) {
        DispatchQueue.main.async {
            NSLog("iOS: 🔔 Connection state changed for \(deviceId): \(state)")
            self.channel?.invokeMethod("onBluetoothConnectionStateChanged", arguments: [
                "deviceId": deviceId,
                "state": state
            ])
        }
    }
    
    private func notifyDataReceived(deviceId: String, data: Data) {
        let dataArray = data.map { Int($0) }
        let message = String(data: data, encoding: .utf8) ?? "Binary Data"
        
        NSLog("iOS: 📩 Received data from \(deviceId): '\(message)' (\(data.count) bytes)")
        NSLog("iOS: 📩 Raw bytes: \(dataArray)")
        
        DispatchQueue.main.async {
            self.channel?.invokeMethod("onBluetoothDataReceived", arguments: [
                "deviceId": deviceId,
                "data": dataArray
            ])
        }
        
        // Auto-respond to "hello" with "hi"
        if message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "hello" {
            NSLog("iOS: 🔄 Received 'hello', sending 'hi' response")
            self.sendAutoResponse(deviceId: deviceId, message: "hi")
        }
    }
    
    private func sendAutoResponse(deviceId: String, message: String) {
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 0.5) {
            guard let peripheral = self.connectedPeripherals[deviceId],
                  let service = peripheral.services?.first(where: { $0.uuid == self.classicServiceUUID }),
                  let characteristic = service.characteristics?.first(where: { $0.uuid == self.dataCharacteristicUUID }) else {
                NSLog("iOS: ❌ Cannot send auto-response, connection lost")
                return
            }
            
            let data = message.data(using: .utf8) ?? Data()
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            NSLog("iOS: ✅ Auto-response sent: '\(message)'")
        }
    }
    
    // MARK: - BLE Methods
    
    private func startBleScan(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard centralManager?.state == .poweredOn else {
            result(FlutterError(code: "BLUETOOTH_DISABLED", message: "Bluetooth is not enabled", details: nil))
            return
        }
        
        let args = call.arguments as? [String: Any]
        let serviceUuids = args?["serviceUuids"] as? [String]
        let timeout = args?["timeout"] as? Int
        
        var services: [CBUUID]?
        if let uuids = serviceUuids {
            services = uuids.compactMap { CBUUID(string: $0) }
        }
        
        if !isBleScanning {
            isBleScanning = true
            centralManager?.scanForPeripherals(withServices: services, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            
            if let timeoutMs = timeout {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) {
                    self.stopBleScan { _ in }
                }
            }
        }
        result(nil)
    }
    
    private func stopBleScan(result: @escaping FlutterResult) {
        if isBleScanning {
            centralManager?.stopScan()
            isBleScanning = false
        }
        result(nil)
    }
    
    // MARK: - Placeholder BLE methods (implement as needed)
    private func connectToBleDevice(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Implementation similar to connectToBluetoothDevice
        result(FlutterMethodNotImplemented)
    }
    
    private func disconnectBleDevice(call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(FlutterMethodNotImplemented)
    }
    
    private func discoverBleServices(call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(FlutterMethodNotImplemented)
    }
    
    private func getBleCharacteristics(call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(FlutterMethodNotImplemented)
    }
    
    private func readBleCharacteristic(call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(FlutterMethodNotImplemented)
    }
    
    private func writeBleCharacteristic(call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(FlutterMethodNotImplemented)
    }
    
    private func subscribeBleCharacteristic(call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(FlutterMethodNotImplemented)
    }
    
    private func unsubscribeBleCharacteristic(call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(FlutterMethodNotImplemented)
    }
    
    // MARK: - iBeacon Methods
    
    private func startBeaconAdvertising(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let uuidString = args["uuid"] as? String,
              let major = args["major"] as? Int,
              let minor = args["minor"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
            return
        }
        
        guard let uuid = UUID(uuidString: uuidString) else {
            result(FlutterError(code: "INVALID_UUID", message: "Invalid UUID format", details: nil))
            return
        }
        
        let identifier = args["identifier"] as? String ?? "UniversalBluetoothBeacon"
        
        let beaconRegion = CLBeaconRegion(proximityUUID: uuid, major: CLBeaconMajorValue(major), minor: CLBeaconMinorValue(minor), identifier: identifier)
        
        guard let peripheralData = beaconRegion.peripheralData(withMeasuredPower: nil) as? [String: Any] else {
            result(FlutterError(code: "ADVERTISING_FAILED", message: "Failed to create peripheral data", details: nil))
            return
        }
        
        if !isAdvertising {
            peripheralManager?.startAdvertising(peripheralData)
            isAdvertising = true
        }
        result(nil)
    }
    
    private func stopBeaconAdvertising(result: @escaping FlutterResult) {
        if isAdvertising {
            peripheralManager?.stopAdvertising()
            isAdvertising = false
        }
        result(nil)
    }
    
    private func startBeaconScanning(call: FlutterMethodCall, result: @escaping FlutterResult) {
        NSLog("iOS: startBeaconScanning called")
        
        let authStatus = CLLocationManager.authorizationStatus()
        guard authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse else {
            NSLog("iOS: Location permission not granted for beacon scanning")
            result(FlutterError(code: "PERMISSION_DENIED", 
                            message: "Location permission not granted for beacon scanning", 
                            details: nil))
            return
        }
        
        guard CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self) else {
            NSLog("iOS: Beacon monitoring not supported on this device")
            result(FlutterError(code: "NOT_SUPPORTED", 
                            message: "Beacon monitoring not supported on this device", 
                            details: nil))
            return
        }
        
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", 
                            message: "Invalid arguments for beacon scanning", 
                            details: nil))
            return
        }
        
        let uuids = args["uuids"] as? [String]
        
        if isBeaconScanning {
            stopBeaconScanningInternal()
        }
        
        if let uuidStrings = uuids, !uuidStrings.isEmpty {
            NSLog("iOS: Starting beacon scanning for \(uuidStrings.count) UUID(s)")
            
            for uuidString in uuidStrings {
                if let uuid = UUID(uuidString: uuidString) {
                    NSLog("iOS: Setting up monitoring and ranging for UUID: \(uuidString)")
                    
                    let region = CLBeaconRegion(proximityUUID: uuid, 
                                            identifier: "BeaconRegion_\(uuid.uuidString)")
                    region.notifyOnEntry = true
                    region.notifyOnExit = true
                    region.notifyEntryStateOnDisplay = true
                    
                    locationManager?.startMonitoring(for: region)
                    
                    if #available(iOS 13.0, *) {
                        let constraint = CLBeaconIdentityConstraint(uuid: uuid)
                        locationManager?.startRangingBeacons(satisfying: constraint)
                    } else {
                        locationManager?.startRangingBeacons(in: region)
                    }
                } else {
                    NSLog("iOS: Invalid UUID format: \(uuidString)")
                }
            }
            
            isBeaconScanning = true
            NSLog("iOS: ✅ Beacon scanning started successfully")
            result(true)
        } else {
            NSLog("iOS: No UUIDs provided - this is not recommended for production apps")
            result(FlutterError(code: "NO_UUIDS", 
                            message: "No beacon UUIDs provided for scanning", 
                            details: nil))
        }
    }

    
    private func stopBeaconScanning(result: @escaping FlutterResult) {
        NSLog("iOS: stopBeaconScanning called")
        
        if isBeaconScanning {
            stopBeaconScanningInternal()
            NSLog("iOS: ✅ Beacon scanning stopped")
            result(true)
        } else {
            NSLog("iOS: Beacon scanning was not active")
            result(false)
        }
    }

    
    private func stopBeaconScanningInternal() {
        if isBeaconScanning {
            NSLog("iOS: Stopping beacon monitoring and ranging...")
            
            for region in locationManager?.monitoredRegions ?? [] {
                locationManager?.stopMonitoring(for: region)
                NSLog("iOS: Stopped monitoring for region: \(region.identifier)")
                
                if let beaconRegion = region as? CLBeaconRegion {
                    if #available(iOS 13.0, *) {
                        let constraint = CLBeaconIdentityConstraint(uuid: beaconRegion.proximityUUID)
                        locationManager?.stopRangingBeacons(satisfying: constraint)
                    } else {
                        locationManager?.stopRangingBeacons(in: beaconRegion)
                    }
                    NSLog("iOS: Stopped ranging beacons for UUID: \(beaconRegion.proximityUUID.uuidString)")
                }
            }
            
            isBeaconScanning = false
        }
    }

    private func requestLocationPermission(result: @escaping FlutterResult) {
        NSLog("iOS: requestLocationPermission called")
        
        let status = CLLocationManager.authorizationStatus()
        NSLog("iOS: Current location permission status: \(status.rawValue)")
        
        switch status {
        case .authorizedAlways:
            NSLog("iOS: Location permission already granted (Always)")
            result(true)
        case .authorizedWhenInUse:
            NSLog("iOS: Location permission already granted (When In Use)")
            result(true)
        case .notDetermined:
            NSLog("iOS: Location permission not determined - requesting...")
            pendingResult = result
            locationManager?.requestWhenInUseAuthorization()
        case .denied:
            NSLog("iOS: Location permission denied")
            result(false)
        case .restricted:
            NSLog("iOS: Location permission restricted")
            result(false)
        @unknown default:
            NSLog("iOS: Unknown location permission status")
            result(false)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension UniversalBluetoothPlugin: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        NSLog("iOS: Central manager state changed to: \(central.state.rawValue)")
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceId = peripheral.identifier.uuidString
        discoveredPeripherals[deviceId] = peripheral
        
        let serviceUuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        
        let deviceName = localName ?? peripheral.name ?? "Unknown"
        
        NSLog("iOS: Found device: \(deviceName) (\(deviceId)) RSSI: \(RSSI)")
        
        let deviceMap: [String: Any] = [
            "id": deviceId,
            "name": deviceName,
            "address": deviceId,
            "rssi": RSSI.intValue,
            "serviceUuids": serviceUuids?.map { $0.uuidString } ?? [],
            "isConnected": false
        ]
        
        if isBleScanning {
            // For BLE scan results
            let bleDeviceMap: [String: Any] = [
                "id": deviceId,
                "name": deviceName,
                "address": deviceId,
                "rssi": RSSI.intValue,
                "serviceUuids": serviceUuids?.map { $0.uuidString } ?? [],
                "isConnectable": true
            ]
            channel?.invokeMethod("onBleScanResult", arguments: bleDeviceMap)
        } else {
            // For Classic Bluetooth scan results
            let scanResult: [String: Any] = [
                "device": deviceMap,
                "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                "isFirstScan": !discoveredPeripherals.keys.contains(deviceId)
            ]
            
            DispatchQueue.main.async {
                NSLog("iOS: Sending scan result to Flutter: \(deviceName) (\(deviceId))")
                self.channel?.invokeMethod("onBluetoothScanResult", arguments: scanResult)
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let deviceId = peripheral.identifier.uuidString
        connectedPeripherals[deviceId] = peripheral
        connectionStates[deviceId] = 2
        
        NSLog("iOS: ✅ Connected to \(peripheral.name ?? "Unknown") (\(deviceId))")
        notifyConnectionStateChanged(deviceId: deviceId, state: 2)
        
        // Discover services
        peripheral.discoverServices([classicServiceUUID])
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier.uuidString
        connectedPeripherals.removeValue(forKey: deviceId)
        characteristics.removeValue(forKey: deviceId)
        connectionStates[deviceId] = 0
        
        NSLog("iOS: 🔌 Disconnected from \(peripheral.name ?? "Unknown") (\(deviceId))")
        if let error = error {
            NSLog("iOS: Disconnect error: \(error.localizedDescription)")
        }
        
        notifyConnectionStateChanged(deviceId: deviceId, state: 0)
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier.uuidString
        connectionStates[deviceId] = 4
        
        NSLog("iOS: ❌ Failed to connect to \(peripheral.name ?? "Unknown") (\(deviceId))")
        if let error = error {
            NSLog("iOS: Connection error: \(error.localizedDescription)")
        }
        
        notifyConnectionStateChanged(deviceId: deviceId, state: 4)
    }
}

// MARK: - CBPeripheralDelegate

extension UniversalBluetoothPlugin: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { 
            if let error = error {
                NSLog("iOS: Error discovering services: \(error.localizedDescription)")
            }
            return 
        }
        
        NSLog("iOS: Discovered \(services.count) services for \(peripheral.name ?? "Unknown")")
        
        for service in services {
            NSLog("iOS: Discovered service: \(service.uuid)")
            if service.uuid == classicServiceUUID {
                // Discover characteristics for our Classic Bluetooth service
                peripheral.discoverCharacteristics([dataCharacteristicUUID], for: service)
            } else {
                // Discover all characteristics for other services
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { 
            if let error = error {
                NSLog("iOS: Error discovering characteristics: \(error.localizedDescription)")
            }
            return 
        }
        
        let deviceId = peripheral.identifier.uuidString
        NSLog("iOS: Discovered \(characteristics.count) characteristics for service \(service.uuid)")
        
        if self.characteristics[deviceId] == nil {
            self.characteristics[deviceId] = [:]
        }
        
        for characteristic in characteristics {
            let key = "\(service.uuid.uuidString):\(characteristic.uuid.uuidString)"
            self.characteristics[deviceId]?[key] = characteristic
            
            NSLog("iOS: Characteristic: \(characteristic.uuid) - Properties: \(characteristic.properties.rawValue)")
            
            // Auto-subscribe to notifications for our data characteristic
            if service.uuid == classicServiceUUID && characteristic.uuid == dataCharacteristicUUID {
                if characteristic.properties.contains(.notify) {
                    NSLog("iOS: Auto-subscribing to data characteristic notifications")
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            NSLog("iOS: Error reading characteristic: \(error.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value else {
            NSLog("iOS: No data in characteristic update")
            return
        }
        
        let deviceId = peripheral.identifier.uuidString
        let serviceUuid = characteristic.service?.uuid.uuidString ?? ""
        let characteristicUuid = characteristic.uuid.uuidString
        
        NSLog("iOS: 📩 Characteristic value updated: \(serviceUuid):\(characteristicUuid)")
        
        // Handle data for Classic Bluetooth simulation
        if characteristic.service?.uuid == classicServiceUUID && characteristic.uuid == dataCharacteristicUUID {
            notifyDataReceived(deviceId: deviceId, data: data)
        } else {
            // Handle BLE characteristic changes
            let dataArray = Array(data)
            let eventData: [String: Any] = [
                "deviceId": deviceId,
                "serviceUuid": serviceUuid,
                "characteristicUuid": characteristicUuid,
                "data": dataArray
            ]
            
            DispatchQueue.main.async {
                self.channel?.invokeMethod("onBleCharacteristicChanged", arguments: eventData)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            NSLog("iOS: ❌ Error writing characteristic: \(error.localizedDescription)")
        } else {
            NSLog("iOS: ✅ Successfully wrote to characteristic: \(characteristic.uuid)")
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            NSLog("iOS: Error updating notification state: \(error.localizedDescription)")
        } else {
            NSLog("iOS: Notification state updated for characteristic: \(characteristic.uuid), isNotifying: \(characteristic.isNotifying)")
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension UniversalBluetoothPlugin: CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        NSLog("iOS: Peripheral manager state changed to: \(peripheral.state.rawValue)")
        
        switch peripheral.state {
        case .poweredOn:
            NSLog("iOS: Peripheral manager powered on - ready for advertising")
        case .poweredOff:
            NSLog("iOS: Peripheral manager powered off")
            isDiscoverable = false
            isAdvertising = false
        case .unsupported:
            NSLog("iOS: Peripheral manager not supported")
        case .unauthorized:
            NSLog("iOS: Peripheral manager unauthorized")
        case .resetting:
            NSLog("iOS: Peripheral manager resetting")
        case .unknown:
            NSLog("iOS: Peripheral manager state unknown")
        @unknown default:
            NSLog("iOS: Peripheral manager unknown state")
        }
    }
    
    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            NSLog("iOS: ❌ Failed to start advertising: \(error.localizedDescription)")
            isDiscoverable = false
            isAdvertising = false
        } else {
            NSLog("iOS: ✅ Successfully started advertising")
            isDiscoverable = true
            isAdvertising = true
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            NSLog("iOS: ❌ Failed to add service: \(error.localizedDescription)")
        } else {
            NSLog("iOS: ✅ Successfully added service: \(service.uuid)")
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        NSLog("iOS: ✅ Central \(central.identifier) subscribed to characteristic \(characteristic.uuid)")
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        NSLog("iOS: 🔌 Central \(central.identifier) unsubscribed from characteristic \(characteristic.uuid)")
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        NSLog("iOS: 📖 Received read request for characteristic: \(request.characteristic.uuid)")
        
        // Handle read request - you can customize the response data here
        if request.characteristic.uuid == dataCharacteristicUUID {
            let responseData = "Hello from iOS".data(using: .utf8) ?? Data()
            if request.offset > responseData.count {
                peripheral.respond(to: request, withResult: .invalidOffset)
                return
            }
            
            request.value = responseData.subdata(in: request.offset..<responseData.count)
            peripheral.respond(to: request, withResult: .success)
        } else {
            peripheral.respond(to: request, withResult: .requestNotSupported)
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        NSLog("iOS: ✏️ Received \(requests.count) write request(s)")
        
        for request in requests {
            NSLog("iOS: Write request for characteristic: \(request.characteristic.uuid)")
            
            if request.characteristic.uuid == dataCharacteristicUUID {
                if let data = request.value {
                    let message = String(data: data, encoding: .utf8) ?? "Binary Data"
                    NSLog("iOS: 📩 Received data in peripheral mode: '\(message)' (\(data.count) bytes)")
                    
                    // Simulate receiving data as a connected device
                    let centralId = request.central.identifier.uuidString
                    notifyDataReceived(deviceId: centralId, data: data)
                    
                    peripheral.respond(to: request, withResult: .success)
                } else {
                    peripheral.respond(to: request, withResult: .invalidPdu)
                }
            } else {
                peripheral.respond(to: request, withResult: .requestNotSupported)
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension UniversalBluetoothPlugin: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        NSLog("iOS: Location authorization status changed to: \(status.rawValue)")
        
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            pendingResult?(true)
        case .denied, .restricted:
            pendingResult?(false)
        case .notDetermined:
            // Wait for user decision
            break
        @unknown default:
            pendingResult?(false)
        }
        
        if status != .notDetermined {
            pendingResult = nil
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        NSLog("iOS: Ranged \(beacons.count) beacons in region: \(region.identifier)")
        
        for beacon in beacons {
            let proximity: String
            switch beacon.proximity {
            case .immediate:
                proximity = "immediate"
            case .near:
                proximity = "near"
            case .far:
                proximity = "far"
            case .unknown:
                proximity = "unknown"
            @unknown default:
                proximity = "unknown"
            }
            
            let beaconData: [String: Any] = [
                "uuid": beacon.proximityUUID.uuidString,
                "major": beacon.major.intValue,
                "minor": beacon.minor.intValue,
                "rssi": beacon.rssi,
                "distance": beacon.accuracy,
                "proximity": proximity,
                "timestamp": Int(Date().timeIntervalSince1970 * 1000)
            ]
            
            DispatchQueue.main.async {
                self.channel?.invokeMethod("onBeaconScanResult", arguments: beaconData)
            }
        }
    }
    
    @available(iOS 13.0, *)
    public func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        NSLog("iOS: Ranged \(beacons.count) beacons satisfying constraint")
        
        for beacon in beacons {
            let proximity: String
            switch beacon.proximity {
            case .immediate:
                proximity = "immediate"
            case .near:
                proximity = "near"
            case .far:
                proximity = "far"
            case .unknown:
                proximity = "unknown"
            @unknown default:
                proximity = "unknown"
            }
            
            let beaconData: [String: Any] = [
                "uuid": beacon.proximityUUID.uuidString,
                "major": beacon.major.intValue,
                "minor": beacon.minor.intValue,
                "rssi": beacon.rssi,
                "distance": beacon.accuracy,
                "proximity": proximity,
                "timestamp": Int(Date().timeIntervalSince1970 * 1000)
            ]
            
            DispatchQueue.main.async {
                self.channel?.invokeMethod("onBeaconScanResult", arguments: beaconData)
            }
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        NSLog("iOS: 📍 Entered beacon region: \(region.identifier)")
        
        if let beaconRegion = region as? CLBeaconRegion {
            NSLog("iOS: Entered beacon region for UUID: \(beaconRegion.proximityUUID.uuidString)")
            
            DispatchQueue.main.async {
                self.channel?.invokeMethod("onBeaconRegionEntered", arguments: [
                    "uuid": beaconRegion.proximityUUID.uuidString,
                    "identifier": region.identifier,
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000)
                ])
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        NSLog("iOS: 🚪 Exited beacon region: \(region.identifier)")
        
        if let beaconRegion = region as? CLBeaconRegion {
            NSLog("iOS: Exited beacon region for UUID: \(beaconRegion.proximityUUID.uuidString)")
            
            DispatchQueue.main.async {
                self.channel?.invokeMethod("onBeaconRegionExited", arguments: [
                    "uuid": beaconRegion.proximityUUID.uuidString,
                    "identifier": region.identifier,
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000)
                ])
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        let stateString: String
        switch state {
        case .inside:
            stateString = "inside"
        case .outside:
            stateString = "outside"
        case .unknown:
            stateString = "unknown"
        @unknown default:
            stateString = "unknown"
        }
        
        NSLog("iOS: 📍 Region state determined: \(region.identifier) - \(stateString)")
        
        if let beaconRegion = region as? CLBeaconRegion {
            DispatchQueue.main.async {
                self.channel?.invokeMethod("onBeaconRegionState", arguments: [
                    "uuid": beaconRegion.proximityUUID.uuidString,
                    "identifier": region.identifier,
                    "state": stateString,
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000)
                ])
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, rangingBeaconsDidFailFor region: CLBeaconRegion, withError error: Error) {
        NSLog("iOS: ❌ Ranging beacons failed for region \(region.identifier): \(error.localizedDescription)")
        
        DispatchQueue.main.async {
            self.channel?.invokeMethod("onBeaconRangingError", arguments: [
                "uuid": region.proximityUUID.uuidString,
                "identifier": region.identifier,
                "error": error.localizedDescription,
                "timestamp": Int(Date().timeIntervalSince1970 * 1000)
            ])
        }
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        NSLog("iOS: ❌ Monitoring failed for region \(region?.identifier ?? "unknown"): \(error.localizedDescription)")
        
        if let beaconRegion = region as? CLBeaconRegion {
            DispatchQueue.main.async {
                self.channel?.invokeMethod("onBeaconMonitoringError", arguments: [
                    "uuid": beaconRegion.proximityUUID.uuidString,
                    "identifier": region?.identifier ?? "unknown",
                    "error": error.localizedDescription,
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000)
                ])
            }
        }
    }
}