# 📡 Bluetooth App

**Bluetooth App**, iOS ve Android cihazlarda **Classic Bluetooth**, **Bluetooth Low Energy (BLE)** ve **iBeacon** teknolojilerini tek bir uygulama içinde bir araya getiren kapsamlı bir Flutter projesidir.  
Kullanıcıların cihazlarını taramasına, bağlanmasına, veri alışverişi yapmasına ve iBeacon sinyallerini algılamasına olanak tanır.

---

## 🚀 Özellikler

### ✅ Classic Bluetooth
- Cihaz tarama ve keşif
- Bağlantı yönetimi (eşleştirme / bağlantı kesme)
- Çift yönlü veri iletişimi
- Bağlantı durumu izleme
- Cihazı diğer cihazlara görünür yapma

### ✅ BLE (Bluetooth Low Energy)
- Servis filtreleme ile BLE cihaz tarama
- GATT bağlantı yönetimi
- Servis ve karakteristik keşfi
- Karakteristik değerlerini okuma/yazma
- Karakteristik bildirimleri ve abonelikler
- Bağlantı durumu izleme

### ✅ iBeacon Desteği
- iBeacon tarama ve mesafe ölçümü (ranging)
- Yakınlık algılama
- Bölge izleme (region monitoring)

---

## 📋 Gereksinimler
- **Flutter:** 3.3.0+
- **Dart:** 3.8.1+
- **Android:** API level 21+ (Android 5.0+)
- **iOS:** 11.0+

---

## 📦 Kurulum & Çalıştırma
```bash
git clone https://github.com/KULLANICI_ADIN/bluetooth_app.git
cd bluetooth_app
flutter pub get
flutter run
