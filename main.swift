import Foundation
import AppKit
import SystemConfiguration

class OpenURLApp: NSObject {
    private var wifiMonitor: WifiMonitor?
    private var statusItem: NSStatusItem?
    private var rules: [WifiRule] = []
    private var isMonitoringPaused = false

    private var pauseMenuItem: NSMenuItem?
    
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.setupMenuBar()
        }
        startWifiMonitoring()
        loadRules()

    }
    
    private func setupMenuBar() {
        DispatchQueue.main.async {
            guard Thread.isMainThread else {
                print("Error: Menu bar setup must be on main thread")
                let alert = NSAlert()
                alert.messageText = "状态栏初始化失败"
                alert.informativeText = "必须在主线程初始化状态栏"
                alert.runModal()
                return
            }
            
            self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            guard let statusItem = self.statusItem else {
                print("Failed to create status item")
                let alert = NSAlert()
                alert.messageText = "状态栏项目创建失败"
                alert.informativeText = "无法创建状态栏项目"
                alert.runModal()
                return
            }
            
            guard let button = statusItem.button else {
                print("Failed to get status item button")
                let alert = NSAlert()
                alert.messageText = "状态栏按钮获取失败"
                alert.informativeText = "无法获取状态栏按钮"
                alert.runModal()
                return
            }
        
        button.image = NSImage(named: NSImage.applicationIconName)
        button.image?.size = NSSize(width: 18, height: 18)
        
        let menu = NSMenu()
        
        let addRuleItem = NSMenuItem(title: "添加规则", action: #selector(self.addRule), keyEquivalent: "")
        addRuleItem.target = self
        menu.addItem(addRuleItem)
        
        let viewLogsItem = NSMenuItem(title: "查看日志", action: #selector(self.viewLogs), keyEquivalent: "")
        viewLogsItem.target = self
        menu.addItem(viewLogsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        self.pauseMenuItem = NSMenuItem(title: "暂停监控", action: #selector(self.togglePause), keyEquivalent: "p")
        self.pauseMenuItem?.target = self
        menu.addItem(self.pauseMenuItem!)
        
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(self.quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
            button.action = #selector(self.buttonClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    private func startWifiMonitoring() {
        wifiMonitor = WifiMonitor()
        wifiMonitor?.onWifiChanged = { [weak self] ssid in
            self?.checkAndOpenURL(for: ssid)
        }
    }
    
    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: "wifiRules") {
            do {
                let decoded = try JSONDecoder().decode([WifiRule].self, from: data)
                rules = decoded
            } catch {
                print("Failed to decode wifi rules: \(error)")
            }
        } else {
            // 加载预设规则
            rules = [
                WifiRule(ssid: "HAS", url: "https://example.com/home"),
            ]
            saveRules()
        }
    }
    

    
    private func checkAndOpenURL(for ssid: String?) {
        guard let ssid = ssid, !isMonitoringPaused else {
            print("未获取到SSID或监控已暂停")
            return 
        }
        
        print("当前SSID: \(ssid)")
        print("所有规则: \(rules)")
        
        if let rule = rules.first(where: { $0.ssid == ssid }) {
            print("找到匹配规则: \(rule)")
            guard let url = URL(string: rule.url), url.scheme != nil, 
                  NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
                print("无效URL: \(rule.url)")
                showInvalidURLError(url: rule.url)
                return
            }
            print("正在打开URL: \(url)")
            NSWorkspace.shared.open(url)
            logEvent(ssid: ssid, url: rule.url)
        } else {
            print("未找到匹配的WiFi规则")
        }
    }
    
    private func logEvent(ssid: String, url: String) {
        let logEntry = "\(Date()): Opened \(url) for WiFi \(ssid)\n"
        if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
            let logsURL = docsDir.appendingPathComponent("openURLLogs.txt")
            if FileManager.default.fileExists(atPath: logsURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logsURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(logEntry.data(using: .utf8)!)
                    fileHandle.closeFile()
                }
            } else {
                try? logEntry.write(to: logsURL, atomically: true, encoding: .utf8)
            }
        }
    }
    
    @objc private func addRule() {
        let alert = createAddRuleAlert()
        
        if alert.runModal() == .alertFirstButtonReturn {
            guard let fields = alert.accessoryView?.subviews.compactMap({ $0 as? NSTextField }),
                  fields.count == 2 else {
                return
            }
            
            let ssid = fields[0].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = fields[1].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !ssid.isEmpty, !url.isEmpty else {
                showEmptyFieldError()
                return
            }
            
            guard isValidURL(url) else {
                showInvalidURLError(url: url)
                return
            }
            
            let newRule = WifiRule(ssid: ssid, url: url)
            rules.append(newRule)
            saveRules()
        }
    }
    
    private func createAddRuleAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "添加WiFi规则"
        alert.informativeText = "请输入WiFi名称和要打开的URL"
        alert.window.level = .floating
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 90))
        
        let ssidField = NSTextField(frame: NSRect(x: 0, y: 30, width: 200, height: 24))
        ssidField.placeholderString = "WiFi名称"
        ssidField.isEditable = true
        ssidField.isSelectable = true
        ssidField.isBezeled = true
        ssidField.bezelStyle = .roundedBezel
        
        let urlField = NSTextField(frame: NSRect(x: 0, y: 60, width: 200, height: 24))
        urlField.placeholderString = "要打开的URL (例如: https://example.com)"
        urlField.isEditable = true
        urlField.isSelectable = true
        urlField.isBezeled = true
        urlField.bezelStyle = .roundedBezel
        
        container.addSubview(ssidField)
        container.addSubview(urlField)
        
        alert.accessoryView = container
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        
        DispatchQueue.main.async {
            alert.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            alert.window.makeFirstResponder(ssidField)
            ssidField.becomeFirstResponder()
            alert.window.orderFrontRegardless()
        }
        
        return alert
    }
    

    
    private func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              url.scheme != nil,
              NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            return false
        }
        return true
    }
    
    private func showEmptyFieldError() {
        let alert = NSAlert()
        alert.messageText = "输入不能为空"
        alert.informativeText = "请确保WiFi名称和URL都已填写"
        alert.runModal()
    }
    
    private func saveRules() {
        if let encoded = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(encoded, forKey: "wifiRules")
        }
    }
    
    private func showInvalidURLError(url: String) {
        let alert = NSAlert()
        alert.messageText = "Invalid URL"
        alert.informativeText = "The URL '\(url)' is not valid or cannot be opened."
        alert.runModal()
    }
    
    @objc private func viewLogs() {
        if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
            let logsURL = docsDir.appendingPathComponent("openURLLogs.txt")
            
            if FileManager.default.fileExists(atPath: logsURL.path) {
                NSWorkspace.shared.open(logsURL)
            } else {
                let alert = NSAlert()
                alert.messageText = "未找到日志文件"
                alert.informativeText = "尚未记录任何URL打开日志。"
                alert.runModal()
            }
        } else {
            let alert = NSAlert()
            alert.messageText = "无法访问文档目录"
            alert.informativeText = "无法获取用户文档目录路径。"
            alert.runModal()
        }
    }
    
    @objc private func togglePause() {
        isMonitoringPaused = !isMonitoringPaused
        pauseMenuItem?.title = isMonitoringPaused ? "恢复监控" : "暂停监控"
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func buttonClicked() {
        statusItem?.button?.performClick(nil)
    }
    
}

struct WifiRule: Codable {
    let ssid: String
    let url: String
}

class WifiMonitor {
    var onWifiChanged: ((String?) -> Void)?
    private var previousSSID: String?
    
    init() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkWifiChange()
        }
    }
    
    private func checkWifiChange() {
        let currentSSID = getCurrentSSID()
        if currentSSID != previousSSID {
            previousSSID = currentSSID
            onWifiChanged?(currentSSID)
        }
    }
    
    private func getCurrentSSID() -> String? {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
        
        for interface in interfaces {
            if let interfaceName = SCNetworkInterfaceGetBSDName(interface) as String?,
               interfaceName.hasPrefix("en") {
                
                if let cfDict = SCNetworkInterfaceGetConfiguration(interface),
                   let dict = cfDict as? [String: Any],
                   let ssid = dict["SSID"] as? String {
                    return ssid
                }
            }
        }
        return nil
    }
}

let app = OpenURLApp()
app.start()
NSApplication.shared.run()