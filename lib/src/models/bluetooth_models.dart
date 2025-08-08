// Classic Bluetooth device
class BluetoothDevice {
  final String id;
  final String name;
  final String address;
  final bool isConnected;
  final int? rssi;
  final List<String> serviceUuids;

  BluetoothDevice({
    required this.id,
    required this.name,
    required this.address,
    required this.isConnected,
    this.rssi,
    this.serviceUuids = const [],
  });

  factory BluetoothDevice.fromMap(Map<String, dynamic> map) {
    return BluetoothDevice(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Unknown Device',
      address: map['address'] as String? ?? '',
      isConnected: map['isConnected'] as bool? ?? false,
      rssi: map['rssi'] as int?,
      serviceUuids: (map['serviceUuids'] as List?)?.cast<String>() ?? [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'isConnected': isConnected,
      'rssi': rssi,
      'serviceUuids': serviceUuids,
    };
  }

  @override
  String toString() {
    return 'BluetoothDevice(id: $id, name: $name, address: $address, rssi: $rssi)';
  }
}

// Classic Bluetooth scan result
class BluetoothScanResult {
  final BluetoothDevice device;
  final DateTime timestamp;
  final bool isFirstScan;

  BluetoothScanResult({
    required this.device,
    required this.timestamp,
    required this.isFirstScan,
  });

  factory BluetoothScanResult.fromMap(Map<String, dynamic> map) {
    // device 필드가 Map<Object?, Object?> 타입일 수 있으므로 안전하게 변환
    final deviceMap = map['device'];
    Map<String, dynamic> safeDeviceMap;

    if (deviceMap is Map<String, dynamic>) {
      safeDeviceMap = deviceMap;
    } else if (deviceMap is Map<Object?, Object?>) {
      safeDeviceMap = Map<String, dynamic>.from(deviceMap);
    } else {
      throw ArgumentError('Invalid device map type: ${deviceMap.runtimeType}');
    }

    return BluetoothScanResult(
      device: BluetoothDevice.fromMap(safeDeviceMap),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestamp'] as int? ?? 0,
      ),
      isFirstScan: map['isFirstScan'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'device': device.toMap(),
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isFirstScan': isFirstScan,
    };
  }

  @override
  String toString() {
    return 'BluetoothScanResult(device: $device, timestamp: $timestamp)';
  }
}

// BLE device
class BleDevice {
  final String id;
  final String name;
  final String address;
  final int rssi;
  final List<String> serviceUuids;
  final bool isConnectable;

  BleDevice({
    required this.id,
    required this.name,
    required this.address,
    required this.rssi,
    this.serviceUuids = const [],
    this.isConnectable = true,
  });

  factory BleDevice.fromMap(Map<String, dynamic> map) {
    return BleDevice(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Unknown Device',
      address: map['address'] as String? ?? '',
      rssi: map['rssi'] as int? ?? -999,
      serviceUuids: (map['serviceUuids'] as List?)?.cast<String>() ?? [],
      isConnectable: map['isConnectable'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'rssi': rssi,
      'serviceUuids': serviceUuids,
      'isConnectable': isConnectable,
    };
  }

  @override
  String toString() {
    return 'BleDevice(id: $id, name: $name, address: $address, rssi: $rssi)';
  }
}

// iBeacon device
class BeaconDevice {
  final String uuid;
  final int major;
  final int minor;
  final int rssi;
  final double? distance;
  final BeaconProximity proximity;

  BeaconDevice({
    required this.uuid,
    required this.major,
    required this.minor,
    required this.rssi,
    this.distance,
    required this.proximity,
  });

  factory BeaconDevice.fromMap(Map<String, dynamic> map) {
    return BeaconDevice(
      uuid: map['uuid'] as String? ?? '',
      major: map['major'] as int? ?? 0,
      minor: map['minor'] as int? ?? 0,
      rssi: map['rssi'] as int? ?? -999,
      distance: map['distance'] as double?,
      proximity: BeaconProximity.values.firstWhere(
        (e) => e.name == map['proximity'],
        orElse: () => BeaconProximity.unknown,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'major': major,
      'minor': minor,
      'rssi': rssi,
      'distance': distance,
      'proximity': proximity.name,
    };
  }

  @override
  String toString() {
    return 'BeaconDevice(uuid: $uuid, major: $major, minor: $minor, rssi: $rssi)';
  }
}

// Enums - 통일된 연결 상태 enum 사용
enum BluetoothConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

enum BeaconProximity { immediate, near, far, unknown }
