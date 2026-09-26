import Cocoa
import UniformTypeIdentifiers
import ServiceManagement

// Watches ~/.Trash; when something lands in it, flies its icon from the cursor into the Dock's Trash.
final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path
    var status: NSStatusItem!
    var login: NSMenuItem!
    var stream: FSEventStreamRef?
    var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "TrashMac")
        let menu = NSMenu()
        menu.addItem(withTitle: "Test Animation", action: #selector(test), keyEquivalent: "t").target = self
        login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        menu.delegate = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit TrashMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
        // Accessibility lets us find the exact Trash icon in the Dock.
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        watch()
    }

    // Read fresh on open: the user can also change this in System Settings → Login Items.
    func menuWillOpen(_ menu: NSMenu) { login.state = SMAppService.mainApp.status == .enabled ? .on : .off }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        // Failed or needs the user's OK: send them to Login Items to finish it there.
        do { try s.status == .enabled ? s.unregister() : s.register() } catch { SMAppService.openSystemSettingsLoginItems() }
        if s.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    @objc func test() { fly(NSWorkspace.shared.icon(for: .plainText), delay: 0.3) }

    func watch() {
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            let app = Unmanaged<App>.fromOpaque(info!).takeUnretainedValue()
            let paths = unsafeBitCast(paths, to: NSArray.self) as! [String]
            var added: [(path: String, dir: Bool)] = []
            for i in 0..<count {
                let p = paths[i], f = Int(flags[i])
                // Apps can't stat inside ~/.Trash (TCC), so go by event flags alone. Removed = Empty Trash.
                // ponytail: "Put Back" also looks like an arrival and animates; pair with a home-dir watch if it matters.
                let arrived = f & (kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemCreated) != 0
                    && f & kFSEventStreamEventFlagItemRemoved == 0
                if arrived, (p as NSString).deletingLastPathComponent == app.trash,
                   !(p as NSString).lastPathComponent.hasPrefix("."), !added.contains(where: { $0.path == p }) {
                    added.append((p, f & kFSEventStreamEventFlagItemIsDir != 0))
                }
            }
            // ponytail: caps a big multi-file delete at 5 flying icons, like Finder's own stacked drag.
            for (i, item) in added.prefix(5).enumerated() {
                let ext = (item.path as NSString).pathExtension
                let type = item.dir && ext.isEmpty ? UTType.folder : UTType(filenameExtension: ext) ?? .data
                app.fly(NSWorkspace.shared.icon(for: type), delay: Double(i) * 0.06)
            }
        }
        stream = FSEventStreamCreate(nil, cb, &ctx, [trash] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents))
        FSEventStreamSetDispatchQueue(stream!, .main)
        FSEventStreamStart(stream!)
    }

    // Trash icon rect in Cocoa (bottom-left origin) coordinates, via the Dock's accessibility tree.
    func trashRect() -> CGRect {
        let primary = NSScreen.screens[0].frame
        if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            let app = AXUIElementCreateApplication(dock.processIdentifier)
            func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
            for list in attr(app, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                for item in attr(list, kAXChildrenAttribute) as? [AXUIElement] ?? [] where attr(item, kAXSubroleAttribute) as? String == "AXTrashDockItem" {
                    var pos = CGPoint.zero, size = CGSize.zero
                    AXValueGetValue(attr(item, kAXPositionAttribute) as! AXValue, .cgPoint, &pos)
                    AXValueGetValue(attr(item, kAXSizeAttribute) as! AXValue, .cgSize, &size)
                    return CGRect(x: pos.x, y: primary.height - pos.y - size.height, width: size.width, height: size.height)
                }
            }
        }
        // ponytail: no Accessibility permission → guess bottom-right of a bottom Dock.
        return CGRect(x: primary.maxX - 140, y: 8, width: 56, height: 56)
    }

    func fly(_ icon: NSImage, delay: Double) {
        let start = NSEvent.mouseLocation, target = trashRect()
        let end = CGPoint(x: target.midX, y: target.midY)
        let frame = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }

        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false; win.backgroundColor = .clear; win.hasShadow = false
        win.ignoresMouseEvents = true; win.isReleasedWhenClosed = false
        win.level = .screenSaver // above the Dock
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size)); view.wantsLayer = true
        win.contentView = view
        let local = { (p: CGPoint) in CGPoint(x: p.x - frame.minX, y: p.y - frame.minY) }

        let layer = CALayer()
        let side: CGFloat = 64
        layer.frame = CGRect(x: 0, y: 0, width: side, height: side)
        var rect = CGRect(x: 0, y: 0, width: side * 2, height: side * 2) // Retina-sharp rep
        layer.contents = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        layer.shadowOpacity = 0.3; layer.shadowRadius = 6; layer.shadowOffset = CGSize(width: 0, height: -3)
        layer.position = local(end); layer.opacity = 0 // final state
        view.layer!.addSublayer(layer)
        windows.append(win)
        win.orderFrontRegardless()

        // Arc: rise a little, then drop into the Trash, like Finder's classic flight.
        let a = local(start), b = local(end)
        let path = CGMutablePath()
        path.move(to: a)
        path.addQuadCurve(to: b, control: CGPoint(x: a.x + (b.x - a.x) * 0.7, y: max(a.y, b.y) + 120))

        let move = CAKeyframeAnimation(keyPath: "position"); move.path = path
        let scale = CABasicAnimation(keyPath: "transform.scale"); scale.fromValue = 1; scale.toValue = target.width * 0.5 / side
        let fade = CAKeyframeAnimation(keyPath: "opacity"); fade.values = [0.95, 0.95, 0]; fade.keyTimes = [0, 0.8, 1]
        let group = CAAnimationGroup()
        group.animations = [move, scale, fade]
        group.duration = 0.5
        group.beginTime = CACurrentMediaTime() + delay
        group.fillMode = .backwards
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.55, 0, 0.8, 0.6) // ease-in, accelerates into the Trash

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in win.orderOut(nil); self?.windows.removeAll { $0 === win } }
        layer.add(group, forKey: "fly")
        CATransaction.commit()
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
