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
import AVFoundation

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
    
    // Audio measurement properties
    private var audioEngine: AVAudioEngine?
    private var audioInputNode: AVAudioInputNode?
    private var currentSoundLevel: Float = 0.0
    private var currentFrequency: Float = 0.0
    private var soundLevelTimer: Timer?
    
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
        locationManager.distanceFilter = kCLDistanceFilterNone // Update for any movement
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .fitness // Optimize for fitness tracking
        
        // Request appropriate authorization
        if CLLocationManager.authorizationStatus() == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        }
        
        // Setup audio measurement
        setupAudioMeasurement()
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
        
        // Remove any existing constraints
        tableview.constraints.forEach { $0.isActive = false }
        
        // Add new constraints
        NSLayoutConstraint.activate([
            tableview.topAnchor.constraint(equalTo: recordButton.bottomAnchor, constant: 16),
            tableview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableview.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupAudioMeasurement() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .mixWithOthers)
            try audioSession.setActive(true)
            
            audioEngine = AVAudioEngine()
            guard let inputNode = audioEngine?.inputNode else {
                print("Could not get audio input node")
                return
            }
            
            // Set up audio tap to measure levels
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
                guard let self = self else { return }
                
                // Calculate RMS (Root Mean Square) for sound level
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameLength = UInt32(buffer.frameLength)
                
                var sum: Float = 0.0
                for i in 0..<Int(frameLength) {
                    let sample = channelData[i]
                    sum += sample * sample
                }
                
                let rms = sqrt(sum / Float(frameLength))
                
                // Convert to dB
                let db = 20 * log10(rms)
                
                // Calculate sound intensity
                let intensity = pow(10, db / 20)
                
                // Update on main thread
                DispatchQueue.main.async {
                    self.currentSoundLevel = db
                    
                    // Calculate frequency
                    let maxIndex = self.findPeakFrequency(data: channelData, frameLength: frameLength)
                    self.currentFrequency = Float(maxIndex) * Float(format.sampleRate) / Float(frameLength)
                    
                    // Print real-time values
                    print("Sound Metrics - dB: \(String(format: "%.2f", db)) | Intensity: \(String(format: "%.4f", intensity)) | Frequency: \(String(format: "%.1f", self.currentFrequency)) Hz")
                }
            }
            
            try audioEngine?.start()
            print("Audio measurement started - Monitoring sound levels...")
            
        } catch {
            print("Failed to set up audio measurement: \(error)")
        }
    }
    
    private func findPeakFrequency(data: UnsafePointer<Float>, frameLength: UInt32) -> Int {
        var maxValue: Float = 0.0
        var maxIndex: Int = 0
        
        for i in 0..<Int(frameLength) {
            let value = abs(data[i])
            if value > maxValue {
                maxValue = value
                maxIndex = i
            }
        }
        
        return maxIndex
    }
    
    override func reloadTableData() {
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
        
        // Add location information to the table
        if let location = currentLocation {
            listData.append(cellRow(type: .normal, value: "Latitude: \(location.coordinate.latitude)"))
            listData.append(cellRow(type: .normal, value: "Longitude: \(location.coordinate.longitude)"))
            listData.append(cellRow(type: .normal, value: "Altitude: \(location.altitude)"))
            listData.append(cellRow(type: .normal, value: "Speed: \(location.speed) m/s"))
            listData.append(cellRow(type: .normal, value: "Accuracy: \(location.horizontalAccuracy) m"))
        } else {
            listData.append(cellRow(type: .normal, value: "Location: Not Available"))
        }
        
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
        
        // Add sound measurement information
        listData.append(cellRow(type: .normal, value: "Sound Level: \(String(format: "%.2f", currentSoundLevel)) dB"))
        listData.append(cellRow(type: .normal, value: "Sound Intensity: \(String(format: "%.4f", pow(10, currentSoundLevel / 20)))"))
        listData.append(cellRow(type: .normal, value: "Frequency: \(String(format: "%.1f", currentFrequency)) Hz"))
        
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
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }
        
        // Start location updates
        if CLLocationManager.authorizationStatus() == .authorizedWhenInUse || 
           CLLocationManager.authorizationStatus() == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
        
        // Create CSV file with headers
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = dir.appendingPathComponent("heartrate_location_data.csv")
            let header = "Timestamp,Heart Rate,Latitude,Longitude,Altitude,Speed(m/s),Sound Level(dB),Frequency(Hz),Sound Intensity,Sport Mode\n"
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
            
            // Calculate sound intensity
            let soundIntensity = pow(10, self.currentSoundLevel / 20)
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let reading = "\(dateFormatter.string(from: Date())),\(self.heartRate),\(latitude),\(longitude),\(altitude),\(speed),\(self.currentSoundLevel),\(self.currentFrequency),\(soundIntensity),\(mode)\n"
            
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
            
            // Update UI
            DispatchQueue.main.async {
                self.reloadTableData()
            }
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
            
            let filename = "heartrate_location_sound_\(mode)_\(timestamp).csv"
            let oldURL = dir.appendingPathComponent("heartrate_location_data.csv")
            let newURL = dir.appendingPathComponent(filename)
            
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
        guard let location = locations.last else { return }
        
        // Update the current location with the latest location
        currentLocation = location
        
        // Log the location update for debugging
        print("Location updated: Latitude: \(location.coordinate.latitude), Longitude: \(location.coordinate.longitude)")
        
        // Update UI on main thread
        DispatchQueue.main.async {
            self.reloadTableData()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
        
        // Show error to user if needed
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                print("Location access denied")
            case .locationUnknown:
                print("Location unknown")
            default:
                print("Location error: \(clError.localizedDescription)")
            }
        }
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
