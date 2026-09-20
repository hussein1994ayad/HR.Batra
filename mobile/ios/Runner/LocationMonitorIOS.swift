// =========================================================================
// HR Pro v6.0 - iOS Region Monitoring Service
// =========================================================================
// يشتغل حتى لو التطبيق مقفل تماماً (Apple يوقظه عند دخول/خروج منطقة).
// يقتصر على وقت الدوام (check-in → check-out فقط).
//
// كيف يعمل:
//   1. عند check-in: Dart يستدعي startMonitoring(branches:, employeeId:)
//   2. Swift يسجّل CLCircularRegion لكل فرع (حد أقصى 20 من Apple).
//   3. عند دخول/خروج، iOS يوقظ التطبيق حتى لو مقفل → 10 ثواني للعمل.
//   4. Swift يرفع الحدث لـ Supabase مباشرة عبر URLSession (بدون Flutter).
//   5. عند check-out: Dart يستدعي stopMonitoring() → كل الأحداث توقف.
// =========================================================================

import Foundation
import CoreLocation
import UIKit
import UserNotifications

@objc class LocationMonitorIOS: NSObject, CLLocationManagerDelegate {

    static let shared = LocationMonitorIOS()

    private let locationManager = CLLocationManager()
    private let userDefaults = UserDefaults.standard

    // مفاتيح تخزين محلية
    private let kSupabaseUrl = "supabase_url"
    private let kSupabaseAnonKey = "supabase_anon_key"
    private let kEmployeeId = "hr_employee_id"
    private let kAccessToken = "supabase_access_token"

    // Cache للفروع (اسم + إحداثيات) للاستعمال في الرفع
    private var branchCache: [String: [String: Any]] = [:]

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    // =====================================================================
    // Public API (called from Flutter via MethodChannel)
    // =====================================================================

    /// تخزين إعدادات Supabase الضرورية للرفع من الخلفية
    @objc func configure(
        supabaseUrl: String,
        supabaseAnonKey: String,
        employeeId: String,
        accessToken: String
    ) {
        userDefaults.set(supabaseUrl, forKey: kSupabaseUrl)
        userDefaults.set(supabaseAnonKey, forKey: kSupabaseAnonKey)
        userDefaults.set(employeeId, forKey: kEmployeeId)
        userDefaults.set(accessToken, forKey: kAccessToken)
    }

    /// بدء مراقبة قائمة فروع (max 20 لأن Apple يحدد ذلك)
    /// branches: [{"id": "uuid", "name": "القناة", "lat": 33.31, "lng": 44.41, "radius": 100}]
    @objc func startMonitoring(branches: [[String: Any]]) {
        // امسح أي مناطق سابقة
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        branchCache.removeAll()

        // اطلب الصلاحيات إذا لم تُطلب
        if CLLocationManager.authorizationStatus() != .authorizedAlways {
            locationManager.requestAlwaysAuthorization()
        }

        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            NSLog("[HR Pro iOS] Region monitoring غير متاح على هذا الجهاز")
            return
        }

        // Apple يسمح بحد أقصى 20 region للتطبيق الواحد
        let limited = branches.prefix(20)

        for branch in limited {
            guard let id = branch["id"] as? String,
                  let lat = branch["lat"] as? Double,
                  let lng = branch["lng"] as? Double
            else { continue }
            let radius = (branch["radius"] as? Double) ?? 100.0
            let name = (branch["name"] as? String) ?? "فرع"

            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                radius: min(radius, locationManager.maximumRegionMonitoringDistance),
                identifier: id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true

            locationManager.startMonitoring(for: region)
            branchCache[id] = ["name": name, "lat": lat, "lng": lng]
        }

        // فعّل أيضاً Significant Location Changes للنسخ الاحتياطية
        locationManager.startMonitoringSignificantLocationChanges()

