//
//  dataViewController.swift
//  Demo
//
//  Created by Scosche on 2/15/19.
//  Copyright © 2019 Scosche. All rights reserved.
//

import Foundation
import ScoscheSDK24
import CoreBluetooth
import UIKit
import CoreLocation

/// dataViewController: Demo of connecting to a Scosche devices with BLE interface. View uses ScoscheViewController to extend a standard UIViewController with services that report monitor activity.
///
/// - Parameter monitor: ScoscheMonitor
class dataViewController: SchoscheViewController, UITableViewDelegate, UITableViewDataSource, CBCentralManagerDelegate, CBPeripheralDelegate, CLLocationManagerDelegate {
    //MARK:- IB Refs
    
    @IBOutlet var tableview: UITableView!
    private var recordButton: UIButton!
    
    // set cell type
    enum cellType {
        case normal
        case user
        case mode
        case fit
    }
    // combine cell type with string for display
    struct cellRow {
        let type: cellType
        let value: String
    }
    
    //MARK:- Local Vars
    var listData: [cellRow] = []
    var returnState: cellType = .normal
    
    // Recording variables
    private var recordingTimer: Timer?
    private var startTime: Date?
    private var heartRateReadings: [(time: Date, hr: Int)] = []
    
    // Location variables
    var locationManager: CLLocationManager!
    var currentLocation: CLLocation?
    
    // Add backgroundTask as a class property
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    //MARK:- Functions
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        ScoscheDeviceConnect(monitor: monitor, monitorView: self)
        listData.append(cellRow(type: .normal, value: "Start Up: \(monitor.deviceName ?? "Unknown")"))
        
        // Create and setup record button
        setupRecordButton()
        
