import Cocoa

struct Worker: Decodable {
    var id: String
    var title: String
    var project: String
    var status: String
    var label: String
    var detail: String
    var active: Bool
    var color: Int
    var expiresAt: Double
    var remaining: Int
    var joinedAt: Double
}

struct Snapshot: Decodable {
    var workers: [Worker]
    var at: Double
    var error: String?
    var ttlSeconds: Int
}

let ink = NSColor(red: 0.14, green: 0.17, blue: 0.20, alpha: 1)
let cream = NSColor(red: 1, green: 0.95, blue: 0.85, alpha: 1)

// A grid owns every worker; cells never have independent windows or positions.
struct WorkerGrid {
    let side: CGFloat
    let columns: Int
    let rows: Int
    var size: NSSize { NSSize(width:CGFloat(columns)*side, height:CGFloat(rows)*side) }
    init(count:Int, side:CGFloat, available:NSSize) {
        self.side = side
        let maxColumns = max(1,Int(available.width / side))
        let maxRows = max(1,Int(available.height / side))
        columns = count == 0 ? 0 : min(count, maxColumns, max(4,Int(ceil(Double(count)/Double(maxRows)))))
        rows = columns == 0 ? 0 : (count + columns - 1) / columns
    }
    func rect(at index:Int) -> NSRect {
        NSRect(x:CGFloat(index % columns)*side,y:CGFloat(index / columns)*side,width:side,height:side)
    }
}

enum WorkerPose: String, CaseIterable {
    case working, cheering, sleeping
    init(_ worker:Worker) {
        switch worker.status {
        case "done": self = .cheering
        case "idle": self = .sleeping
        case "waiting", "error", "unknown": self = .working
        default: self = worker.active ? .working : .sleeping
        }
    }
}

// Load the exact approved transparent PNGs once; no regeneration or recoloring.
enum WorkerArtwork {
    static let images: [WorkerPose:NSImage] = {
        var result: [WorkerPose:NSImage] = [:]
        for pose in WorkerPose.allCases {
            guard let url = Bundle.main.url(forResource:pose.rawValue,withExtension:"png",subdirectory:"Workers"),
                  let data = try? Data(contentsOf:url), let bitmap = NSBitmapImageRep(data:data),
                  bitmap.hasAlpha else { continue }
            let size = NSSize(width:bitmap.pixelsWide,height:bitmap.pixelsHigh)
            bitmap.size = size
            let image = NSImage(size:size); image.addRepresentation(bitmap)
            result[pose] = image
        }
        return result
    }()
    static var errorMessage:String? {
        images.count == WorkerPose.allCases.count ? nil : "工人透明素材缺失，请重新安装本机应用"
    }
}

func text(_ value: String, _ rect: NSRect, size: CGFloat, color: NSColor,
          weight: NSFont.Weight = .medium, alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    (value as NSString).draw(in: rect, withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color, .paragraphStyle: paragraph
    ])
}