        NSLog("[HR Pro iOS] بدأت مراقبة \(limited.count) فرع + SLC")
    }

    /// إيقاف كل المراقبة (يُستدعى عند check-out)
    @objc func stopMonitoring() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        locationManager.stopMonitoringSignificantLocationChanges()
        branchCache.removeAll()
        NSLog("[HR Pro iOS] توقفت المراقبة تماماً")
    }

    // =====================================================================
    // CLLocationManagerDelegate — يُستدعى حتى لو التطبيق مقفل
    // =====================================================================

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        NSLog("[HR Pro iOS] دخول منطقة: \(region.identifier)")
        handleRegionEvent(regionId: region.identifier, event: "enter")
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        NSLog("[HR Pro iOS] خروج منطقة: \(region.identifier)")
        handleRegionEvent(regionId: region.identifier, event: "exit")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        uploadLocationPoint(latitude: loc.coordinate.latitude,
                            longitude: loc.coordinate.longitude,
                            accuracy: loc.horizontalAccuracy)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[HR Pro iOS] Location error: \(error.localizedDescription)")
    }

    // =====================================================================
    // Direct HTTP upload to Supabase (يشتغل حتى بدون Flutter engine)
    // =====================================================================

    private func handleRegionEvent(regionId: String, event: String) {
        guard let url = userDefaults.string(forKey: kSupabaseUrl),
              let anon = userDefaults.string(forKey: kSupabaseAnonKey),
              let employeeId = userDefaults.string(forKey: kEmployeeId)
        else { return }

        let branch = branchCache[regionId] ?? [:]
        let branchName = branch["name"] as? String ?? "فرع"

        let title = event == "enter" ? "دخول فرع \(branchName)" : "خروج من فرع \(branchName)"
        let body = "تم رصد \(event == "enter" ? "دخولك إلى" : "خروجك من") فرع \(branchName)"

        // 1) أرسل إشعار للسيرفر
        insertNotification(
            supabaseUrl: url, anonKey: anon, employeeId: employeeId,
            title: title, body: body, type: "attendance"
        )

        // 2) إذا كان دخول فرع → سجّل نقطة location_tracking
        if event == "enter",
           let lat = branch["lat"] as? Double,
           let lng = branch["lng"] as? Double {
            uploadLocationPoint(latitude: lat, longitude: lng, accuracy: 100.0)
        }

        // 3) إشعار محلي فوري للمستخدم (اختياري)
        showLocalNotification(title: title, body: body)
    }

    private func insertNotification(
        supabaseUrl: String, anonKey: String, employeeId: String,
        title: String, body: String, type: String
    ) {
        let endpoint = "\(supabaseUrl)/rest/v1/notifications"
        guard let requestUrl = URL(string: endpoint) else { return }

        var request = URLRequest(url: requestUrl)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(anonKey, forHTTPHeaderField: "apikey")
        request.addValue(
            "Bearer \(userDefaults.string(forKey: kAccessToken) ?? anonKey)",
            forHTTPHeaderField: "Authorization"
        )
        request.addValue("return=minimal", forHTTPHeaderField: "Prefer")

        let payload: [String: Any] = [
            "employee_id": employeeId,
            "title": title,
            "body": body,
            "type": type,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        // Background-safe URLSession task
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                NSLog("[HR Pro iOS] Notification insert failed: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                NSLog("[HR Pro iOS] Notification insert status: \(http.statusCode)")
            }
        }
        task.resume()
    }

    private func uploadLocationPoint(latitude: Double, longitude: Double, accuracy: Double) {
        guard let url = userDefaults.string(forKey: kSupabaseUrl),
              let anon = userDefaults.string(forKey: kSupabaseAnonKey),
              let employeeId = userDefaults.string(forKey: kEmployeeId)
        else { return }

        let endpoint = "\(url)/rest/v1/location_tracking"
        guard let requestUrl = URL(string: endpoint) else { return }

        var request = URLRequest(url: requestUrl)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(anon, forHTTPHeaderField: "apikey")
        request.addValue(
            "Bearer \(userDefaults.string(forKey: kAccessToken) ?? anon)",
            forHTTPHeaderField: "Authorization"
        )
        request.addValue("return=minimal", forHTTPHeaderField: "Prefer")

        let iso = ISO8601DateFormatter().string(from: Date())
        let payload: [String: Any] = [
            "employee_id": employeeId,
            "latitude": latitude,
            "longitude": longitude,
            "timestamp": iso,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    private func showLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound(named: UNNotificationSoundName("special_chime.wav"))

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
