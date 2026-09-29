import Flutter
import UIKit
import AlarmKit
import CryptoKit
import SwiftUI
import AVFoundation

@available(iOS 26.0, *)
private struct ElychronAlarmMetadata: AlarmMetadata {}

enum NativeAlarmBridge {
    private static var player: AVAudioPlayer?

    static func register(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "celechron/alarm", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            if call.method == "start" {
                startSound()
                result(nil)
                return
            }
            if call.method == "stop" {
                stopSound()
                result(nil)
                return
            }
            if call.method == "openAppNotificationSettings" {
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                result(nil)
                return
            }
            guard #available(iOS 26.0, *) else {
                result(false)
                return
            }

            switch call.method {
            case "canSetSystemAlarm":
                result(AlarmManager.shared.authorizationState != .denied)
            case "setSystemAlarm", "scheduleTaskAlarm":
                guard let arguments = call.arguments as? [String: Any],
                      let millis = arguments["atMillis"] as? NSNumber,
                      let label = arguments["label"] as? String else {
                    result(false)
                    return
                }
                let id: UUID
                if call.method == "scheduleTaskAlarm" {
                    guard let uid = arguments["uid"] as? String else {
                        result(false)
                        return
                    }
                    id = taskID(uid)
                } else {
                    id = UUID()
                }
                Task { @MainActor in
                    result(await schedule(id: id, millis: millis.doubleValue, label: label))
                }
            case "cancelTaskAlarm":
                if let arguments = call.arguments as? [String: Any],
                   let uid = arguments["uid"] as? String {
                    try? AlarmManager.shared.cancel(id: taskID(uid))
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private static func startSound() {
        guard player == nil else { return }
        let key = FlutterDartProject.lookupKey(forAsset: "assets/sounds/ding.wav")
        guard let url = Bundle.main.url(forResource: key, withExtension: nil) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                             options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.numberOfLoops = -1
            audio.prepareToPlay()
            audio.play()
            player = audio
        } catch {
            NSLog("Elychron alarm sound failed: %@", String(describing: error))
        }
    }

    private static func stopSound() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false,
            options: .notifyOthersOnDeactivation)
    }

    private static func taskID(_ uid: String) -> UUID {
        if let id = UUID(uuidString: uid) { return id }
        let bytes = Array(SHA256.hash(data: Data(uid.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    @available(iOS 26.0, *)
    @MainActor
    private static func schedule(id: UUID, millis: Double, label: String) async -> Bool {
        let date = Date(timeIntervalSince1970: millis / 1000)
        guard date > Date() else { return false }
        let manager = AlarmManager.shared
        do {
            let state = manager.authorizationState == .notDetermined
                ? try await manager.requestAuthorization()
                : manager.authorizationState
            guard state == .authorized else { return false }

            let title = LocalizedStringResource(stringLiteral: label)
            let alert: AlarmPresentation.Alert
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(title: title)
            } else {
                let stop = AlarmButton(text: "停止", textColor: .white,
                                       systemImageName: "stop.fill")
                alert = AlarmPresentation.Alert(title: title, stopButton: stop)
            }
            let attributes = AlarmAttributes<ElychronAlarmMetadata>(
                presentation: AlarmPresentation(alert: alert), tintColor: .pink)
            let configuration = AlarmManager.AlarmConfiguration.alarm(
                schedule: .fixed(date), attributes: attributes)
            try? manager.cancel(id: id)
            _ = try await manager.schedule(id: id, configuration: configuration)
            return true
        } catch {
            NSLog("Elychron AlarmKit scheduling failed: %@", String(describing: error))
            return false
        }
    }
}