func rounded(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

final class PetView: NSView {
    var worker: Worker
    var pressedAt: NSPoint?
    var originalOrigin: NSPoint?
    var moved = false
    var onTap: (() -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onMove: (() -> Void)?
    var onMenu: (() -> NSMenu)?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    init(worker: Worker) {
        self.worker = worker
        super.init(frame: NSRect(x:0,y:0,width:48,height:48))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        update(worker)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    func update(_ new: Worker) {
        worker = new
        toolTip = "\(worker.title)\n\(worker.label) · \(worker.project)\n拖动整组 · 点击详情 · 右键设置"
        setAccessibilityLabel("\(worker.title)，\(worker.label)")
        needsDisplay = true
    }
    override func mouseDown(with event:NSEvent) {
        pressedAt = NSEvent.mouseLocation
        originalOrigin = window?.frame.origin
        moved = false
    }
    func dragGroup(to point:NSPoint) { onDrag?(point) }
    override func mouseDragged(with event:NSEvent) {
        guard let start = pressedAt, let origin = originalOrigin else { return }
        let point = NSEvent.mouseLocation
        let dx = point.x - start.x, dy = point.y - start.y
        if abs(dx) + abs(dy) > 3 { moved = true }
        if moved { dragGroup(to:NSPoint(x:origin.x + dx,y:origin.y + dy)) }
    }
    override func mouseUp(with event:NSEvent) {
        if moved { onMove?() } else { onTap?() }
        pressedAt = nil; originalOrigin = nil
    }
    override func rightMouseDown(with event:NSEvent) {
        if let menu = onMenu?() { NSMenu.popUpContextMenu(menu,with:event,for:self) }
    }
    override func accessibilityPerformPress() -> Bool { onTap?(); return true }

    override func draw(_ dirtyRect:NSRect) {
        guard let graphics = NSGraphicsContext.current else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        graphics.cgContext.clear(bounds)
        graphics.imageInterpolation = .none
        if let image = WorkerArtwork.images[WorkerPose(worker)] {
            let factor = min(bounds.width/image.size.width,bounds.height/image.size.height)
            let size = NSSize(width:image.size.width*factor,height:image.size.height*factor)
            let rect = NSRect(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2,
                              width:size.width,height:size.height)
            image.draw(in:rect,from:.zero,operation:.sourceOver,
                       fraction:worker.status == "unknown" ? 0.42 : 1,
                       respectFlipped:true,hints:nil)
        }
        if worker.status == "waiting" || worker.status == "error" {
            (worker.status == "waiting" ? NSColor.systemOrange : NSColor.systemRed).setFill()
            NSRect(x:bounds.maxX-6,y:4,width:3,height:3).fill()
        }
    }
}

final class SquadView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect:NSRect) { NSGraphicsContext.current?.cgContext.clear(dirtyRect) }
}

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetController: NSObject {
    let view: PetView
    var popover: NSPopover?
    var onMenu: (() -> NSMenu)?

    init(worker:Worker) {
        view = PetView(worker:worker)
        super.init()
        view.onTap = { [weak self] in self?.showDetails() }
        view.onMenu = { [weak self] in self?.onMenu?() ?? NSMenu() }
    }
    func showDetails() {
        if let popover, popover.isShown { popover.close(); return }
        let w = view.worker
        let vc = NSViewController()
        vc.view = NSView(frame: NSRect(x:0,y:0,width:300,height:176))
        let title = NSTextField(wrappingLabelWithString: w.title)
        title.font = .systemFont(ofSize:13, weight:.semibold)
        title.frame = NSRect(x:16,y:118,width:268,height:44)
        vc.view.addSubview(title)
        let detail = NSTextField(wrappingLabelWithString: "\(w.label) · \(w.project)\n\(w.detail)")
        detail.font = .systemFont(ofSize:11)
        detail.textColor = .secondaryLabelColor
        detail.frame = NSRect(x:16,y:64,width:268,height:47)
        vc.view.addSubview(detail)
        let copy = NSButton(title:"复制会话名", target:self, action:#selector(copyTitle))
        copy.bezelStyle = .rounded; copy.frame = NSRect(x:12,y:16,width:116,height:30)
        vc.view.addSubview(copy)
        let open = NSButton(title:"打开 Codex", target:self, action:#selector(openCodex))
        open.bezelStyle = .rounded; open.frame = NSRect(x:164,y:16,width:120,height:30)
        vc.view.addSubview(open)
        let p = NSPopover(); p.contentViewController = vc; p.behavior = .transient
        popover = p
        p.show(relativeTo:view.bounds.insetBy(dx:8,dy:6), of:view, preferredEdge:.maxY)
    }
    @objc func copyTitle() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(view.worker.title, forType:.string)
        popover?.close()
    }
    @objc func openCodex() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.openai.codex") else { return }
        NSWorkspace.shared.openApplication(at:url, configuration:NSWorkspace.OpenConfiguration())
        popover?.close()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var pets: [String: PetController] = [:]
    var order: [String] = []
    var statusItem: NSStatusItem!
    var process: Process?
    var timer: Timer?
    var pipe: Pipe?
    var pending = Data()
    var latestAt: Double = 0
    var scanError: String?
    var hidden = false
    var ttl = 300
    var tileSide: CGFloat = 48
    var groupTopLeft: NSPoint?
    let board = SquadView(frame:.zero)
    let panel: PetPanel

    override init() {
        panel = PetPanel(contentRect:NSRect(x:0,y:0,width:48,height:48),
                         styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        super.init()
        panel.title = "Codex Workers · 工人小队"
        panel.identifier = NSUserInterfaceItemIdentifier("workers-grid")
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = board
    }
    var frame = 0

    var dataDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_WORKERS_DATA"] { return URL(fileURLWithPath:path) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex-workers")
    }
    var loginStartupEnabled: Bool {
        FileManager.default.fileExists(atPath:FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/local.codex.workers.login.plist").path)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if NSRunningApplication.runningApplications(withBundleIdentifier:"local.codex.workers").count > 1 {
            NSApp.terminate(nil); return
        }
        let prefs = UserDefaults.standard
        // A new size preference lets existing installations adopt the smaller grid.
        let savedSide = prefs.double(forKey:"tileSide")
        tileSide = [40.0,48,56,64].contains(savedSide) ? CGFloat(savedSide) : 48
        if let point = prefs.array(forKey:"groupTopLeft") as? [Double], point.count == 2,
           point.allSatisfy({ $0.isFinite }) { groupTopLeft = NSPoint(x:point[0],y:point[1]) }
        NotificationCenter.default.addObserver(self,selector:#selector(screenLayoutChanged),
                                               name:NSApplication.didChangeScreenParametersNotification,object:nil)
        if let data = try? Data(contentsOf:dataDirectory.appendingPathComponent("settings.json")),
           let object = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
           let value = object["ttlSeconds"] as? Int { ttl = max(10,min(86400,value)) }
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName:"person.2.fill", accessibilityDescription:"Codex 工人")
        statusItem.button?.imagePosition = .imageLeading
        refreshMenu()
        startCollector()
        timer = Timer.scheduledTimer(withTimeInterval:0.20, repeats:true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode:.common)
    }
    func startCollector() {
        guard let script = Bundle.main.path(forResource:"collector", ofType:"py") else {
            scanError = "找不到状态读取器"; refreshMenu(); return
        }
        let task = Process(), stream = Pipe()
        task.executableURL = URL(fileURLWithPath:"/usr/bin/python3")
        task.arguments = ["-u",script,"--watch"]
        task.standardOutput = stream
        task.standardError = FileHandle.nullDevice
        pending = Data()
        stream.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.receive(data) }
        }
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.scanError = "读取器已停止，可从菜单重新连接"
                self?.refreshMenu()
            }
        }
        do { try task.run(); process = task; pipe = stream }
        catch { scanError = "无法启动本机 Python 3 读取器"; refreshMenu() }
    }
    func receive(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of:10) {
            let line = pending.prefix(upTo:newline)
            pending.removeSubrange(...newline)
            do { apply(try JSONDecoder().decode(Snapshot.self, from:line)) }
            catch { scanError = "会话状态格式发生变化" }
        }
        if pending.count > 4_000_000 { pending.removeAll(); scanError = "状态读取异常" }
    }
    func apply(_ snapshot:Snapshot) {
        latestAt = snapshot.at; scanError = snapshot.error ?? WorkerArtwork.errorMessage; ttl = snapshot.ttlSeconds
        let ids = Set(snapshot.workers.map(\.id))
        for id in Array(pets.keys) where !ids.contains(id) { removePet(id) }
        order = snapshot.workers.map(\.id)
        for worker in snapshot.workers {
            if let pet = pets[worker.id] { pet.view.update(worker) }
            else {
                let pet = PetController(worker:worker)
                pet.onMenu = { [weak self] in self?.makeMenu() ?? NSMenu() }
                pet.view.onDrag = { [weak self] point in self?.moveGroup(to:point) }
                pet.view.onMove = { [weak self] in self?.saveGroupPosition() }
                pets[worker.id] = pet
                board.addSubview(pet.view)
            }
        }
        layoutGroup()
        refreshMenu()
        writeDiagnostics()
    }
    func removePet(_ id:String) {
        pets[id]?.popover?.close()
        pets[id]?.view.removeFromSuperview()
        pets.removeValue(forKey:id)
    }
    func writeDiagnostics() {
        let value: [String:Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "updatedAt": latestAt,
            "workerCount": pets.count,
            "activeCount": pets.values.filter { $0.view.worker.active }.count,
            "visibleWindowCount": panel.isVisible ? 1 : 0,
            "visibleWorkerCount": panel.isVisible ? pets.count : 0,
            "floatingWindowCount": panel.isVisible && panel.level == .floating ? 1 : 0,
            "ttlSeconds": ttl,
            "loginStartupEnabled": loginStartupEnabled,
            "layout": "single-panel-grid",
            "appearance": "transparent-workstations",
            "loadedSpriteCount": WorkerArtwork.images.count,
            "tileWidth": Double(tileSide),
            "tileHeight": Double(tileSide),
            "windowWidth": panel.frame.width,
            "windowHeight": panel.frame.height,
            "error": scanError ?? ""
        ]
        do {
            try FileManager.default.createDirectory(at:dataDirectory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let data = try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys])
            try data.write(to:dataDirectory.appendingPathComponent("runtime.json"),options:.atomic)
        } catch { /* Optional local diagnostics must not affect the workers. */ }
    }
    func screenBounds(near point:NSPoint?) -> NSRect {
        let screen = point.flatMap { point in NSScreen.screens.first { $0.frame.contains(point) } }
        return (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x:0,y:0,width:1200,height:800)
    }
    func constrainedOrigin(_ point:NSPoint, size:NSSize, bounds:NSRect) -> NSPoint {
        NSPoint(x:max(bounds.minX,min(point.x,bounds.maxX-size.width)),
                y:max(bounds.minY,min(point.y,bounds.maxY-size.height)))
    }
    func layoutGroup() {
        order = order.filter { pets[$0] != nil }
        guard !order.isEmpty else { panel.orderOut(nil); return }
        let bounds = screenBounds(near:groupTopLeft)
        let grid = WorkerGrid(count:order.count,side:tileSide,available:bounds.size)
        let topLeft = groupTopLeft ?? NSPoint(x:bounds.maxX-16-grid.size.width,
                                              y:bounds.minY+18+grid.size.height)
        let origin = constrainedOrigin(NSPoint(x:topLeft.x,y:topLeft.y-grid.size.height),size:grid.size,bounds:bounds)
        panel.setFrame(NSRect(origin:origin,size:grid.size),display:false)
        board.frame = NSRect(origin:.zero,size:grid.size)
        for (index,id) in order.enumerated() { pets[id]?.view.frame = grid.rect(at:index) }
        groupTopLeft = NSPoint(x:panel.frame.minX,y:panel.frame.maxY)
        if !hidden && !panel.isVisible { panel.orderFrontRegardless() }
    }
    func moveGroup(to point:NSPoint) {
        let center = NSPoint(x:point.x+panel.frame.width/2,y:point.y+panel.frame.height/2)
        let origin = constrainedOrigin(point,size:panel.frame.size,bounds:screenBounds(near:center))
        panel.setFrameOrigin(origin)
        groupTopLeft = NSPoint(x:panel.frame.minX,y:panel.frame.maxY)
    }
    func saveGroupPosition() {
        if let point = groupTopLeft { UserDefaults.standard.set([point.x,point.y],forKey:"groupTopLeft") }
    }
    @objc func screenLayoutChanged() { layoutGroup(); writeDiagnostics() }
    func tick() {
        frame += 1
        let now = Date().timeIntervalSince1970
        let stale = now - latestAt > 8
        var removed = false
        for id in Array(pets.keys) {
            guard let pet = pets[id] else { continue }
            if stale && pet.view.worker.status != "unknown" {
                var disconnected = pet.view.worker
                disconnected.active = false; disconnected.status = "unknown"; disconnected.label = "连接已离开"
                pet.view.update(disconnected)
            }
            if !pet.view.worker.active && now >= pet.view.worker.expiresAt {
                removePet(id); removed = true
            }
        }
        if removed { layoutGroup(); writeDiagnostics() }
        if removed || frame % 25 == 0 { refreshMenu() }
    }
    func refreshMenu() {
        guard statusItem != nil else { return }
        let active = pets.values.filter { $0.view.worker.active }.count
        statusItem.button?.title = " \(active)"
        statusItem.button?.toolTip = "Codex 工人 · \(active) 个活跃 · \(pets.count) 个在桌面"
        if statusItem.menu == nil { statusItem.menu = makeMenu() }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        let fresh = makeMenu()
        menu.removeAllItems()
        for item in Array(fresh.items) { fresh.removeItem(item); menu.addItem(item) }
    }
    func item(_ title:String, _ action:Selector? = nil, tag:Int = 0) -> NSMenuItem {
        let value = NSMenuItem(title:title, action:action, keyEquivalent:"")
        value.target = self; value.tag = tag
        return value
    }
    func makeMenu() -> NSMenu {
        let menu = NSMenu(); menu.delegate = self
        let active = pets.values.filter { $0.view.worker.active }.count
        menu.addItem(item("工人小队  ·  \(active) 活跃 / \(pets.count) 在场"))
        menu.addItem(item("仅本机 · 停止活动后 \(ttl / 60) 分钟撤离"))
        if let scanError { menu.addItem(item(scanError)) }
        else if pets.isEmpty { menu.addItem(item("等待活跃会话，新任务开始后工人会出现")) }
        menu.addItem(.separator())
        menu.addItem(item(hidden ? "显示所有工人" : "暂时收起工人",#selector(toggleVisibility)))
        menu.addItem(item("将小队移回屏幕角落",#selector(arrange)))
        let ttlMenu = NSMenu()
        for minutes in [1,3,5,10,30] {
            let row = item("\(minutes) 分钟",#selector(setTTL(_:)),tag:minutes*60)
            row.state = ttl == minutes*60 ? .on : .off; ttlMenu.addItem(row)
        }
        let ttlItem = item("离场等待时间（TTL）"); ttlItem.submenu = ttlMenu; menu.addItem(ttlItem)
        let sizeMenu = NSMenu()
        for (label,value) in [("更小 · 40",40),("小巧 · 48（默认）",48),("适中 · 56",56),("稍大 · 64",64)] {
            let row = item(label,#selector(setSize(_:)),tag:value)
            row.state = abs(Double(tileSide) - Double(value)) < 0.01 ? .on : .off; sizeMenu.addItem(row)
        }
        let sizeItem = item("工人大小"); sizeItem.submenu = sizeMenu; menu.addItem(sizeItem)
        menu.addItem(.separator())
        let login = item("登录时自动启动",#selector(toggleLoginStartup))
        login.state = loginStartupEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("重新连接",#selector(reconnect)))
        menu.addItem(item("打开 Codex",#selector(openCodex)))
        menu.addItem(item("退出工人小队",#selector(quit)))
        return menu
    }
    @objc func toggleVisibility() {
        hidden.toggle()
        if hidden { panel.orderOut(nil) } else { layoutGroup() }
        writeDiagnostics()
    }
    @objc func arrange() {
        groupTopLeft = nil
        layoutGroup(); saveGroupPosition(); writeDiagnostics()
    }
    @objc func setTTL(_ sender:NSMenuItem) {
        do {
            try FileManager.default.createDirectory(at:dataDirectory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let data = try JSONSerialization.data(withJSONObject:["ttlSeconds":sender.tag],options:[.prettyPrinted])
            try data.write(to:dataDirectory.appendingPathComponent("settings.json"),options:.atomic)
            ttl = sender.tag
        } catch { scanError = "无法保存 TTL 设置" }
        refreshMenu()
    }
    @objc func setSize(_ sender:NSMenuItem) {
        guard [40,48,56,64].contains(sender.tag) else { return }
        tileSide = CGFloat(sender.tag); UserDefaults.standard.set(Double(tileSide),forKey:"tileSide")
        layoutGroup(); saveGroupPosition(); writeDiagnostics()
    }
    @objc func reconnect() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil; pipe = nil
        startCollector()
    }
    @objc func toggleLoginStartup() {
        guard let script = Bundle.main.path(forResource:"login_startup",ofType:"py") else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath:"/usr/bin/python3")
        task.arguments = [script,loginStartupEnabled ? "disable" : "enable"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] task in
            DispatchQueue.main.async {
                if task.terminationStatus != 0 { self?.scanError = "登录自启设置失败，请检查本机启动配置" }
                self?.writeDiagnostics()
            }
        }
        do { try task.run() }
        catch { scanError = "无法修改登录自启设置" }
    }
    @objc func openCodex() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.openai.codex") else { return }
        NSWorkspace.shared.openApplication(at:url,configuration:NSWorkspace.OpenConfiguration())
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool {
        hidden = false
        layoutGroup(); writeDiagnostics()
        return false
    }
    func applicationWillTerminate(_ notification:Notification) {
        saveGroupPosition()
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate(); pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
    }
}

func fixture(_ index:Int, status:String = "working", active:Bool = true) -> Worker {
    Worker(id:"fixture-\(index)",title:"示例任务 \(index+1)",project:"本机示例",status:status,
           label:status,detail:"演示",active:active,color:index % 6,
           expiresAt:Date().timeIntervalSince1970+300,remaining:300,joinedAt:Double(index))
}

func smokeTest() {
    let defaults = UserDefaults.standard
    let keys = ["tileSide","groupTopLeft"]
    let saved = keys.map { defaults.object(forKey:$0) }
    defer {
        for (index,key) in keys.enumerated() {
            if let value = saved[index] { defaults.set(value,forKey:key) }
            else { defaults.removeObject(forKey:key) }
        }
    }
    let delegate = AppDelegate()
    let now = Date().timeIntervalSince1970
    var workers = (0..<6).map { fixture($0) }
    func apply(_ rows:[Worker]) {
        delegate.apply(Snapshot(workers:rows,at:now,error:nil,ttlSeconds:300))
    }
    func checkGrid(_ ids:[String]) {
        precondition(delegate.order == ids && delegate.pets.count == ids.count)
        if ids.isEmpty { precondition(!delegate.panel.isVisible); return }
        let grid = WorkerGrid(count:ids.count,side:delegate.tileSide,available:delegate.screenBounds(near:delegate.groupTopLeft).size)
        precondition(delegate.panel.frame.size == grid.size)
        for (index,id) in ids.enumerated() {
            let view = delegate.pets[id]!.view
            precondition(view.window === delegate.panel && view.superview === delegate.board)
            precondition(view.frame == grid.rect(at:index))
            precondition(view.frame.width == view.frame.height)
        }
        precondition(delegate.board.subviews.count == ids.count)
    }
    apply(Array(workers.prefix(3)))
    checkGrid(Array(workers.prefix(3)).map(\.id))
    precondition(delegate.tileSide == 48 && delegate.panel.frame.size == NSSize(width:144,height:48))
    precondition(delegate.panel.isVisible && delegate.panel.level == .floating && !delegate.panel.isOpaque)
    precondition(!delegate.panel.hidesOnDeactivate && delegate.panel.collectionBehavior.contains(.canJoinAllSpaces))
    // Exercise real bundled PNGs and the production renderer, including state changes
    // on the same view. This catches missing assets and accidental opaque tile fills.
    precondition(WorkerArtwork.errorMessage == nil)
    let stateView = delegate.pets[workers[0].id]!.view
    var renderedStates = Set<Data>()
    for (status,active) in [("working",true),("done",false),("idle",false)] {
        stateView.update(fixture(0,status:status,active:active))
        let bitmap = workerBitmap(stateView,pixels:96)
        precondition(bitmap.hasAlpha && bitmap.colorAt(x:0,y:0)!.alphaComponent == 0)
        precondition(bitmap.colorAt(x:95,y:95)!.alphaComponent == 0)
        var clear = 0, solid = 0
        for y in 0..<96 { for x in 0..<96 {
            let alpha = bitmap.colorAt(x:x,y:y)!.alphaComponent
            if alpha < 0.01 { clear += 1 }
            if alpha > 0.99 { solid += 1 }
        } }
        precondition(clear > 96*96/4 && solid > 96*96/5)
        renderedStates.insert(bitmap.representation(using:.png,properties:[:])!)
    }
    precondition(renderedStates.count == 3)
    stateView.update(workers[0])
    // Every tile invokes the same group movement, preserving all local offsets.
    let positions = delegate.order.map { delegate.pets[$0]!.view.frame }
    let screen = delegate.screenBounds(near:delegate.groupTopLeft)
    let destination = NSPoint(x:screen.midX-72,y:screen.midY-24)
    delegate.pets[workers[1].id]!.view.dragGroup(to:destination)
    // AppKit aligns native window origins to device pixels.
    precondition(abs(delegate.panel.frame.minX-destination.x) < 1 && abs(delegate.panel.frame.minY-destination.y) < 1)
    precondition(delegate.order.map { delegate.pets[$0]!.view.frame } == positions)
    precondition(delegate.pets.values.allSatisfy { $0.view.window === delegate.panel })
    delegate.saveGroupPosition()
    precondition(defaults.array(forKey:"groupTopLeft") != nil)
    let anchor = delegate.groupTopLeft
    apply(workers)
    checkGrid(workers.map(\.id))
    precondition(delegate.groupTopLeft == anchor)
    precondition(delegate.panel.frame.size == NSSize(width:192,height:96))
    // A middle departure closes its details and fills the hole immediately.
    let survivor = delegate.pets[workers[3].id]!
    workers.remove(at:1)
    apply(workers)
    checkGrid(workers.map(\.id))
    precondition(delegate.pets[workers[2].id] === survivor)
    precondition(survivor.view.frame.origin == NSPoint(x:96,y:0))
    delegate.toggleVisibility(); precondition(!delegate.panel.isVisible)
    delegate.toggleVisibility(); precondition(delegate.panel.isVisible)
    for side in [40,48,56,64] {
        let size = NSMenuItem(); size.tag = side; delegate.setSize(size)
        precondition(delegate.tileSide == CGFloat(side)); checkGrid(workers.map(\.id))
    }
    let narrow = WorkerGrid(count:6,side:48,available:NSSize(width:100,height:800))
    precondition(narrow.columns == 2 && narrow.rows == 3)
    let short = WorkerGrid(count:12,side:48,available:NSSize(width:800,height:100))
    precondition(short.columns == 6 && short.rows == 2)
    delegate.groupTopLeft = NSPoint(x:-50000,y:-50000)
    delegate.screenLayoutChanged()
    precondition(delegate.screenBounds(near:delegate.groupTopLeft).contains(delegate.panel.frame))
    let setting = NSMenuItem(); setting.tag = 60; delegate.setTTL(setting)
    precondition(delegate.ttl == 60)
    precondition(WorkerPose(fixture(0)) == .working)
    precondition(WorkerPose(fixture(0,status:"done",active:false)) == .cheering)
    precondition(WorkerPose(fixture(0,status:"idle",active:false)) == .sleeping)
    precondition(WorkerPose(fixture(0,status:"waiting")) == .working)
    precondition(WorkerPose(fixture(0,status:"error",active:false)) == .working)
    precondition(WorkerPose(fixture(0,status:"unknown",active:false)) == .working)
    // The native fallback also repacks on TTL expiration if updates stop.
    workers[1].active = false; workers[1].status = "done"; workers[1].expiresAt = now-1
    apply(workers); delegate.tick()
    workers.remove(at:1)
    checkGrid(workers.map(\.id))
    apply([]); checkGrid([])
    delegate.panel.close()
    print("Native smoke test passed: bundled transparent artwork, three distinct rendered states, alpha-preserving tiles, shared panel, group dragging, reflow, sizes, screen bounds and TTL cleanup.")
}

func workerBitmap(_ view:PetView, pixels:Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,
                                       bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,
                                       colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    bitmap.size = view.bounds.size
    view.cacheDisplay(in:view.bounds,to:bitmap)
    return bitmap
}

func drawSample(_ worker:Worker, in rect:NSRect) {
    let view = PetView(worker:worker)
    let bitmap = workerBitmap(view,pixels:max(96,Int(rect.width*2)))
    let sprite = NSImage(size:view.bounds.size); sprite.addRepresentation(bitmap)
    sprite.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1)
}

// Only synthetic examples, rendered locally with the production drawing code.
func renderPreview(_ path:String) {
    let size = NSSize(width:600,height:340)
    let image = NSImage(size:size); image.lockFocus()
    NSColor(red:0.90,green:0.92,blue:0.91,alpha:1).setFill()
    NSRect(origin:.zero,size:size).fill()
    text("工人小队 · 透明工位",NSRect(x:28,y:295,width:544,height:25),size:18,color:ink,weight:.semibold)
    text("透明背景 · 每格 48 × 48 · 拖动整组",NSRect(x:28,y:273,width:544,height:18),size:11,color:ink.withAlphaComponent(0.7))
    let states = [("working",true,"低头 · 工作"),("done",false,"举手 · 欢呼"),("idle",false,"趴桌 · 睡眠")]
    for (index,state) in states.enumerated() {
        let worker = fixture(index,status:state.0,active:state.1)
        drawSample(worker,in:NSRect(x:CGFloat(index)*96+28,y:139,width:96,height:96))
        text(state.2,NSRect(x:CGFloat(index)*96+24,y:110,width:104,height:18),size:11,color:ink)
    }
    text("三种姿态 · 放大预览",NSRect(x:28,y:80,width:288,height:18),size:10,color:ink.withAlphaComponent(0.55))
    for index in 0..<8 {
        let state = states[index % states.count]
        drawSample(fixture(index,status:state.0,active:state.1),
                   in:NSRect(x:364+CGFloat(index%4)*48,y:139+CGFloat(1-index/4)*48,width:48,height:48))
    }
    text("紧凑方格 · 自动补位",NSRect(x:354,y:110,width:212,height:18),size:11,color:ink)
    text("悬停看任务名称 · 点击看详情",NSRect(x:28,y:27,width:544,height:18),size:11,color:ink.withAlphaComponent(0.7))
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data:tiff),
          let png = rep.representation(using:.png,properties:[:]) else { return }
    do { try png.write(to:URL(fileURLWithPath:path)) }
    catch { fatalError("Cannot save preview: \(error)") }
}

let app = NSApplication.shared
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--render-preview" {
    renderPreview(CommandLine.arguments[2])
} else if CommandLine.arguments.contains("--smoke-test") {
    guard ProcessInfo.processInfo.environment["CODEX_WORKERS_DATA"] != nil else {
        fatalError("Set CODEX_WORKERS_DATA to an isolated test directory")
    }
    smokeTest()
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
