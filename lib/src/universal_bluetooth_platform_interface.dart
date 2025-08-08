import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'models/bluetooth_models.dart';
import 'universal_bluetooth_method_channel.dart';

abstract class UniversalBluetoothPlatform extends PlatformInterface {
  UniversalBluetoothPlatform() : super(token: _token);

  static final Object _token = Object();

  static UniversalBluetoothPlatform _instance =
      MethodChannelUniversalBluetooth();

  static UniversalBluetoothPlatform get instance => _instance;

  static set instance(UniversalBluetoothPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // Classic Bluetooth
  Future<bool> get isBluetoothAvailable;
  Future<bool> get isBluetoothEnabled;
  Future<String> getBluetoothAddress();
  Future<bool> requestBluetoothEnable();
  Future<void> startBluetoothScan();
  Future<void> stopBluetoothScan();
  Future<bool> startBluetoothDiscoverable({int duration = 120});
  Future<void> stopBluetoothDiscoverable();
  Stream<BluetoothScanResult> get bluetoothScanResults;
  Future<void> connectToBluetoothDevice(String deviceId);
  Future<void> disconnectBluetoothDevice(String deviceId);
  Future<void> sendBluetoothData(String deviceId, List<int> data);
  Stream<List<int>> bluetoothDataReceived(String deviceId);
  Stream<BluetoothConnectionState> bluetoothConnectionStateChanged(
    String deviceId,
  );

  // BLE
  Future<bool> get isBleAvailable;
  Future<void> startBleScan({List<String>? serviceUuids, Duration? timeout});
  Future<void> stopBleScan();
  Stream<BleDevice> get bleScanResults;
  Future<void> connectToBleDevice(String deviceId);
  Future<void> disconnectBleDevice(String deviceId);
  Future<List<String>> discoverBleServices(String deviceId);
  Future<List<String>> getBleCharacteristics(
    String deviceId,
    String serviceUuid,
  );
  Future<List<int>> readBleCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  );
  Future<void> writeBleCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
    List<int> data, {
    bool withoutResponse = false,
  });
  Future<void> subscribeBleCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  );
  Future<void> unsubscribeBleCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  );
  Stream<List<int>> bleCharacteristicValueChanged(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  );
  // 수정된 부분: BleConnectionState -> BluetoothConnectionState로 변경
  Stream<BluetoothConnectionState> bleConnectionStateChanged(String deviceId);

  // iBeacon
  Future<bool> get isBeaconSupported;
  Future<void> startBeaconAdvertising({
    required String uuid,
    required int major,
    required int minor,
    String? identifier,
  });
  Future<void> stopBeaconAdvertising();
  Future<void> startBeaconScanning({List<String>? uuids});
  Future<void> stopBeaconScanning();
  Stream<BeaconDevice> get beaconScanResults;
  Future<bool> requestLocationPermission();
}
