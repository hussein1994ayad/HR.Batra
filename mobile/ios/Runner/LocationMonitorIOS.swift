// =========================================================================
// HR Pro - iOS Location Monitor
// =========================================================================
// يسجّل مسار الموظف **بين بصمة الحضور وبصمة الانصراف فقط** — وهو المصرّح به
// في سياسة الخصوصية. خارج الدوام لا يُجمع ولا يُرفع أي موقع.
//
// أثناء الدوام:
//   • داخل الفرع: Region Monitoring + Significant Location Changes (بطارية منخفضة)
//   • خارج الفرع: startUpdatingLocation (مسار متتابع كل 30م)
//   • CLVisit يرصد التوقفات حتى لو التطبيق مقفول
//
// الرفع يتم مباشرة لـ Supabase (بدون Flutter engine) بتوكن الجلسة. إذا انتهت
// صلاحية التوكن (ساعة) أو انقطعت الشبكة تُحفظ النقاط محلياً، ويرفعها تطبيق
// Flutter عند الفتح القادم (drainPendingPoints).
//
// مؤشر الموقع الأزرق ظاهر دائماً: التتبع مُعلَن للموظف وغير مخفي.
// =========================================================================

import Foundation
import CoreLocation
import UIKit

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
    private let kCheckedIn = "hr_checked_in"
    private let kPendingPoints = "hr_pending_location_points"
    private let maxPendingPoints = 2000

    private var branchCache: [String: [String: Any]] = [:]
    private var isCheckedIn: Bool {
        get { userDefaults.bool(forKey: kCheckedIn) }
        set { userDefaults.set(newValue, forKey: kCheckedIn) }
    }
    private var isCurrentlyInsideAnyBranch: Bool = false
    private var continuousUpdatesActive: Bool = false
    private let pendingQueue = DispatchQueue(label: "com.batra.hrpro.pending-points")

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
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

    /// تحديث توكن الجلسة فقط (يُستدعى عند تجديد الجلسة في Flutter).
    @objc func updateAccessToken(_ token: String) {
        userDefaults.set(token, forKey: kAccessToken)
    }

    @objc func startMonitoring(branches: [[String: Any]]) {
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

        for branch in branches.prefix(20) {
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

        userDefaults.set(true, forKey: kActiveMonitoring)
        if isCheckedIn { startShiftTracking() }
        NSLog("[HR Pro iOS] Monitoring \(branchCache.count) branches, checkedIn=\(isCheckedIn)")
    }

    /// بصمة حضور → يبدأ التتبع. بصمة انصراف → يتوقف كل التتبع.
    @objc func setCheckedIn(_ checkedIn: Bool) {
        isCheckedIn = checkedIn
        if checkedIn {
            startShiftTracking()
        } else {
            stopShiftTracking()
        }
    }

    @objc func stopMonitoring() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        stopShiftTracking()
        branchCache.removeAll()
        isCheckedIn = false
        userDefaults.set(false, forKey: kActiveMonitoring)
        userDefaults.removeObject(forKey: kAccessToken)
        NSLog("[HR Pro iOS] Full stop — all monitoring cancelled")
    }

    /// النقاط التي لم تُرفع (توكن منتهٍ أو بدون شبكة). تُفرَّغ بعد القراءة.
    @objc func drainPendingPoints() -> [[String: Any]] {
        return pendingQueue.sync {
            let points = userDefaults.array(forKey: kPendingPoints) as? [[String: Any]] ?? []
            userDefaults.removeObject(forKey: kPendingPoints)
            return points
        }
    }

    // =====================================================================
    // Shift tracking
    // =====================================================================

    private func startShiftTracking() {
        locationManager.startMonitoringSignificantLocationChanges()
        locationManager.startMonitoringVisits()
        // نعرف هل هو داخل فرع الآن لنقرر المسار المستمر
        locationManager.requestLocation()
        if !isCurrentlyInsideAnyBranch {
            startContinuousUpdates()
        }
    }

    private func stopShiftTracking() {
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()
        stopContinuousUpdates()
    }

    private func startContinuousUpdates() {
        if continuousUpdatesActive { return }
        locationManager.distanceFilter = 30
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
        continuousUpdatesActive = true
    }

    private func stopContinuousUpdates() {
        if !continuousUpdatesActive { return }
        locationManager.stopUpdatingLocation()
        continuousUpdatesActive = false
    }

    // =====================================================================
    // CLLocationManagerDelegate
    // =====================================================================

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        isCurrentlyInsideAnyBranch = true
        if isCheckedIn { stopContinuousUpdates() }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        isCurrentlyInsideAnyBranch = false
        if isCheckedIn { startContinuousUpdates() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isCheckedIn, let loc = locations.last else { return }
        if loc.horizontalAccuracy < 0 || loc.horizontalAccuracy > 100 { return }

        uploadLocationPoint(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            timestamp: loc.timestamp
        )
        updateBranchStateFromLocation(loc)
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard isCheckedIn else { return }
        let timestamp = visit.departureDate == Date.distantFuture ? visit.arrivalDate : visit.departureDate
        uploadLocationPoint(
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude,
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
            if location.distance(from: CLLocation(latitude: lat, longitude: lng)) <= radius {
                insideAny = true
                break
            }
        }
        if insideAny != isCurrentlyInsideAnyBranch {
            isCurrentlyInsideAnyBranch = insideAny
            if isCheckedIn {
                if insideAny { stopContinuousUpdates() } else { startContinuousUpdates() }
            }
        }
    }

    // =====================================================================
    // Upload (Supabase REST) with offline/expired-token buffer
    // =====================================================================

    /// هل توكن الجلسة صالح لدقيقتين قادمتين على الأقل؟
    private func tokenIsFresh(_ token: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return false }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double
        else { return false }
        return Date(timeIntervalSince1970: exp).timeIntervalSinceNow > 120
    }

    private func bufferPoint(_ point: [String: Any]) {
        pendingQueue.async {
            var points = self.userDefaults.array(forKey: self.kPendingPoints) as? [[String: Any]] ?? []
            points.append(point)
            if points.count > self.maxPendingPoints {
                points.removeFirst(points.count - self.maxPendingPoints)
            }
            self.userDefaults.set(points, forKey: self.kPendingPoints)
        }
    }

    private func uploadLocationPoint(latitude: Double, longitude: Double, timestamp: Date) {
        guard let employeeId = userDefaults.string(forKey: kEmployeeId) else { return }
        let point: [String: Any] = [
            "employee_id": employeeId,
            "latitude": latitude,
            "longitude": longitude,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
        ]

        guard let url = userDefaults.string(forKey: kSupabaseUrl),
              let anon = userDefaults.string(forKey: kSupabaseAnonKey),
              let token = userDefaults.string(forKey: kAccessToken),
              tokenIsFresh(token),
              let requestUrl = URL(string: "\(url)/rest/v1/location_tracking")
        else {
            bufferPoint(point)
            return
        }

        var request = URLRequest(url: requestUrl)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(anon, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: point)

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if error != nil || !(200..<300).contains(status) {
                self?.bufferPoint(point)
            }
        }.resume()
    }
}
