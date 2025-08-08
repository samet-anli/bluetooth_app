package com.samet.bluetooth_app

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    
    private val CHANNEL = "universal_bluetooth"
    private lateinit var bluetoothHandler: UniversalBluetoothHandler
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // MethodChannel oluştur
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        // BluetoothHandler'ı başlat
        bluetoothHandler = UniversalBluetoothHandler(
            context = applicationContext,
            activity = this,
            channel = channel
        )
        
        // MethodCallHandler'ı ayarla
        channel.setMethodCallHandler(bluetoothHandler)
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Activity oluşturulduktan sonra handler'a bildir
        if (::bluetoothHandler.isInitialized) {
            bluetoothHandler.updateActivity(this)
        }
    }
    
    override fun onResume() {
        super.onResume()
        
        // Activity tekrar aktif olduğunda handler'a bildir
        if (::bluetoothHandler.isInitialized) {
            bluetoothHandler.updateActivity(this)
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        
        // Cleanup yapmayı unutma
        if (::bluetoothHandler.isInitialized) {
            bluetoothHandler.cleanup()
        }
    }
    
    // İzin sonuçlarını bluetooth handler'a ilet
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        if (::bluetoothHandler.isInitialized) {
            val handled = bluetoothHandler.handlePermissionResult(requestCode, permissions, grantResults)
            if (!handled) {
                // Eğer bluetooth handler işlemediyse, parent'a ilet
                super.onRequestPermissionsResult(requestCode, permissions, grantResults)
            }
        }
    }
    
    // Activity result'ları bluetooth handler'a ilet
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        if (::bluetoothHandler.isInitialized) {
            val handled = bluetoothHandler.handleActivityResult(requestCode, resultCode, data)
            if (!handled) {
                // Eğer bluetooth handler işlemediyse, parent'a ilet
                super.onActivityResult(requestCode, resultCode, data)
            }
        }
    }
}