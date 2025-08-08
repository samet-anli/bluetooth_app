import 'package:flutter/material.dart';
import 'src/models/bluetooth_models.dart';
import 'src/universal_bluetooth.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Universal Bluetooth Demo',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const BluetoothDemo(),
    );
  }
}

class BluetoothDemo extends StatefulWidget {
  const BluetoothDemo({super.key});

  @override
  State<BluetoothDemo> createState() => _BluetoothDemoState();
}

class _BluetoothDemoState extends State<BluetoothDemo>
    with TickerProviderStateMixin {
  late TabController _tabController;

  // Classic Bluetooth
  bool _isBluetoothEnabled = false;
  bool _isScanning = false;
  bool _isDiscoverable = false;
  String _bluetoothAddress = 'Unknown';
  List<BluetoothScanResult> _bluetoothDevices = [];

  // 연결 상태 관리를 위한 추가 변수들
  Map<String, BluetoothConnectionState> _connectionStates = {};
  String? _connectedDeviceId;

  // BLE
  bool _isBleScanning = false;
  List<BleDevice> _bleDevices = [];

  // iBeacon
  bool _isBeaconScanning = false;
  bool _isBeaconAdvertising = false;
  List<BeaconDevice> _beacons = [];

  bool _hasBluetoothPermissions = false;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeBluetooth();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initializeBluetooth() async {
    // 🔧 앱 시작 시 바로 권한 요청
    print('앱 시작 - 블루투스 권한 확인 중...');
    final hasPermissions = await _requestBluetoothPermissions();

    setState(() {
      _hasBluetoothPermissions = hasPermissions;
    });

    if (!hasPermissions) {
      print('블루투스 권한이 거부되었습니다.');
      _showSnackBar('⚠️ 블루투스 권한이 필요합니다. 설정에서 권한을 허용해주세요.');
      // 권한이 없어도 기본 초기화는 진행
    }

    // Check Bluetooth status
    final isEnabled = await UniversalBluetooth.isBluetoothEnabled;
    String bluetoothAddress = 'Unknown';

    try {
      bluetoothAddress = await UniversalBluetooth.getBluetoothAddress();
      print('My Bluetooth Address: $bluetoothAddress');
    } catch (e) {
      print('블루투스 주소 가져오기 실패: $e');
      if (hasPermissions) {
        bluetoothAddress = 'Permission Required';
      } else {
        bluetoothAddress = 'Permission Denied';
      }
    }

    setState(() {
      _isBluetoothEnabled = isEnabled;
      _bluetoothAddress = bluetoothAddress;
    });

    // 권한이 있고 블루투스가 활성화되어 있다면 성공 메시지
    if (hasPermissions && isEnabled) {
      _showSnackBar('✅ 블루투스가 준비되었습니다!');
    } else if (hasPermissions && !isEnabled) {
      _showSnackBar('📱 블루투스를 활성화해주세요.');
    }

    // 🔧 개선된 글로벌 메서드 호출 핸들러 설정
    UniversalBluetoothExtensions.setMethodCallHandler((call) async {
      print('Flutter: 🔔 Global received method call: ${call.method}');
      print('Flutter: 🔔 Arguments: ${call.arguments}');

      try {
        switch (call.method) {
          case 'onBluetoothDataReceived':
            final arguments = call.arguments as Map<Object?, Object?>;
            final String deviceId = arguments['deviceId'] as String;
            final List<int> data = List<int>.from(arguments['data'] as List);

            print('Flutter: 📩 Processing received data from $deviceId: $data');
            _handleReceivedData(deviceId, data);
            break;

          case 'onBluetoothConnectionStateChanged':
            final arguments = call.arguments as Map<Object?, Object?>;
            final String deviceId = arguments['deviceId'] as String;
            final int state = arguments['state'] as int;

            print(
              'Flutter: 🔗 Processing connection state change for $deviceId: $state',
            );
            _handleConnectionStateChanged(deviceId, state);
            break;

          default:
            print('Flutter: ❓ Unknown method call: ${call.method}');
        }
      } catch (e, stackTrace) {
        print('Flutter: ❌ Error processing method call ${call.method}: $e');
        print('Flutter: ❌ Stack trace: $stackTrace');
      }
    });

    // 🔧 수정: 스캔 결과 리스너를 더 안정적으로 설정
    _setupBluetoothScanListeners();

    // Listen to BLE scan results
    UniversalBluetooth.bleScanResults.listen((device) {
      setState(() {
        final index = _bleDevices.indexWhere((d) => d.id == device.id);
        if (index >= 0) {
          _bleDevices[index] = device;
        } else {
          _bleDevices.add(device);
        }
      });
    });

    // Listen to beacon scan results
    UniversalBluetooth.beaconScanResults.listen((beacon) {
      print("Flutter: 📡 Received beacon: ${beacon.uuid} (${beacon.major}:${beacon.minor})");
      setState(() {
        final index = _beacons.indexWhere(
          (b) =>
              b.uuid == beacon.uuid &&
              b.major == beacon.major &&
              b.minor == beacon.minor,
        );
        if (index >= 0) {
          _beacons[index] = beacon;
        } else {
          _beacons.add(beacon);
        }
      });
    });
  }

  void _setupBluetoothScanListeners() {
    // Listen to scan results with improved error handling
    UniversalBluetooth.bluetoothScanResults.listen(
      (result) {
        print(
          'Flutter: Received scan result - ${result.device.name} (${result.device.address})',
        );
        setState(() {
          final index = _bluetoothDevices.indexWhere(
            (device) => device.device.address == result.device.address,
          );
          if (index >= 0) {
            // 기존 기기 업데이트 (RSSI 등)
            _bluetoothDevices[index] = result;
            print('Flutter: Updated device at index $index');
          } else {
            // 새 기기 추가
            _bluetoothDevices.add(result);
            print(
              'Flutter: Added new device, total: ${_bluetoothDevices.length}',
            );
          }
          // 신호 강도 순으로 정렬 (강한 신호부터)
          _bluetoothDevices.sort(
            (a, b) => (b.device.rssi ?? -999).compareTo(a.device.rssi ?? -999),
          );
        });
      },
      onError: (error) {
        print('Flutter: Error in scan results stream: $error');
        _showSnackBar('스캔 오류: $error');
      },
    );

    // Listen to scan finished events
    UniversalBluetooth.bluetoothScanFinished.listen(
      (_) {
        print('Flutter: Scan finished event received');
        setState(() {
          _isScanning = false;
        });
        _showSnackBar('스캔 완료! ${_bluetoothDevices.length}개 기기 발견');
      },
      onError: (error) {
        print('Flutter: Error in scan finished stream: $error');
      },
    );
  }

  // 🔧 개선된 데이터 수신 처리 메서드
  void _handleReceivedData(String deviceId, List<int> data) {
    try {
      final message = String.fromCharCodes(data);
      print('Flutter: 📩 Received data from $deviceId:');
      print('Flutter: 📩   Raw bytes: $data');
      print('Flutter: 📩   Message: "$message"');
      print('Flutter: 📩   Length: ${data.length} bytes');

      // 수신된 메시지에 따라 다른 응답
      if (message.trim().toLowerCase() == 'hello') {
        print('Flutter: 🔄 Received "hello", will show notification');
        _showSnackBar('📩 받은 메시지: "$message" - 상대방이 인사했습니다!');
      } else if (message.trim().toLowerCase() == 'hi') {
        print('Flutter: 🔄 Received "hi", showing response notification');
        _showSnackBar('📩 받은 응답: "$message" - 상대방이 응답했습니다!');
      } else {
        print('Flutter: 🔄 Received other message');
        _showSnackBar('📩 받은 메시지: "$message"');
      }

      // 🔧 추가: UI 상태 업데이트
      setState(() {
        // 필요시 UI 상태 업데이트
      });
    } catch (e, stackTrace) {
      print('Flutter: ❌ Error handling received data: $e');
      print('Flutter: ❌ Stack trace: $stackTrace');
      _showSnackBar('❌ 데이터 처리 오류: $e');
    }
  }

  // 연결 상태 변경 처리 메서드
  void _handleConnectionStateChanged(String deviceId, int state) {
    print('🔔 Flutter: Connection state changed for $deviceId: $state');

    setState(() {
      switch (state) {
        case 0: // disconnected
          _connectionStates[deviceId] = BluetoothConnectionState.disconnected;
          if (_connectedDeviceId == deviceId) {
            _connectedDeviceId = null;
          }
          break;
        case 1: // connecting
          _connectionStates[deviceId] = BluetoothConnectionState.connecting;
          break;
        case 2: // connected
          _connectionStates[deviceId] = BluetoothConnectionState.connected;
          _connectedDeviceId = deviceId;
          break;
        case 4: // error
          _connectionStates[deviceId] = BluetoothConnectionState.error;
          break;
      }
    });

    // 사용자에게 알림
    final deviceResult = _bluetoothDevices.firstWhere(
      (result) => result.device.id == deviceId,
      orElse: () => BluetoothScanResult(
        device: BluetoothDevice(
          isConnected: true,
          id: deviceId,
          name: 'Unknown Device',
          address: deviceId,
          rssi: 0,
        ),
        timestamp: DateTime.now(),
        isFirstScan: true,
      ),
    );

    final deviceName = deviceResult.device.name.isNotEmpty
        ? deviceResult.device.name
        : 'Unknown Device';

    switch (state) {
      case 2: // connected
        _showSnackBar('🔗 $deviceName 연결됨');
        break;
      case 0: // disconnected
        _showSnackBar('🔌 $deviceName 연결 해제됨');
        break;
      case 4: // error
        _showSnackBar('❌ $deviceName 연결 오류');
        break;
    }
  }

  // 권한 상태 표시 위젯
  Widget _buildPermissionStatus() {
    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: _hasBluetoothPermissions
            ? Colors.green.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _hasBluetoothPermissions ? Colors.green : Colors.orange,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _hasBluetoothPermissions ? Icons.check_circle : Icons.warning,
            color: _hasBluetoothPermissions ? Colors.green : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _hasBluetoothPermissions ? '블루투스 권한이 허용되었습니다' : '블루투스 권한이 필요합니다',
              style: TextStyle(
                color: _hasBluetoothPermissions ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          if (!_hasBluetoothPermissions)
            TextButton(
              onPressed: () async {
                final granted = await _requestBluetoothPermissions();
                setState(() {
                  _hasBluetoothPermissions = granted;
                });
                if (granted) {
                  _showSnackBar('✅ 권한이 승인되었습니다!');
                  // 권한 승인 후 블루투스 주소 다시 가져오기
                  try {
                    final address =
                        await UniversalBluetooth.getBluetoothAddress();
                    setState(() {
                      _bluetoothAddress = address;
                    });
                  } catch (e) {
                    print('블루투스 주소 가져오기 실패: $e');
                  }
                }
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: const Text('허용', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Future<bool> _requestBluetoothPermissions() async {
    print('블루투스 권한 요청 시작...');

    try {
      Map<Permission, PermissionStatus> permissions = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.location,
        Permission.locationWhenInUse,
      ].request();

      print('권한 요청 결과:');
      permissions.forEach((permission, status) {
        print('  ${permission.toString()}: ${status.toString()}');
      });

      // 필수 권한 체크 (좀 더 유연하게)
      bool hasBluetoothBasic =
          permissions[Permission.bluetooth] == PermissionStatus.granted ||
          permissions[Permission.bluetoothConnect] == PermissionStatus.granted;

      bool hasBluetoothScan =
          permissions[Permission.bluetoothScan] == PermissionStatus.granted ||
          permissions[Permission.bluetooth] == PermissionStatus.granted;

      if (!hasBluetoothBasic || !hasBluetoothScan) {
        print('⚠️ 필수 블루투스 권한이 거부되었습니다.');

        // 사용자에게 더 친화적인 메시지와 설정 이동 옵션 제공
        _showPermissionDialog();
        return false;
      }

      print('✅ 블루투스 권한이 승인되었습니다.');
      return true;
    } catch (e) {
      print('권한 요청 중 오류: $e');
      _showSnackBar('권한 요청 중 오류가 발생했습니다: $e');
      return false;
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.bluetooth_disabled, color: Colors.orange),
              SizedBox(width: 8),
              Text('블루투스 권한 필요'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('이 앱을 사용하려면 다음 권한이 필요합니다:'),
              SizedBox(height: 8),
              Text('• 블루투스 연결'),
              Text('• 블루투스 스캔'),
              Text('• 위치 정보 (BLE 스캔용)'),
              SizedBox(height: 12),
              Text(
                '설정에서 권한을 허용해주세요.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('나중에'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings(); // 설정 앱으로 이동
              },
              child: const Text('설정 열기'),
            ),
          ],
        );
      },
    );
  }

  // Classic Bluetooth Methods
  Future<void> _toggleBluetoothScan() async {
    // 권한 확인 및 요청
    final hasPermissions = await _requestBluetoothPermissions();
    if (!hasPermissions) {
      return;
    }

    if (!_isBluetoothEnabled) {
      final enabled = await UniversalBluetooth.requestBluetoothEnable();
      if (!enabled) {
        _showSnackBar('Bluetooth is not enabled');
        return;
      }
      setState(() {
        _isBluetoothEnabled = true;
      });
    }

    try {
      if (_isScanning) {
        await UniversalBluetooth.stopBluetoothScan();
      } else {
        await UniversalBluetooth.startBluetoothScan();
        setState(() {
          _bluetoothDevices.clear();
        });
      }

      setState(() {
        _isScanning = !_isScanning;
      });
    } catch (e) {
      _showSnackBar('Bluetooth scan error: $e');
    }
  }

  Future<void> _toggleBluetoothDiscoverable() async {
    // 권한 확인 및 요청
    final hasPermissions = await _requestBluetoothPermissions();
    if (!hasPermissions) {
      return;
    }

    if (!_isBluetoothEnabled) {
      final enabled = await UniversalBluetooth.requestBluetoothEnable();
      if (!enabled) {
        _showSnackBar('Bluetooth is not enabled');
        return;
      }
      setState(() {
        _isBluetoothEnabled = true;
      });
    }

    try {
      if (_isDiscoverable) {
        await UniversalBluetooth.stopBluetoothDiscoverable();
        _showSnackBar('Stopped advertising');
      } else {
        final success = await UniversalBluetooth.startBluetoothDiscoverable(
          duration: 300,
        );
        if (success) {
          _showSnackBar('Device is now discoverable for 5 minutes');
        } else {
          _showSnackBar('Discoverable request was cancelled');
          return;
        }
      }

      setState(() {
        _isDiscoverable = !_isDiscoverable;
      });
    } catch (e) {
      _showSnackBar('Bluetooth discoverable error: $e');
    }
  }

  // 연결 메서드 수정
  Future<void> _connectBluetoothDevice(String deviceId) async {
    if (_isScanning) {
      await UniversalBluetooth.stopBluetoothScan();
      setState(() {
        _isScanning = false;
      });
    }

    final deviceResult = _bluetoothDevices.firstWhere(
      (result) => result.device.id == deviceId,
      orElse: () => _bluetoothDevices.first,
    );

    final deviceName = deviceResult.device.name.isNotEmpty
        ? deviceResult.device.name
        : 'Unknown Device';

    try {
      _showSnackBar('$deviceName 연결 중...');
      await UniversalBluetooth.connectToBluetoothDevice(deviceId);

      // 🔧 글로벌 리스너가 연결 상태를 처리하므로 여기서는 제거
      print('Flutter: Connection request sent for $deviceId');
    } catch (e) {
      print('Flutter: Connection failed for $deviceId: $e');
      _showSnackBar('❌ $deviceName 연결 실패: $e');
    }
  }

  // 디버깅을 위한 테스트 메서드들 추가
  Future<void> _testConnection() async {
    if (_connectedDeviceId == null) {
      _showSnackBar('❌ 연결된 기기가 없습니다.');
      return;
    }

    try {
      // 연결된 기기 목록 확인
      final connectedDevices =
          await UniversalBluetoothExtensions.getConnectedDevices();
      print('📱 Connected devices: $connectedDevices');
      _showSnackBar('📱 연결된 기기: ${connectedDevices.length}개');

      // 테스트 데이터 전송
      final result = await UniversalBluetoothExtensions.testDataSend(
        _connectedDeviceId!,
      );
      _showSnackBar('🧪 테스트 결과: $result');
    } catch (e) {
      _showSnackBar('❌ 테스트 실패: $e');
    }
  }

  // 데이터 수신 리스너 설정
  void _setupDataListener(String deviceId) {
    UniversalBluetooth.bluetoothDataReceived(deviceId).listen(
      (data) {
        final message = String.fromCharCodes(data);
        print('Flutter: Received data from $deviceId: $message');

        // 수신된 메시지에 따라 다른 응답
        if (message.trim().toLowerCase() == 'hello') {
          _showSnackBar('📩 받은 메시지: "$message" - "hi" 응답 전송됨');
        } else if (message.trim().toLowerCase() == 'hi') {
          _showSnackBar('📩 받은 응답: "$message"');
        } else {
          _showSnackBar('📩 받은 메시지: "$message"');
        }
      },
      onError: (error) {
        print('Flutter: Error in data stream: $error');
        _showSnackBar('데이터 수신 오류: $error');
      },
    );
  }

  // 🔧 개선된 Hello 메시지 전송 메서드
  Future<void> _sendHelloMessage() async {
    if (_connectedDeviceId == null) {
      _showSnackBar('❌ 연결된 기기가 없습니다.');
      return;
    }

    try {
      print('Flutter: 📤 Sending hello message to $_connectedDeviceId');

      final message = 'hello';
      final data = message.codeUnits;

      print('Flutter: 📤 Message: "$message"');
      print('Flutter: 📤 Data: $data');

      await UniversalBluetooth.sendBluetoothData(_connectedDeviceId!, data);

      print('Flutter: ✅ Hello message sent successfully');
      _showSnackBar('📤 "hello" 메시지 전송됨 - 응답을 기다려보세요!');
    } catch (e, stackTrace) {
      print('Flutter: ❌ Failed to send hello message: $e');
      print('Flutter: ❌ Stack trace: $stackTrace');
      _showSnackBar('❌ 메시지 전송 실패: $e');
    }
  }

  // 🔧 테스트용 다양한 메시지 전송 메서드
  Future<void> _sendTestMessage(String message) async {
    if (_connectedDeviceId == null) {
      _showSnackBar('❌ 연결된 기기가 없습니다.');
      return;
    }

    try {
      print('Flutter: 📤 Sending test message: "$message"');

      final data = message.codeUnits;
      await UniversalBluetooth.sendBluetoothData(_connectedDeviceId!, data);

      print('Flutter: ✅ Test message sent successfully');
      _showSnackBar('📤 메시지 전송됨: "$message"');
    } catch (e) {
      print('Flutter: ❌ Failed to send test message: $e');
      _showSnackBar('❌ 메시지 전송 실패: $e');
    }
  }

  // 연결 해제 메서드
  Future<void> _disconnectDevice(String deviceId) async {
    try {
      await UniversalBluetooth.disconnectBluetoothDevice(deviceId);
      setState(() {
        _connectionStates[deviceId] = BluetoothConnectionState.disconnected;
        if (_connectedDeviceId == deviceId) {
          _connectedDeviceId = null;
        }
      });
      _showSnackBar('🔌 연결 해제됨');
    } catch (e) {
      _showSnackBar('❌ 연결 해제 실패: $e');
    }
  }

  // BLE Methods
  Future<void> _toggleBleScan() async {
    // 권한 확인 및 요청
    final hasPermissions = await _requestBluetoothPermissions();
    if (!hasPermissions) {
      return;
    }

    if (!_isBluetoothEnabled) {
      final enabled = await UniversalBluetooth.requestBluetoothEnable();
      if (!enabled) {
        _showSnackBar('Bluetooth is not enabled');
        return;
      }
      setState(() {
        _isBluetoothEnabled = true;
      });
    }

    try {
      if (_isBleScanning) {
        await UniversalBluetooth.stopBleScan();
      } else {
        await UniversalBluetooth.startBleScan(
          timeout: const Duration(seconds: 30),
        );
        setState(() {
          _bleDevices.clear();
        });
      }

      setState(() {
        _isBleScanning = !_isBleScanning;
      });
    } catch (e) {
      _showSnackBar('BLE scan error: $e');
    }
  }

  Future<void> _connectBleDevice(String deviceId) async {
    try {
      await UniversalBluetooth.connectToBleDevice(deviceId);
      _showSnackBar('Connecting to BLE device...');

      // Listen for connection state changes
      UniversalBluetooth.bleConnectionStateChanged(deviceId).listen((state) {
        _showSnackBar('BLE Connection state: ${state.name}');
      });
    } catch (e) {
      _showSnackBar('Failed to connect to BLE device: $e');
    }
  }

  // iBeacon Methods
  Future<void> _toggleBeaconScanning() async {
  print('🌀 _toggleBeaconScanning çağrıldı');
  try {
    if (_isBeaconScanning) {
      print('🛑 Scanning durduruluyor');
      await UniversalBluetooth.stopBeaconScanning();
    } else {
      print('📍 Scanning başlatılıyor - izin kontrolü yapılıyor...');
      final hasPermission =
          await UniversalBluetooth.requestLocationPermission();

      print('📍 İzin durumu: $hasPermission');
      if (!hasPermission) {
        _showSnackBar('Location permission is required for beacon scanning');
        return;
      }

      print('✅ startBeaconScanning() çağrılıyor');
      await UniversalBluetooth.startBeaconScanning(uuids: ["FDA50693-A4E2-4FB1-AFCF-C6EB07647825"]);
      setState(() {
        _beacons.clear();
      });
    }

    setState(() {
      _isBeaconScanning = !_isBeaconScanning;
    });
  } catch (e) {
    _showSnackBar('Beacon scanning error: $e');
  }
}


  Future<void> _toggleBeaconAdvertising() async {
    try {
      if (_isBeaconAdvertising) {
        await UniversalBluetooth.stopBeaconAdvertising();
      } else {
        await UniversalBluetooth.startBeaconAdvertising(
          uuid: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
          major: 1,
          minor: 100,
          identifier: 'UniversalBluetoothDemo',
        );
        _showSnackBar('Started advertising as iBeacon');
      }

      setState(() {
        _isBeaconAdvertising = !_isBeaconAdvertising;
      });
    } catch (e) {
      _showSnackBar('Failed to start beacon advertising: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Universal Bluetooth Demo'),
        actions: [
          // 🔧 디버깅 버튼 추가
          if (_connectedDeviceId != null)
            IconButton(
              icon: const Icon(Icons.bug_report),
              onPressed: _testConnection,
              tooltip: 'Test Connection',
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Classic BT', icon: Icon(Icons.bluetooth)),
            Tab(text: 'BLE', icon: Icon(Icons.bluetooth_connected)),
            Tab(text: 'iBeacon', icon: Icon(Icons.location_on)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildClassicBluetoothTab(),
          _buildBleTab(),
          _buildBeaconTab(),
        ],
      ),
      // Hello 메시지 전송을 위한 플로팅 액션 버튼 추가
      floatingActionButton: _connectedDeviceId != null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FloatingActionButton(
                  onPressed: () => _sendTestMessage('test'),
                  child: const Icon(Icons.science),
                  backgroundColor: Colors.purple,
                  heroTag: "test",
                  tooltip: 'Send Test',
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  onPressed: () => _sendTestMessage('hi'),
                  child: const Icon(Icons.waving_hand),
                  backgroundColor: Colors.orange,
                  heroTag: "hi",
                  tooltip: 'Send Hi',
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  onPressed: _sendHelloMessage,
                  icon: const Icon(Icons.send),
                  label: const Text('Hello'),
                  backgroundColor: Colors.green,
                  heroTag: "hello",
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildClassicBluetoothTab() {
    return Column(
      children: [
        _buildPermissionStatus(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bluetooth Status: ${_isBluetoothEnabled ? "Enabled" : "Disabled"}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'My Address: $_bluetoothAddress',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _bluetoothAddress.contains('Permission')
                                    ? Colors.orange
                                    : null,
                              ),
                        ),
                        if (_connectedDeviceId != null)
                          Text(
                            'Connected: $_connectedDeviceId',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _toggleBluetoothScan,
                      icon: Icon(_isScanning ? Icons.stop : Icons.search),
                      label: Text(_isScanning ? '스캔 중지' : '기기 검색'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isScanning ? Colors.red : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _toggleBluetoothDiscoverable,
                      icon: Icon(
                        _isDiscoverable
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      label: Text(_isDiscoverable ? '광고 중지' : '광고 시작'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isDiscoverable
                            ? Colors.green
                            : Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '발견된 기기: ${_bluetoothDevices.length}개',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: _bluetoothDevices.isEmpty ? Colors.grey : Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        if (_isScanning)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: LinearProgressIndicator(),
          ),
        Expanded(
          child: _bluetoothDevices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bluetooth_searching,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isScanning
                            ? '블루투스 기기를 검색 중...'
                            : '스캔 버튼을 눌러 기기를 검색하세요',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _bluetoothDevices.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final result = _bluetoothDevices[index];
                    final device = result.device;
                    final rssi = device.rssi ?? -999;
                    final isConnected =
                        _connectionStates[device.id] ==
                        BluetoothConnectionState.connected;

                    // 신호 강도에 따른 색상 결정
                    Color signalColor;
                    IconData signalIcon;
                    String signalText;
                    if (rssi > -50) {
                      signalColor = Colors.green;
                      signalIcon = Icons.bluetooth_connected;
                      signalText = '강함';
                    } else if (rssi > -70) {
                      signalColor = Colors.orange;
                      signalIcon = Icons.bluetooth;
                      signalText = '보통';
                    } else if (rssi > -90) {
                      signalColor = Colors.red;
                      signalIcon = Icons.bluetooth_disabled;
                      signalText = '약함';
                    } else {
                      signalColor = Colors.grey;
                      signalIcon = Icons.bluetooth_disabled;
                      signalText = '매우약함';
                    }

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: isConnected
                            ? Colors.green.withOpacity(0.1)
                            : Colors.blue.withOpacity(0.1),
                        child: Icon(
                          isConnected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth,
                          color: isConnected ? Colors.green : Colors.blue,
                        ),
                      ),
                      title: Text(
                        device.name.isNotEmpty ? device.name : 'Unknown Device',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isConnected ? Colors.green : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            device.address,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(signalIcon, size: 16, color: signalColor),
                              const SizedBox(width: 4),
                              Text(
                                'RSSI: ${rssi}dBm ($signalText)',
                                style: TextStyle(
                                  color: signalColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (isConnected) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    '연결됨',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      trailing: isConnected
                          ? ElevatedButton(
                              onPressed: () => _disconnectDevice(device.id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                minimumSize: const Size(70, 36),
                              ),
                              child: const Text(
                                '해제',
                                style: TextStyle(fontSize: 12),
                              ),
                            )
                          : ElevatedButton(
                              onPressed: () =>
                                  _connectBluetoothDevice(device.id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                minimumSize: const Size(70, 36),
                              ),
                              child: const Text(
                                '연결',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                      onTap: isConnected
                          ? null
                          : () => _connectBluetoothDevice(device.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBleTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'BLE Devices Found: ${_bleDevices.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ElevatedButton(
                onPressed: _toggleBleScan,
                child: Text(_isBleScanning ? 'Stop Scan' : 'Start Scan'),
              ),
            ],
          ),
        ),
        if (_isBleScanning)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: LinearProgressIndicator(),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _bleDevices.length,
            itemBuilder: (context, index) {
              final device = _bleDevices[index];
              return ListTile(
                title: Text(
                  device.name.isNotEmpty ? device.name : 'Unknown Device',
                ),
                subtitle: Text('${device.address}\nRSSI: ${device.rssi}'),
                trailing: ElevatedButton(
                  onPressed: () => _connectBleDevice(device.id),
                  child: const Text('Connect'),
                ),
                leading: const Icon(Icons.bluetooth_connected),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBeaconTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        print('🚀 Start/Stop Beacon Scanning butonuna basıldı');
                        _toggleBeaconScanning();},
                      child: Text(
                        _isBeaconScanning ? 'Stop Scanning' : 'Start Scanning',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _toggleBeaconAdvertising,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isBeaconAdvertising
                            ? Colors.red
                            : null,
                      ),
                      child: Text(
                        _isBeaconAdvertising
                            ? 'Stop Advertising'
                            : 'Start Advertising',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Beacons Found: ${_beacons.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        if (_isBeaconScanning)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: LinearProgressIndicator(),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _beacons.length,
            itemBuilder: (context, index) {
              final beacon = _beacons[index];
              return ListTile(
                title: Text('UUID: ${beacon.uuid}'),
                subtitle: Text(
                  'Major: ${beacon.major}, Minor: ${beacon.minor}\n'
                  'RSSI: ${beacon.rssi}, Distance: ${beacon.distance?.toStringAsFixed(2)}m\n'
                  'Proximity: ${beacon.proximity.name}',
                ),
                leading: Icon(
                  Icons.location_on,
                  color: _getProximityColor(beacon.proximity),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getProximityColor(BeaconProximity proximity) {
    switch (proximity) {
      case BeaconProximity.immediate:
        return Colors.green;
      case BeaconProximity.near:
        return Colors.orange;
      case BeaconProximity.far:
        return Colors.red;
      case BeaconProximity.unknown:
        return Colors.grey;
    }
  }
}
