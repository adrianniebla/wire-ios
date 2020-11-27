//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import Foundation
import WireDataModel
import LocalAuthentication

private let zmLog = ZMSLog(tag: "UI")
private let UserDefaultsDomainStateKey = "DomainStateKey"

public class AppLock {
    // Returns true if user enabled the app lock feature.
    
    public static var rules = AppLockRules.fromBundle()

    public static var isActive: Bool {
        get {
            guard !rules.forceAppLock else { return true }
            guard let data = ZMKeychain.data(forAccount: SettingsPropertyName.lockApp.rawValue),
                data.count != 0 else {
                    return false
            }
            
            return String(data: data, encoding: .utf8) == "YES"
        }
        set {
            guard !rules.forceAppLock else { return }
            let data = (newValue ? "YES" : "NO").data(using: .utf8)!
            ZMKeychain.setData(data, forAccount: SettingsPropertyName.lockApp.rawValue)
        }
    }
    
    // Returns the time since last lock happened.
    public static var lastUnlockedDate: Date = Date(timeIntervalSince1970: 0)
    
    public enum AuthenticationResult {
        /// User sucessfully authenticated
        case granted
        /// User failed to authenticate or cancelled the request
        case denied
        /// There's no authenticated method available (no passcode is set)
        case unavailable
        /// Biometrics failed and account password is needed instead of device PIN
        case needAccountPassword
    }
    
    public enum AuthenticationScenario {
        case screenLock(requireBiometrics: Bool, grantAccessIfPolicyCannotBeEvaluated: Bool)
        case databaseLock
        
        var policy: LAPolicy {
            switch self {
            case .screenLock(requireBiometrics: let requireBiometrics, grantAccessIfPolicyCannotBeEvaluated: _):
                return requireBiometrics ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
            case .databaseLock:
                return .deviceOwnerAuthentication
                
            }
        }
        
        var supportsUserFallback: Bool {
            if case .screenLock(requireBiometrics: true, grantAccessIfPolicyCannotBeEvaluated: _) = self {
                return true
            }
            
            return false
        }
        
        var grantAccessIfPolicyCannotBeEvaluated: Bool {
            if case .screenLock(requireBiometrics: _, grantAccessIfPolicyCannotBeEvaluated: true) = self {
                return true
            }
            
            return false
        }
                
    }

    /// a weak reference to LAContext, it should be nil when evaluatePolicy is done.
    public static weak var weakLAContext: LAContext? = nil // TODO jacob make private again
    
    // Creates a new LAContext and evaluates the authentication settings of the user.
    public class func evaluateAuthentication(scenario: AuthenticationScenario,
                                             description: String,
                                             with callback: @escaping (AuthenticationResult, LAContext) -> Void) {
        guard AppLock.weakLAContext == nil else { return }

        let context: LAContext = LAContext()
        var error: NSError?

        AppLock.weakLAContext = context
        
        let canEvaluatePolicy = context.canEvaluatePolicy(scenario.policy, error: &error)
                
        if scenario.supportsUserFallback && (BiometricsState.biometricsChanged(in: context) || !canEvaluatePolicy) {
            callback(.needAccountPassword, context)
            return
        }

        if canEvaluatePolicy {
            context.evaluatePolicy(scenario.policy, localizedReason: description, reply: { (success, error) -> Void in
                var authResult: AuthenticationResult = success ? .granted : .denied
            
                if scenario.supportsUserFallback, let laError = error as? LAError, laError.code == .userFallback {
                    authResult = .needAccountPassword
                }
                
                callback(authResult, context)
            })
        } else {
            // If the policy can't be evaluated automatically grant access unless app lock
            // is a requirement to run the app. This will for example allow a user to access
            // the app if he/she has disabled his/her passcode.
            callback(scenario.grantAccessIfPolicyCannotBeEvaluated ? .granted : .unavailable, context)
            zmLog.error("Local authentication error: \(String(describing: error?.localizedDescription))")
        }
    }
    
    public class func persistBiometrics() {
        BiometricsState.persist()
    }
}

public struct AppLockRules: Codable {
    public let useBiometricsOrAccountPassword: Bool
    public let useCustomCodeInsteadOfAccountPassword: Bool
    public let forceAppLock: Bool
    public let appLockTimeout: UInt
    public let isEnabled: Bool
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        useBiometricsOrAccountPassword = try container.decode(Bool.self, forKey: .useBiometricsOrAccountPassword)
        useCustomCodeInsteadOfAccountPassword = try container.decode(Bool.self, forKey: .useCustomCodeInsteadOfAccountPassword)
        forceAppLock = try container.decode(Bool.self, forKey: .forceAppLock)
        appLockTimeout = try container.decode(UInt.self, forKey: .appLockTimeout)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
    
    public static func fromBundle() -> AppLockRules {
        if let fileURL = Bundle.main.url(forResource: "session_manager", withExtension: "json"),
            let fileData = try? Data(contentsOf: fileURL) {
            return fromData(fileData)
        } else {
            fatalError("session_manager.json not exist")
        }
    }
    
    public static func fromData(_ data: Data) -> AppLockRules {
        let decoder = JSONDecoder()
        return try! decoder.decode(AppLockRules.self, from: data)
    }
}

// MARK: - For testing purposes
extension AppLockRules {
    init(useBiometricsOrAccountPassword: Bool,
         useCustomCodeInsteadOfAccountPassword: Bool,
         forceAppLock: Bool,
         appLockTimeout: UInt) {
        self.useBiometricsOrAccountPassword = useBiometricsOrAccountPassword
        self.useCustomCodeInsteadOfAccountPassword = useCustomCodeInsteadOfAccountPassword
        self.forceAppLock = forceAppLock
        self.appLockTimeout = appLockTimeout
        self.isEnabled = true
    }
}
