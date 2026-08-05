import Foundation

public typealias DeviceMetadata = PushTokenPayload.PushToken.Attributes.MetaData

public struct PushTokenData: Equatable, Codable {
    public var pushToken: String
    public var pushEnablement: PushEnablement
    public var pushBackground: PushBackground
    public var deviceData: DeviceMetadata

    public init(
        pushToken: String,
        pushEnablement: PushEnablement,
        pushBackground: PushBackground,
        deviceData: DeviceMetadata
    ) {
        self.pushToken = pushToken
        self.pushEnablement = pushEnablement
        self.pushBackground = pushBackground
        self.deviceData = deviceData
    }
}
