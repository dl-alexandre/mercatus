import Foundation

public class TigerBeetleConfigValidator {
    public static func validateStartup(config: TigerBeetleConfig) throws {
        if config.enabled {
            if config.clusterId == 0 {
                throw SmartVestorError.configurationError("TigerBeetle clusterId cannot be zero when enabled")
            }
            if config.replicaAddresses.isEmpty {
                throw SmartVestorError.configurationError("TigerBeetle replicaAddresses cannot be empty when enabled")
            }
            for address in config.replicaAddresses {
                if address.isEmpty {
                    throw SmartVestorError.configurationError("TigerBeetle replica address cannot be empty")
                }
            }
        }
    }
}
