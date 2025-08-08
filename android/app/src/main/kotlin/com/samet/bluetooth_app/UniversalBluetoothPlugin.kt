package com.samet.bluetooth_app

import android.Manifest
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.*
import java.io.IOException
import android.app.Activity

// iBeacon scanning için ek değişkenler
private var isBeaconScanning = false
private val beaconScanResults: MutableMap<String, BeaconDevice> = mutableMapOf()

// Beacon device data class
data class BeaconDevice(
    val uuid: String,
    val major: Int,
    val minor: Int,
    val rssi: Int,
    val distance: Double?,
    val proximity: BeaconProximity,
    val address: String,
    val timestamp: Long = System.currentTimeMillis()
)

enum class BeaconProximity {
    IMMEDIATE,  // 0-0.5m
    NEAR,       // 0.5-3m  
    FAR,        // 3m+
    UNKNOWN     // Cannot determine
}

class UniversalBluetoothHandler(
    private val context: Context,
    private var activity: Activity?,
    private val channel: MethodChannel
) : MethodCallHandler {
    
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private var bluetoothLeAdvertiser: BluetoothLeAdvertiser? = null
    
    private val connectedDevices: MutableMap<String, BluetoothDevice> = mutableMapOf()
    private val connectedGattDevices: MutableMap<String, BluetoothGatt> = mutableMapOf()
    private val scanResults: MutableMap<String, BluetoothDevice> = mutableMapOf()
    private val bleScanResults: MutableMap<String, BluetoothDevice> = mutableMapOf()

    private val bluetoothSockets: MutableMap<String, BluetoothSocket> = mutableMapOf()
    private val bluetoothServerSocket: MutableMap<String, BluetoothServerSocket> = mutableMapOf()
    private val dataReadThreads: MutableMap<String, Thread> = mutableMapOf()
    
    private var isScanning = false
    private var isBleScanning = false
    private var pendingResult: Result? = null

    private var isServerRunning = false
    private var serverThread: Thread? = null

    private var bluetoothReceiver: BluetoothReceiver? = null

    private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    companion object {
        private const val LOCATION_PERMISSION_REQUEST_CODE = 1001
        private const val REQUEST_DISCOVERABLE = 1002
    }

    init {
        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter
        bluetoothLeScanner = bluetoothAdapter?.bluetoothLeScanner
        bluetoothLeAdvertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        
        setupBluetoothReceiver()
    }

    private fun setupBluetoothReceiver() {
        bluetoothReceiver = BluetoothReceiver()
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_STARTED)
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(bluetoothReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(bluetoothReceiver, filter)
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            // Classic Bluetooth
            "isBluetoothAvailable" -> result.success(bluetoothAdapter != null)
            "isBluetoothEnabled" -> result.success(bluetoothAdapter?.isEnabled ?: false)
            "getBluetoothAddress" -> getBluetoothAddress(result)
            "requestBluetoothEnable" -> requestBluetoothEnable(result)
            "startBluetoothScan" -> startBluetoothScan(result)
            "stopBluetoothScan" -> stopBluetoothScan(result)
            "startBluetoothDiscoverable" -> startBluetoothDiscoverable(call, result)
            "stopBluetoothDiscoverable" -> stopBluetoothDiscoverable(result)
            "connectToBluetoothDevice" -> connectToBluetoothDevice(call, result)
            "disconnectBluetoothDevice" -> disconnectBluetoothDevice(call, result)
            "sendBluetoothData" -> sendBluetoothData(call, result)
            "getConnectedDevices" -> getConnectedDevices(result)
            "testDataSend" -> testDataSend(call, result)
            
            // BLE
            "isBleAvailable" -> result.success(context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE))
            "startBleScan" -> startBleScan(call, result)
            "stopBleScan" -> stopBleScan(result)
            "connectToBleDevice" -> connectToBleDevice(call, result)
            "disconnectBleDevice" -> disconnectBleDevice(call, result)
            "discoverBleServices" -> discoverBleServices(call, result)
            "getBleCharacteristics" -> getBleCharacteristics(call, result)
            "readBleCharacteristic" -> readBleCharacteristic(call, result)
            "writeBleCharacteristic" -> writeBleCharacteristic(call, result)
            "subscribeBleCharacteristic" -> subscribeBleCharacteristic(call, result)
            "unsubscribeBleCharacteristic" -> unsubscribeBleCharacteristic(call, result)
            
            // iBeacon
            "isBeaconSupported" -> result.success(bluetoothLeAdvertiser != null)
            "startBeaconAdvertising" -> startBeaconAdvertising(call, result)
            "stopBeaconAdvertising" -> stopBeaconAdvertising(result)
            "startBeaconScanning" -> startBeaconScanning(call, result)
            "stopBeaconScanning" -> stopBeaconScanning(result)
            "requestLocationPermission" -> requestLocationPermission(result)
            
            else -> result.notImplemented()
        }
    }

    // Activity güncellemesi için
    fun updateActivity(newActivity: Activity?) {
        activity = newActivity
    }

    // İzin sonuçlarını işlemek için
    fun handlePermissionResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        when (requestCode) {
            LOCATION_PERMISSION_REQUEST_CODE -> {
                val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
                pendingResult?.success(granted)
                pendingResult = null
                return true
            }
        }
        return false
    }

    // Activity result işlemek için
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        android.util.Log.d("UniversalBT", "handleActivityResult: requestCode=$requestCode, resultCode=$resultCode")
        when (requestCode) {
            REQUEST_DISCOVERABLE -> {
                val success = resultCode > 0
                android.util.Log.d("UniversalBT", "Discoverable result: success=$success, resultCode=$resultCode")
                pendingResult?.success(success)
                pendingResult = null
                return true
            }
        }
        return false
    }

    // Cleanup method
    fun cleanup() {
        stopBluetoothServer()
        
        bluetoothSockets.values.forEach { socket ->
            try {
                socket.close()
            } catch (e: IOException) {
                android.util.Log.e("UniversalBT", "Error closing socket: ${e.message}")
            }
        }
        bluetoothSockets.clear()
        
        dataReadThreads.values.forEach { thread ->
            thread.interrupt()
        }
        dataReadThreads.clear()
        
        bluetoothReceiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (e: Exception) {
                // Already unregistered
            }
        }
    }

    // === Bluetooth Implementation Methods ===

    private fun getConnectedDevices(result: Result) {
        val connectedList = bluetoothSockets.keys.toList()
        android.util.Log.d("UniversalBT", "Connected devices: $connectedList")
        result.success(connectedList)
    }

    private fun testDataSend(call: MethodCall, result: Result) {
        val deviceId: String? = call.argument("deviceId")
        val testMessage = "test_message_from_kotlin"
        
        if (deviceId == null) {
            result.error("INVALID_ARGUMENT", "Device ID is required", null)
            return
        }
        
        android.util.Log.d("UniversalBT", "🧪 Test sending data to $deviceId")
        
        Thread {
            try {
                val socket = bluetoothSockets[deviceId]
                if (socket != null && socket.isConnected) {
                    val outputStream = socket.outputStream
                    outputStream.write(testMessage.toByteArray(Charsets.UTF_8))
                    outputStream.flush()
                    
                    android.util.Log.d("UniversalBT", "✅ Test data sent successfully: $testMessage")
                    
                    Handler(Looper.getMainLooper()).post {
                        result.success("Test data sent: $testMessage")
                    }
                } else {
                    android.util.Log.e("UniversalBT", "❌ Socket not found or not connected for $deviceId")
                    Handler(Looper.getMainLooper()).post {
                        result.error("NOT_CONNECTED", "Socket not connected", null)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("UniversalBT", "❌ Test send failed: ${e.message}")
                Handler(Looper.getMainLooper()).post {
                    result.error("SEND_FAILED", "Test send failed: ${e.message}", null)
                }
            }
        }.start()
    }

    private fun getBluetoothAddress(result: Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                    android.util.Log.w("UniversalBT", "BLUETOOTH_CONNECT permission not granted, cannot get address")
                    result.success("Permission Denied")
                    return
                }
            }
            
            val address = bluetoothAdapter?.address ?: "Unknown"
            android.util.Log.d("UniversalBT", "My Bluetooth address: $address")
            result.success(address)
        } catch (e: SecurityException) {
            android.util.Log.w("UniversalBT", "Security exception getting Bluetooth address: ${e.message}")
            result.success("Permission Required")
        } catch (e: Exception) {
            android.util.Log.e("UniversalBT", "Failed to get Bluetooth address", e)
            result.success("Unknown")
        }
    }

    private fun requestBluetoothEnable(result: Result) {
        if (bluetoothAdapter?.isEnabled == true) {
            result.success(true)
            return
        }
        
        pendingResult = result
        result.success(false)
    }

    private fun startBluetoothScan(result: Result) {
        android.util.Log.d("UniversalBT", "startBluetoothScan called")
        
        if (!checkBluetoothPermissions()) {
            android.util.Log.e("UniversalBT", "Bluetooth scan permissions not granted")
            result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null)
            return
        }
        
        if (bluetoothAdapter?.isEnabled != true) {
            android.util.Log.e("UniversalBT", "Bluetooth is not enabled")
            result.error("BLUETOOTH_DISABLED", "Bluetooth is not enabled", null)
            return
        }
        
        if (isScanning) {
            android.util.Log.d("UniversalBT", "Already scanning, stopping previous scan")
            bluetoothAdapter?.cancelDiscovery()
            Thread.sleep(500)
        }
        
        scanResults.clear()
        
        android.util.Log.d("UniversalBT", "Starting Bluetooth discovery")
        isScanning = true
        
        val discoveryStarted = bluetoothAdapter?.startDiscovery() ?: false
        android.util.Log.d("UniversalBT", "Discovery started: $discoveryStarted")
        
        if (!discoveryStarted) {
            isScanning = false
            result.error("SCAN_FAILED", "Failed to start discovery", null)
            return
        }
        
        Handler(Looper.getMainLooper()).postDelayed({
            if (isScanning) {
                android.util.Log.d("UniversalBT", "Scan timeout reached, stopping discovery")
                bluetoothAdapter?.cancelDiscovery()
            }
        }, 30000)
        
        result.success(null)
    }

    private fun stopBluetoothScan(result: Result) {
        if (isScanning) {
            bluetoothAdapter?.cancelDiscovery()
            isScanning = false
        }
        result.success(null)
    }

    private fun startBluetoothDiscoverable(call: MethodCall, result: Result) {
        android.util.Log.d("UniversalBT", "startBluetoothDiscoverable called")
        
        if (!checkBluetoothPermissions()) {
            android.util.Log.e("UniversalBT", "Bluetooth permissions not granted")
            result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null)
            return
        }
        
        val duration: Int = call.argument("duration") ?: 300
        android.util.Log.d("UniversalBT", "Discoverable duration: $duration")
        
        try {
            android.util.Log.d("UniversalBT", "Starting server socket before discoverable mode")
            startBluetoothServer()
            
            activity?.let { act ->
                android.util.Log.d("UniversalBT", "Creating discoverable intent")
                val discoverableIntent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).apply {
                    putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, duration)
                }
                try {
                    pendingResult = result
                    android.util.Log.d("UniversalBT", "Starting discoverable activity")
                    act.startActivityForResult(discoverableIntent, REQUEST_DISCOVERABLE)
                } catch (e: Exception) {
                    android.util.Log.e("UniversalBT", "Failed to start discoverable intent", e)
                    pendingResult = null
                    result.error("INTENT_FAILED", "Failed to start discoverable intent: ${e.message}", null)
                }
            } ?: run {
                android.util.Log.e("UniversalBT", "Activity context not available")
                result.error("NO_ACTIVITY", "Activity context not available", null)
            }
        } catch (e: Exception) {
            android.util.Log.e("UniversalBT", "Exception in startBluetoothDiscoverable", e)
            result.error("DISCOVERABLE_FAILED", "Failed to make discoverable: ${e.message}", null)
        }
    }

    private fun stopBluetoothDiscoverable(result: Result) {
        result.success(null)
    }

    private fun connectToBluetoothDevice(call: MethodCall, result: Result) {
        val deviceId: String? = call.argument("deviceId")
        if (deviceId == null) {
            result.error("INVALID_ARGUMENT", "Device ID is required", null)
            return
        }
        
        if (!checkBluetoothPermissions()) {
            result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null)
            return
        }
        
        try {
            val device = bluetoothAdapter?.getRemoteDevice(deviceId)
            if (device == null) {
                result.error("DEVICE_NOT_FOUND", "Device not found", null)
                return
            }
            
            android.util.Log.d("UniversalBT", "🔗 Attempting to connect to device: ${device.name} (${device.address})")
            
            notifyConnectionStateChanged(deviceId, 1) // connecting
            
            Thread {
                try {
                    Thread.sleep(1000)
                    
                    android.util.Log.d("UniversalBT", "Creating RFCOMM socket to UUID: $SPP_UUID")
                    val socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                    
                    android.util.Log.d("UniversalBT", "Connecting to socket...")
                    socket.connect()
                    
                    bluetoothSockets[deviceId] = socket
                    android.util.Log.d("UniversalBT", "✅ Successfully connected to ${device.name}")
                    
                    notifyConnectionStateChanged(deviceId, 2) // connected
                    
                    startDataReadThread(deviceId, socket)
                    
                } catch (e: IOException) {
                    android.util.Log.e("UniversalBT", "❌ Connection failed: ${e.message}")
                    notifyConnectionStateChanged(deviceId, 4) // error
                } catch (e: SecurityException) {
                    android.util.Log.e("UniversalBT", "❌ Security exception: ${e.message}")
                    notifyConnectionStateChanged(deviceId, 4) // error
                } catch (e: InterruptedException) {
                    android.util.Log.e("UniversalBT", "❌ Connection interrupted: ${e.message}")
                    notifyConnectionStateChanged(deviceId, 4) // error
                }
            }.start()
            
            result.success(null)
            
        } catch (e: Exception) {
            android.util.Log.e("UniversalBT", "Connection initiation failed", e)
            result.error("CONNECTION_FAILED", "Failed to connect: ${e.message}", null)
        }
    }

    private fun startBluetoothServer() {
        if (isServerRunning) {
            android.util.Log.d("UniversalBT", "Server already running")
            return
        }
        
        serverThread = Thread {
            try {
                if (!checkBluetoothPermissions()) {
                    android.util.Log.e("UniversalBT", "No permissions for server")
                    return@Thread
                }
                
                android.util.Log.d("UniversalBT", "Creating server socket with UUID: $SPP_UUID")
                val serverSocket = bluetoothAdapter?.listenUsingRfcommWithServiceRecord(
                    "UniversalBluetoothService",
                    SPP_UUID
                )
                
                if (serverSocket != null) {
                    isServerRunning = true
                    android.util.Log.d("UniversalBT", "✅ Server socket listening on UUID: $SPP_UUID")
                    
                    android.util.Log.d("UniversalBT", "Service record registered, waiting for connections...")
                    
                    while (isServerRunning) {
                        try {
                            android.util.Log.d("UniversalBT", "⏳ Waiting for incoming connections...")
                            val socket = serverSocket.accept()
                            
                            if (socket != null) {
                                val deviceId = socket.remoteDevice.address
                                val deviceName = try {
                                    socket.remoteDevice.name ?: "Unknown Device"
                                } catch (e: SecurityException) {
                                    "Unknown Device"
                                }
                                
                                android.util.Log.d("UniversalBT", "✅ Incoming connection from: $deviceName ($deviceId)")
                                
                                bluetoothSockets[deviceId] = socket
                                
                                Handler(Looper.getMainLooper()).post {
                                    notifyConnectionStateChanged(deviceId, 2) // connected
                                }
                                
                                startDataReadThread(deviceId, socket)
                            }
                        } catch (e: IOException) {
                            if (isServerRunning) {
                                android.util.Log.e("UniversalBT", "❌ Server accept failed: ${e.message}")
                                Thread.sleep(1000)
                            } else {
                                android.util.Log.d("UniversalBT", "Server socket closed intentionally")
                                break
                            }
                        }
                    }
                    
                    try {
                        serverSocket.close()
                        android.util.Log.d("UniversalBT", "Server socket closed")
                    } catch (e: IOException) {
                        android.util.Log.e("UniversalBT", "Error closing server socket: ${e.message}")
                    }
                } else {
                    android.util.Log.e("UniversalBT", "❌ Failed to create server socket")
                }
            } catch (e: SecurityException) {
                android.util.Log.e("UniversalBT", "❌ Security exception in server: ${e.message}")
            } catch (e: Exception) {
                android.util.Log.e("UniversalBT", "❌ Server socket error", e)
            } finally {
                isServerRunning = false
                android.util.Log.d("UniversalBT", "Server thread finished")
            }
        }
        
        serverThread?.start()
        android.util.Log.d("UniversalBT", "Server thread started")
    }

    private fun stopBluetoothServer() {
        android.util.Log.d("UniversalBT", "Stopping Bluetooth server")
        isServerRunning = false
        serverThread?.interrupt()
        serverThread = null
    }

    private fun startDataReadThread(deviceId: String, socket: BluetoothSocket) {
        android.util.Log.d("UniversalBT", "🔧 Starting data read thread for $deviceId")
        val thread = Thread {
            try {
                val inputStream = socket.inputStream
                val buffer = ByteArray(1024)

                android.util.Log.d("UniversalBT", "📡 Data read thread started for $deviceId")
                android.util.Log.d("UniversalBT", "📡 Socket connected: ${socket.isConnected}")
                android.util.Log.d("UniversalBT", "📡 InputStream available: ${inputStream.available()}")
                
                while (socket.isConnected && !Thread.currentThread().isInterrupted) {
                    try {
                        if (inputStream.available() > 0) {
                            android.util.Log.d("UniversalBT", "📡 Data available: ${inputStream.available()} bytes")
                            
                            val bytesRead = inputStream.read(buffer)
                            if (bytesRead > 0) {
                                val receivedData = buffer.copyOf(bytesRead)
                                val message = String(receivedData, Charsets.UTF_8)
                                
                                android.util.Log.d("UniversalBT", "📩 Received data from $deviceId: '$message' (${bytesRead} bytes)")
                                android.util.Log.d("UniversalBT", "📩 Raw bytes: ${receivedData.joinToString { "%02x".format(it) }}")
                                
                                Handler(Looper.getMainLooper()).post {
                                    val dataList = receivedData.map { it.toInt() and 0xFF }
                                    android.util.Log.d("UniversalBT", "📤 Sending to Flutter: $dataList")
                                    channel.invokeMethod("onBluetoothDataReceived", mapOf(
                                        "deviceId" to deviceId,
                                        "data" to dataList
                                    ))
                                }
                                
                                if (message.trim().equals("hello", ignoreCase = true)) {
                                    android.util.Log.d("UniversalBT", "🔄 Received 'hello', sending 'hi' response")
                                    sendResponse(deviceId, "hi")
                                }
                            }
                        } else {
                            Thread.sleep(50)
                        }
                    } catch (e: IOException) {
                        if (socket.isConnected && !Thread.currentThread().isInterrupted) {
                            android.util.Log.e("UniversalBT", "❌ Data read IOException: ${e.message}")
                            break
                        }
                    } catch (e: InterruptedException) {
                        android.util.Log.d("UniversalBT", "📡 Data read thread interrupted")
                        break
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("UniversalBT", "❌ Data read error: ${e.message}", e)
            } finally {
                android.util.Log.d("UniversalBT", "📡 Data read thread finished for $deviceId")
            }
        }
        
        dataReadThreads[deviceId] = thread
        thread.start()
    }

    private fun sendResponse(deviceId: String, message: String) {
        Thread {
            try {
                val socket = bluetoothSockets[deviceId]
                if (socket != null && socket.isConnected) {
                    val outputStream = socket.outputStream
                    val data = message.toByteArray(Charsets.UTF_8)
                    
                    android.util.Log.d("UniversalBT", "📤 Sending response '$message' to $deviceId (${data.size} bytes)")
                    outputStream.write(data)
                    outputStream.flush()
                    android.util.Log.d("UniversalBT", "✅ Response sent successfully")
                } else {
                    android.util.Log.e("UniversalBT", "❌ No connection to send response to $deviceId")
                }
            } catch (e: IOException) {
                android.util.Log.e("UniversalBT", "❌ Failed to send response: ${e.message}")
            } catch (e: Exception) {
                android.util.Log.e("UniversalBT", "❌ Unexpected error sending response: ${e.message}")
            }
        }.start()
    }

    private fun disconnectBluetoothDevice(call: MethodCall, result: Result) {
        val deviceId: String? = call.argument("deviceId")
        if (deviceId == null) {
            result.error("INVALID_ARGUMENT", "Device ID is required", null)
            return
        }
        
        try {
            dataReadThreads[deviceId]?.interrupt()
            dataReadThreads.remove(deviceId)
            
            bluetoothSockets[deviceId]?.close()
            bluetoothSockets.remove(deviceId)
            
            notifyConnectionStateChanged(deviceId, 0) // disconnected
            
            android.util.Log.d("UniversalBT", "Disconnected from $deviceId")
            result.success(null)
        } catch (e: Exception) {
            android.util.Log.e("UniversalBT", "Disconnect failed: ${e.message}")
            result.error("DISCONNECT_FAILED", "Failed to disconnect: ${e.message}", null)
        }
    }

    private fun notifyConnectionStateChanged(deviceId: String, state: Int) {
        Handler(Looper.getMainLooper()).post {
            channel.invokeMethod("onBluetoothConnectionStateChanged", mapOf(
                "deviceId" to deviceId,
                "state" to state
            ))
        }
    }

    private fun sendBluetoothData(call: MethodCall, result: Result) {
        val deviceId: String? = call.argument("deviceId")
        val data: List<Int>? = call.argument("data")
        
        if (deviceId == null || data == null) {
            result.error("INVALID_ARGUMENT", "Device ID and data are required", null)
            return
        }

        val message = String(data.map { it.toByte() }.toByteArray(), Charsets.UTF_8)
        android.util.Log.d("UniversalBT", "📤 Sending data to $deviceId: '$message' (${data.size} bytes)")
        android.util.Log.d("UniversalBT", "📤 Raw data: $data")
        
        Thread {
            try {
                val socket = bluetoothSockets[deviceId]
                if (socket != null && socket.isConnected) {
                    val outputStream = socket.outputStream
                    val byteArray = data.map { it.toByte() }.toByteArray()
                    
                    android.util.Log.d("UniversalBT", "📤 Writing to output stream...")
                    outputStream.write(byteArray)
                    outputStream.flush()
                    
                    android.util.Log.d("UniversalBT", "✅ Data sent successfully to $deviceId")
                    
                    Handler(Looper.getMainLooper()).post {
                        result.success(null)
                    }
                } else {
                    android.util.Log.e("UniversalBT", "❌ Socket not connected for $deviceId")
                    android.util.Log.d("UniversalBT", "📊 Socket status: exists=${bluetoothSockets.containsKey(deviceId)}, connected=${bluetoothSockets[deviceId]?.isConnected}")
                    
                    Handler(Looper.getMainLooper()).post {
                        result.error("NOT_CONNECTED", "Device is not connected", null)
                    }
                }
            } catch (e: IOException) {
                android.util.Log.e("UniversalBT", "❌ Failed to send data: ${e.message}")
                Handler(Looper.getMainLooper()).post {
                    result.error("SEND_FAILED", "Failed to send data: ${e.message}", null)
                }
            } catch (e: Exception) {
                android.util.Log.e("UniversalBT", "❌ Unexpected error sending data: ${e.message}")
                Handler(Looper.getMainLooper()).post {
                    result.error("SEND_FAILED", "Unexpected error: ${e.message}", null)
                }
            }
        }.start()
    }

    // === BLE Implementation Methods ===

    private fun startBleScan(call: MethodCall, result: Result) {
        if (!checkBlePermissions()) {
            result.error("PERMISSION_DENIED", "BLE permissions not granted", null)
            return
        }
        
        if (bluetoothAdapter?.isEnabled != true) {
            result.error("BLUETOOTH_DISABLED", "Bluetooth is not enabled", null)
            return
        }
        
        if (isBleScanning) {
            result.success(null)
            return
        }
        
        val serviceUuids: List<String>? = call.argument("serviceUuids")
        val timeout: Int? = call.argument("timeout")
        
        val scanSettings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
            
        val scanFilters: MutableList<ScanFilter> = mutableListOf()
        serviceUuids?.forEach { uuid ->
            scanFilters.add(
                ScanFilter.Builder()
                    .setServiceUuid(ParcelUuid.fromString(uuid))
                    .build()
            )
        }
        
        isBleScanning = true
        bluetoothLeScanner?.startScan(scanFilters, scanSettings, bleScanCallback)
        
        timeout?.let { timeoutMs ->
            Handler(Looper.getMainLooper()).postDelayed({
                if (isBleScanning) {
                    bluetoothLeScanner?.stopScan(bleScanCallback)
                    isBleScanning = false
                }
            }, timeoutMs.toLong())
        }
        
        result.success(null)
    }

    private fun stopBleScan(result: Result) {
        if (isBleScanning) {
            bluetoothLeScanner?.stopScan(bleScanCallback)
            isBleScanning = false
        }
        result.success(null)
    }

    private val bleScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            val rssi = result.rssi
            val scanRecord = result.scanRecord
            
            val serviceUuids: List<String> = scanRecord?.serviceUuids?.map { it.toString() } ?: emptyList()
            
            val deviceMap: Map<String, Any> = mapOf(
                "id" to device.address,
                "name" to (device.name ?: "Unknown"),
                "address" to device.address,
                "rssi" to rssi,
                "serviceUuids" to serviceUuids,
                "isConnectable" to true
            )
            
            channel.invokeMethod("onBleScanResult", deviceMap)
        }
        
        override fun onScanFailed(errorCode: Int) {
            // Handle scan failure
        }
    }

    private fun connectToBleDevice(call: MethodCall, result: Result) {
        val deviceId: String? = call.argument("deviceId")
        if (deviceId == null) {
            result.error("INVALID_ARGUMENT", "Device ID is required", null)
            return
        }
        
        val device = bluetoothAdapter?.getRemoteDevice(deviceId)
        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "Device not found", null)
            return
        }
        
        val gatt = device.connectGatt(context, false, gattCallback)
        connectedGattDevices[deviceId] = gatt
        result.success(null)
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            val deviceId = gatt.device.address
            val connectionState = when (newState) {
                BluetoothProfile.STATE_CONNECTED -> 2
                BluetoothProfile.STATE_CONNECTING -> 1
                BluetoothProfile.STATE_DISCONNECTING -> 3
                BluetoothProfile.STATE_DISCONNECTED -> 0
                else -> 4
            }
            
            val eventData: Map<String, Any> = mapOf(
                "deviceId" to deviceId,
                "state" to connectionState
            )
            
            channel.invokeMethod("onBleConnectionStateChanged", eventData)
            
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                gatt.discoverServices()
            }
        }
        
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            // Services discovered
        }
        
        override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            // Handle characteristic read
        }
        
        override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            // Handle characteristic write
        }
        
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            val deviceId = gatt.device.address
            val serviceUuid = characteristic.service.uuid.toString()
            val characteristicUuid = characteristic.uuid.toString()
            val data: List<Int> = characteristic.value?.map { it.toInt() and 0xFF } ?: emptyList()
            
            val eventData: Map<String, Any> = mapOf(
                "deviceId" to deviceId,
                "serviceUuid" to serviceUuid,
                "characteristicUuid" to characteristicUuid,
                "data" to data
            )
            
            channel.invokeMethod("onBleCharacteristicChanged", eventData)
        }
    }

    private fun disconnectBleDevice(call: MethodCall, result: Result) {
        val deviceId: String? = call.argument("deviceId")
        if (deviceId == null) {
            result.error("INVALID_ARGUMENT", "Device ID is required", null)
            return
        }
        
        connectedGattDevices[deviceId]?.disconnect()
        connectedGattDevices.remove(deviceId)
        result.success(null)
    }

    private fun discoverBleServices(call: MethodCall, result: Result) {
        val deviceId: String? = call.argument("deviceId")
        if (deviceId == null) {
            result.error("INVALID_ARGUMENT", "Device ID is required", null)
            return
        }
        
        val gatt = connectedGattDevices[deviceId]
        if (gatt == null) {
            result.error("DEVICE_NOT_CONNECTED", "Device is not connected", null)
            return
        }
        
        val services: List<String> = gatt.services.map { it.uuid.toString() }
        result.success(services)
    }

    private fun getBleCharacteristics(call: MethodCall, result: Result) {
        val deviceId: String? = call.argument("deviceId")
        val serviceUuid: String? = call.argument("serviceUuid")
        
        if (deviceId == null || serviceUuid == null) {
            result.error("INVALID_ARGUMENT", "Device ID and Service UUID are required", null)
            return
        }
        
        val gatt = connectedGattDevices[deviceId]
        if (gatt == null) {
            result.error("DEVICE_NOT_CONNECTED", "Device is not connected", null)
            return
        }
        
        val service = gatt.getService(UUID.fromString(serviceUuid))
        if (service == null) {
            result.error("SERVICE_NOT_FOUND", "Service not found", null)
            return
        }
        
        val characteristics: List<String> = service.characteristics.map { it.uuid.toString() }
        result.success(characteristics)
    }

    private fun readBleCharacteristic(call: MethodCall, result: Result) {
        val deviceId: String? = call.argument("deviceId")
        val serviceUuid: String? = call.argument("serviceUuid")
        val characteristicUuid: String? = call.argument("characteristicUuid")
        
        if (deviceId == null || serviceUuid == null || characteristicUuid == null) {
            result.error("INVALID_ARGUMENT", "All parameters are required", null)
            return
        }
        
        val gatt = connectedGattDevices[deviceId]
        if (gatt == null) {
            result.error("DEVICE_NOT_CONNECTED", "Device is not connected", null)
            return
        }
        
        val service = gatt.getService(UUID.fromString(serviceUuid))
        val characteristic = service?.getCharacteristic(UUID.fromString(characteristicUuid))
        
        if (characteristic == null) {
            result.error("CHARACTERISTIC_NOT_FOUND", "Characteristic not found", null)
            return
        }
        
        if (gatt.readCharacteristic(characteristic)) {
            val data: List<Int> = characteristic.value?.map { it.toInt() and 0xFF } ?: emptyList()
            result.success(data)
        } else {
            result.error("READ_FAILED", "Failed to read characteristic", null)
        }
    }

    private fun writeBleCharacteristic(call: MethodCall, result: Result) {
        val deviceId: String? = call.argument("deviceId")
        val serviceUuid: String? = call.argument("serviceUuid")
        val characteristicUuid: String? = call.argument("characteristicUuid")
        val data: List<Int>? = call.argument("data")
        val withoutResponse: Boolean = call.argument("withoutResponse") ?: false
        
        if (deviceId == null || serviceUuid == null || characteristicUuid == null || data == null) {
            result.error("INVALID_ARGUMENT", "All parameters are required", null)
            return
        }
        
        val gatt = connectedGattDevices[deviceId]
        if (gatt == null) {
            result.error("DEVICE_NOT_CONNECTED", "Device is not connected", null)
            return
        }
        
        val service = gatt.getService(UUID.fromString(serviceUuid))
        val characteristic = service?.getCharacteristic(UUID.fromString(characteristicUuid))
        
        if (characteristic == null) {
            result.error("CHARACTERISTIC_NOT_FOUND", "Characteristic not found", null)
            return
        }
        
        characteristic.value = data.map { it.toByte() }.toByteArray()
        characteristic.writeType = if (withoutResponse) BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE else BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        
        if (gatt.writeCharacteristic(characteristic)) {
            result.success(null)
        } else {
            result.error("WRITE_FAILED", "Failed to write characteristic", null)
        }
    }

    private fun subscribeBleCharacteristic(call: MethodCall, result: Result) {
        val deviceId: String? = call.argument("deviceId")
        val serviceUuid: String? = call.argument("serviceUuid")
        val characteristicUuid: String? = call.argument("characteristicUuid")
        
        if (deviceId == null || serviceUuid == null || characteristicUuid == null) {
            result.error("INVALID_ARGUMENT", "All parameters are required", null)
            return
        }
        
        val gatt = connectedGattDevices[deviceId]
        if (gatt == null) {
            result.error("DEVICE_NOT_CONNECTED", "Device is not connected", null)
            return
        }
        
        val service = gatt.getService(UUID.fromString(serviceUuid))
        val characteristic = service?.getCharacteristic(UUID.fromString(characteristicUuid))
        
        if (characteristic == null) {
            result.error("CHARACTERISTIC_NOT_FOUND", "Characteristic not found", null)
            return
        }
        
        gatt.setCharacteristicNotification(characteristic, true)
        
        val descriptor = characteristic.getDescriptor(UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"))
        descriptor?.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        
        if (gatt.writeDescriptor(descriptor)) {
            result.success(null)
        } else {
            result.error("SUBSCRIBE_FAILED", "Failed to subscribe to characteristic", null)
        }
    }

    private fun unsubscribeBleCharacteristic(call: MethodCall, result: Result) {
        val deviceId: String? = call.argument("deviceId")
        val serviceUuid: String? = call.argument("serviceUuid")
        val characteristicUuid: String? = call.argument("characteristicUuid")
        
        if (deviceId == null || serviceUuid == null || characteristicUuid == null) {
            result.error("INVALID_ARGUMENT", "All parameters are required", null)
            return
        }
        
        val gatt = connectedGattDevices[deviceId]
        if (gatt == null) {
            result.error("DEVICE_NOT_CONNECTED", "Device is not connected", null)
            return
        }
        
        val service = gatt.getService(UUID.fromString(serviceUuid))
        val characteristic = service?.getCharacteristic(UUID.fromString(characteristicUuid))
        
        if (characteristic == null) {
            result.error("CHARACTERISTIC_NOT_FOUND", "Characteristic not found", null)
            return
        }
        
        gatt.setCharacteristicNotification(characteristic, false)
        result.success(null)
    }

    // === Beacon Implementation Methods ===

    private fun startBeaconAdvertising(call: MethodCall, result: Result) {
        if (!checkBlePermissions()) {
            result.error("PERMISSION_DENIED", "BLE permissions not granted", null)
            return
        }
        
        val uuid: String? = call.argument("uuid")
        val major: Int? = call.argument("major")
        val minor: Int? = call.argument("minor")
        
        if (uuid == null || major == null || minor == null) {
            result.error("INVALID_ARGUMENT", "UUID, Major, and Minor are required", null)
            return
        }
        
        result.success(null)
    }

    private fun stopBeaconAdvertising(result: Result) {
        bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        result.success(null)
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            // Advertising started successfully
        }
        
        override fun onStartFailure(errorCode: Int) {
            // Advertising failed to start
        }
    }

    private fun startBeaconScanning(call: MethodCall, result: Result) {
        android.util.Log.d("UniversalBT", "🔍 Starting beacon scanning...")
        
        if (!checkLocationPermissions()) {
            android.util.Log.e("UniversalBT", "❌ Location permissions not granted")
            result.error("PERMISSION_DENIED", "Location permissions not granted", null)
            return
        }
        
        if (!checkBlePermissions()) {
            android.util.Log.e("UniversalBT", "❌ BLE permissions not granted") 
            result.error("PERMISSION_DENIED", "BLE permissions not granted", null)
            return
        }
        
        if (bluetoothAdapter?.isEnabled != true) {
            android.util.Log.e("UniversalBT", "❌ Bluetooth is not enabled")
            result.error("BLUETOOTH_DISABLED", "Bluetooth is not enabled", null)
            return
        }
        
        if (isBeaconScanning) {
            android.util.Log.d("UniversalBT", "⚠️ Already scanning beacons")
            result.success(null)
            return
        }
        
        val scanTimeout: Int? = call.argument("timeout")
        val targetUuids: List<String>? = call.argument("uuids")
        
        android.util.Log.d("UniversalBT", "🎯 Scan timeout: ${scanTimeout}ms")
        android.util.Log.d("UniversalBT", "🎯 Target UUIDs: $targetUuids")
        
        try {
            beaconScanResults.clear()
            
            val scanSettings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
                .setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
                .setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
                .setReportDelay(0L)
                .build()
            
            val scanFilters: MutableList<ScanFilter> = mutableListOf()
            
            targetUuids?.forEach { uuidString ->
                try {
                    val uuid = UUID.fromString(uuidString)
                    val uuidBytes = uuidToBytes(uuid)
                    
                    scanFilters.add(
                        ScanFilter.Builder()
                            .setServiceUuid(ParcelUuid.fromString(uuidString))
                            .build()
                    )
                    
                    android.util.Log.d("UniversalBT", "🎯 Added UUID filter: $uuidString")
                } catch (e: Exception) {
                    android.util.Log.w("UniversalBT", "⚠️ Invalid UUID format: $uuidString")
                }
            }
            
            if (scanFilters.isEmpty()) {
                android.util.Log.d("UniversalBT", "🎯 Using general BLE scan for beacons")
            }
            
            isBeaconScanning = true
            bluetoothLeScanner?.startScan(scanFilters.takeIf { it.isNotEmpty() }, scanSettings, beaconScanCallback)
            
            android.util.Log.d("UniversalBT", "✅ Beacon scanning started successfully")
            
            scanTimeout?.let { timeoutMs ->
                Handler(Looper.getMainLooper()).postDelayed({
                    if (isBeaconScanning) {
                        android.util.Log.d("UniversalBT", "⏰ Beacon scan timeout reached")
                        stopBeaconScanningInternal()
                        channel.invokeMethod("onBeaconScanTimeout", null)
                    }
                }, timeoutMs.toLong())
            }
            
            result.success(null)
            
        } catch (e: Exception) {
            android.util.Log.e("UniversalBT", "❌ Failed to start beacon scanning", e)
            isBeaconScanning = false
            result.error("SCAN_FAILED", "Failed to start beacon scanning: ${e.message}", null)
        }
    }

    private fun stopBeaconScanning(result: Result) {
        android.util.Log.d("UniversalBT", "🛑 Stopping beacon scanning...")
        
        val wasScanningBefore = isBeaconScanning
        stopBeaconScanningInternal()
        
        android.util.Log.d("UniversalBT", "✅ Beacon scanning stopped (was scanning: $wasScanningBefore)")
        result.success(null)
    }

    private fun stopBeaconScanningInternal() {
        if (isBeaconScanning) {
            try {
                bluetoothLeScanner?.stopScan(beaconScanCallback)
                android.util.Log.d("UniversalBT", "BLE scan stopped")
            } catch (e: Exception) {
                android.util.Log.w("UniversalBT", "Error stopping BLE scan: ${e.message}")
            }
            
            isBeaconScanning = false
            
            Handler(Looper.getMainLooper()).post {
                channel.invokeMethod("onBeaconScanFinished", mapOf(
                    "totalBeaconsFound" to beaconScanResults.size,
                    "scanDuration" to System.currentTimeMillis()
                ))
            }
        }
    }

    private val beaconScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            try {
                val scanRecord = result.scanRecord
                val device = result.device
                val rssi = result.rssi
                
                android.util.Log.d("UniversalBT", "📡 BLE scan result from ${device.address}, RSSI: $rssi")
                
                val manufacturerData = scanRecord?.manufacturerSpecificData
                var beacon: BeaconDevice? = null
                
                if (manufacturerData != null) {
                    for (i in 0 until manufacturerData.size()) {
                        val manufacturerId = manufacturerData.keyAt(i)
                        val data = manufacturerData.valueAt(i)
                        
                        android.util.Log.d("UniversalBT", "📡 Manufacturer ID: 0x${manufacturerId.toString(16)}, Data length: ${data?.size ?: 0}")
                        
                        if (data != null && data.size >= 23) {
                            beacon = parseIBeaconFromManufacturerData(data, device.address, rssi, manufacturerId)
                            if (beacon != null) break
                        }
                    }
                }
                
                if (beacon == null) {
                    val serviceData = scanRecord?.serviceData
                    serviceData?.forEach { (parcelUuid, data) ->
                        if (data.size >= 20) {
                            beacon = parseIBeaconFromServiceData(data, device.address, rssi, parcelUuid.uuid)
                            if (beacon != null) return@forEach
                        }
                    }
                }
                
                beacon?.let { foundBeacon ->
                    val beaconKey = "${foundBeacon.uuid}_${foundBeacon.major}_${foundBeacon.minor}"
                    
                    val existingBeacon = beaconScanResults[beaconKey]
                    val shouldNotify = existingBeacon == null || 
                                    Math.abs(existingBeacon.rssi - foundBeacon.rssi) > 3 || 
                                    (System.currentTimeMillis() - existingBeacon.timestamp) > 5000
                    
                    beaconScanResults[beaconKey] = foundBeacon
                    
                    if (shouldNotify) {
                        android.util.Log.d("UniversalBT", "📍 Beacon found: UUID=${foundBeacon.uuid.take(8)}..., Major=${foundBeacon.major}, Minor=${foundBeacon.minor}, RSSI=${foundBeacon.rssi}, Distance=${foundBeacon.distance?.let { "%.2fm".format(it) } ?: "unknown"}")
                        
                        Handler(Looper.getMainLooper()).post {
                            val beaconData = mapOf(
                                "uuid" to foundBeacon.uuid,
                                "major" to foundBeacon.major,
                                "minor" to foundBeacon.minor,
                                "rssi" to foundBeacon.rssi,
                                "distance" to foundBeacon.distance,
                                "proximity" to foundBeacon.proximity.name.lowercase(),
                                "address" to foundBeacon.address,
                                "timestamp" to foundBeacon.timestamp
                            )
                            
                            channel.invokeMethod("onBeaconScanResult", beaconData)
                        }
                    }
                }
                
            } catch (e: Exception) {
                android.util.Log.e("UniversalBT", "❌ Error processing beacon scan result", e)
            }
        }
        
        override fun onScanFailed(errorCode: Int) {
            android.util.Log.e("UniversalBT", "❌ Beacon scan failed with error code: $errorCode")
            
            val errorMessage = when (errorCode) {
                SCAN_FAILED_ALREADY_STARTED -> "Scan already started"
                SCAN_FAILED_APPLICATION_REGISTRATION_FAILED -> "App registration failed"
                SCAN_FAILED_FEATURE_UNSUPPORTED -> "Feature unsupported" 
                SCAN_FAILED_INTERNAL_ERROR -> "Internal error"
                SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES -> "Out of hardware resources"
                else -> "Unknown error ($errorCode)"
            }
            
            isBeaconScanning = false
            
            Handler(Looper.getMainLooper()).post {
                channel.invokeMethod("onBeaconScanError", mapOf(
                    "errorCode" to errorCode,
                    "errorMessage" to errorMessage
                ))
            }
        }
    }

    private fun parseIBeaconFromManufacturerData(data: ByteArray, address: String, rssi: Int, manufacturerId: Int): BeaconDevice? {
        try {
            if (data.size >= 23 && data[0] == 0x02.toByte() && data[1] == 0x15.toByte()) {
                return parseIBeaconData(data, address, rssi, 2)
            }
            
            if (data.size >= 21) {
                return parseIBeaconData(data, address, rssi, 0)
            }
            
            return null
            
        } catch (e: Exception) {
            android.util.Log.e("UniversalBT", "❌ Failed to parse manufacturer beacon data", e)
            return null
        }
    }

    private fun parseIBeaconFromServiceData(data: ByteArray, address: String, rssi: Int, serviceUuid: UUID): BeaconDevice? {
        try {
            val uuid = serviceUuid.toString().uppercase()
            
            val major = if (data.size >= 2) {
                ((data[0].toUByte().toInt() shl 8) or data[1].toUByte().toInt())
            } else 0
            
            val minor = if (data.size >= 4) {
                ((data[2].toUByte().toInt() shl 8) or data[3].toUByte().toInt())
            } else 0
            
            val txPower = if (data.size >= 5) data[4].toInt() else -59
            
            val distance = calculateDistance(rssi, txPower)
            val proximity = calculateProximity(distance)
            
            android.util.Log.d("UniversalBT", "🔍 Parsed service beacon - UUID: $uuid, Major: $major, Minor: $minor")
            
            return BeaconDevice(
                uuid = uuid,
                major = major,
                minor = minor,
                rssi = rssi,
                distance = distance,
                proximity = proximity,
                address = address
            )
            
        } catch (e: Exception) {
            android.util.Log.e("UniversalBT", "❌ Failed to parse service beacon data", e)
            return null
        }
    }

    private fun parseIBeaconData(data: ByteArray, address: String, rssi: Int, uuidStartIndex: Int): BeaconDevice? {
        try {
            if (data.size < uuidStartIndex + 20) return null
            
            val uuidBytes = data.sliceArray(uuidStartIndex until uuidStartIndex + 16)
            val uuid = bytesToUuid(uuidBytes).toString().uppercase()
            
            val majorIndex = uuidStartIndex + 16
            val major = if (data.size >= majorIndex + 2) {
                ((data[majorIndex].toUByte().toInt() shl 8) or data[majorIndex + 1].toUByte().toInt())
            } else 0
            
            val minorIndex = majorIndex + 2
            val minor = if (data.size >= minorIndex + 2) {
                ((data[minorIndex].toUByte().toInt() shl 8) or data[minorIndex + 1].toUByte().toInt())
            } else 0
            
            val txPowerIndex = minorIndex + 2
            val txPower = if (data.size > txPowerIndex) data[txPowerIndex].toInt() else -59
            
            val distance = calculateDistance(rssi, txPower)
            val proximity = calculateProximity(distance)
            
            android.util.Log.d("UniversalBT", "🔍 Parsed beacon - UUID: ${uuid.take(8)}..., Major: $major, Minor: $minor, TxPower: $txPower")
            
            return BeaconDevice(
                uuid = uuid,
                major = major,
                minor = minor,
                rssi = rssi,
                distance = distance,
                proximity = proximity,
                address = address
            )
            
        } catch (e: Exception) {
            android.util.Log.e("UniversalBT", "❌ Failed to parse beacon data", e)
            return null
        }
    }

    private fun uuidToBytes(uuid: UUID): ByteArray {
        val buffer = ByteArray(16)
        val mostSigBits = uuid.mostSignificantBits
        val leastSigBits = uuid.leastSignificantBits
        
        for (i in 0..7) {
            buffer[i] = (mostSigBits shr (8 * (7 - i))).toByte()
            buffer[8 + i] = (leastSigBits shr (8 * (7 - i))).toByte()
        }
        
        return buffer
    }

    private fun bytesToUuid(bytes: ByteArray): UUID {
        if (bytes.size != 16) throw IllegalArgumentException("UUID bytes must be 16 bytes")
        
        var mostSigBits = 0L
        var leastSigBits = 0L
        
        for (i in 0..7) {
            mostSigBits = (mostSigBits shl 8) or (bytes[i].toUByte().toLong())
            leastSigBits = (leastSigBits shl 8) or (bytes[8 + i].toUByte().toLong())
        }
        
        return UUID(mostSigBits, leastSigBits)
    }

    private fun calculateDistance(rssi: Int, txPower: Int): Double? {
        return try {
            if (rssi == 0) {
                null
            } else {
                val ratio = (txPower - rssi).toDouble()
                if (ratio < 1.0) {
                    Math.pow(ratio, 10.0)
                } else {
                    val accuracy = (0.89976 * Math.pow(ratio, 7.7095)) + 0.111
                    accuracy
                }
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun calculateProximity(distance: Double?): BeaconProximity {
        return when {
            distance == null -> BeaconProximity.UNKNOWN
            distance < 0.5 -> BeaconProximity.IMMEDIATE
            distance < 3.0 -> BeaconProximity.NEAR
            else -> BeaconProximity.FAR
        }
    }

    private fun requestLocationPermission(result: Result) {
        if (checkLocationPermissions()) {
            result.success(true)
            return
        }
        
        pendingResult = result
        activity?.let { activity ->
            val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.BLUETOOTH_ADVERTISE
                )
            } else {
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                    Manifest.permission.BLUETOOTH,
                    Manifest.permission.BLUETOOTH_ADMIN
                )
            }
            
            ActivityCompat.requestPermissions(
                activity,
                permissions,
                LOCATION_PERMISSION_REQUEST_CODE
            )
        } ?: result.success(false)
    }

    // === Permission Check Methods ===

    private fun checkBluetoothPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val hasScan = ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
            val hasConnect = ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
            val hasAdvertise = ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED
            hasScan && hasConnect && hasAdvertise
        } else {
            val hasBluetooth = ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH) == PackageManager.PERMISSION_GRANTED
            val hasAdmin = ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_ADMIN) == PackageManager.PERMISSION_GRANTED
            hasBluetooth && hasAdmin
        }
    }

    private fun checkBlePermissions(): Boolean {
        return checkBluetoothPermissions() && checkLocationPermissions()
    }

    private fun checkLocationPermissions(): Boolean {
        return ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
               ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    // === Bluetooth Receiver ===

    private inner class BluetoothReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            android.util.Log.d("UniversalBT", "BroadcastReceiver onReceive: ${intent.action}")
            when (intent.action) {
                BluetoothAdapter.ACTION_DISCOVERY_STARTED -> {
                    android.util.Log.d("UniversalBT", "Discovery started")
                }
                BluetoothDevice.ACTION_FOUND -> {
                    android.util.Log.d("UniversalBT", "Device found!")
                    val device: BluetoothDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    }
                    
                    val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE).toInt()
                    
                    device?.let { bluetoothDevice ->
                        try {
                            val deviceName = if (checkBluetoothPermissions()) {
                                bluetoothDevice.name ?: "Unknown"
                            } else {
                                "Unknown"
                            }
                            
                            android.util.Log.d("UniversalBT", "Found device: $deviceName (${bluetoothDevice.address}) RSSI: $rssi")
                            
                            val deviceMap: Map<String, Any> = mapOf(
                                "id" to bluetoothDevice.address,
                                "name" to deviceName,
                                "address" to bluetoothDevice.address,
                                "rssi" to rssi,
                                "isConnected" to false,
                                "serviceUuids" to emptyList<String>()
                            )
                            
                            val scanResult: Map<String, Any> = mapOf(
                                "device" to deviceMap,
                                "timestamp" to System.currentTimeMillis(),
                                "isFirstScan" to !scanResults.containsKey(bluetoothDevice.address)
                            )
                            
                            scanResults[bluetoothDevice.address] = bluetoothDevice
                            android.util.Log.d("UniversalBT", "Sending scan result to Flutter: $deviceName (${bluetoothDevice.address})")
                            
                            Handler(Looper.getMainLooper()).post {
                                channel.invokeMethod("onBluetoothScanResult", scanResult)
                            }
                        } catch (e: SecurityException) {
                            android.util.Log.w("UniversalBT", "Security exception getting device info: ${e.message}")
                        } catch (e: Exception) {
                            android.util.Log.e("UniversalBT", "Error processing found device: ${e.message}")
                        }
                    }
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    android.util.Log.d("UniversalBT", "Discovery finished")
                    android.util.Log.d("UniversalBT", "Sending scan finished event to Flutter")
                    
                    Handler(Looper.getMainLooper()).post {
                        channel.invokeMethod("onBluetoothScanFinished", null)
                    }
                    
                    isScanning = false
                }
            }
        }
    }
}