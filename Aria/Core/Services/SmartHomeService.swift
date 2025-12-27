import Foundation
import HomeKit

/// Smart home service using HomeKit
actor SmartHomeService {
    // MARK: - HomeKit

    private let homeManager = HMHomeManager()
    private var homes: [HMHome] = []
    private var primaryHome: HMHome?

    // MARK: - Cache

    private var devicesCache: [SmartHomeDevice] = []
    private var scenesCache: [SmartHomeScene] = []
    private var roomsCache: [SmartHomeRoom] = []

    // MARK: - Initialization

    func initialize() async throws {
        // HomeKit requires delegation setup
        // In a real implementation, this would be handled via delegate pattern
        homes = homeManager.homes
        primaryHome = homeManager.primaryHome

        await refreshDevices()
    }

    // MARK: - Homes & Rooms

    func getHomes() -> [SmartHome] {
        homes.map { home in
            SmartHome(
                id: UUID(),
                homeKitId: home.uniqueIdentifier.uuidString,
                name: home.name,
                rooms: mapRooms(home.rooms),
                scenes: [], // Would map HMActionSet
                isPrimary: home == primaryHome
            )
        }
    }

    func getRooms() -> [SmartHomeRoom] {
        roomsCache
    }

    private func mapRooms(_ rooms: [HMRoom]) -> [SmartHomeRoom] {
        rooms.map { room in
            SmartHomeRoom(
                id: UUID(),
                homeKitId: room.uniqueIdentifier.uuidString,
                name: room.name,
                devices: room.accessories.flatMap { mapAccessory($0) }
            )
        }
    }

    // MARK: - Devices

    func getDevices(inRoom room: String? = nil, ofType type: DeviceType? = nil) async -> [SmartHomeDevice] {
        var devices = devicesCache

        if let room = room {
            devices = devices.filter { $0.room == room }
        }

        if let type = type {
            devices = devices.filter { $0.type == type }
        }

        return devices
    }

    func getDevice(named name: String) async -> SmartHomeDevice? {
        devicesCache.first { $0.name.lowercased().contains(name.lowercased()) }
    }

    func refreshDevices() async {
        guard let home = primaryHome else { return }

        var devices: [SmartHomeDevice] = []

        for accessory in home.accessories {
            let mappedDevices = mapAccessory(accessory)
            devices.append(contentsOf: mappedDevices)
        }

        devicesCache = devices

        // Update rooms cache
        roomsCache = mapRooms(home.rooms)
    }

    private func mapAccessory(_ accessory: HMAccessory) -> [SmartHomeDevice] {
        accessory.services.compactMap { service -> SmartHomeDevice? in
            guard service.serviceType != HMServiceTypeAccessoryInformation else { return nil }

            let type = mapServiceType(service.serviceType)
            let state = readCurrentState(from: service)
            let capabilities = mapCapabilities(from: service)

            return SmartHomeDevice(
                homeKitId: service.uniqueIdentifier.uuidString,
                name: service.name,
                room: accessory.room?.name,
                type: type,
                manufacturer: accessory.manufacturer,
                model: accessory.model,
                isReachable: accessory.isReachable,
                currentState: state,
                capabilities: capabilities
            )
        }
    }

    private func mapServiceType(_ type: String) -> DeviceType {
        switch type {
        case HMServiceTypeLightbulb: return .light
        case HMServiceTypeThermostat: return .thermostat
        case HMServiceTypeLockMechanism: return .lock
        case HMServiceTypeDoorbell: return .doorbell
        case HMServiceTypeSwitch: return .switch_
        case HMServiceTypeOutlet: return .outlet
        case HMServiceTypeFan: return .fan
        case HMServiceTypeGarageDoorOpener: return .garageDoor
        case HMServiceTypeWindowCovering: return .blinds
        case HMServiceTypeSecuritySystem: return .securitySystem
        case HMServiceTypeMotionSensor: return .sensor
        case HMServiceTypeContactSensor: return .sensor
        default: return .other
        }
    }

    private func readCurrentState(from service: HMService) -> DeviceState {
        var state = DeviceState()

        for characteristic in service.characteristics {
            switch characteristic.characteristicType {
            case HMCharacteristicTypePowerState:
                state.isOn = characteristic.value as? Bool

            case HMCharacteristicTypeBrightness:
                state.brightness = characteristic.value as? Int

            case HMCharacteristicTypeHue:
                state.hue = characteristic.value as? Double

            case HMCharacteristicTypeSaturation:
                state.saturation = characteristic.value as? Double

            case HMCharacteristicTypeCurrentTemperature:
                state.currentTemperature = characteristic.value as? Double

            case HMCharacteristicTypeTargetTemperature:
                state.targetTemperature = characteristic.value as? Double

            case HMCharacteristicTypeLockMechanismLastKnownAction,
                 HMCharacteristicTypeLockCurrentState:
                if let value = characteristic.value as? Int {
                    state.isLocked = value == 1 // 1 = secured
                }

            case HMCharacteristicTypeCurrentDoorState:
                if let value = characteristic.value as? Int {
                    state.isOpen = value == 0 // 0 = open
                }

            case HMCharacteristicTypeMotionDetected:
                state.motionDetected = characteristic.value as? Bool

            case HMCharacteristicTypeContactState:
                state.contactState = characteristic.value as? Bool

            case HMCharacteristicTypeBatteryLevel:
                state.batteryLevel = characteristic.value as? Int

            default:
                break
            }
        }

        return state
    }

    private func mapCapabilities(from service: HMService) -> [DeviceCapability] {
        var capabilities: [DeviceCapability] = []

        for characteristic in service.characteristics {
            switch characteristic.characteristicType {
            case HMCharacteristicTypePowerState:
                capabilities.append(.onOff)
            case HMCharacteristicTypeBrightness:
                capabilities.append(.brightness)
            case HMCharacteristicTypeHue, HMCharacteristicTypeSaturation:
                if !capabilities.contains(.color) {
                    capabilities.append(.color)
                }
            case HMCharacteristicTypeColorTemperature:
                capabilities.append(.colorTemperature)
            case HMCharacteristicTypeTargetTemperature:
                capabilities.append(.thermostat)
            case HMCharacteristicTypeLockTargetState:
                capabilities.append(.lock)
            case HMCharacteristicTypeTargetDoorState:
                capabilities.append(.openClose)
            case HMCharacteristicTypeMotionDetected:
                capabilities.append(.motionSensor)
            case HMCharacteristicTypeContactState:
                capabilities.append(.contactSensor)
            case HMCharacteristicTypeBatteryLevel:
                capabilities.append(.battery)
            default:
                break
            }
        }

        return capabilities
    }

    // MARK: - Control

    func turnOn(device: SmartHomeDevice) async throws {
        try await setDeviceState(device, isOn: true)
    }

    func turnOff(device: SmartHomeDevice) async throws {
        try await setDeviceState(device, isOn: false)
    }

    func toggle(device: SmartHomeDevice) async throws {
        let newState = !(device.currentState.isOn ?? false)
        try await setDeviceState(device, isOn: newState)
    }

    func setDeviceState(_ device: SmartHomeDevice, isOn: Bool? = nil, brightness: Int? = nil) async throws {
        guard let home = primaryHome,
              let accessory = findAccessory(device.homeKitId, in: home),
              let service = findService(device.homeKitId, in: accessory) else {
            throw SmartHomeError.deviceNotFound
        }

        if let isOn = isOn {
            if let powerChar = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypePowerState }) {
                try await powerChar.writeValue(isOn)
            }
        }

        if let brightness = brightness {
            if let brightnessChar = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeBrightness }) {
                try await brightnessChar.writeValue(brightness)
            }
        }

        await refreshDevices()
    }

    func setBrightness(_ device: SmartHomeDevice, level: Int) async throws {
        try await setDeviceState(device, brightness: min(100, max(0, level)))
    }

    func setThermostat(_ device: SmartHomeDevice, temperature: Double, mode: HeatingCoolingMode? = nil) async throws {
        guard let home = primaryHome,
              let accessory = findAccessory(device.homeKitId, in: home),
              let service = findService(device.homeKitId, in: accessory) else {
            throw SmartHomeError.deviceNotFound
        }

        if let targetTemp = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeTargetTemperature }) {
            try await targetTemp.writeValue(temperature)
        }

        if let mode = mode,
           let modeChar = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeTargetHeatingCoolingState }) {
            let modeValue: Int = switch mode {
            case .off: 0
            case .heat: 1
            case .cool: 2
            case .auto: 3
            }
            try await modeChar.writeValue(modeValue)
        }

        await refreshDevices()
    }

    func lock(_ device: SmartHomeDevice) async throws {
        try await setLockState(device, locked: true)
    }

    func unlock(_ device: SmartHomeDevice) async throws {
        try await setLockState(device, locked: false)
    }

    private func setLockState(_ device: SmartHomeDevice, locked: Bool) async throws {
        guard let home = primaryHome,
              let accessory = findAccessory(device.homeKitId, in: home),
              let service = findService(device.homeKitId, in: accessory),
              let lockChar = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypeLockTargetState }) else {
            throw SmartHomeError.deviceNotFound
        }

        try await lockChar.writeValue(locked ? 1 : 0)
        await refreshDevices()
    }

    // MARK: - Room Control

    func turnOnRoom(_ roomName: String) async throws {
        let devices = await getDevices(inRoom: roomName, ofType: .light)
        for device in devices {
            try? await turnOn(device: device)
        }
    }

    func turnOffRoom(_ roomName: String) async throws {
        let devices = await getDevices(inRoom: roomName, ofType: .light)
        for device in devices {
            try? await turnOff(device: device)
        }
    }

    // MARK: - Scenes

    func getScenes() -> [SmartHomeScene] {
        scenesCache
    }

    func executeScene(_ scene: SmartHomeScene) async throws {
        guard let home = primaryHome,
              let actionSet = home.actionSets.first(where: { $0.uniqueIdentifier.uuidString == scene.homeKitId }) else {
            throw SmartHomeError.sceneNotFound
        }

        try await home.executeActionSet(actionSet)
    }

    func executeScene(named name: String) async throws {
        guard let scene = scenesCache.first(where: { $0.name.lowercased() == name.lowercased() }) else {
            throw SmartHomeError.sceneNotFound
        }
        try await executeScene(scene)
    }

    // MARK: - Helpers

    private func findAccessory(_ serviceId: String, in home: HMHome) -> HMAccessory? {
        for accessory in home.accessories {
            if accessory.services.contains(where: { $0.uniqueIdentifier.uuidString == serviceId }) {
                return accessory
            }
        }
        return nil
    }

    private func findService(_ serviceId: String, in accessory: HMAccessory) -> HMService? {
        accessory.services.first { $0.uniqueIdentifier.uuidString == serviceId }
    }

    // MARK: - Status Queries

    func areAllLightsOff(inRoom room: String? = nil) async -> Bool {
        let lights = await getDevices(inRoom: room, ofType: .light)
        return lights.allSatisfy { $0.currentState.isOn != true }
    }

    func areAllDoorsLocked() async -> Bool {
        let locks = await getDevices(ofType: .lock)
        return locks.allSatisfy { $0.currentState.isLocked == true }
    }

    func getCurrentTemperature() async -> Double? {
        let thermostats = await getDevices(ofType: .thermostat)
        return thermostats.first?.currentState.currentTemperature
    }

    func getOpenDoors() async -> [SmartHomeDevice] {
        await getDevices(ofType: .lock).filter { $0.currentState.isOpen == true }
    }
}

// MARK: - Errors

enum SmartHomeError: Error, LocalizedError {
    case notConfigured
    case deviceNotFound
    case sceneNotFound
    case controlFailed
    case noHomeConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Smart home not configured"
        case .deviceNotFound: return "Device not found"
        case .sceneNotFound: return "Scene not found"
        case .controlFailed: return "Failed to control device"
        case .noHomeConfigured: return "No home configured in HomeKit"
        }
    }
}
