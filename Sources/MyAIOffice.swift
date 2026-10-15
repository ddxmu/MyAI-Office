import Cocoa
import UniformTypeIdentifiers

enum OfficeModule: CaseIterable {
    case writer
    case sheet
    case slides
    case pdf

    var title: String {
        switch self {
        case .writer: return "MyAI Word"
        case .sheet: return "MyAI Excel"
        case .slides: return "MyAI Power Point"
        case .pdf: return "MyAI PDF"
        }
    }

    var subtitle: String {
        switch self {
        case .writer: return "文字处理 · DOCX / DOC / RTF"
        case .sheet: return "电子表格 · XLSX / XLS / CSV"
        case .slides: return "演示文稿 · PPTX"
        case .pdf: return "阅读、整理、合并与保护 PDF"
        }
    }

    var helperName: String {
        switch self {
        case .writer: return "myai-writer"
        case .sheet: return "myai-sheet"
        case .slides: return "myai-slides"
        case .pdf: return "myai-pdf"
        }
    }

    var symbolName: String {
        switch self {
        case .writer: return "doc.text"
        case .sheet: return "tablecells"
        case .slides: return "rectangle.on.rectangle"
        case .pdf: return "doc.richtext"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .writer: return NSColor(calibratedRed: 0.12, green: 0.43, blue: 0.91, alpha: 1)
        case .sheet: return NSColor(calibratedRed: 0.10, green: 0.63, blue: 0.48, alpha: 1)
        case .slides: return NSColor(calibratedRed: 0.86, green: 0.35, blue: 0.23, alpha: 1)
        case .pdf: return NSColor(calibratedRed: 0.56, green: 0.32, blue: 0.82, alpha: 1)
        }
    }
}

final class GradientView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.04, green: 0.24, blue: 0.68, alpha: 1),
            NSColor(calibratedRed: 0.02, green: 0.60, blue: 0.58, alpha: 1)
        ])
        gradient?.draw(in: bounds, angle: 18)
    }
}

final class LogoView: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 52, height: 52) }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 15, yRadius: 15)
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.02, green: 0.15, blue: 0.48, alpha: 1),
            NSColor(calibratedRed: 0.10, green: 0.84, blue: 0.67, alpha: 1)
        ])
        gradient?.draw(in: path, angle: 42)

        NSColor.white.withAlphaComponent(0.96).setStroke()
        let mark = NSBezierPath()
        mark.lineWidth = 5
        mark.lineCapStyle = .round
        mark.move(to: NSPoint(x: bounds.minX + 15, y: bounds.minY + 15))
        mark.line(to: NSPoint(x: bounds.maxX - 15, y: bounds.maxY - 15))
        mark.move(to: NSPoint(x: bounds.minX + 15, y: bounds.maxY - 15))
        mark.line(to: NSPoint(x: bounds.maxX - 15, y: bounds.minY + 15))
        mark.stroke()
    }
}

final class ModuleIconView: NSView {
    private let module: OfficeModule
    private let imageView = NSImageView()

    init(module: OfficeModule) {
        self.module = module
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.backgroundColor = module.accentColor.cgColor

        imageView.image = NSImage(systemSymbolName: module.symbolName, accessibilityDescription: module.title)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 56),
            heightAnchor.constraint(equalToConstant: 56),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 27),
            imageView.heightAnchor.constraint(equalToConstant: 27)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

final class ModuleCard: NSView {
    let module: OfficeModule
    let action: () -> Void

    init(module: OfficeModule, action: @escaping () -> Void) {
        self.module = module
        self.action = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.22).cgColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.98).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.11).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        heightAnchor.constraint(equalToConstant: 142).isActive = true
        build()
    }

    required init?(coder: NSCoder) { nil }

    private func build() {
        let root = NSStackView()
        root.orientation = .horizontal
        root.alignment = .centerY
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        root.addArrangedSubview(ModuleIconView(module: module))

        let details = NSStackView()
        details.orientation = .vertical
        details.alignment = .leading
        details.spacing = 5
        details.setContentHuggingPriority(.defaultLow, for: .horizontal)
        details.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let title = NSTextField(labelWithString: module.title)
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.textColor = NSColor(calibratedWhite: 0.11, alpha: 1)
        title.lineBreakMode = .byTruncatingTail
        details.addArrangedSubview(title)

        let subtitle = NSTextField(labelWithString: module.subtitle)
        subtitle.font = NSFont.systemFont(ofSize: 12)
        subtitle.textColor = NSColor.secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        subtitle.lineBreakMode = .byTruncatingTail
        details.addArrangedSubview(subtitle)

        let status = NSTextField(labelWithString: "已内置")
        status.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        status.textColor = module.accentColor
        details.addArrangedSubview(status)
        root.addArrangedSubview(details)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        root.addArrangedSubview(spacer)

        let button = NSButton(title: "打开", target: self, action: #selector(clicked))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.contentTintColor = module.accentColor
        button.widthAnchor.constraint(equalToConstant: 64).isActive = true
        root.addArrangedSubview(button)
    }

    @objc private func clicked() { action() }
}

