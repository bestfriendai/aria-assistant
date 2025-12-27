import Foundation

/// Smart home device model (HomeKit abstraction)
struct SmartHomeDevice: Identifiable, Codable, Hashable {
    let id: UUID
    let homeKitId: String

    var name: String
    var room: String?
    var type: DeviceType
    var manufacturer: String?
    var model: String?

    var isReachable: Bool
    var isPrimaryDevice: Bool

    var currentState: DeviceState
    var capabilities: [DeviceCapability]

    var lastUpdated: Date

    init(
        id: UUID = UUID(),
        homeKitId: String,
        name: String,
        room: String? = nil,
        type: DeviceType,
        manufacturer: String? = nil,
        model: String? = nil,
        isReachable: Bool = true,
        isPrimaryDevice: Bool = false,
        currentState: DeviceState = DeviceState(),
        capabilities: [DeviceCapability] = [],
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.homeKitId = homeKitId
        self.name = name
        self.room = room
        self.type = type
        self.manufacturer = manufacturer
        self.model = model
        self.isReachable = isReachable
        self.isPrimaryDevice = isPrimaryDevice
        self.currentState = currentState
        self.capabilities = capabilities
        self.lastUpdated = lastUpdated
    }

    var icon: String {
        type.icon
    }
}

enum DeviceType: String, Codable, CaseIterable {
    case light
    case thermostat
    case lock
    case doorbell
    case camera
    case switch_
    case outlet
    case fan
    case garageDoor = "garage_door"
    case blinds
    case speaker
    case television
    case sensor
    case securitySystem = "security_system"
    case other

    var icon: String {
        switch self {
        case .light: return "lightbulb.fill"
        case .thermostat: return "thermometer"
        case .lock: return "lock.fill"
        case .doorbell: return "bell.fill"
        case .camera: return "video.fill"
        case .switch_: return "switch.2"
        case .outlet: return "poweroutlet.fill"
        case .fan: return "fan.fill"
        case .garageDoor: return "door.garage.closed"
        case .blinds: return "blinds.horizontal.closed"
        case .speaker: return "hifispeaker.fill"
        case .television: return "tv.fill"
        case .sensor: return "sensor.fill"
        case .securitySystem: return "shield.fill"
        case .other: return "house.fill"
        }
    }

    var displayName: String {
        switch self {
        case .switch_: return "Switch"
        case .garageDoor: return "Garage Door"
        case .securitySystem: return "Security System"
        default: return rawValue.capitalized
        }
    }
}

struct DeviceState: Codable, Hashable {
    // Power
    var isOn: Bool?

    // Light
    var brightness: Int? // 0-100
    var colorTemperature: Int? // Kelvin
    var hue: Double? // 0-360
    var saturation: Double? // 0-100

    // Thermostat
    var currentTemperature: Double?
    var targetTemperature: Double?
    var heatingCoolingMode: HeatingCoolingMode?
    var humidity: Double?

    // Lock
    var isLocked: Bool?
    var isJammed: Bool?

    // Door/Window
    var isOpen: Bool?
    var openPercentage: Int? // 0-100 for blinds, garage doors

    // Security
    var securityState: SecurityState?

    // Sensor
    var motionDetected: Bool?
    var contactState: Bool? // true = closed
    var batteryLevel: Int?

    // Camera
    var isStreaming: Bool?
    var hasMotion: Bool?

    init(
        isOn: Bool? = nil,
        brightness: Int? = nil,
        colorTemperature: Int? = nil,
        hue: Double? = nil,
        saturation: Double? = nil,
        currentTemperature: Double? = nil,
        targetTemperature: Double? = nil,
        heatingCoolingMode: HeatingCoolingMode? = nil,
        humidity: Double? = nil,
        isLocked: Bool? = nil,
        isJammed: Bool? = nil,
        isOpen: Bool? = nil,
        openPercentage: Int? = nil,
        securityState: SecurityState? = nil,
        motionDetected: Bool? = nil,
        contactState: Bool? = nil,
        batteryLevel: Int? = nil,
        isStreaming: Bool? = nil,
        hasMotion: Bool? = nil
    ) {
        self.isOn = isOn
        self.brightness = brightness
        self.colorTemperature = colorTemperature
        self.hue = hue
        self.saturation = saturation
        self.currentTemperature = currentTemperature
        self.targetTemperature = targetTemperature
        self.heatingCoolingMode = heatingCoolingMode
        self.humidity = humidity
        self.isLocked = isLocked
        self.isJammed = isJammed
        self.isOpen = isOpen
        self.openPercentage = openPercentage
        self.securityState = securityState
        self.motionDetected = motionDetected
        self.contactState = contactState
        self.batteryLevel = batteryLevel
        self.isStreaming = isStreaming
        self.hasMotion = hasMotion
    }
}

enum HeatingCoolingMode: String, Codable {
    case off
    case heat
    case cool
    case auto
}

enum SecurityState: String, Codable {
    case disarmed
    case armedHome = "armed_home"
    case armedAway = "armed_away"
    case armedNight = "armed_night"
    case triggered
}

enum DeviceCapability: String, Codable {
    case onOff = "on_off"
    case brightness
    case colorTemperature = "color_temperature"
    case color
    case thermostat
    case lock
    case openClose = "open_close"
    case percentage
    case security
    case motionSensor = "motion_sensor"
    case contactSensor = "contact_sensor"
    case camera
    case doorbell
    case battery
}

/// Smart home scene/automation
struct SmartHomeScene: Identifiable, Codable, Hashable {
    let id: UUID
    let homeKitId: String
    var name: String
    var icon: String?
    var actions: [SceneAction]

    init(
        id: UUID = UUID(),
        homeKitId: String,
        name: String,
        icon: String? = nil,
        actions: [SceneAction] = []
    ) {
        self.id = id
        self.homeKitId = homeKitId
        self.name = name
        self.icon = icon
        self.actions = actions
    }
}

struct SceneAction: Codable, Hashable {
    let deviceId: String
    let deviceName: String
    let targetState: DeviceState
}

/// Room grouping
struct SmartHomeRoom: Identifiable, Codable, Hashable {
    let id: UUID
    let homeKitId: String
    var name: String
    var devices: [SmartHomeDevice]

    var lightsOn: Int {
        devices.filter { $0.type == .light && $0.currentState.isOn == true }.count
    }

    var totalLights: Int {
        devices.filter { $0.type == .light }.count
    }
}

/// Home structure
struct SmartHome: Identifiable, Codable, Hashable {
    let id: UUID
    let homeKitId: String
    var name: String
    var rooms: [SmartHomeRoom]
    var scenes: [SmartHomeScene]
    var isPrimary: Bool

    var allDevices: [SmartHomeDevice] {
        rooms.flatMap { $0.devices }
    }
}
