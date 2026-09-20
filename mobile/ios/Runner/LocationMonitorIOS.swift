// =========================================================================
// HR Pro v6.0 - iOS Location Monitor (Multi-Mode Tracking)
// =========================================================================
// تصميم ذكي يحترم قيود Apple ويعطي أقصى تغطية ممكنة:
//
// Mode A - REGION MONITORING (داخل فرع)
//   • CLCircularRegion لكل فرع (max 20)
//   • Significant Location Changes كنسخة احتياط
//   • CLVisit لتسجيل التوقفات (توقف/غادر) — لا يحتاج التطبيق شغّال
//   • بطارية منخفضة، بدون مؤشر أزرق
//
// Mode B - CONTINUOUS PATH (خارج فرع، أثناء check-in)
//   • startUpdatingLocation مع allowsBackgroundLocationUpdates
//   • distance filter 30م — يعطي مسار متتابع
//   • يشتغل ~10 دقيقة بعد إغلاق التطبيق (حد Apple)
//   • بعد الـ 10 دقائق، SLC + CLVisit يحلّان محله
//
// SWITCHING:
//   • dxEnterRegion → Mode A (رجع للفرع، نكفي المسار المستمر)
//   • didExitRegion  → Mode B (طلع من الفرع، نفعّل المسار المستمر)
//
// كل الأحداث تُرفع مباشرة لـ Supabase عبر URLSession (بدون Flutter engine)
// =========================================================================

import Foundation
import CoreLocation
import UIKit
import UserNotifications

@objc class LocationMonitorIOS: NSObject, CLLocationManagerDelegate {

    static let shared = LocationMonitorIOS()

    private let locationManager = CLLocationManager()
    private let userDefaults = UserDefaults.standard

    // مفاتيح التخزين
    private let kSupabaseUrl = "supabase_url"
    private let kSupabaseAnonKey = "supabase_anon_key"
    private let kEmployeeId = "hr_employee_id"
    private let kAccessToken = "supabase_access_token"
    private let kActiveMonitoring = "hr_active_monitoring"

