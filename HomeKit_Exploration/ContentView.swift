import SwiftUI
import HomeKit

struct ContentView: View {
    @StateObject var homeKitManager = HomeKitManager()

    var body: some View {
        NavigationView {
            List {
                // Homes Section
                Section(header: Text("Homes")) {
                    ForEach(homeKitManager.homes, id: \.uniqueIdentifier) { home in
                        Button(action: {
                            homeKitManager.selectHome(home)
                        }) {
                            Text(home.name)
                                .fontWeight(homeKitManager.selectedHome == home ? .bold : .regular)
                        }
                    }
                }

                // Accessories Section
                Section(header: Text("Accessories")) {
                    ForEach(homeKitManager.accessories, id: \.uniqueIdentifier) { accessory in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(accessory.name)
                                .font(.headline)

                            // Show slider if window service found
                            if let windowService = accessory.services.first(where: { $0.serviceType == HMServiceTypeWindow }),
                               let targetChar = windowService.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeTargetPosition }) {
                                WindowPositionSlider(
                                    accessory: accessory,
                                    characteristic: targetChar,
                                    homeKitManager: homeKitManager
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Temperature Section
                Section(header: Text("Temperature")) {
                    if let temp = homeKitManager.temperature {
                        Text(String(format: "%.1f °C", temp))
                            .font(.largeTitle)
                    } else {
                        Text("No temperature data")
                    }
                }
            }
            .listStyle(GroupedListStyle())
            .navigationTitle("HomeKit Live")
        }
        .onAppear {
            if let firstHome = homeKitManager.homes.first {
                homeKitManager.selectHome(firstHome)
            }
        }
    }
}

// MARK: - WindowPositionSlider View

struct WindowPositionSlider: View {
    var accessory: HMAccessory
    var characteristic: HMCharacteristic

    @ObservedObject var homeKitManager: HomeKitManager

    @State private var sliderValue: Double = 0
    @State private var isEditing = false

    // Computed property for current window position in HomeKitManager
    private var windowPosition: Int? {
        homeKitManager.windowPositions[accessory.uniqueIdentifier]
    }

    var body: some View {
        VStack(alignment: .leading) {
            Slider(value: $sliderValue, in: 0...100, step: 1) { editing in
                isEditing = editing
                if !editing {
                    let pos = Int(sliderValue)
                    homeKitManager.setWindowPosition(accessory, to: pos)
                }
            }
            Text("Position: \(Int(sliderValue))%")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .onAppear {
            if let savedPos = windowPosition {
                sliderValue = Double(savedPos)
            } else if let currentValue = characteristic.value as? NSNumber {
                sliderValue = currentValue.doubleValue
            }
        }
        .onChange(of: windowPosition) { oldValue, newValue in
            guard !isEditing, let newPos = newValue else { return }
            sliderValue = Double(newPos)
        }

    }
}


// Preview

#Preview {
    ContentView()
}
