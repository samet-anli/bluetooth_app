import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'models/bluetooth_models.dart';
import 'universal_bluetooth_platform_interface.dart';

class MethodChannelUniversalBluetooth extends UniversalBluetoothPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('universal_bluetooth');

  // Event channels
  final _bluetoothScanResultsController =
      StreamController<BluetoothScanResult>.broadcast();
  final _bluetoothScanFinishedController = StreamController<void>.broadcast();
  final _bleScanResultsController = StreamController<BleDevice>.broadcast();
  final _beaconScanResultsController =
      StreamController<BeaconDevice>.broadcast();
  final _bluetoothDataControllers = <String, StreamController<List<int>>>{};
  final _bleCharacteristicControllers = <String, StreamController<List<int>>>{};
  final _bluetoothConnectionControllers =
      <String, StreamController<BluetoothConnectionState>>{};
  final _bleConnectionControllers =
      <String, StreamController<BluetoothConnectionState>>{};

  MethodChannelUniversalBluetooth() {
    methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    print('Flutter: Received method call: ${call.method}');

    try {
      switch (call.method) {
        case 'onBluetoothScanResult':
          print('Flutter: Processing scan result: ${call.arguments}');
          final arguments = call.arguments as Map<Object?, Object?>;
          final Map<String, dynamic> safeArguments = Map<String, dynamic>.from(
            arguments,
          );

          final result = BluetoothScanResult.fromMap(safeArguments);
          print('Flutter: Created BluetoothScanResult: $result');
          _bluetoothScanResultsController.add(result);
          print('Flutter: Added to stream');
          break;

        case 'onBluetoothScanFinished':
          print('Flutter: Processing scan finished');
          _bluetoothScanFinishedController.add(null);
          break;

        case 'onBleScanResult':
          final arguments = call.arguments as Map<Object?, Object?>;
          final Map<String, dynamic> safeArguments = Map<String, dynamic>.from(
            arguments,
          );
          final result = BleDevice.fromMap(safeArguments);
          _bleScanResultsController.add(result);
          break;

        case 'onBeaconScanResult':
          final arguments = call.arguments as Map<Object?, Object?>;
          print('🔥 onBeaconScanResult tetiklendi');
          print('🔥 Arguments: ${call.arguments}');
          final Map<String, dynamic> safeArguments = Map<String, dynamic>.from(
            arguments,
          );
          final result = BeaconDevice.fromMap(safeArguments);
          _beaconScanResultsController.add(result);
          break;

        case 'onBluetoothDataReceived':
          final arguments = call.arguments as Map<Object?, Object?>;
          final deviceId = arguments['deviceId'] as String;
          final data = List<int>.from(arguments['data'] as List);
          _bluetoothDataControllers[deviceId]?.add(data);

          // 🔧 추가: 글로벌 핸들러로도 전달
          if (_globalMethodCallHandler != null) {
            _globalMethodCallHandler!(call);
          }
          break;

        case 'onBleCharacteristicChanged':
          final arguments = call.arguments as Map<Object?, Object?>;
          final deviceId = arguments['deviceId'] as String;
          final serviceUuid = arguments['serviceUuid'] as String;
          final characteristicUuid = arguments['characteristicUuid'] as String;
          final data = List<int>.from(arguments['data'] as List);
          final key = '$deviceId:$serviceUuid:$characteristicUuid';
          _bleCharacteristicControllers[key]?.add(data);
          break;

        case 'onBluetoothConnectionStateChanged':
          final arguments = call.arguments as Map<Object?, Object?>;
          final deviceId = arguments['deviceId'] as String;
          final state =
              BluetoothConnectionState.values[arguments['state'] as int];
          _bluetoothConnectionControllers[deviceId]?.add(state);

          // 🔧 추가: 글로벌 핸들러로도 전달
          if (_globalMethodCallHandler != null) {
            _globalMethodCallHandler!(call);
          }
          break;

        case 'onBleConnectionStateChanged':
          final arguments = call.arguments as Map<Object?, Object?>;
          final deviceId = arguments['deviceId'] as String;
          final state =
              BluetoothConnectionState.values[arguments['state'] as int];
          _bleConnectionControllers[deviceId]?.add(state);
          break;

        default:
          print('Flutter: Unknown method call: ${call.method}');
          // 🔧 추가: 알 수 없는 메서드도 글로벌 핸들러로 전달
          if (_globalMethodCallHandler != null) {
            _globalMethodCallHandler!(call);
          }
          break;
      }
    } catch (e, stackTrace) {
      print('Flutter: Error processing method call ${call.method}: $e');
      print('Flutter: Stack trace: $stackTrace');
      print('Flutter: Arguments: ${call.arguments}');
    }
  }

  // 🔧 추가: 글로벌 메서드 호출 핸들러
  static Future<void> Function(MethodCall)? _globalMethodCallHandler;

  static void setGlobalMethodCallHandler(
    Future<void> Function(MethodCall) handler,
  ) {
    _globalMethodCallHandler = handler;
  }

  // Classic Bluetooth
  @override
  Future<bool> get isBluetoothAvailable async {
    final result = await methodChannel.invokeMethod<bool>(
      'isBluetoothAvailable',
    );
    return result ?? false;
  }

  @override
  Future<bool> get isBluetoothEnabled async {
    final result = await methodChannel.invokeMethod<bool>('isBluetoothEnabled');
    return result ?? false;
  }

  @override
  Future<String> getBluetoothAddress() async {
    final result = await methodChannel.invokeMethod<String>(
      'getBluetoothAddress',
    );
    return result ?? 'Unknown';
  }

  @override
  Future<bool> requestBluetoothEnable() async {
    final result = await methodChannel.invokeMethod<bool>(
      'requestBluetoothEnable',
    );
    return result ?? false;
  }

  @override
  Future<void> startBluetoothScan() async {
    await methodChannel.invokeMethod('startBluetoothScan');
  }

  @override
  Future<void> stopBluetoothScan() async {
    await methodChannel.invokeMethod('stopBluetoothScan');
  }

  @override
  Future<bool> startBluetoothDiscoverable({int duration = 120}) async {
    final result = await methodChannel.invokeMethod<bool>(
      'startBluetoothDiscoverable',
      {'duration': duration},
    );
    return result ?? false;
  }

  @override
  Future<void> stopBluetoothDiscoverable() async {
    await methodChannel.invokeMethod('stopBluetoothDiscoverable');
  }

  @override
  Stream<BluetoothScanResult> get bluetoothScanResults =>
      _bluetoothScanResultsController.stream;

  Stream<void> get bluetoothScanFinished =>
      _bluetoothScanFinishedController.stream;

  @override
  Future<void> connectToBluetoothDevice(String deviceId) async {
    await methodChannel.invokeMethod('connectToBluetoothDevice', {
      'deviceId': deviceId,
    });
  }

  @override
  Future<void> disconnectBluetoothDevice(String deviceId) async {
    await methodChannel.invokeMethod('disconnectBluetoothDevice', {
      'deviceId': deviceId,
    });
  }

  @override
  Future<void> sendBluetoothData(String deviceId, List<int> data) async {
    await methodChannel.invokeMethod('sendBluetoothData', {
      'deviceId': deviceId,
      'data': data,
    });
  }

  @override
  Stream<List<int>> bluetoothDataReceived(String deviceId) {
    if (!_bluetoothDataControllers.containsKey(deviceId)) {
      _bluetoothDataControllers[deviceId] =
          StreamController<List<int>>.broadcast();
    }
    return _bluetoothDataControllers[deviceId]!.stream;
  }

  @override
  Stream<BluetoothConnectionState> bluetoothConnectionStateChanged(
    String deviceId,
  ) {
    if (!_bluetoothConnectionControllers.containsKey(deviceId)) {
      _bluetoothConnectionControllers[deviceId] =
          StreamController<BluetoothConnectionState>.broadcast();
    }
    return _bluetoothConnectionControllers[deviceId]!.stream;
  }

  // BLE methods (이하 동일)
  @override
  Future<bool> get isBleAvailable async {
    final result = await methodChannel.invokeMethod<bool>('isBleAvailable');
    return result ?? false;
  }

  @override
  Future<void> startBleScan({
    List<String>? serviceUuids,
    Duration? timeout,
  }) async {
    await methodChannel.invokeMethod('startBleScan', {
      'serviceUuids': serviceUuids,
      'timeout': timeout?.inMilliseconds,
    });
  }

  @override
  Future<void> stopBleScan() async {
    await methodChannel.invokeMethod('stopBleScan');
  }

  @override
  Stream<BleDevice> get bleScanResults => _bleScanResultsController.stream;

  @override
  Future<void> connectToBleDevice(String deviceId) async {
    await methodChannel.invokeMethod('connectToBleDevice', {
      'deviceId': deviceId,
    });
  }

  @override
  Future<void> disconnectBleDevice(String deviceId) async {
    await methodChannel.invokeMethod('disconnectBleDevice', {
      'deviceId': deviceId,
    });
  }

  @override
  Future<List<String>> discoverBleServices(String deviceId) async {
    final result = await methodChannel.invokeMethod<List>(
      'discoverBleServices',
      {'deviceId': deviceId},
    );
    return result?.cast<String>() ?? [];
  }

  @override
  Future<List<String>> getBleCharacteristics(
    String deviceId,
    String serviceUuid,
  ) async {
    final result = await methodChannel.invokeMethod<List>(
      'getBleCharacteristics',
      {'deviceId': deviceId, 'serviceUuid': serviceUuid},
    );
    return result?.cast<String>() ?? [];
  }

  @override
  Future<List<int>> readBleCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    final result = await methodChannel
        .invokeMethod<List>('readBleCharacteristic', {
          'deviceId': deviceId,
          'serviceUuid': serviceUuid,
          'characteristicUuid': characteristicUuid,
        });
    return result?.cast<int>() ?? [];
  }

  @override
  Future<void> writeBleCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
    List<int> data, {
    bool withoutResponse = false,
  }) async {
    await methodChannel.invokeMethod('writeBleCharacteristic', {
      'deviceId': deviceId,
      'serviceUuid': serviceUuid,
      'characteristicUuid': characteristicUuid,
      'data': data,
      'withoutResponse': withoutResponse,
    });
  }

  @override
  Future<void> subscribeBleCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    await methodChannel.invokeMethod('subscribeBleCharacteristic', {
      'deviceId': deviceId,
      'serviceUuid': serviceUuid,
      'characteristicUuid': characteristicUuid,
    });
  }

  @override
  Future<void> unsubscribeBleCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    await methodChannel.invokeMethod('unsubscribeBleCharacteristic', {
      'deviceId': deviceId,
      'serviceUuid': serviceUuid,
      'characteristicUuid': characteristicUuid,
    });
  }

  @override
  Stream<List<int>> bleCharacteristicValueChanged(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) {
    final key = '$deviceId:$serviceUuid:$characteristicUuid';
    if (!_bleCharacteristicControllers.containsKey(key)) {
      _bleCharacteristicControllers[key] =
          StreamController<List<int>>.broadcast();
    }
    return _bleCharacteristicControllers[key]!.stream;
  }

  @override
  Stream<BluetoothConnectionState> bleConnectionStateChanged(String deviceId) {
    if (!_bleConnectionControllers.containsKey(deviceId)) {
      _bleConnectionControllers[deviceId] =
          StreamController<BluetoothConnectionState>.broadcast();
    }
    return _bleConnectionControllers[deviceId]!.stream;
  }

  // iBeacon methods (이하 동일)
  @override
  Future<bool> get isBeaconSupported async {
    final result = await methodChannel.invokeMethod<bool>('isBeaconSupported');
    return result ?? false;
  }

  @override
  Future<void> startBeaconAdvertising({
    required String uuid,
    required int major,
    required int minor,
    String? identifier,
  }) async {
    await methodChannel.invokeMethod('startBeaconAdvertising', {
      'uuid': uuid,
      'major': major,
      'minor': minor,
      'identifier': identifier,
    });
  }

  @override
  Future<void> stopBeaconAdvertising() async {
    await methodChannel.invokeMethod('stopBeaconAdvertising');
  }

  @override
  Future<void> startBeaconScanning({List<String>? uuids}) async {
    await methodChannel.invokeMethod('startBeaconScanning', {'uuids': uuids});
  }

  @override
  Future<void> stopBeaconScanning() async {
    await methodChannel.invokeMethod('stopBeaconScanning');
  }

  @override
  Stream<BeaconDevice> get beaconScanResults =>
      _beaconScanResultsController.stream;

  @override
  Future<bool> requestLocationPermission() async {
    final result = await methodChannel.invokeMethod<bool>(
      'requestLocationPermission',
    );
    return result ?? false;
  }
}