        // Setup location manager
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.requestAlwaysAuthorization()
    }
    
    private func setupRecordButton() {
        // Create button
        recordButton = UIButton(type: .system)
        recordButton.setTitle("Start Recording", for: .normal)
        recordButton.backgroundColor = .systemBlue
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.layer.cornerRadius = 8
        
        // Add button to view
        view.addSubview(recordButton)
        
        // Setup constraints
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            recordButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            recordButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            recordButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            recordButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // Add target action
        recordButton.addTarget(self, action: #selector(recordButtonTapped(_:)), for: .touchUpInside)
        
        // Adjust table view constraints
        tableview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableview.topAnchor.constraint(equalTo: recordButton.bottomAnchor, constant: 16),
            tableview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableview.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    override func reloadTableData(){
        listData = []
        listData.append(cellRow(type: .normal, value: "Sensor Name: \(monitor.deviceName ?? "Unknown")"))
        if monitor.r24SportMode != nil {
            listData.append(cellRow(type: .mode, value: "Sport Mode: \(sportMode)"))
        }
        listData.append(cellRow(type: .normal, value: "Connection Status: \(connected)"))
        listData.append(cellRow(type: .normal, value: "Heart Rate: \(heartRate)"))
        listData.append(cellRow(type: .normal, value: "RR Interval: \(rrInterval)"))
        listData.append(cellRow(type: .normal, value: "Signal Quality: \(signalQuality)"))
        listData.append(cellRow(type: .normal, value: "Battery Level: \(batteryLevel)"))
        listData.append(cellRow(type: .user, value: "User Name: \(userInfo.name)"))
        listData.append(cellRow(type: .user, value: "Resting Heart Rate: \(userInfo.restinghr)"))
        listData.append(cellRow(type: .user, value: "Maximum Heart Rate: \(userInfo.maxhr)"))
        listData.append(cellRow(type: .user, value: "Gender: \(userInfo.gender)"))
        listData.append(cellRow(type: .user, value: "Age in Months: \(userInfo.age)"))
        listData.append(cellRow(type: .user, value: "Weight: \(userInfo.weight)"))
        listData.append(cellRow(type: .user, value: "Height: \(userInfo.height)"))
        listData.append(cellRow(type: .normal, value: "Zone One: \(userInfo.hrZoneOne)"))
        listData.append(cellRow(type: .normal, value: "Zone Two: \(userInfo.hrZoneTwo)"))
        listData.append(cellRow(type: .normal, value: "Zone Three: \(userInfo.hrZoneThree)"))
        listData.append(cellRow(type: .normal, value: "Zone Four: \(userInfo.hrZoneFour)"))
        if fitFileList.count == 0 {
            listData.append(cellRow(type: .normal, value: "FitFile Count: \(fitFileList.count)"))
        } else {
            listData.append(cellRow(type: .fit, value: "FitFile Count: \(fitFileList.count)"))
        }
        
        listData.append(cellRow(type: .normal, value: "VDC Signal: \(vdcSignal)"))
        listData.append(cellRow(type: .normal, value: "VDC Optical: \(vdcOptical)"))
        listData.append(cellRow(type: .normal, value: "VDC Heart Rate: \(vdcHeartRate)"))
        listData.append(cellRow(type: .normal, value: "VDC Step Rate: \(vdcStepRate)"))
        listData.append(cellRow(type: .normal, value: "VDC Stride Rate: \(vdcStrideRate)"))
        listData.append(cellRow(type: .normal, value: "VDC Distance: \(vdcDistance)"))
        listData.append(cellRow(type: .normal, value: "VDC Calories: \(vdcTotalCalories)"))
        listData.append(cellRow(type: .normal, value: "VDC Data 1: \(vdcRRIDataRegister1)"))
        listData.append(cellRow(type: .normal, value: "VDC Data 2: \(vdcRRIDataRegister2)"))
        listData.append(cellRow(type: .normal, value: "VDC Data 3: \(vdcRRIDataRegister3)"))
        listData.append(cellRow(type: .normal, value: "VDC Data 4: \(vdcRRIDataRegister4)"))
        listData.append(cellRow(type: .normal, value: "VDC Data 5: \(vdcRRIDataRegister5)"))
        listData.append(cellRow(type: .normal, value: "VDC Data Timestamp: \(vdcRRITimestamp)"))
        listData.append(cellRow(type: .normal, value: "VDC Data Status: \(vdcRRIStatus)"))
        tableview.reloadData()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "gotoWorkout" {
            if let destinationVC = segue.destination as? workoutViewController {
                destinationVC.fitFileList = fitFileList
            }
        }
        if segue.identifier == "gotoUser" {
            if let destinationVC = segue.destination as? userViewController {
                destinationVC.tempUserInfo = userInfo
            }
        }
        if segue.identifier == "gotoMode" {
            if let destinationVC = segue.destination as? modeViewController {
                destinationVC.tempMode = sportMode
            }
        }
    }
    
    @IBAction func unwindToData(_ unwindSegue: UIStoryboardSegue) {
        print("Unwind to data view")
        
        if returnState == .user {
            ScoscheDeviceUpdateInfo(monitor: monitor, userInfo: userInfo)
            ScoscheUserInfoWrite(userInfo: userInfo)
        }
        if returnState == .mode {
            self.onModeChangeAction?(sportMode)
        }
        reloadTableData()
    }
    
    //MARK:- Table
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return listData.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = listData[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath as IndexPath) as! dataTableViewCell
        cell.header.text = row.value
        if row.type == .normal {
            cell.accessoryType = .none
        } else {
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = listData[indexPath.row]
        if row.type == .fit {
           self.performSegue(withIdentifier: "gotoWorkout", sender: nil)
        }
        if row.type == .user {
            self.performSegue(withIdentifier: "gotoUser", sender: nil)
        }
        if row.type == .mode {
            self.performSegue(withIdentifier: "gotoMode", sender: nil)
        }
    }
    
    @objc private func recordButtonTapped(_ sender: UIButton) {
        if sender.title(for: .normal) == "Start Recording" {
            startRecording()
        } else {
            stopRecording()
        }
    }
    
    private func startRecording() {
        heartRateReadings.removeAll()
        startTime = Date()
        recordButton.setTitle("Stop Recording", for: .normal)
        
        // Request background execution time
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "RecordingTask") {
            // Clean up if the task expires
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }
        
        // Ensure location updates are active
        if CLLocationManager.authorizationStatus() == .authorizedWhenInUse {
            locationManager.startUpdatingLocation()
        }
        
        // Create CSV file with headers
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = dir.appendingPathComponent("heartrate_location_data.csv")
            let header = "Timestamp,Heart Rate,Latitude,Longitude,Altitude,Speed(m/s),Sport Mode\n"
            try? header.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        
        // Start recording timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            
            let location = self.currentLocation
            let latitude = location?.coordinate.latitude ?? 0.0
            let longitude = location?.coordinate.longitude ?? 0.0
            let altitude = location?.altitude ?? 0.0
            let speed = location?.speed ?? 0.0
            let mode = self.monitor.r24SportMode != nil ? self.sportMode.rawValue.description : "Standard"
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let reading = "\(dateFormatter.string(from: Date())),\(self.heartRate),\(latitude),\(longitude),\(altitude),\(speed),\(mode)\n"
            
            // Save the reading to file
            if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = dir.appendingPathComponent("heartrate_location_data.csv")
                
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(reading.data(using: .utf8) ?? Data())
                    handle.closeFile()
                }
            }
            
            // Record heart rate
            self.heartRateReadings.append((Date(), self.heartRate))
        }
    }
    
    private func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordButton.setTitle("Start Recording", for: .normal)
        
        // Stop location updates
        locationManager.stopUpdatingLocation()
        
        // End background task
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        
        // Get the current mode for the filename
        let mode = monitor.r24SportMode != nil ? sportMode.rawValue.description : "Standard"
        
        // Show results and file location
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = dateFormatter.string(from: Date())
            
            // Include mode in filename
            let filename = "heartrate_location_\(mode)_\(timestamp).csv"
            let oldURL = dir.appendingPathComponent("heartrate_location_data.csv")
            let newURL = dir.appendingPathComponent(filename)
            
            // Rename the file to include the mode and timestamp
            try? FileManager.default.moveItem(at: oldURL, to: newURL)
            
            let alert = UIAlertController(
                title: "Recording Complete",
                message: "Data has been saved as:\n\(filename)\nMode: \(mode)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Share", style: .default) { _ in
                let activityVC = UIActivityViewController(
                    activityItems: [newURL],
                    applicationActivities: nil
                )
                self.present(activityVC, animated: true)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            present(alert, animated: true)
        }
    }
    
    // MARK: - Location Manager Delegate Methods
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location access granted")
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            print("Location access denied")
            // Alert the user that location access is needed
            let alert = UIAlertController(
                title: "Location Access Required",
                message: "Please enable location access in Settings to track location data with heart rate.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        case .notDetermined:
            print("Location access not determined")
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            print("Unknown location authorization status")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Update the current location with the latest location
        currentLocation = locations.last
        print("Location updated: \(String(describing: currentLocation?.coordinate))")
        
        // Log the location update for debugging
        if let location = currentLocation {
            print("Latitude: \(location.coordinate.latitude), Longitude: \(location.coordinate.longitude)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }
    
    // MARK: - CBCentralManagerDelegate Methods
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // Bluetooth is on and ready
            break
        case .poweredOff:
            print("Bluetooth is powered off")
        case .resetting:
            print("Bluetooth is resetting")
        case .unauthorized:
            print("Bluetooth is unauthorized")
        case .unsupported:
            print("Bluetooth is not supported")
        case .unknown:
            print("Bluetooth state is unknown")
        @unknown default:
            print("Unknown Bluetooth state")
        }
    }
}