    private var branchCache: [String: [String: Any]] = [:]
    private var isCheckedIn: Bool = false
    private var isCurrentlyInsideAnyBranch: Bool = false
    private var continuousUpdatesActive: Bool = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        // ✅ إخفاء المؤشر الأزرق (يعمل فقط للتوزيع الخاص — Ad Hoc / Enterprise)
        // لا يمكن للمستخدم رؤية "أنت تُتتبع" — Apple تسمح بهذا في Ad Hoc
        locationManager.showsBackgroundLocationIndicator = false
    }

    // =====================================================================
    // Public API
    // =====================================================================

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

    @objc func startMonitoring(branches: [[String: Any]]) {
        // احذف المناطق القديمة
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        branchCache.removeAll()

        if CLLocationManager.authorizationStatus() != .authorizedAlways {
            locationManager.requestAlwaysAuthorization()
        }

        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            NSLog("[HR Pro iOS] Region monitoring غير متاح")
            return
        }

        // Mode A - Region Monitoring
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

            branchCache[id] = ["name": name, "lat": lat, "lng": lng, "radius": radius]
        }

        // مراقبة إضافية دائمة (تشتغل حتى لو التطبيق مقفول)
        locationManager.startMonitoringSignificantLocationChanges()
        locationManager.startMonitoringVisits() // CLVisit — رصد التوقفات

        // فحص الحالة الحالية (داخل أم خارج فرع؟) لبدء Mode مناسب
        checkCurrentBranchState()

        userDefaults.set(true, forKey: kActiveMonitoring)
        NSLog("[HR Pro iOS] Monitoring active: \(limited.count) branches + SLC + Visits")
    }

    /// بلّغ الطبقة إن الموظف عمل check-in — نفعّل المسار المستمر
    @objc func setCheckedIn(_ checkedIn: Bool) {
        isCheckedIn = checkedIn
        if checkedIn {
            // إذا كان خارج فرع → فعّل GPS المستمر لتسجيل المسار
            if !isCurrentlyInsideAnyBranch {
                startContinuousUpdates()
            }
        } else {
            // Check-out → أوقف المسار المستمر (نبقي فقط SLC + Regions للأمان)
            stopContinuousUpdates()
        }
    }

    @objc func stopMonitoring() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()
        stopContinuousUpdates()
        branchCache.removeAll()
        isCheckedIn = false
        userDefaults.set(false, forKey: kActiveMonitoring)
        NSLog("[HR Pro iOS] Full stop — all monitoring cancelled")
    }

    // =====================================================================
    // Mode Switching
    // =====================================================================

    private func startContinuousUpdates() {
        if continuousUpdatesActive { return }
        locationManager.distanceFilter = 30 // كل 30 متر
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
        continuousUpdatesActive = true
        NSLog("[HR Pro iOS] Mode B activated — continuous path tracking")
    }

    private func stopContinuousUpdates() {
        if !continuousUpdatesActive { return }
        locationManager.stopUpdatingLocation()
        continuousUpdatesActive = false
        NSLog("[HR Pro iOS] Mode A activated — region monitoring only")
    }

    private func checkCurrentBranchState() {
        // نستدعي requestLocation مرة واحدة لنعرف الحالة الحالية
        locationManager.requestLocation()
    }

    // =====================================================================
    // CLLocationManagerDelegate
    // =====================================================================

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        NSLog("[HR Pro iOS] Enter region: \(region.identifier)")
        isCurrentlyInsideAnyBranch = true
        handleRegionEvent(regionId: region.identifier, event: "enter")

        // رجع لفرع → أوقف المسار المستمر (توفير بطارية)
        if isCheckedIn {
            stopContinuousUpdates()
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        NSLog("[HR Pro iOS] Exit region: \(region.identifier)")
        isCurrentlyInsideAnyBranch = false
        handleRegionEvent(regionId: region.identifier, event: "exit")

        // خرج من فرع أثناء check-in → فعّل المسار المستمر
        if isCheckedIn {
            startContinuousUpdates()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // تجاهل النقاط غير الدقيقة (>100م)
        if loc.horizontalAccuracy < 0 || loc.horizontalAccuracy > 100 { return }

        uploadLocationPoint(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            accuracy: loc.horizontalAccuracy,
            source: continuousUpdatesActive ? "continuous" : "slc"
        )

        // فحص حالة فرع كل نقطة (لو دخل/خرج ما التقطه Region Monitoring)
        updateBranchStateFromLocation(loc)
    }

    /// CLVisit — Apple ترصد التوقفات (30+ دقيقة في نفس المكان)
    /// يشتغل حتى لو التطبيق مقفول تماماً
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let event: String
        let timestamp: Date
        if visit.departureDate == Date.distantFuture {
            event = "visit_arrival"
            timestamp = visit.arrivalDate
        } else {
            event = "visit_departure"
            timestamp = visit.departureDate
        }
        NSLog("[HR Pro iOS] Visit \(event) at \(visit.coordinate)")

        uploadLocationPoint(
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude,
            accuracy: visit.horizontalAccuracy,
            source: event,
            timestamp: timestamp
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[HR Pro iOS] Location error: \(error.localizedDescription)")
    }

    private func updateBranchStateFromLocation(_ location: CLLocation) {
        var insideAny = false
        for (_, info) in branchCache {
            guard let lat = info["lat"] as? Double,
                  let lng = info["lng"] as? Double,
                  let radius = info["radius"] as? Double
            else { continue }
            let center = CLLocation(latitude: lat, longitude: lng)
            let distance = location.distance(from: center)
            if distance <= radius {
                insideAny = true
                break
            }
        }
        if insideAny != isCurrentlyInsideAnyBranch {
            isCurrentlyInsideAnyBranch = insideAny
            if isCheckedIn {
                if insideAny {
                    stopContinuousUpdates()
                } else {
                    startContinuousUpdates()
                }
            }
        }
    }

    // =====================================================================
    // Supabase Direct Upload (yes, without Flutter engine)
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

        insertNotification(
            supabaseUrl: url, anonKey: anon, employeeId: employeeId,
            title: title, body: body, type: "attendance"
        )

        if event == "enter",
           let lat = branch["lat"] as? Double,
           let lng = branch["lng"] as? Double {
            uploadLocationPoint(latitude: lat, longitude: lng, accuracy: 100.0, source: "region_enter")
        }
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

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                NSLog("[HR Pro iOS] Notif upload failed: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                NSLog("[HR Pro iOS] Notif upload status: \(http.statusCode)")
            }
        }.resume()
    }

    private func uploadLocationPoint(
        latitude: Double, longitude: Double, accuracy: Double,
        source: String, timestamp: Date = Date()
    ) {
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

        let iso = ISO8601DateFormatter().string(from: timestamp)
        let payload: [String: Any] = [
            "employee_id": employeeId,
            "latitude": latitude,
            "longitude": longitude,
            "timestamp": iso,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }
}