final class FileAssociationManager {
    static let shared = FileAssociationManager()

    private struct SupportedType {
        let fileExtension: String
        let contentType: UTType
    }

    private let backupKey = "MyAI Office.FileAssociationBackup"
    private let configuredKey = "MyAI Office.FileAssociationConfigured"
    private let types: [SupportedType] = [
        SupportedType(fileExtension: "docx", contentType: .init(filenameExtension: "docx")!),
        SupportedType(fileExtension: "doc", contentType: .init(filenameExtension: "doc")!),
        SupportedType(fileExtension: "rtf", contentType: .init(filenameExtension: "rtf")!),
        SupportedType(fileExtension: "xlsx", contentType: .init(filenameExtension: "xlsx")!),
        SupportedType(fileExtension: "xls", contentType: .init(filenameExtension: "xls")!),
        SupportedType(fileExtension: "csv", contentType: .init(filenameExtension: "csv")!),
        SupportedType(fileExtension: "pptx", contentType: .init(filenameExtension: "pptx")!),
        SupportedType(fileExtension: "ppt", contentType: .init(filenameExtension: "ppt")!),
        SupportedType(fileExtension: "pdf", contentType: .pdf
        )
    ]

    private init() {}

    var supportedFileSummary: String {
        "DOCX · DOC · XLSX · XLS · PPTX · PPT · PDF"
    }

    var areAllDefaultsMyAI: Bool {
        types.allSatisfy { currentDefault(for: $0) == Bundle.main.bundleURL.standardizedFileURL }
    }

    var statusText: String {
        areAllDefaultsMyAI ? "MyAI Office 已是这些文件的默认打开方式" : "当前仍有文件类型使用其它应用打开"
    }

    func configureOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: configuredKey) else { return }
        captureCurrentDefaults()
        applyDefaults { success in
            if success { UserDefaults.standard.set(true, forKey: self.configuredKey) }
        }
    }

    func applyDefaults(completion: ((Bool) -> Void)?) {
        captureCurrentDefaults()
        setDefault(at: 0, errors: [], completion: completion)
    }

    func restorePreviousDefaults(completion: ((Bool) -> Void)?) {
        let backup = UserDefaults.standard.dictionary(forKey: backupKey) as? [String: String] ?? [:]
        restore(at: 0, backup: backup, errors: [], completion: completion)
    }

    private func probeURL(for type: SupportedType) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("myai-office-association-probe.\(type.fileExtension)")
    }

    private func currentDefault(for type: SupportedType) -> URL? {
        let probe = probeURL(for: type)
        FileManager.default.createFile(atPath: probe.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: probe) }
        return NSWorkspace.shared.urlForApplication(toOpen: probe)?.standardizedFileURL
    }

    private func captureCurrentDefaults() {
        guard UserDefaults.standard.dictionary(forKey: backupKey) == nil else { return }
        var backup: [String: String] = [:]
        for type in types {
            guard let url = currentDefault(for: type), url.path != Bundle.main.bundleURL.standardizedFileURL.path else { continue }
            backup[type.fileExtension] = url.path
        }
        UserDefaults.standard.set(backup, forKey: backupKey)
    }

    private func setDefault(at index: Int, errors: [String], completion: ((Bool) -> Void)?) {
        guard index < types.count else {
            completion?(errors.isEmpty)
            return
        }
        let type = types[index]
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type.contentType) { [weak self] error in
            guard let self else { return }
            var nextErrors = errors
            if let error { nextErrors.append("\(type.fileExtension): \(error.localizedDescription)") }
            self.setDefault(at: index + 1, errors: nextErrors, completion: completion)
        }
    }

    private func restore(at index: Int, backup: [String: String], errors: [String], completion: ((Bool) -> Void)?) {
        guard index < types.count else {
            completion?(errors.isEmpty)
            return
        }
        let type = types[index]
        if let previousPath = backup[type.fileExtension], FileManager.default.fileExists(atPath: previousPath) {
            NSWorkspace.shared.setDefaultApplication(at: URL(fileURLWithPath: previousPath), toOpen: type.contentType) { [weak self] error in
                guard let self else { return }
                var nextErrors = errors
                if let error { nextErrors.append("\(type.fileExtension): \(error.localizedDescription)") }
                self.restore(at: index + 1, backup: backup, errors: nextErrors, completion: completion)
            }
        } else {
            restore(at: index + 1, backup: backup, errors: errors, completion: completion)
        }
    }
}

