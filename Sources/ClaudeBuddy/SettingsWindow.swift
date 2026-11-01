import AppKit
import ServiceManagement

/// A small settings window. Built on demand and thrown away on close to keep idle memory down.
final class SettingsWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let onSkinChange: (String) -> Void
    private let onClose: () -> Void
    private let folderLabel = NSTextField(labelWithString: "")
    private let skinPopup = NSPopUpButton()
    private var skinIds: [String] = []

    private static let permissionModes = ["", "acceptEdits", "auto", "plan", "dontAsk", "bypassPermissions"]
    private static let sleepChoices: [Double] = [1, 2, 5, 10, 15, 30]

    init(onSkinChange: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.onSkinChange = onSkinChange
        self.onClose = onClose
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Claude Buddy Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self

        folderLabel.stringValue = Prefs.workingFolder
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let chooseFolder = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))

        let permPopup = NSPopUpButton()
        permPopup.addItems(withTitles: Self.permissionModes.map { $0.isEmpty ? "CLI default" : $0 })
        permPopup.selectItem(at: Self.permissionModes.firstIndex(of: Prefs.permissionMode) ?? 0)
        permPopup.target = self
        permPopup.action = #selector(permissionChanged(_:))

        reloadSkins()
        skinPopup.target = self
        skinPopup.action = #selector(skinChanged(_:))
        let openSkins = NSButton(title: "Open Skins Folder", target: self, action: #selector(openSkinsFolder))

        let sleepPopup = NSPopUpButton()
        sleepPopup.addItems(withTitles: Self.sleepChoices.map { "\(Int($0)) min" })
        sleepPopup.selectItem(at: Self.sleepChoices.firstIndex(of: Prefs.sleepMinutes) ?? 2)
        sleepPopup.target = self
        sleepPopup.action = #selector(sleepChanged(_:))

        let summarise = NSButton(checkboxWithTitle: "Summarise other sessions' replies with Haiku",
                                 target: self, action: #selector(summariseChanged(_:)))
        summarise.state = Prefs.summariseOtherSessions ? .on : .off

        let login = NSButton(checkboxWithTitle: "Open at login", target: self, action: #selector(loginChanged(_:)))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off

        func row(_ label: String, _ views: NSView...) -> [NSView] {
            let stack = NSStackView(views: views)
            stack.spacing = 8
            return [NSTextField(labelWithString: label), stack]
        }
        let grid = NSGridView(views: [
            row("Talk:", ShortcutRecorder(.talk)),
            row("Open last reply:", ShortcutRecorder(.openLast)),
            row("New chat:", ShortcutRecorder(.newChat)),
            row("Working folder:", folderLabel, chooseFolder),
            row("Permission mode:", permPopup),
            row("Skin:", skinPopup, openSkins),
            row("Nap after:", sleepPopup),
            [NSGridCell.emptyContentView, summarise],
            [NSGridCell.emptyContentView, login],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            folderLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
        ])
        window.contentView = content
        window.center()
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [onClose] in onClose() }
    }

    private func reloadSkins() {
        let skins = Skin.available()
        skinIds = skins.map(\.id)
        skinPopup.removeAllItems()
        for s in skins {
            let name = (try? Skin(directory: s.url).name) ?? s.id
            skinPopup.addItem(withTitle: name)
        }
        skinPopup.selectItem(at: skinIds.firstIndex(of: Prefs.skin) ?? 0)
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: Prefs.workingFolder)
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            Prefs.workingFolder = url.path
            self?.folderLabel.stringValue = url.path
        }
    }

    @objc private func permissionChanged(_ sender: NSPopUpButton) {
        Prefs.permissionMode = Self.permissionModes[sender.indexOfSelectedItem]
    }

    @objc private func skinChanged(_ sender: NSPopUpButton) {
        guard skinIds.indices.contains(sender.indexOfSelectedItem) else { return }
        Prefs.skin = skinIds[sender.indexOfSelectedItem]
        onSkinChange(Prefs.skin)
    }

    @objc private func openSkinsFolder() {
        NSWorkspace.shared.open(Skin.userSkinsDir)
        reloadSkins()
    }

    @objc private func sleepChanged(_ sender: NSPopUpButton) {
        Prefs.sleepMinutes = Self.sleepChoices[sender.indexOfSelectedItem]
    }

    @objc private func summariseChanged(_ sender: NSButton) {
        Prefs.summariseOtherSessions = sender.state == .on
    }

    @objc private func loginChanged(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
            NSAlert(error: error).beginSheetModal(for: window)
        }
    }
}
