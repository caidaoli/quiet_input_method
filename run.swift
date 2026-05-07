import AppKit
import Carbon
import Foundation

var lastSwitchTime = Date.distantPast
let switchCooldownSeconds: TimeInterval = 2

// 获取所有输入法ID
func getInputMethodList() -> [String] {
  let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
  var inputMethodList = [String]()
  for source in list {
    if let namePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
      let sourceName = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
      inputMethodList.append(sourceName)
    }
  }
  return inputMethodList
}

// 获取当前激活的输入法ID
func getSelectedInputMethod() -> String {
  let currentSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
  if let namePtr = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) {
    let sourceName = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
    return sourceName
  }
  return ""
}

// 缓存输入法列表，避免每次切换都重建
var cachedInputSources: [TISInputSource]?

// 切换输入法
func switchInputMethod(to inputMethod: String) {
  // 已经是目标输入法则跳过（用子串匹配，和下方选择逻辑保持一致）
  let currentID = getSelectedInputMethod()
  if currentID.range(of: inputMethod, options: .caseInsensitive) != nil {
    return
  }

  // 冷却时间限制
  let now = Date()
  if now.timeIntervalSince(lastSwitchTime) < switchCooldownSeconds {
    return
  }

  if cachedInputSources == nil {
    cachedInputSources = TISCreateInputSourceList(nil, false).takeRetainedValue() as? [TISInputSource]
  }
  for inputSource in cachedInputSources ?? [] {
    if let inputSourceIDPtr = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) {
      let inputSourceID = Unmanaged<CFString>.fromOpaque(inputSourceIDPtr).takeUnretainedValue() as String
      if inputSourceID.range(of: inputMethod, options: .caseInsensitive) != nil {
        print("Switching to \(inputSourceID)")
        TISSelectInputSource(inputSource)
        lastSwitchTime = now
        return
      }
    }
  }

  print("Not found \(inputMethod), maybe not installed?")
}

// 读取配置文件
let fileManager = FileManager.default
let configFilePath = "\(NSHomeDirectory())/.quiet_input_method/.quiet.json"

var DEFAULT_CONFIG = """
{
  "default": "abc",
  "appConfig": {
    "Shuangpin": ["Telegram", "WeChat"],
    "abc": ["Code"]
  }
}
"""

func jsonToDict(jsonData: Data) -> [String: Any] {
  return (try? JSONSerialization.jsonObject(with: jsonData, options: .mutableContainers)) as? [String: Any] ?? [:]
}

var configData: Data? = fileManager.contents(atPath: configFilePath)
let config = jsonToDict(jsonData: configData ?? DEFAULT_CONFIG.data(using: .utf8)!)

// 通过 App 名获取输入法配置
func getInputMethodByConfig(appName: String) -> String {
  if let appConfig = config["appConfig"] as? [String: [String]] {
    for (inputMethod, appList) in appConfig {
      if appList.contains(appName) {
        return inputMethod
      }
    }
  }
  return config["default"] as? String ?? "Unknown"
}

// 监听 App 切换
let workspace = NSWorkspace.shared
var currentApp: NSRunningApplication?

workspace.notificationCenter.addObserver(
  forName: NSWorkspace.didActivateApplicationNotification,
  object: nil,
  queue: nil
) { notification in
  if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
    if app != currentApp {
      currentApp = app
      let appName = app.localizedName ?? "Unknown"
      let inputMethod = getInputMethodByConfig(appName: appName)
      if inputMethod == "Unknown" {
        return
      }
      print("Current app: \(appName) -> input method: \(inputMethod)")
      switchInputMethod(to: inputMethod)
    }
  }
}

print("Listening for app switch events...")

// 输出所有输入法
print("Available input methods:")
for inputMethod in getInputMethodList() {
  print("- \(inputMethod)")
}

// 保持主线程运行
RunLoop.main.run()