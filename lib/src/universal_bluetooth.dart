library universal_bluetooth;

import 'package:flutter/services.dart';
import 'models/bluetooth_models.dart';
import 'universal_bluetooth_method_channel.dart';
import 'universal_bluetooth_platform_interface.dart';

class UniversalBluetoothExtensions {
  static const MethodChannel _channel = MethodChannel('universal_bluetooth');

  static Future<List<String>> getConnectedDevices() async {
    try {
      final result = await _channel.invokeMethod('getConnectedDevices');
      return List<String>.from(result ?? []);
    } catch (e) {
      print('Error getting connected devices: $e');
      return [];
    }
  }

  static Future<String> testDataSend(String deviceId) async {
    try {
      final result = await _channel.invokeMethod('testDataSend', {
        'deviceId': deviceId,
      });
      return result ?? 'No response';
    } catch (e) {
      print('Error in test data send: $e');
      throw e;
    }
  }

  // 🔧 수정: 글로벌 메서드 핸들러로 설정
  static void setMethodCallHandler(Future<void> Function(MethodCall) handler) {
    MethodChannelUniversalBluetooth.setGlobalMethodCallHandler(handler);
  }
}

class UniversalBluetooth {
  static UniversalBluetoothPlatform get _platform =>
      UniversalBluetoothPlatform.instance;

  /// Classic Bluetooth Methods

  /// Check if Classic Bluetooth is available
  static Future<bool> get isBluetoothAvailable =>
      _platform.isBluetoothAvailable;

  /// Check if Classic Bluetooth is enabled
  static Future<bool> get isBluetoothEnabled => _platform.isBluetoothEnabled;

  /// Get Bluetooth MAC address
  static Future<String> getBluetoothAddress() =>
      _platform.getBluetoothAddress();

  /// Request to enable Bluetooth
  static Future<bool> requestBluetoothEnable() =>
      _platform.requestBluetoothEnable();

  /// Start scanning for Classic Bluetooth devices
  static Future<void> startBluetoothScan() => _platform.startBluetoothScan();

  /// Stop scanning for Classic Bluetooth devices
  static Future<void> stopBluetoothScan() => _platform.stopBluetoothScan();

  /// Make device discoverable for Classic Bluetooth
  static Future<bool> startBluetoothDiscoverable({int duration = 120}) =>
      _platform.startBluetoothDiscoverable(duration: duration);

  /// Stop Classic Bluetooth discoverability
  static Future<void> stopBluetoothDiscoverable() =>
      _platform.stopBluetoothDiscoverable();

  /// Get stream of discovered Classic Bluetooth devices
  static Stream<BluetoothScanResult> get bluetoothScanResults =>
      _platform.bluetoothScanResults;

  /// Get stream for Classic Bluetooth scan completion
  static Stream<void> get bluetoothScanFinished =>
      (_platform as MethodChannelUniversalBluetooth).bluetoothScanFinished;

  /// Connect to a Classic Bluetooth device
  static Future<void> connectToBluetoothDevice(String deviceId) =>
      _platform.connectToBluetoothDevice(deviceId);

  /// Disconnect from Classic Bluetooth device
  static Future<void> disconnectBluetoothDevice(String deviceId) =>
      _platform.disconnectBluetoothDevice(deviceId);

  /// Send data to connected Classic Bluetooth device
  static Future<void> sendBluetoothData(String deviceId, List<int> data) =>
      _platform.sendBluetoothData(deviceId, data);

  /// Listen for incoming data from Classic Bluetooth device
  static Stream<List<int>> bluetoothDataReceived(String deviceId) =>
      _platform.bluetoothDataReceived(deviceId);

  /// Get Classic Bluetooth connection state stream
  static Stream<BluetoothConnectionState> bluetoothConnectionStateChanged(
    String deviceId,
  ) => _platform.bluetoothConnectionStateChanged(deviceId);

  /// BLE (Bluetooth Low Energy) Methods

  /// Check if BLE is available
  static Future<bool> get isBleAvailable => _platform.isBleAvailable;

  /// Start scanning for BLE devices
  static Future<void> startBleScan({
    List<String>? serviceUuids,
    Duration? timeout,
  }) => _platform.startBleScan(serviceUuids: serviceUuids, timeout: timeout);

  /// Stop BLE scan
  static Future<void> stopBleScan() => _platform.stopBleScan();

  /// Get stream of discovered BLE devices
  static Stream<BleDevice> get bleScanResults => _platform.bleScanResults;

  /// Connect to BLE device
  static Future<void> connectToBleDevice(String deviceId) =>
      _platform.connectToBleDevice(deviceId);

  /// Disconnect from BLE device
  static Future<void> disconnectBleDevice(String deviceId) =>
      _platform.disconnectBleDevice(deviceId);

  /// Discover services for connected BLE device
  static Future<List<String>> discoverBleServices(String deviceId) =>
      _platform.discoverBleServices(deviceId);

  /// Get characteristics for a service
  static Future<List<String>> getBleCharacteristics(
    String deviceId,
    String serviceUuid,
  ) => _platform.getBleCharacteristics(deviceId, serviceUuid);

  /// Read characteristic value
  static Future<List<int>> readBleCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) => _platform.readBleCharacteristic(
    deviceId,
    serviceUuid,
    characteristicUuid,
  );

  /// Write to characteristic
  static Future<void> writeBleCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
    List<int> data, {
    bool withoutResponse = false,
  }) => _platform.writeBleCharacteristic(
    deviceId,
    serviceUuid,
    characteristicUuid,
    data,
    withoutResponse: withoutResponse,
  );

  /// Subscribe to characteristic notifications
  static Future<void> subscribeBleCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) => _platform.subscribeBleCharacteristic(
    deviceId,
    serviceUuid,
    characteristicUuid,
  );

  /// Unsubscribe from characteristic notifications
  static Future<void> unsubscribeBleCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) => _platform.unsubscribeBleCharacteristic(
    deviceId,
    serviceUuid,
    characteristicUuid,
  );

  /// Listen for BLE characteristic value changes
  static Stream<List<int>> bleCharacteristicValueChanged(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) => _platform.bleCharacteristicValueChanged(
    deviceId,
    serviceUuid,
    characteristicUuid,
  );

  /// Get BLE connection state stream
  static Stream<BluetoothConnectionState> bleConnectionStateChanged(
    String deviceId,
  ) => _platform.bleConnectionStateChanged(deviceId);

  /// iBeacon Methods

  /// Check if iBeacon is supported
  static Future<bool> get isBeaconSupported => _platform.isBeaconSupported;

  /// Start advertising as iBeacon
  static Future<void> startBeaconAdvertising({
    required String uuid,
    required int major,
    required int minor,
    String? identifier,
  }) => _platform.startBeaconAdvertising(
    uuid: uuid,
    major: major,
    minor: minor,
    identifier: identifier,
  );

  /// Stop beacon advertising
  static Future<void> stopBeaconAdvertising() =>
      _platform.stopBeaconAdvertising();

  /// Start scanning for iBeacons
  static Future<void> startBeaconScanning({List<String>? uuids}) =>
      _platform.startBeaconScanning(uuids: uuids);

  /// Stop beacon scanning
  static Future<void> stopBeaconScanning() => _platform.stopBeaconScanning();

  /// Get stream of discovered beacons
  static Stream<BeaconDevice> get beaconScanResults =>
      _platform.beaconScanResults;

  /// Request location permissions (required for beacon scanning)
  static Future<bool> requestLocationPermission() =>
      _platform.requestLocationPermission();
}
