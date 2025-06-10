import Foundation
import HomeKit
import Combine

class HomeKitManager: NSObject, ObservableObject, HMHomeManagerDelegate, HMAccessoryDelegate {
    @Published var homes: [HMHome] = []
    @Published var selectedHome: HMHome? = nil
    @Published var accessories: [HMAccessory] = []
    @Published var temperature: Double? = nil  // Celsius
    @Published var homeHubState: HMHomeHubState = .notAvailable

    
    // Keep track of window positions for UI syncing
    @Published var windowPositions: [UUID: Int] = [:]
    
    private var homeManager: HMHomeManager!

    override init() {
        super.init()
        homeManager = HMHomeManager()
        homeManager.delegate = self
    }

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        homes = manager.homes
        
        if let firstHome = homes.first {
            selectHome(firstHome)
            homeHubState = firstHome.homeHubState  // <-- Add this (redundant, but explicit)
        }
    }


    func selectHome(_ home: HMHome) {
        selectedHome = home
        accessories = home.accessories
        homeHubState = home.homeHubState  // <-- Add this
        logHubState(home.homeHubState)
        readTemperatureFromThermometer()
        observeWindows()
    }

    
    // MARK: - Temperature Sensor
    
    func readTemperatureFromThermometer() {
        guard let home = selectedHome else { return }
        
        for accessory in home.accessories {
            accessory.delegate = self
            
            if let tempService = accessory.services.first(where: { $0.serviceType == HMServiceTypeTemperatureSensor }) {
                if let tempCharacteristic = tempService.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeCurrentTemperature }) {
                    
                    tempCharacteristic.enableNotification(true) { error in
                        if let error = error {
                            print("Failed to enable notifications: \(error.localizedDescription)")
                            return
                        }
                        print("Enabled live temperature notifications.")
                    }
                    
                    tempCharacteristic.readValue { error in
                        if let error = error {
                            print("Failed to read temperature: \(error.localizedDescription)")
                            return
                        }
                        
                        if let tempValue = tempCharacteristic.value as? Double {
                            DispatchQueue.main.async {
                                self.temperature = tempValue
                                print("Current temperature: \(tempValue)°C")
                                self.handleTemperatureChange(tempValue)
                            }
                        }
                    }
                    return
                }
            }
        }
        print("No temperature sensor accessory found.")
    }
    
    // MARK: - Window Covering Control

    func observeWindows() {
        guard let home = selectedHome else { return }
        
        for accessory in home.accessories {
            accessory.delegate = self
            
            let windowServices = accessory.services.filter {
                $0.serviceType == HMServiceTypeWindow || $0.serviceType == HMServiceTypeWindowCovering
            }
            
            for service in windowServices {
                let positionChars = service.characteristics.filter {
                    $0.characteristicType == HMCharacteristicTypeCurrentPosition ||
                    $0.characteristicType == HMCharacteristicTypeTargetPosition
                }
                
                for characteristic in positionChars {
                    characteristic.enableNotification(true) { error in
                        if let error = error {
                            print("Error enabling notification for \(characteristic.characteristicType): \(error.localizedDescription)")
                        } else {
                            print("Enabled notifications for \(characteristic.characteristicType)")
                        }
                    }
                    
                    characteristic.readValue { error in
                        if let error = error {
                            print("Error reading \(characteristic.characteristicType): \(error.localizedDescription)")
                        } else if let position = characteristic.value as? Int {
                            DispatchQueue.main.async {
                                self.windowPositions[accessory.uniqueIdentifier] = position
                            }
                        }
                    }
                }
            }
        }
    }

    func setWindowPosition(_ accessory: HMAccessory, to position: Int) {
        guard let windowService = accessory.services.first(where: { $0.serviceType == HMServiceTypeWindow }) else {
            print("No window service found")
            return
        }
        
        guard let targetPositionChar = windowService.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeTargetPosition }) else {
            print("No target position characteristic found")
            return
        }
        
        targetPositionChar.writeValue(position) { error in
            if let error = error {
                print("Failed to set window position: \(error.localizedDescription)")
            } else {
                print("Window position set to \(position)%")
                DispatchQueue.main.async {
                    self.windowPositions[accessory.uniqueIdentifier] = position
                }
            }
        }
    }

    // MARK: - Automation Logic (No Home Hub)
    private func handleTemperatureChange(_ temperature: Double) {
        guard let home = selectedHome else { return }
        
        for accessory in home.accessories {
            if let windowService = accessory.services.first(where: { $0.serviceType == HMServiceTypeWindow }),
               let _ = windowService.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeTargetPosition }) {
                
                let targetPos = temperature < 20 ? 0 : 100
                setWindowPosition(accessory, to: targetPos)
            }
        }
    }

    // MARK: - HMAccessoryDelegate
    
    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        if characteristic.characteristicType == HMCharacteristicTypeCurrentTemperature {
            if let tempValue = characteristic.value as? Double {
                DispatchQueue.main.async {
                    self.temperature = tempValue
                    print("Live temperature update: \(tempValue)°C")
                    self.handleTemperatureChange(tempValue)
                }
            }
        }
        
        if characteristic.characteristicType == HMCharacteristicTypeCurrentPosition {
            if let pos = characteristic.value as? Int {
                DispatchQueue.main.async {
                    self.windowPositions[accessory.uniqueIdentifier] = pos
                    print("Live window position update: \(pos)%")
                }
            }
        }
    }
    
    private func logHubState(_ state: HMHomeHubState) {
        switch state {
        case .connected:
            print("Home Hub is connected.")
        case .disconnected:
            print("Home Hub is disconnected.")
        case .notAvailable:
            print("No Home Hub available.")
        @unknown default:
            print("Unknown Home Hub state.")
        }
    }

}
