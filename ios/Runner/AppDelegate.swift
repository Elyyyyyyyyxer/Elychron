import Flutter
import UIKit
import WidgetKit
import workmanager
import flutter_local_notifications

extension FlutterError: Error {}

private func registerSigningConfiguration(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "celechron/signing", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
        if call.method == "getAppGroup" {
            result(AppGroupConfiguration.identifier())
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
}

private class FlowMessengerImplementation: FlowMessenger {
    func transfer(data: FlowMessage, completion: @escaping (Result<Bool, Error>) -> Void) {
        let userDefaults = AppGroupConfiguration.identifier().flatMap { UserDefaults(suiteName: $0) }
        userDefaults?.set(try? JSONEncoder().encode(data.flowListDto), forKey: "flowList")
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: "FlowWidget")
        }
    }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    private let shareStream = ShareStreamHandler()

    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        shareStream.emit()
    }

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Background AppRefresh MethodChannel
        WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "top.celechron.celechron.backgroundScholarFetch", frequency: NSNumber(value: 15 * 60))
        WorkmanagerPlugin.setPluginRegistrantCallback { registry in
            GeneratedPluginRegistrant.register(with: registry)
            if let registrar = registry.registrar(forPlugin: "ElychronSigning") {
                registerSigningConfiguration(messenger: registrar.messenger())
            }
        }

        // Notification MethodChannel
        UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
        FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
            GeneratedPluginRegistrant.register(with: registry)
            if let registrar = registry.registrar(forPlugin: "ElychronSigning") {
                registerSigningConfiguration(messenger: registrar.messenger())
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        registerSigningConfiguration(messenger: engineBridge.applicationRegistrar.messenger())

        // Flow widget MethodChannel
        FlowMessengerSetup.setUp(binaryMessenger: engineBridge.applicationRegistrar.messenger(), api: FlowMessengerImplementation())

        // ECard widget MethodChannel
        let ecardWidgetChannel = FlutterMethodChannel(name: "top.celechron.celechron/ecardWidget", binaryMessenger: engineBridge.applicationRegistrar.messenger())
        ecardWidgetChannel.setMethodCallHandler({
          (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            if #available(iOS 14.0, *) {
                WidgetCenter.shared.reloadTimelines(ofKind: "ECardWidget")
            }
        })

        NativeAlarmBridge.register(messenger: engineBridge.applicationRegistrar.messenger())

        let messenger = engineBridge.applicationRegistrar.messenger()
        let shareMethod = FlutterMethodChannel(name: "celechron/share", binaryMessenger: messenger)
        shareMethod.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(nil); return }
            switch call.method {
            case "getInitialShared":
                result(self.shareStream.initial())
            case "ackShared":
                let batches = call.arguments as? [String] ?? []
                self.shareStream.acknowledge(batches)
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        FlutterEventChannel(name: "celechron/share/stream", binaryMessenger: messenger)
            .setStreamHandler(shareStream)
    }
}