final class SettingsWindowController: NSWindowController {
    private let defaultCheck = NSButton(checkboxWithTitle: "将 MyAI Office 设为默认打开方式", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let manager = FileAssociationManager.shared

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 468),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "文件关联设置"
        window.center()
        window.isRestorable = false
        window.restorationClass = nil
        window.identifier = nil
        super.init(window: window)
        defaultCheck.target = self
        defaultCheck.action = #selector(toggleDefault)
        buildUI()
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedRed: 0.95, green: 0.97, blue: 0.98, alpha: 1).cgColor

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -26)
        ])

        let title = NSTextField(labelWithString: "文件打开方式")
        title.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(title)

        let description = NSTextField(labelWithString: "安装后首次启动会设置常用办公文件由 MyAI Office 打开。你也可以在这里随时切换。")
        description.font = NSFont.systemFont(ofSize: 13)
        description.textColor = NSColor.secondaryLabelColor
        description.maximumNumberOfLines = 2
        description.lineBreakMode = .byWordWrapping
        description.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(description)

        let panel = NSStackView()
        panel.orientation = .vertical
        panel.alignment = .leading
        panel.spacing = 13
        panel.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 14
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.22).cgColor
        panel.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.98).cgColor
        panel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(panel)

        defaultCheck.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        panel.addArrangedSubview(defaultCheck)

        let typesLabel = NSTextField(labelWithString: "覆盖类型  \(manager.supportedFileSummary)")
        typesLabel.font = NSFont.systemFont(ofSize: 12)
        typesLabel.textColor = NSColor.secondaryLabelColor
        panel.addArrangedSubview(typesLabel)

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 10
        let applyButton = NSButton(title: "立即应用", target: self, action: #selector(applyDefaults))
        applyButton.bezelStyle = .rounded
        applyButton.controlSize = .large
        actions.addArrangedSubview(applyButton)
        let restoreButton = NSButton(title: "恢复之前方式", target: self, action: #selector(restoreDefaults))
        restoreButton.bezelStyle = .rounded
        restoreButton.controlSize = .large
        actions.addArrangedSubview(restoreButton)
        panel.addArrangedSubview(actions)

        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = NSColor(calibratedRed: 0.04, green: 0.47, blue: 0.49, alpha: 1)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusLabel)

        let note = NSTextField(labelWithString: "删除应用时，macOS 会移除 MyAI Office 的文件关联并回落到其它可用应用。若要精确恢复安装前的选择，请在删除前点击“恢复之前方式”。")
        note.font = NSFont.systemFont(ofSize: 12)
        note.textColor = NSColor.tertiaryLabelColor
        note.maximumNumberOfLines = 3
        note.lineBreakMode = .byWordWrapping
        note.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(note)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor),
            title.topAnchor.constraint(equalTo: root.topAnchor),
            description.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            description.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            description.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            panel.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            panel.topAnchor.constraint(equalTo: description.bottomAnchor, constant: 18),
            panel.heightAnchor.constraint(equalToConstant: 128),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: panel.bottomAnchor, constant: 14),
            note.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            note.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            note.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 14),
            note.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor)
        ])
    }

    @objc private func toggleDefault() {
        if defaultCheck.state == .on {
            applyDefaults()
        } else {
            restoreDefaults()
        }
    }

    @objc private func applyDefaults() {
        manager.applyDefaults { [weak self] success in
            self?.statusLabel.stringValue = success ? "已应用默认打开方式" : "部分文件类型未能应用，请重试"
            self?.refresh()
        }
    }

    @objc private func restoreDefaults() {
        manager.restorePreviousDefaults { [weak self] success in
            self?.statusLabel.stringValue = success ? "已恢复安装前的打开方式" : "部分文件类型未能恢复，请重试"
            self?.refresh()
        }
    }

    private func refresh() {
        defaultCheck.state = manager.areAllDefaultsMyAI ? .on : .off
        if statusLabel.stringValue.isEmpty { statusLabel.stringValue = manager.statusText }
    }
}

final class SuiteWindowController: NSWindowController, NSWindowDelegate {
    private let statusLabel = NSTextField(labelWithString: "请选择一个模块，或直接打开已有文件")
    private let versionLabel = NSTextField(labelWithString: "MyAI Office \(MyAIOfficeUpdateManager.currentVersion)")
    private let updateDot = NSView()
    private let upgradeButton = NSButton(title: "升级", target: nil, action: nil)
    private var settingsController: SettingsWindowController?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1020, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MyAI Office"
        window.center()
        window.minSize = NSSize(width: 860, height: 620)
        window.isRestorable = false
        window.restorationClass = nil
        window.identifier = nil
        super.init(window: window)
        window.delegate = self
        buildUI()
        MyAIOfficeUpdateManager.shared.observe { [weak self] state in
            self?.renderUpdateState(state)
        }
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedRed: 0.95, green: 0.97, blue: 0.98, alpha: 1).cgColor

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        let header = GradientView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.heightAnchor.constraint(equalToConstant: 144).isActive = true

        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 15
        headerStack.edgeInsets = NSEdgeInsets(top: 22, left: 32, bottom: 22, right: 32)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerStack)
        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerStack.topAnchor.constraint(equalTo: header.topAnchor),
            headerStack.bottomAnchor.constraint(equalTo: header.bottomAnchor)
        ])

        headerStack.addArrangedSubview(LogoView())

        let heading = NSStackView()
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 4
        let brand = NSTextField(labelWithString: "MyAI Office")
        brand.font = NSFont.systemFont(ofSize: 29, weight: .bold)
        brand.textColor = .white
        heading.addArrangedSubview(brand)
        let tagline = NSTextField(labelWithString: "一套入口，办公与 AI 工作流")
        tagline.font = NSFont.systemFont(ofSize: 14)
        tagline.textColor = NSColor.white.withAlphaComponent(0.88)
        heading.addArrangedSubview(tagline)
        headerStack.addArrangedSubview(heading)

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerStack.addArrangedSubview(headerSpacer)

        let aiBadge = NSTextField(labelWithString: "AI 助手 · 即将加入")
        aiBadge.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        aiBadge.textColor = NSColor.white.withAlphaComponent(0.94)
        aiBadge.alignment = .center
        aiBadge.wantsLayer = true
        aiBadge.layer?.cornerRadius = 10
        aiBadge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        aiBadge.widthAnchor.constraint(equalToConstant: 122).isActive = true
        aiBadge.heightAnchor.constraint(equalToConstant: 30).isActive = true
        headerStack.addArrangedSubview(aiBadge)

        let settingsButton = NSButton(
            title: "设置",
            image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "文件关联设置") ?? NSImage(),
            target: self,
            action: #selector(openSettings)
        )
        settingsButton.isBordered = false
        settingsButton.imagePosition = .imageLeading
        settingsButton.contentTintColor = NSColor.white.withAlphaComponent(0.92)
        settingsButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        settingsButton.setAccessibilityLabel("文件关联设置")
        settingsButton.toolTip = "文件关联设置"
        settingsButton.widthAnchor.constraint(equalToConstant: 62).isActive = true
        settingsButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
        headerStack.addArrangedSubview(settingsButton)

        let openButton = NSButton(title: "打开文件…", target: self, action: #selector(openFile))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .large
        openButton.bezelColor = NSColor.white.withAlphaComponent(0.92)
        openButton.attributedTitle = NSAttributedString(
            string: "打开文件…",
            attributes: [
                .foregroundColor: NSColor(calibratedRed: 0.03, green: 0.34, blue: 0.42, alpha: 1),
                .font: NSFont.systemFont(ofSize: 13, weight: .medium)
            ]
        )
        openButton.widthAnchor.constraint(equalToConstant: 112).isActive = true
        headerStack.addArrangedSubview(openButton)
        root.addArrangedSubview(header)

        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .width
        body.spacing = 16
        body.edgeInsets = NSEdgeInsets(top: 27, left: 32, bottom: 22, right: 32)
        body.setContentHuggingPriority(.defaultLow, for: .vertical)

        let intro = NSStackView()
        intro.orientation = .vertical
        intro.alignment = .leading
        intro.spacing = 5
        let eyebrow = NSTextField(labelWithString: "WORKSPACE")
        eyebrow.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        eyebrow.textColor = NSColor(calibratedRed: 0.04, green: 0.47, blue: 0.49, alpha: 1)
        intro.addArrangedSubview(eyebrow)
        let welcome = NSTextField(labelWithString: "选择你的工作模块")
        welcome.font = NSFont.systemFont(ofSize: 23, weight: .semibold)
        welcome.textColor = NSColor(calibratedWhite: 0.10, alpha: 1)
        intro.addArrangedSubview(welcome)
        let hint = NSTextField(labelWithString: "编辑源文件，或打开已有文档继续工作。导出的 PDF 可交给 MyAI PDF 继续整理。")
        hint.font = NSFont.systemFont(ofSize: 13)
        hint.textColor = NSColor.secondaryLabelColor
        intro.addArrangedSubview(hint)
        body.addArrangedSubview(intro)

        body.addArrangedSubview(moduleRow(.writer, .sheet))
        body.addArrangedSubview(moduleRow(.slides, .pdf))

        let infoBox = NSStackView()
        infoBox.orientation = .horizontal
        infoBox.alignment = .centerY
        infoBox.spacing = 12
        infoBox.edgeInsets = NSEdgeInsets(top: 11, left: 14, bottom: 11, right: 14)
        infoBox.wantsLayer = true
        infoBox.layer?.cornerRadius = 12
        infoBox.layer?.backgroundColor = NSColor(calibratedRed: 0.88, green: 0.96, blue: 0.95, alpha: 1).cgColor

        let infoImage = NSImageView(image: NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI") ?? NSImage())
        infoImage.contentTintColor = NSColor(calibratedRed: 0.05, green: 0.48, blue: 0.45, alpha: 1)
        infoImage.imageScaling = .scaleProportionallyUpOrDown
        infoImage.widthAnchor.constraint(equalToConstant: 20).isActive = true
        infoImage.heightAnchor.constraint(equalToConstant: 20).isActive = true
        infoBox.addArrangedSubview(infoImage)

        let info = NSTextField(labelWithString: "PDF 工作台已内嵌。DOCX / XLSX / PPTX 使用各自原生排版引擎导出 PDF，AI 功能将在后续版本加入。")
        info.font = NSFont.systemFont(ofSize: 12)
        info.textColor = NSColor(calibratedRed: 0.05, green: 0.32, blue: 0.34, alpha: 1)
        info.maximumNumberOfLines = 2
        info.lineBreakMode = .byTruncatingTail
        infoBox.addArrangedSubview(info)
        body.addArrangedSubview(infoBox)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = NSColor.secondaryLabelColor
        footer.addArrangedSubview(statusLabel)
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(footerSpacer)
        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.textColor = NSColor.tertiaryLabelColor
        versionLabel.setAccessibilityLabel("当前版本 \(MyAIOfficeUpdateManager.currentVersion)")

        updateDot.wantsLayer = true
        updateDot.layer?.cornerRadius = 4
        updateDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        updateDot.isHidden = true
        updateDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        updateDot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        updateDot.toolTip = "有新版本可升级"
        updateDot.setAccessibilityLabel("有新版本可升级")

        upgradeButton.target = self
        upgradeButton.action = #selector(startUpdate)
        upgradeButton.bezelStyle = .rounded
        upgradeButton.controlSize = .small
        upgradeButton.contentTintColor = NSColor(calibratedRed: 0.03, green: 0.42, blue: 0.45, alpha: 1)
        upgradeButton.isHidden = true
        upgradeButton.setAccessibilityLabel("升级 MyAI Office")
        upgradeButton.toolTip = "升级 MyAI Office"

        let versionCluster = NSStackView(views: [versionLabel, updateDot, upgradeButton])
        versionCluster.orientation = .horizontal
        versionCluster.alignment = .centerY
        versionCluster.spacing = 7
        footer.addArrangedSubview(versionCluster)
        body.addArrangedSubview(footer)

        let bottomSpacer = NSView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        body.addArrangedSubview(bottomSpacer)
        root.addArrangedSubview(body)
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func startUpdate() {
        MyAIOfficeUpdateManager.shared.startPendingUpdate()
    }

    private func renderUpdateState(_ state: MyAIOfficeUpdateState) {
        switch state {
        case .available(let version, let notes):
            updateDot.isHidden = false
            upgradeButton.isHidden = false
            upgradeButton.isEnabled = true
            upgradeButton.title = "升级"
            upgradeButton.toolTip = notes.isEmpty ? "升级到 MyAI Office \(version)" : "升级到 MyAI Office \(version)：\(notes)"
        case .downloading(let version):
            updateDot.isHidden = false
            upgradeButton.isHidden = false
            upgradeButton.isEnabled = false
            upgradeButton.title = "下载中…"
            upgradeButton.toolTip = "正在下载 MyAI Office \(version)"
        case .installing(let version):
            updateDot.isHidden = false
            upgradeButton.isHidden = false
            upgradeButton.isEnabled = false
            upgradeButton.title = "安装中…"
            upgradeButton.toolTip = "正在安装 MyAI Office \(version)，完成后自动重启"
        case .failed(let message):
            updateDot.isHidden = false
            upgradeButton.isHidden = false
            upgradeButton.isEnabled = true
            upgradeButton.title = "重试"
            upgradeButton.toolTip = message
        case .idle, .checking:
            updateDot.isHidden = true
            upgradeButton.isHidden = true
            upgradeButton.isEnabled = false
        }
    }

    func showSettings() {
        if settingsController == nil { settingsController = SettingsWindowController() }
        settingsController?.showWindow(nil)
        settingsController?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func moduleRow(_ first: OfficeModule, _ second: OfficeModule) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 16
        row.distribution = .fillEqually
        row.addArrangedSubview(ModuleCard(module: first) { [weak self] in self?.launch(first) })
        row.addArrangedSubview(ModuleCard(module: second) { [weak self] in self?.launch(second) })
        return row
    }

    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "docx"), UTType(filenameExtension: "doc"), UTType(filenameExtension: "rtf"),
            UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "xls"), UTType(filenameExtension: "csv"),
            UTType(filenameExtension: "pptx"), UTType(filenameExtension: "pdf")
        ].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    func open(url: URL) {
        guard let module = module(for: url) else {
            showError(title: "无法识别文件", message: "MyAI Office 暂时没有为此扩展名配置编辑器。")
            return
        }
        launch(module, url: url)
    }

    private func module(for url: URL) -> OfficeModule? {
        switch url.pathExtension.lowercased() {
        case "docx", "doc", "rtf", "rtfd", "odt", "txt", "md", "html": return .writer
        case "xlsx", "xls", "csv", "tsv": return .sheet
        case "pptx", "ppt", "odp": return .slides
        case "pdf": return .pdf
        default: return nil
        }
    }

    private func helperURL(for module: OfficeModule) -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(module.helperName, isDirectory: false)
    }

    private func launch(_ module: OfficeModule, url: URL? = nil) {
        let helper = helperURL(for: module)
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            showError(
                title: "模块尚未构建",
                message: "找不到 \(module.title) 的运行文件。\n请重新运行套件构建脚本。"
            )
            return
        }
        let task = Process()
        task.executableURL = helper
        task.arguments = url.map { [$0.path] } ?? []
        var environment = ProcessInfo.processInfo.environment
        environment["MYAI_OFFICE_LANGUAGE"] = "zh-hans"
        task.environment = environment
        do {
            try task.run()
            statusLabel.stringValue = "已打开 \(module.title)"
        } catch {
            showError(title: "启动失败", message: error.localizedDescription)
        }
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: SuiteWindowController?
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        controller = SuiteWindowController()
        mainWindow = controller?.window
        controller?.showWindow(nil)
        controller?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            FileAssociationManager.shared.configureOnFirstLaunch()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            MyAIOfficeUpdateManager.shared.checkForUpdates(presenting: self.mainWindow)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let controller, let window = mainWindow else { return }
        if !window.isVisible {
            controller.showWindow(nil)
            window.orderFrontRegardless()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let controller, let window = mainWindow else { return false }
        if !flag || !window.isVisible {
            controller.showWindow(nil)
            window.orderFrontRegardless()
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if controller == nil {
            applicationDidFinishLaunching(Notification(name: Notification.Name("MyAIOfficeLaunch")))
        }
        controller?.open(url: url)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        if controller == nil {
            applicationDidFinishLaunching(Notification(name: Notification.Name("MyAIOfficeOpen")))
        }
        controller?.open(url: url)
        return true
    }
}

@main
struct MyAIOfficeMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
