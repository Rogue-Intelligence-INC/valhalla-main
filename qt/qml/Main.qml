import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtCore

// VAL-DAL main edition — FluentWinUI3 controls with the VAL-DAL minimal agent layout:
// title bar · icon rail · session list · conversation canvas · 边栏.
// One settings entry (title bar), one status light (rail, opens the status popup),
// settings is a full-screen page.
ApplicationWindow {
    id: win
    width: 1360; height: 860; minimumWidth: 860; minimumHeight: 600
    visible: true
    title: "VAL-DAL"
    color: win.c.bg

    property bool dark: true
    property int page: 0            // 0 chat, 1 workspace, 2 settings (full screen)
    property int settingsSection: 0 // pipeline, online, knowledge, appearance, accounts, about
    property bool listOpen: true
    property bool sidebarOpen: false
    property bool webMode: false
    property string cdkMsg: ""
    property string grabName: "grab.png"
    property string schedText: ""
    property double schedAt: 0
    property int toolId: -1
    readonly property bool listShown: listOpen && page === 0 && width >= 1000
    readonly property bool drawerFloat: width < 1180

    readonly property QtObject c: QtObject {
        readonly property color bg:      win.dark ? "#101112" : "#f6f6f4"
        readonly property color side:    win.dark ? "#141516" : "#efefec"
        readonly property color panel:   win.dark ? "#171819" : "#ffffff"
        readonly property color raised:  win.dark ? "#1c1e1e" : "#ffffff"
        readonly property color line:    win.dark ? "#303233" : "#d9dbd8"
        readonly property color line2:   win.dark ? "#252728" : "#e6e7e4"
        readonly property color hover:   win.dark ? "#262829" : "#e7e8e4"
        readonly property color active:  win.dark ? "#27292a" : "#e0e2de"
        readonly property color text:    win.dark ? "#e6e7e5" : "#1d1f1e"
        readonly property color strong:  win.dark ? "#f1f1ed" : "#111312"
        readonly property color soft:    win.dark ? "#b7b9b7" : "#4a4e4c"
        readonly property color muted:   win.dark ? "#808485" : "#6f7372"
        readonly property color low:     win.dark ? "#5f6364" : "#9a9e9c"
        readonly property color accent:  win.dark ? "#d8dbd4" : "#1f2321"
        readonly property color ink:     win.dark ? "#151716" : "#f4f5f1"
        readonly property color good:    win.dark ? "#a6b89d" : "#5f8a4e"
        readonly property color warn:    win.dark ? "#d1b36a" : "#a88420"
        readonly property color bad:     win.dark ? "#d27a6e" : "#b4493b"
        readonly property color composer: win.dark ? "#171919" : "#ffffff"
        readonly property color composerLine: win.dark ? "#4b504e" : "#c9ccc8"
        readonly property color focus:   win.dark ? "#8f9690" : "#6f7672"
    }
    palette.accent: win.c.accent
    palette.highlight: win.c.accent
    palette.highlightedText: win.c.ink

    Settings { id: store; category: "valdal-main"; property string plan: ""; property string code: ""; property bool darkTheme: true }
    function t(zh, en) { return bridge.lang === "zh" ? zh : en }
    function applyTheme() { bridge.setDarkTheme(win.dark) }
    function goSettings(section) { win.settingsSection = section; win.page = 2 }
    function cdkPlanName(p) { return p === "MAX" ? t("Max 专业版", "Max Pro") : p === "ENT" ? t("企业定制版", "Enterprise") : t("Pro 个人版", "Pro") }
    function redeemCdk(raw) {
        var code = raw.toUpperCase().replace(/\s/g, ""); var parts = code.split("-")
        if (parts.length !== 5 || parts[0] !== "VALDAL" || (parts[1] !== "PRO" && parts[1] !== "MAX" && parts[1] !== "ENT")) { win.cdkMsg = t("兑换码格式不正确，应为 VALDAL-PRO-……", "Invalid code format (VALDAL-PRO-...)"); return }
        var flat = code.replace(/-/g, ""); var body = flat.substring(0, flat.length - 1); var sum = 0
        for (var i = 0; i < body.length; i++) sum += body.charCodeAt(i)
        var cs = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        if (cs.charAt((sum * 31 + 17) % 36) !== flat.charAt(flat.length - 1)) { win.cdkMsg = t("兑换码无效，请检查后重试，或联系 joulyman@gmail.com", "Code not recognized. Check it, or contact joulyman@gmail.com"); return }
        store.plan = parts[1]; store.code = code
        if (parts[1] === "ENT") bridge.setEnterpriseActive(true)
        win.cdkMsg = t("兑换成功，已开通 ", "Redeemed: ") + win.cdkPlanName(parts[1])
    }
    // 0 red, 1 yellow, 2 green
    function sigPipeline() { return bridge.pipelineBusy ? 1 : (bridge.enginePresent && bridge.modelInstalled ? 2 : (bridge.enginePresent ? 1 : 0)) }
    function sigModel() { return bridge.modelLoaded ? 2 : (bridge.modelInstalled ? 1 : 0) }
    function sigLink() { return !bridge.enginePresent ? 0 : (store.plan !== "" ? 2 : 1) }
    // Online not configured is normal for the local edition, so it does not dim the single light.
    function sigAll() { return Math.min(sigPipeline(), sigModel(), sigLink() === 0 ? 0 : 2) }
    function sigColor(s) { return s === 2 ? win.c.good : s === 1 ? win.c.warn : win.c.bad }
    function sigWord(s) { return s === 2 ? t("运行正常", "All good") : s === 1 ? t("需要注意", "Attention") : t("异常", "Problem") }
    function stageState(i) {
        if (bridge.busy) return i === 0 ? 2 : (i === 1 ? 1 : 0)
        if (bridge.turnCount === 0) return 0
        return 2
    }
    function stagesDone() { var n = 0; for (var i = 0; i < 4; i++) if (stageState(i) === 2) n++; return n }
    function shortModel() { var m = bridge.currentModelName; var k = m.lastIndexOf("/"); return k >= 0 ? m.substring(k + 1) : m }
    function userInitial() { var u = bridge.currentUser || "U"; return u.substring(0, 1).toUpperCase() }
    function doSend() {
        var q = input.text.trim()
        if (q === "" || bridge.busy || bridge.webBusy) return
        if (win.webMode) bridge.webSearch(q, true); else bridge.send(q)
        input.clear()
    }
    function prefill(s) { input.text = s; input.cursorPosition = s.length; input.forceActiveFocus(); win.page = 0 }
    // Inline execution record derived from the tools the backend recorded for that turn.
    function stepsFor(m) {
        var tools = m.tools || []; if (tools.length === 0) return []
        var out = [{ ico: "\uE73E", tone: 2, zh: "理解问题", en: "Understood the request" }]
        for (var i = 0; i < tools.length; i++) {
            var s = tools[i]
            if (s.indexOf("web:") === 0) out.push({ ico: "\uE774", tone: 2, zh: "联网查找 · " + s.substring(4) + " 条来源", en: "Web search · " + s.substring(4) + " sources" })
            else if (s === "screen") out.push({ ico: "\uE7F4", tone: 2, zh: "读取屏幕 / OCR 上下文", en: "Read screen / OCR context" })
            else if (s.indexOf("file:") === 0) out.push({ ico: "\uE723", tone: 2, zh: "读取文件 · " + s.substring(5), en: "Read files · " + s.substring(5) })
            else if (s === "task") out.push({ ico: "\uE9D5", tone: 2, zh: "任务模式执行", en: "Ran in task mode" })
        }
        out.push({ ico: "\uE721", tone: 2, zh: "结构检索本地知识", en: "Structured retrieval" })
        if (tools.indexOf("control") >= 0) out.push({ ico: "\uE7C9", tone: 2, zh: "执行电脑操作", en: "Ran computer actions" })
        if (tools.indexOf("control-blocked") >= 0) out.push({ ico: "\uE7BA", tone: 1, zh: "电脑控制未授权，操作已跳过", en: "Computer control off; actions skipped" })
        out.push({ ico: "\uE73E", tone: 2, zh: "生成回答" + (m.badge ? " · " + m.badge : ""), en: "Answered" + (m.badge ? " · " + m.badge : "") })
        return out
    }
    function elapsedOf(m) { var tools = m.tools || []; for (var i = 0; i < tools.length; i++) if (tools[i].indexOf("elapsed:") === 0) return tools[i].substring(8) + " s"; return "" }
    function openTool(id) { win.toolId = id; toolPop.open() }
    function runAction(a) {
        toolPop.close()
        if (a === "attach") attachDlg.open()
        else if (a === "screen") bridge.recognize()
        else if (a === "ocr") ocrDlg.open()
        else if (a === "ctl-on") { if (!bridge.allowControl) ctlDlg.open() }
        else if (a === "ctl-off") bridge.setAllowControl(false)
        else if (a === "web-on") win.webMode = true
        else if (a === "web-off") win.webMode = false
        else if (a === "kb") win.goSettings(2)
        else if (a === "kb-import") kbDlg.open()
        else if (a === "task") bridge.setTaskMode(!bridge.taskMode)
        else if (a === "sched") schedDlg.open()
        else if (a === "export") exportDlg.open()
        else if (a === "clear") bridge.clearContext()
        else if (a === "drawer") win.sidebarOpen = true
        else if (a === "models") win.goSettings(0)
    }
    readonly property var tools: [
        { zh: "文件", en: "Files", dz: "把文本、代码、表格等文件内容带入本轮上下文。", de: "Bring text, code or table files into this turn's context.",
          acts: [{ id: "attach", zh: "附加文件", en: "Attach files" }, { id: "clear", zh: "清空上下文", en: "Clear context" }] },
        { zh: "屏幕", en: "Screen", dz: "识别当前屏幕的文字与控件，或用 OCR 读取图片。", de: "Read on-screen text and controls, or OCR images.",
          acts: [{ id: "screen", zh: "识别屏幕", en: "Recognize screen" }, { id: "ocr", zh: "OCR 导入图片", en: "OCR images" }] },
        { zh: "电脑控制", en: "Computer control", dz: "默认关闭。开启后，回答中的操作会在本机执行，需先确认。", de: "Off by default. When on, actions in answers run on this PC after confirmation.",
          acts: [{ id: "ctl-on", zh: "请求授权", en: "Allow" }, { id: "ctl-off", zh: "关闭", en: "Turn off" }] },
        { zh: "联网查找", en: "Web search", dz: "回答前先检索最新来源，结果归入本轮上下文。", de: "Fetch fresh sources before answering; results join the context.",
          acts: [{ id: "web-on", zh: "开启检索", en: "Turn on" }, { id: "web-off", zh: "仅本地", en: "Local only" }] },
        { zh: "知识", en: "Knowledge", dz: "本地知识库是回答的依据来源，可直接编辑或导入资料。", de: "The local knowledge base is the evidence source; edit or import files.",
          acts: [{ id: "kb", zh: "打开知识库", en: "Open knowledge" }, { id: "kb-import", zh: "导入资料", en: "Import files" }] },
        { zh: "任务调度", en: "Tasks", dz: "任务模式直接执行并汇报结果；也可把当前输入定时执行。", de: "Task mode executes and reports; or schedule the current input.",
          acts: [{ id: "task", zh: "切换任务模式", en: "Toggle task mode" }, { id: "sched", zh: "定时执行…", en: "Schedule…" }] },
        { zh: "更多", en: "More", dz: "导出对话、查看边栏中的执行进度与权限。", de: "Export the chat, or open the sidebar for progress and permissions.",
          acts: [{ id: "export", zh: "导出对话", en: "Export chat" }, { id: "drawer", zh: "打开边栏", en: "Open sidebar" }, { id: "models", zh: "管理模型", en: "Manage models" }] } ]

    function dumpTree(item, depth) {
        if (depth > 6 || !item) return
        var s = ""; for (var k = 0; k < depth; k++) s += "  "
        console.log(s + item.toString().split("(")[0].split("_QML")[0] + " x=" + Math.round(item.x) + " y=" + Math.round(item.y) + " w=" + Math.round(item.width) + " h=" + Math.round(item.height) + " vis=" + item.visible + (item.text ? " text=" + item.text : ""))
        var ch = item.children || []
        for (var i = 0; i < ch.length; i++) dumpTree(ch[i], depth + 1)
    }
    Component.onCompleted: {
        win.dark = store.darkTheme
        if (Qt.application.arguments.indexOf("--dump") >= 0) Qt.callLater(function(){ win.dumpTree(win.contentItem, 0) })
        if (Qt.application.arguments.indexOf("--grab") >= 0) grabTimer.start()
        var args = Qt.application.arguments
        for (var i = 0; i < args.length; i++) {
            if (args[i] === "--light") win.dark = false
            else if (args[i] === "--dark") win.dark = true
            else if (args[i].indexOf("--page=") === 0) win.page = parseInt(args[i].substring(7))
            else if (args[i].indexOf("--section=") === 0) win.settingsSection = parseInt(args[i].substring(10))
            else if (args[i].indexOf("--grabname=") === 0) win.grabName = args[i].substring(11)
            else if (args[i] === "--status") Qt.callLater(function(){ statusPopup.open() })
            else if (args[i] === "--drawer") win.sidebarOpen = true
            else if (args[i].indexOf("--prefill=") === 0) { var pf = args[i].substring(10); Qt.callLater(function(){ input.text = pf.replace(/\\n/g, "\n") }) }
            else if (args[i].indexOf("--tool=") === 0) { var n = parseInt(args[i].substring(7)); Qt.callLater(function(){ win.openTool(n) }) }
            else if (args[i] === "--buyinfo") { win.page = 2; win.settingsSection = 1; buyInfoDlg.open() }
        }
        applyTheme(); if (bridge.accountsEnabled) loginDlg.open()
    }
    onDarkChanged: { store.darkTheme = win.dark; applyTheme() }

    // ===== shared components =====
    component Ico: Text { font.family: "Segoe Fluent Icons"; font.pixelSize: 16; color: win.c.soft; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
    component BrandMark: Item {
        property real u: 4; property color ink: win.c.accent
        width: u * 4.5; height: u * 4.5
        Grid { anchors.centerIn: parent; columns: 3; spacing: u * 0.75; rotation: -18
            Repeater { model: [1, 0.3, 1, 1, 0, 0.3, 1, 1, 1]
                Rectangle { required property real modelData; width: u; height: u; radius: u * 0.22; color: ink; opacity: modelData } } }
    }
    component Ghost: AbstractButton {
        id: gb
        property string ico: ""; property string tip: ""; property bool on: false; property real size: 17; property string label: ""
        implicitWidth: label === "" ? 34 : row.implicitWidth + 20; implicitHeight: 32
        hoverEnabled: true
        background: Rectangle { radius: 5; color: gb.on || gb.down ? win.c.active : (gb.hovered ? win.c.hover : "transparent"); border.color: gb.label !== "" ? win.c.line : "transparent" }
        contentItem: Item { RowLayout { id: row; anchors.centerIn: parent; spacing: 6
            Ico { text: gb.ico; font.pixelSize: gb.size; color: !gb.enabled ? win.c.low : (gb.on || gb.hovered ? win.c.strong : win.c.soft) }
            Text { visible: gb.label !== ""; text: gb.label; font.pixelSize: 11; color: gb.hovered ? win.c.strong : win.c.soft } } }
        ToolTip.visible: hovered && tip !== ""; ToolTip.text: tip; ToolTip.delay: 350
    }
    component RailBtn: AbstractButton {
        id: rb
        property string ico: ""; property string tip: ""; property bool current: false
        implicitWidth: 39; implicitHeight: 39; hoverEnabled: true
        background: Rectangle { radius: 8; color: rb.current ? win.c.active : (rb.hovered ? win.c.hover : "transparent")
            Rectangle { visible: rb.current; x: -13; y: 11; width: 2; height: 17; radius: 1; color: win.c.accent } }
        contentItem: Ico { text: rb.ico; font.pixelSize: 18; color: rb.current ? win.c.strong : win.c.muted }
        ToolTip.visible: hovered && tip !== ""; ToolTip.text: tip; ToolTip.delay: 350
    }
    component Pill: AbstractButton {
        id: pl
        property string ico: ""; property bool primary: false
        implicitHeight: 32; implicitWidth: prow.implicitWidth + 24; hoverEnabled: true
        background: Rectangle { radius: 5; color: pl.primary ? (pl.hovered ? win.c.strong : win.c.accent) : (pl.hovered ? win.c.hover : win.c.active); border.color: pl.primary ? "transparent" : win.c.line; opacity: pl.enabled ? 1 : 0.45 }
        contentItem: Item { RowLayout { id: prow; anchors.centerIn: parent; spacing: 7
            Ico { visible: pl.ico !== ""; text: pl.ico; font.pixelSize: 13; color: pl.primary ? win.c.ink : win.c.text }
            Text { text: pl.text; font.pixelSize: 12; color: pl.primary ? win.c.ink : win.c.text } } }
    }
    component Card: Frame {
        padding: 16
        background: Rectangle { radius: 7; color: win.c.panel; border.color: win.c.line2 }
    }
    component Eyebrow: Text { font.pixelSize: 10; font.letterSpacing: 1.6; color: win.c.muted }
    component H1: Text { font.pixelSize: 20; font.weight: Font.DemiBold; color: win.c.strong; Layout.fillWidth: true; wrapMode: Text.Wrap }
    component H2: Text { font.pixelSize: 13; font.weight: Font.DemiBold; color: win.c.strong; Layout.fillWidth: true; wrapMode: Text.Wrap }
    component Body: Text { font.pixelSize: 12; color: win.c.soft; Layout.fillWidth: true; wrapMode: Text.Wrap; lineHeight: 1.25 }
    component Note: Text { font.pixelSize: 11; color: win.c.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    component Rule: Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: win.c.line2 }
    component Dot: Rectangle { property int level: 2; width: 6; height: 6; radius: 3; color: win.sigColor(level)
        Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: "transparent"; border.color: parent.color; opacity: 0.18; border.width: 2 } }
    component SigRow: RowLayout {
        property string ico: ""; property string name: ""; property int level: 0; property string detail: ""
        spacing: 12; Layout.fillWidth: true
        Rectangle { Layout.alignment: Qt.AlignTop; width: 30; height: 30; radius: 6; color: win.c.active
            Ico { anchors.centerIn: parent; text: ico; font.pixelSize: 14 }
            Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: -2; width: 9; height: 9; radius: 4.5; color: win.sigColor(level); border.color: win.c.raised; border.width: 2 } }
        ColumnLayout { spacing: 2; Layout.fillWidth: true
            Text { text: name; font.pixelSize: 12; font.weight: Font.DemiBold; color: win.c.strong }
            Note { text: detail } }
    }
    component Line2: RowLayout { property string k: ""; property string v: ""; Layout.fillWidth: true
        Text { text: k; font.pixelSize: 11; color: win.c.muted; Layout.fillWidth: true }
        Text { text: v; font.pixelSize: 11; color: win.c.text; elide: Text.ElideLeft; Layout.maximumWidth: 180 } }
    component Perm: RowLayout { property string k: ""; property alias checked: sw.checked; signal toggled(bool on); Layout.fillWidth: true
        Text { text: k; font.pixelSize: 11; color: win.c.soft; Layout.fillWidth: true }
        Switch { id: sw; scale: 0.8; onToggled: parent.toggled(checked) } }

    // ===== status popup (single light on the rail opens it) =====
    Popup { id: statusPopup; x: 72; y: win.height - height - 16; width: 340; padding: 18
        height: statusCol.implicitHeight + 36; modal: false; focus: true; closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 8; color: win.c.raised; border.color: win.c.line }
        ColumnLayout { id: statusCol; anchors.fill: parent; spacing: 14
            RowLayout { Layout.fillWidth: true; spacing: 10
                Dot { level: win.sigAll() }
                H2 { text: t("状态", "Status") + " · " + win.sigWord(win.sigAll()) }
                Ghost { ico: "\uE711"; size: 12; tip: t("关闭", "Close"); onClicked: statusPopup.close() } }
            SigRow { ico: "\uE945"; name: t("Valhalla 管线", "Valhalla pipeline"); level: win.sigPipeline(); detail: bridge.enginePresent ? t("引擎就绪 · 五段管线", "Engine ready · 5-stage pipeline") : t("未找到引擎", "Engine missing") }
            SigRow { ico: "\uE950"; name: t("本地模型", "Local model"); level: win.sigModel(); detail: bridge.currentModelName + " · " + (bridge.modelLoaded ? t("已加载", "Loaded") : t("未加载", "Not loaded")) + " · " + bridge.computeDevice }
            SigRow { ico: "\uE753"; name: t("连接", "Connection"); level: win.sigLink(); detail: store.plan !== "" ? (t("在线 · ", "Online · ") + win.cdkPlanName(store.plan)) : t("本地运行 · 在线版未开通", "Local · online not activated") }
            Note { text: bridge.runtimeText; font.pixelSize: 10; visible: text !== "" }
            RowLayout { spacing: 8
                Pill { text: t("检查运行时", "Probe runtime"); ico: "\uE9D9"; enabled: !bridge.busy; onClicked: bridge.probe() }
                Pill { text: t("修复管线", "Repair pipeline"); ico: "\uE90F"; enabled: !bridge.pipelineBusy; onClicked: { statusPopup.close(); win.goSettings(0); bridge.repairPipeline() } } }
        }
    }

    Timer { id: grabTimer; interval: 2500; onTriggered: rootItem.grabToImage(function(r){ r.saveToFile("C:/Ai/rogue-products/valhalla-windows/qt/shots/" + win.grabName); console.log("GRABBED") }, Qt.size(1360, 860)) }
    Timer { interval: 1000; repeat: true; running: win.schedAt > 0
        onTriggered: if (Date.now() >= win.schedAt && !bridge.busy && !bridge.webBusy) { var q = win.schedText; win.schedAt = 0; win.schedText = ""; win.page = 0; bridge.send(q) } }

    Rectangle { id: rootItem; anchors.fill: parent; color: win.c.bg
    ColumnLayout { anchors.fill: parent; spacing: 0

        // ===== title bar =====
        Rectangle { Layout.fillWidth: true; implicitHeight: 48; color: win.c.bg
            Rule { anchors.bottom: parent.bottom; width: parent.width }
            RowLayout { anchors.fill: parent; anchors.leftMargin: 21; anchors.rightMargin: 14; spacing: 0
                RowLayout { Layout.preferredWidth: win.width < 1000 ? 190 : 251; Layout.maximumWidth: win.width < 1000 ? 190 : 251; spacing: 12
                    BrandMark { u: 4 }
                    Text { text: "VAL–DAL"; font.pixelSize: 14; font.weight: Font.Bold; font.letterSpacing: 1.3; color: win.c.strong }
                    Text { text: "瓦序"; font.pixelSize: 10; font.letterSpacing: 1.4; color: win.c.muted } Item { Layout.fillWidth: true } }
                RowLayout { spacing: 12; visible: win.width >= 760; Layout.fillWidth: true
                    Text { text: bridge.currentWorkspace; font.pixelSize: 12; color: win.c.low; elide: Text.ElideRight; Layout.maximumWidth: 160 }
                    Text { text: "/"; font.pixelSize: 13; color: win.c.low }
                    Text { text: bridge.currentProject; font.pixelSize: 12; color: win.c.soft; elide: Text.ElideRight; Layout.maximumWidth: 160 }
                    Text { visible: win.page === 0; text: "/"; font.pixelSize: 13; color: win.c.low }
                    Text { visible: win.page === 0; text: bridge.chatTitle; font.pixelSize: 12; color: win.c.soft; elide: Text.ElideRight; Layout.maximumWidth: 260; Layout.minimumWidth: 40 }
                    Text { visible: win.page !== 0; text: "/"; font.pixelSize: 13; color: win.c.low }
                    Text { visible: win.page !== 0; text: win.page === 1 ? t("工作区", "Workspace") : t("设置", "Settings"); font.pixelSize: 12; color: win.c.soft } Item { Layout.fillWidth: true } }
                Item { Layout.fillWidth: true; visible: win.width < 760 }
                Text { text: shortModel() + " · " + (store.plan !== "" ? t("在线", "Online") : t("本地", "Local")); font.pixelSize: 11; color: win.c.muted; visible: win.width >= 900; Layout.rightMargin: 14 }
                Rectangle { width: 1; height: 18; color: win.c.line; visible: win.width >= 900; Layout.rightMargin: 8 }
                Ghost { ico: win.dark ? "\uE706" : "\uE708"; tip: t("切换浅色/深色", "Toggle light/dark"); onClicked: win.dark = !win.dark }
                Ghost { ico: "\uE713"; tip: t("设置", "Settings"); on: win.page === 2; onClicked: win.page === 2 ? win.page = 0 : win.goSettings(win.settingsSection) } } }

        RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0

            // ===== icon rail =====
            Rectangle { visible: win.page !== 2; Layout.preferredWidth: 64; Layout.fillHeight: true; color: win.c.side
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: win.c.line2 }
                ColumnLayout { anchors.fill: parent; anchors.topMargin: 21; anchors.bottomMargin: 18; spacing: 12
                    RailBtn { Layout.alignment: Qt.AlignHCenter; ico: "\uE8F2"; tip: t("对话", "Chat"); current: win.page === 0; onClicked: win.page = 0 }
                    RailBtn { Layout.alignment: Qt.AlignHCenter; ico: "\uE8B7"; tip: t("工作区与项目", "Workspaces & projects"); current: win.page === 1; onClicked: win.page = 1 }
                    RailBtn { Layout.alignment: Qt.AlignHCenter; ico: "\uE710"; tip: t("新建会话", "New session"); visible: !win.listShown; enabled: !bridge.busy; onClicked: { bridge.newChat(); win.page = 0; input.forceActiveFocus() } }
                    Item { Layout.fillHeight: true }
                    RailBtn { Layout.alignment: Qt.AlignHCenter; ico: "\uE8A0"; tip: win.listOpen ? t("收起会话列表", "Hide sessions") : t("展开会话列表", "Show sessions"); current: win.listShown; visible: win.page === 0 && win.width >= 1000; onClicked: win.listOpen = !win.listOpen }
                    // the single status light
                    AbstractButton { id: lightBtn; Layout.alignment: Qt.AlignHCenter; implicitWidth: 39; implicitHeight: 39; hoverEnabled: true; onClicked: statusPopup.open()
                        ToolTip.visible: hovered; ToolTip.text: win.sigWord(win.sigAll()) + t(" · 查看管线、模型与连接", " · pipeline, model and connection"); ToolTip.delay: 350
                        background: Rectangle { radius: 8; color: lightBtn.hovered ? win.c.hover : "transparent" }
                        contentItem: Item { Dot { anchors.centerIn: parent; level: win.sigAll(); width: 8; height: 8; radius: 4
                            SequentialAnimation on opacity { running: bridge.busy || bridge.webBusy; loops: Animation.Infinite; NumberAnimation { to: 0.3; duration: 600 } NumberAnimation { to: 1; duration: 600 } } } } }
                } }

            // ===== session list =====
            Rectangle { visible: win.listShown; Layout.preferredWidth: 228; Layout.fillHeight: true; color: win.c.side
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: win.c.line2 }
                ColumnLayout { anchors.fill: parent; anchors.margins: 13; anchors.topMargin: 27; spacing: 0
                    RowLayout { Layout.fillWidth: true; Layout.leftMargin: 7; Layout.bottomMargin: 22
                        Eyebrow { text: t("会话 / SESSIONS", "SESSIONS"); Layout.fillWidth: true }
                        Ghost { ico: "\uE76B"; size: 12; implicitWidth: 26; implicitHeight: 26; tip: t("收起", "Collapse"); onClicked: win.listOpen = false } }
                    AbstractButton { id: newBtn; Layout.fillWidth: true; implicitHeight: 35; hoverEnabled: true; enabled: !bridge.busy; Layout.bottomMargin: 18
                        onClicked: { bridge.newChat(); input.forceActiveFocus() }
                        background: Rectangle { radius: 5; color: newBtn.hovered ? win.c.hover : win.c.active; border.color: win.c.line }
                        contentItem: RowLayout { spacing: 9
                            Ico { text: "\uE710"; font.pixelSize: 12; color: win.c.text; Layout.leftMargin: 12 }
                            Text { text: t("新建会话", "New session"); font.pixelSize: 12; color: win.c.text; Layout.fillWidth: true } } }
                    TextField { id: searchField; Layout.fillWidth: true; Layout.bottomMargin: 18; placeholderText: t("搜索会话", "Search sessions"); font.pixelSize: 11; onTextChanged: bridge.setSearch(text) }
                    ListView { id: convList; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 3; model: bridge.conversations
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        section.property: "project"
                        section.delegate: Text { required property string section; text: section; font.pixelSize: 10; color: win.c.muted; leftPadding: 9; topPadding: 12; bottomPadding: 8 }
                        delegate: AbstractButton { id: cv; required property var modelData; width: ListView.view.width; implicitHeight: 34; hoverEnabled: true
                            onClicked: { bridge.openChat(modelData.id); win.page = 0 }
                            background: Rectangle { radius: 5; color: cv.modelData.active ? win.c.active : (cv.hovered ? win.c.hover : "transparent") }
                            contentItem: RowLayout { spacing: 6
                                Text { text: cv.modelData.title; font.pixelSize: 11; color: cv.modelData.active ? win.c.strong : win.c.muted; Layout.fillWidth: true; elide: Text.ElideRight; Layout.leftMargin: 10 }
                                Ghost { visible: cv.hovered; ico: "\uE74D"; size: 11; implicitWidth: 24; implicitHeight: 24; tip: t("删除会话", "Delete session"); onClicked: bridge.deleteChat(cv.modelData.id) } } } }
                    Rule { Layout.topMargin: 10 }
                    RowLayout { Layout.fillWidth: true; Layout.topMargin: 14; Layout.leftMargin: 8; spacing: 9
                        Rectangle { width: 22; height: 22; radius: 5; color: win.c.accent; Text { anchors.centerIn: parent; text: win.userInitial(); font.pixelSize: 10; font.weight: Font.Bold; color: win.c.ink } }
                        Text { text: bridge.currentUser + " · " + bridge.accountRole; font.pixelSize: 11; color: win.c.muted; Layout.fillWidth: true; elide: Text.ElideRight } } } }

            StackLayout { Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: win.page

                // ===== conversation canvas =====
                Item { id: canvas
                    ColumnLayout { anchors.fill: parent; spacing: 0
                        // chat top
                        Rectangle { Layout.fillWidth: true; implicitHeight: 56; color: win.c.bg
                            Rule { anchors.bottom: parent.bottom; width: parent.width }
                            RowLayout { anchors.fill: parent; anchors.leftMargin: win.width < 950 ? 20 : 35; anchors.rightMargin: 20; spacing: 13
                                Ghost { visible: !win.listShown && win.width >= 1000; ico: "\uE700"; size: 15; tip: t("展开会话列表", "Show sessions"); onClicked: win.listOpen = true }
                                Text { text: bridge.chatTitle; font.pixelSize: 13; font.weight: Font.DemiBold; color: win.c.strong; elide: Text.ElideRight; Layout.maximumWidth: canvas.width * 0.45 }
                                Text { text: "/ " + (bridge.taskMode ? t("Agent 任务", "Agent task") : t("对话", "Chat")); font.pixelSize: 11; color: win.c.muted }
                                Item { Layout.fillWidth: true }
                                Ghost { ico: "\uE78C"; size: 15; tip: t("导出对话（Markdown）", "Export chat (Markdown)"); enabled: msgList.count > 0; onClicked: exportDlg.open() }
                                Ghost { label: t("边栏", "Sidebar"); ico: "\uE8FD"; size: 13; on: win.sidebarOpen; tip: t("执行进度、上下文与权限", "Progress, context and permissions"); onClicked: win.sidebarOpen = !win.sidebarOpen } } }

                        RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                            ColumnLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                                Rectangle { Layout.fillWidth: true; Layout.margins: 14; Layout.bottomMargin: 0; visible: !bridge.envReady && !bridge.envDismissed; radius: 6; color: win.c.panel; border.color: win.c.line; implicitHeight: envRow.implicitHeight + 20
                                    RowLayout { id: envRow; anchors.fill: parent; anchors.margins: 10; spacing: 10
                                        Ico { text: "\uE7BA"; color: win.c.warn; font.pixelSize: 14 }
                                        Body { text: t("运行环境未就绪：", "Runtime not ready: ") + bridge.envReport }
                                        Pill { text: t("一键配置", "Set up"); primary: true; onClicked: bridge.setupEnvironment() }
                                        Ghost { ico: "\uE711"; size: 12; tip: t("关闭", "Dismiss"); onClicked: bridge.dismissEnvSetup() } } }

                                Item { Layout.fillWidth: true; Layout.fillHeight: true
                                    ListView {
                                        id: msgList; anchors.fill: parent; clip: true; spacing: 34
                                        topMargin: win.width < 950 ? 28 : 48; bottomMargin: 24
                                        model: bridge.messages
                                        ScrollBar.vertical: ScrollBar {}
                                        header: Item { width: msgList.width; height: 44
                                            RowLayout { width: Math.min(790, msgList.width - 48); x: (msgList.width - width) / 2; spacing: 15
                                                Text { text: t("今天 · ", "TODAY · ") + Qt.formatDate(new Date(), bridge.lang === "zh" ? "M月d日" : "MMM d"); font.pixelSize: 10; font.letterSpacing: 1.2; color: win.c.low }
                                                Rule {} } }
                                        delegate: Item {
                                            id: md
                                            required property var modelData; required property int index
                                            readonly property var steps: win.stepsFor(modelData)
                                            width: msgList.width; height: mrow.implicitHeight
                                            RowLayout { id: mrow; width: Math.min(790, msgList.width - (win.width < 950 ? 40 : 80)); x: (msgList.width - width) / 2; spacing: 13
                                                Rectangle { Layout.alignment: Qt.AlignTop; Layout.topMargin: 1; width: 26; height: 26; radius: 6
                                                    color: md.modelData.user ? win.c.accent : win.c.active
                                                    Text { visible: md.modelData.user; anchors.centerIn: parent; text: win.userInitial(); font.pixelSize: 11; font.weight: Font.Bold; color: win.c.ink }
                                                    BrandMark { visible: !md.modelData.user && md.modelData.path !== "web"; anchors.centerIn: parent; u: 2.4 }
                                                    Ico { visible: md.modelData.path === "web"; anchors.centerIn: parent; text: "\uE774"; font.pixelSize: 12 } }
                                                ColumnLayout { Layout.fillWidth: true; spacing: 0
                                                    RowLayout { spacing: 10; Layout.bottomMargin: 10
                                                        Text { text: md.modelData.user ? t("你", "You") : (md.modelData.path === "web" ? t("联网来源", "Web sources") : t("瓦序", "VAL-DAL")); font.pixelSize: 12; font.weight: Font.DemiBold; color: win.c.text }
                                                        Text { text: md.modelData.time || ""; font.pixelSize: 10; color: win.c.low } }
                                                    TextEdit { id: msgText; Layout.fillWidth: true; Layout.maximumWidth: 690; text: md.modelData.text; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
                                                        font.pixelSize: md.modelData.path === "web" ? 11 : 13; color: md.modelData.error ? win.c.bad : (md.modelData.path === "web" ? win.c.soft : win.c.text)
                                                        selectionColor: win.c.accent; selectedTextColor: win.c.ink }
                                                    // inline execution record
                                                    Item { visible: md.steps.length > 0; Layout.fillWidth: true; Layout.topMargin: 18; implicitHeight: stepCol.implicitHeight + 4
                                                        Rectangle { x: 0; y: 2; width: 1; height: parent.height - 2; color: win.c.line }
                                                        Rectangle { x: -2; y: 3; width: 5; height: 5; radius: 2.5; color: win.c.soft }
                                                        ColumnLayout { id: stepCol; x: 22; width: Math.min(610, parent.width - 22); spacing: 11
                                                            RowLayout { Layout.fillWidth: true
                                                                Text { text: t("执行过程", "EXECUTION"); font.pixelSize: 10; font.letterSpacing: 0.6; color: win.c.soft; Layout.fillWidth: true }
                                                                Text { text: md.steps.length + t(" 步", " steps") + (win.elapsedOf(md.modelData) ? " · " + win.elapsedOf(md.modelData) : ""); font.pixelSize: 10; color: win.c.muted } }
                                                            Repeater { model: md.steps
                                                                RowLayout { required property var modelData; Layout.fillWidth: true; spacing: 10
                                                                    Ico { text: modelData.ico; font.pixelSize: 12; color: modelData.tone === 2 ? win.c.good : win.c.warn }
                                                                    Text { text: bridge.lang === "zh" ? modelData.zh : modelData.en; font.pixelSize: 11; color: win.c.text; Layout.fillWidth: true; elide: Text.ElideRight }
                                                                    Text { text: modelData.tone === 2 ? t("完成", "Done") : t("跳过", "Skipped"); font.pixelSize: 11; color: win.c.muted } } } } }
                                                    RowLayout { visible: !md.modelData.user; spacing: 2; Layout.topMargin: 12; Layout.leftMargin: -6
                                                        Ghost { ico: "\uE8C8"; size: 13; implicitWidth: 28; implicitHeight: 28; tip: t("复制", "Copy"); onClicked: bridge.copyText(msgText.text) }
                                                        Ghost { ico: "\uE767"; size: 13; implicitWidth: 28; implicitHeight: 28; visible: md.modelData.path !== "web"; tip: t("朗读", "Read aloud"); onClicked: bridge.speakText(msgText.text) }
                                                        Ghost { ico: "\uE71A"; size: 13; implicitWidth: 28; implicitHeight: 28; visible: md.modelData.path !== "web"; tip: t("停止朗读", "Stop reading"); onClicked: bridge.stopSpeak() }
                                                        Ghost { ico: "\uE8F1"; size: 13; implicitWidth: 28; implicitHeight: 28; visible: !md.modelData.error; tip: t("加入知识库（长期记忆）", "Save to knowledge (memory)"); onClicked: bridge.saveKnowledge(bridge.knowledgeText + "\n\n" + msgText.text) }
                                                        Ghost { ico: "\uE72C"; size: 13; implicitWidth: 28; implicitHeight: 28; visible: md.modelData.path !== "web" && md.index === msgList.count - 1; enabled: !bridge.busy; tip: t("重新生成", "Regenerate"); onClicked: bridge.retryLast() }
                                                        Ghost { ico: "\uE8C1"; size: 13; implicitWidth: 28; implicitHeight: 28; visible: msgText.selectedText !== ""; tip: t("翻译选中内容", "Translate selection"); onClicked: bridge.askSelection("translate", msgText.selectedText) }
                                                        Ghost { ico: "\uE82F"; size: 13; implicitWidth: 28; implicitHeight: 28; visible: msgText.selectedText !== ""; tip: t("解释选中内容", "Explain selection"); onClicked: bridge.askSelection("explain", msgText.selectedText) } } } } }
                                        onCountChanged: Qt.callLater(function(){ msgList.positionViewAtEnd() })
                                    }
                                    // empty state
                                    ColumnLayout { visible: msgList.count === 0; anchors.centerIn: parent; anchors.verticalCenterOffset: -20; width: Math.min(600, parent.width - 48); spacing: 12
                                        BrandMark { u: 9; Layout.alignment: Qt.AlignHCenter; Layout.bottomMargin: 10 }
                                        Text { text: t("告诉瓦序你想做什么", "Tell VAL-DAL what to do"); font.pixelSize: 22; font.weight: Font.DemiBold; color: win.c.strong; Layout.alignment: Qt.AlignHCenter }
                                        Text { text: t("本地运行 · 依据可核查 · 屏幕、文件、联网与电脑控制都在输入框里", "Local · checkable evidence · screen, files, web and control live in the composer"); font.pixelSize: 11; color: win.c.muted; Layout.alignment: Qt.AlignHCenter; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; Layout.fillWidth: true }
                                        GridLayout { columns: width > 460 ? 2 : 1; columnSpacing: 10; rowSpacing: 10; Layout.fillWidth: true; Layout.topMargin: 14
                                            Repeater { model: [
                                                    { ico: "\uE7F4", zh: "读懂当前屏幕", en: "Explain my screen", dz: "识别屏幕后说明内容与可做操作", de: "Recognize, then explain and suggest actions", a: 0 },
                                                    { ico: "\uE774", zh: "联网查找", en: "Search the web", dz: "先查最新来源，再结合本地知识", de: "Fresh sources plus local knowledge", a: 1 },
                                                    { ico: "\uE9D5", zh: "拆解任务", en: "Break down a task", dz: "把目标拆成可执行步骤", de: "Turn a goal into executable steps", a: 2 },
                                                    { ico: "\uE723", zh: "分析文件", en: "Analyze a file", dz: "附加文本、代码或表格后提问", de: "Attach text, code or tables, then ask", a: 3 } ]
                                                AbstractButton { id: qs; required property var modelData; Layout.fillWidth: true; implicitHeight: 58; hoverEnabled: true
                                                    onClicked: {
                                                        if (modelData.a === 0) { bridge.recognize(); win.prefill(t("说明当前屏幕上的内容，并指出可以进行的操作。", "Explain what is on the screen and what I can do next.")) }
                                                        else if (modelData.a === 1) { win.webMode = true; win.prefill("") }
                                                        else if (modelData.a === 2) win.prefill(t("把这个任务拆解为可执行的步骤：", "Break this task into executable steps: "))
                                                        else attachDlg.open() }
                                                    background: Rectangle { radius: 7; color: qs.hovered ? win.c.hover : "transparent"; border.color: win.c.line }
                                                    contentItem: RowLayout { spacing: 12
                                                        Ico { text: qs.modelData.ico; font.pixelSize: 16; Layout.leftMargin: 14 }
                                                        ColumnLayout { spacing: 2; Layout.fillWidth: true
                                                            Text { text: bridge.lang === "zh" ? qs.modelData.zh : qs.modelData.en; font.pixelSize: 12; color: win.c.text }
                                                            Text { text: bridge.lang === "zh" ? qs.modelData.dz : qs.modelData.de; font.pixelSize: 10; color: win.c.muted; Layout.fillWidth: true; elide: Text.ElideRight } } } } } } }
                                }

                                // ===== composer =====
                                Item { Layout.fillWidth: true; implicitHeight: compCol.implicitHeight + (win.width < 950 ? 30 : 39)
                                    ColumnLayout { id: compCol; width: Math.min(790, parent.width - (win.width < 950 ? 40 : 80)); x: (parent.width - width) / 2; y: 13; spacing: 10
                                        RowLayout { Layout.fillWidth: true; spacing: 11
                                            RowLayout { spacing: 6
                                                Dot { level: bridge.busy || bridge.webBusy ? 1 : 2; width: 5; height: 5 }
                                                Text { text: bridge.busy || bridge.webBusy ? t("执行中", "Working") : t("Agent 模式", "Agent mode"); font.pixelSize: 11; color: win.c.soft } }
                                            Repeater { model: [
                                                    { on: win.webMode, ico: "\uE774", zh: "联网查找", en: "Web search" },
                                                    { on: bridge.taskMode, ico: "\uE9D5", zh: "任务模式", en: "Task mode" },
                                                    { on: bridge.allowControl, ico: "\uE7C9", zh: "电脑控制", en: "Control on" },
                                                    { on: bridge.screenText !== "", ico: "\uE7F4", zh: "屏幕上下文", en: "Screen context" },
                                                    { on: bridge.attachments.length > 0, ico: "\uE723", zh: bridge.attachments.length + " 个文件", en: bridge.attachments.length + " files" },
                                                    { on: bridge.webSources.length > 0, ico: "\uE71B", zh: bridge.webSources.length + " 条来源", en: bridge.webSources.length + " sources" },
                                                    { on: win.schedAt > 0, ico: "\uE823", zh: "已定时", en: "Scheduled" } ]
                                                RowLayout { required property var modelData; visible: modelData.on; spacing: 4
                                                    Text { text: "·"; color: win.c.low; font.pixelSize: 11 }
                                                    Ico { text: modelData.ico; font.pixelSize: 11; color: win.c.soft }
                                                    Text { text: bridge.lang === "zh" ? modelData.zh : modelData.en; font.pixelSize: 11; color: win.c.muted } } }
                                            Ghost { visible: bridge.screenText !== "" || bridge.attachments.length > 0 || bridge.webSources.length > 0; ico: "\uE894"; size: 10; implicitWidth: 22; implicitHeight: 22; tip: t("清空上下文", "Clear context"); onClicked: bridge.clearContext() }
                                            Item { Layout.fillWidth: true }
                                            Text { visible: compCol.width > 600; text: t("Enter 发送 · Shift + Enter 换行", "Enter to send · Shift + Enter for newline"); font.pixelSize: 10; color: win.c.low } }
                                        Rectangle { id: composer; Layout.fillWidth: true; radius: 9; color: win.c.composer
                                            border.color: input.activeFocus ? win.c.focus : win.c.composerLine
                                            Behavior on border.color { ColorAnimation { duration: 200 } }
                                            implicitHeight: inSv.height + ctrlRow.implicitHeight + 16
                                            ScrollView { id: inSv; x: 6; y: 6; width: parent.width - 12
                                                height: Math.min(Math.max(62, input.implicitHeight), Math.max(120, win.height * 0.32))
                                                TextArea { id: input; wrapMode: TextArea.Wrap; font.pixelSize: 13; font.family: "Microsoft YaHei UI"; color: win.c.strong; leftPadding: 13; rightPadding: 13; topPadding: 12; bottomPadding: 6
                                                    placeholderText: win.webMode ? t("输入要联网查找的问题…", "Ask something to search the web for…") : t("告诉瓦序你想做什么…", "Tell VAL-DAL what to do…")
                                                    placeholderTextColor: win.c.low; background: Item {}
                                                    Keys.onPressed: function(e) { if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) { win.doSend(); e.accepted = true } } } }
                                            RowLayout { id: ctrlRow; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 10; anchors.topMargin: 0; spacing: 3
                                                Ghost { ico: "\uE723"; tip: t("文件", "Files"); on: bridge.attachments.length > 0; onClicked: win.openTool(0) }
                                                Ghost { ico: "\uE7F4"; tip: t("屏幕识别 / OCR", "Screen / OCR"); on: bridge.screenText !== ""; onClicked: win.openTool(1) }
                                                Ghost { ico: "\uE7C9"; tip: t("电脑控制", "Computer control"); on: bridge.allowControl; onClicked: win.openTool(2) }
                                                Ghost { ico: "\uE774"; tip: t("联网查找", "Web search"); on: win.webMode; onClicked: win.openTool(3) }
                                                Rectangle { width: 1; height: 19; color: win.c.line; Layout.leftMargin: 7; Layout.rightMargin: 7 }
                                                Ghost { ico: "\uE8F1"; tip: t("知识", "Knowledge"); onClicked: win.openTool(4) }
                                                Ghost { ico: "\uE9D5"; tip: t("任务调度", "Tasks"); on: bridge.taskMode || win.schedAt > 0; onClicked: win.openTool(5) }
                                                Rectangle { width: 1; height: 19; color: win.c.line; Layout.leftMargin: 7; Layout.rightMargin: 7; visible: composer.width > 470 }
                                                Ghost { ico: "\uE712"; tip: t("更多能力", "More"); onClicked: win.openTool(6) }
                                                Item { Layout.fillWidth: true }
                                                AbstractButton { id: modelBtn; implicitHeight: 32; implicitWidth: mrowb.implicitWidth + 16; hoverEnabled: true; onClicked: modelPop.open()
                                                    ToolTip.visible: hovered; ToolTip.text: t("切换模型", "Switch model"); ToolTip.delay: 350
                                                    background: Rectangle { radius: 5; color: modelBtn.hovered ? win.c.hover : "transparent" }
                                                    contentItem: Item { RowLayout { id: mrowb; anchors.centerIn: parent; spacing: 6
                                                        Text { visible: composer.width > 560; text: shortModel() + " · " + (store.plan !== "" ? "Online" : "Local"); font.pixelSize: 11; color: modelBtn.hovered ? win.c.strong : win.c.soft; elide: Text.ElideRight; Layout.maximumWidth: 200 }
                                                        Ico { text: composer.width > 560 ? "\uE70D" : "\uE950"; font.pixelSize: composer.width > 560 ? 9 : 15 } } } }
                                                BusyIndicator { running: bridge.busy || bridge.webBusy; visible: running; implicitWidth: 22; implicitHeight: 22 }
                                                AbstractButton { id: sendBtn; implicitWidth: 34; implicitHeight: 32; hoverEnabled: true; enabled: !bridge.busy && !bridge.webBusy && input.text.trim() !== ""; onClicked: win.doSend()
                                                    ToolTip.visible: hovered; ToolTip.text: win.webMode ? t("联网查找并回答", "Search and answer") : t("发送", "Send"); ToolTip.delay: 350
                                                    background: Rectangle { radius: 5; color: sendBtn.hovered ? win.c.strong : win.c.accent; opacity: sendBtn.enabled ? 1 : 0.35 }
                                                    contentItem: Ico { text: win.webMode ? "\uE721" : "\uE72A"; font.pixelSize: 14; color: win.c.ink } } }

                                            // tool popover, anchored above the composer
                                            Popup { id: toolPop; parent: composer; width: Math.min(540, composer.width - 20); x: (composer.width - width) / 2; y: -height - 46; padding: 18
                                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                                background: Rectangle { radius: 8; color: win.c.raised; border.color: win.c.line }
                                                readonly property var tool: win.toolId >= 0 ? win.tools[win.toolId] : null
                                                ColumnLayout { anchors.fill: parent; spacing: 10
                                                    RowLayout { Layout.fillWidth: true
                                                        H2 { text: toolPop.tool ? (bridge.lang === "zh" ? toolPop.tool.zh : toolPop.tool.en) : "" }
                                                        Ghost { ico: "\uE711"; size: 11; implicitWidth: 26; implicitHeight: 26; onClicked: toolPop.close() } }
                                                    Note { text: toolPop.tool ? (bridge.lang === "zh" ? toolPop.tool.dz : toolPop.tool.de) : ""; lineHeight: 1.3 }
                                                    Flow { Layout.fillWidth: true; spacing: 9; Layout.topMargin: 6
                                                        Repeater { model: toolPop.tool ? toolPop.tool.acts : []
                                                            Pill { required property var modelData; text: bridge.lang === "zh" ? modelData.zh : modelData.en
                                                                enabled: !(modelData.id === "sched" && input.text.trim() === "") && !(modelData.id === "export" && msgList.count === 0)
                                                                onClicked: win.runAction(modelData.id) } } } } }
                                            Popup { id: modelPop; parent: modelBtn; width: 300; x: modelBtn.width - width; y: -height - 8; padding: 8
                                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                                background: Rectangle { radius: 8; color: win.c.raised; border.color: win.c.line }
                                                ColumnLayout { anchors.fill: parent; spacing: 2
                                                    Eyebrow { text: t("本地模型", "LOCAL MODELS"); Layout.margins: 8 }
                                                    Repeater { model: bridge.models
                                                        AbstractButton { id: mi; required property var modelData; required property int index; visible: modelData.installed; Layout.fillWidth: true; implicitHeight: visible ? 32 : 0; hoverEnabled: true
                                                            onClicked: { modelPop.close(); if (!modelData.current) bridge.useOrDownloadModel(index) }
                                                            background: Rectangle { radius: 5; color: mi.hovered ? win.c.hover : "transparent" }
                                                            contentItem: RowLayout { spacing: 8
                                                                Ico { text: mi.modelData.current ? "\uE73E" : ""; font.pixelSize: 11; Layout.preferredWidth: 16; Layout.leftMargin: 6; color: win.c.good }
                                                                Text { text: mi.modelData.label; font.pixelSize: 12; color: win.c.text; Layout.fillWidth: true; elide: Text.ElideRight }
                                                                Text { text: mi.modelData.size; font.pixelSize: 10; color: win.c.muted; Layout.rightMargin: 8 } } } }
                                                    Rule { Layout.topMargin: 4; Layout.bottomMargin: 4 }
                                                    AbstractButton { id: mm; Layout.fillWidth: true; implicitHeight: 32; hoverEnabled: true; onClicked: { modelPop.close(); win.goSettings(0) }
                                                        background: Rectangle { radius: 5; color: mm.hovered ? win.c.hover : "transparent" }
                                                        contentItem: RowLayout { spacing: 8
                                                            Ico { text: "\uE896"; font.pixelSize: 12; Layout.preferredWidth: 16; Layout.leftMargin: 6 }
                                                            Text { text: t("下载与管理模型…", "Download & manage models…"); font.pixelSize: 12; color: win.c.text; Layout.fillWidth: true } } } } }
                                        }
                                        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; font.pixelSize: 10; color: win.c.muted
                                            text: bridge.statusText !== "" ? bridge.statusText : t("文件、屏幕、知识、工具和执行权限集中在输入框 · 执行详情在边栏", "Files, screen, knowledge, tools and permissions live in the composer · details in the sidebar") } } }
                            }

                            // ===== 边栏 (docked when wide) =====
                            Item { visible: win.sidebarOpen && !win.drawerFloat; Layout.preferredWidth: 330; Layout.fillHeight: true
                                Loader { anchors.fill: parent; active: parent.visible; sourceComponent: drawerContent } }
                        } }
                    // ===== 边栏 (floating when narrow) =====
                    Rectangle { visible: win.sidebarOpen && win.drawerFloat; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.topMargin: 56
                        width: Math.min(330, canvas.width * 0.85); color: "transparent"; z: 20
                        Rectangle { anchors.fill: parent; anchors.leftMargin: -24; gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "transparent" } GradientStop { position: 0.07; color: win.dark ? "#55000000" : "#22000000" } } opacity: 0.6 }
                        Loader { anchors.fill: parent; active: parent.visible; sourceComponent: drawerContent } }
                }

                // ===== workspace page =====
                Item { id: wsPage
                    ColumnLayout { width: Math.min(900, wsPage.width - 56); x: Math.max(28, (wsPage.width - width) / 2); y: 32; spacing: 14
                        H1 { text: t("工作区与项目", "Workspaces & projects") }
                        Note { text: t("对话按项目归档；在左侧会话列表中按项目分组显示。", "Chats are filed by project and grouped that way in the session list.") }
                        GridLayout { columns: wsPage.width > 760 ? 2 : 1; columnSpacing: 14; rowSpacing: 14; Layout.fillWidth: true; Layout.topMargin: 6
                            Card { Layout.fillWidth: true
                                ColumnLayout { anchors.fill: parent; spacing: 10
                                    RowLayout { spacing: 8; Ico { text: "\uE8B7"; font.pixelSize: 14 } H2 { text: t("工作区", "Workspace") } }
                                    ComboBox { Layout.fillWidth: true; model: bridge.workspaces; textRole: "name"; currentIndex: { for (var i=0;i<bridge.workspaces.length;i++) if (bridge.workspaces[i].name===bridge.currentWorkspace) return i; return 0 } onActivated: bridge.switchWorkspace(currentText) }
                                    RowLayout { Layout.fillWidth: true
                                        TextField { id: wsName; placeholderText: t("新工作区名", "New workspace name"); Layout.fillWidth: true }
                                        Pill { text: t("新建", "Create"); ico: "\uE710"; enabled: wsName.text.trim() !== ""; onClicked: { bridge.addWorkspace(wsName.text); wsName.clear() } } } } }
                            Card { Layout.fillWidth: true
                                ColumnLayout { anchors.fill: parent; spacing: 10
                                    RowLayout { spacing: 8; Ico { text: "\uE8F1"; font.pixelSize: 14 } H2 { text: t("项目", "Project") } }
                                    ComboBox { Layout.fillWidth: true; model: bridge.projects; textRole: "name"; currentIndex: { for (var i=0;i<bridge.projects.length;i++) if (bridge.projects[i].name===bridge.currentProject) return i; return 0 } onActivated: bridge.switchProject(currentText) }
                                    RowLayout { Layout.fillWidth: true
                                        TextField { id: pjName; placeholderText: t("新项目名", "New project name"); Layout.fillWidth: true }
                                        Pill { text: t("新建", "Create"); ico: "\uE710"; enabled: pjName.text.trim() !== ""; onClicked: { bridge.addProject(pjName.text); pjName.clear() } } } } } } } }

                // ===== settings (full screen) =====
                ColumnLayout { spacing: 0
                    RowLayout { Layout.fillWidth: true; Layout.preferredHeight: 56; Layout.leftMargin: 14; Layout.rightMargin: 20; spacing: 10
                        Ghost { ico: "\uE72B"; size: 14; tip: t("返回对话", "Back to chat"); onClicked: win.page = 0 }
                        Text { text: t("设置", "Settings"); font.pixelSize: 15; font.weight: Font.DemiBold; color: win.c.strong; Layout.fillWidth: true } }
                    Rule {}
                    RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                        Rectangle { Layout.preferredWidth: 228; Layout.fillHeight: true; color: win.c.side
                            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: win.c.line2 }
                            ColumnLayout { anchors.fill: parent; anchors.margins: 13; anchors.topMargin: 20; spacing: 3
                                Repeater { model: [
                                        { ico: "\uE945", zh: "管线与模型", en: "Pipeline & models" },
                                        { ico: "\uE753", zh: "在线大模型", en: "Online model" },
                                        { ico: "\uE8F1", zh: "知识库", en: "Knowledge" },
                                        { ico: "\uE790", zh: "外观与语言", en: "Appearance & language" },
                                        { ico: "\uE716", zh: "账号", en: "Accounts" },
                                        { ico: "\uE946", zh: "关于 VAL-DAL", en: "About VAL-DAL" } ]
                                    AbstractButton { id: sn; required property var modelData; required property int index; Layout.fillWidth: true; implicitHeight: 35; hoverEnabled: true; onClicked: win.settingsSection = index
                                        background: Rectangle { radius: 5; color: win.settingsSection === sn.index ? win.c.active : (sn.hovered ? win.c.hover : "transparent")
                                            Rectangle { visible: win.settingsSection === sn.index; x: -1; y: 10; width: 2; height: 15; radius: 1; color: win.c.accent } }
                                        contentItem: RowLayout { spacing: 10
                                            Ico { text: sn.modelData.ico; font.pixelSize: 14; Layout.leftMargin: 10; color: win.settingsSection === sn.index ? win.c.strong : win.c.muted }
                                            Text { text: bridge.lang === "zh" ? sn.modelData.zh : sn.modelData.en; font.pixelSize: 12; color: win.settingsSection === sn.index ? win.c.strong : win.c.soft; Layout.fillWidth: true } } } }
                                Item { Layout.fillHeight: true } } }

                        StackLayout { Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: win.settingsSection
                            // 0 pipeline & models
                            ScrollView { id: svA; contentWidth: availableWidth
                                ColumnLayout { width: Math.min(880, svA.availableWidth - 56); x: Math.max(28, (svA.availableWidth - width) / 2); spacing: 12
                                    Item { height: 18 }
                                    H1 { text: t("管线与模型", "Pipeline & models") }
                                    Card { Layout.fillWidth: true
                                        ColumnLayout { anchors.fill: parent; spacing: 10
                                            RowLayout { Layout.fillWidth: true; spacing: 10
                                                Dot { level: win.sigPipeline() }
                                                H2 { text: t("Valhalla 管线", "Valhalla pipeline") }
                                                Pill { primary: true; ico: "\uE90F"; text: bridge.pipelineBusy ? t("处理中…", "Working…") : t("修复 / 初始化", "Repair / initialize"); enabled: !bridge.pipelineBusy; onClicked: bridge.repairPipeline() } }
                                            Body { text: bridge.pipelineReport; visible: text !== ""; font.pixelSize: 11 } } }
                                    RowLayout { Layout.fillWidth: true; Layout.topMargin: 8
                                        Eyebrow { text: t("模型目录", "MODEL CATALOG"); Layout.fillWidth: true }
                                        Note { text: bridge.catalogStatus; horizontalAlignment: Text.AlignRight }
                                        Ghost { ico: "\uE895"; size: 14; tip: t("更新模型列表", "Update model list"); onClicked: bridge.updateModelCatalog() } }
                                    Repeater { model: bridge.models
                                        Rectangle { required property var modelData; required property int index; Layout.fillWidth: true; implicitHeight: 58; radius: 7; color: win.c.panel; border.color: modelData.current ? win.c.focus : win.c.line2
                                            RowLayout { anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 12; spacing: 12
                                                Rectangle { width: 32; height: 32; radius: 6; color: modelData.current ? win.c.accent : win.c.active
                                                    Text { anchors.centerIn: parent; text: (modelData.family || "?").substring(0, 2); font.pixelSize: 11; font.weight: Font.Bold; color: modelData.current ? win.c.ink : win.c.text } }
                                                ColumnLayout { Layout.fillWidth: true; spacing: 2
                                                    Text { text: modelData.label + (modelData.current ? ("  ·  " + t("当前", "Current")) : ""); font.pixelSize: 12; font.weight: Font.DemiBold; color: win.c.strong; elide: Text.ElideRight; Layout.fillWidth: true }
                                                    Note { text: modelData.note + " · " + modelData.size; elide: Text.ElideRight; wrapMode: Text.NoWrap } }
                                                Pill { text: modelData.current ? t("使用中", "In use") : (modelData.installed ? t("使用", "Use") : t("下载", "Download")); ico: modelData.installed ? "" : "\uE896"; primary: !modelData.installed && !modelData.current; enabled: !bridge.busy && !modelData.current; onClicked: bridge.useOrDownloadModel(index) } } } }
                                    Item { height: 24 } } }
                            // 1 online model
                            ScrollView { id: svB; contentWidth: availableWidth
                                ColumnLayout { width: Math.min(880, svB.availableWidth - 56); x: Math.max(28, (svB.availableWidth - width) / 2); spacing: 12
                                    Item { height: 18 }
                                    RowLayout { Layout.fillWidth: true
                                        H1 { text: t("在线大模型", "Online model") }
                                        Pill { text: t("说明", "About"); ico: "\uE946"; onClicked: buyInfoDlg.open() } }
                                    Body { text: store.plan === "" ? t("当前未开通在线版，本地版可离线使用。", "Online edition not active; the local edition works offline.") : (t("已开通：", "Active: ") + win.cdkPlanName(store.plan)) }
                                    GridLayout { columns: svB.availableWidth > 820 ? 3 : 1; columnSpacing: 12; rowSpacing: 12; Layout.fillWidth: true
                                        Repeater { model: [{n:"PRO", zh:"个人版", en:"Personal", pz:"¥29/月", pe:"¥29/mo", oz:"A测价 · 原价 ¥79/月", oe:"Alpha · was ¥79/mo", fit:0.5, fzh:"个人学习 / 轻任务", fen:"Personal study / light tasks"}, {n:"MAX", zh:"专业版", en:"Professional", pz:"¥79/月", pe:"¥79/mo", oz:"A测价 · 原价 ¥199/月", oe:"Alpha · was ¥199/mo", fit:0.8, fzh:"长回答 / 高并发", fen:"Long answers / high concurrency"}, {n:"ENT", zh:"企业定制版", en:"Enterprise", pz:"联系开通", pe:"Contact us", oz:"私有部署可选", oe:"Private deployment available", fit:1.0, fzh:"私有部署 / 团队定制", fen:"Private deployment / team customization"}]
                                            Rectangle { required property var modelData; Layout.fillWidth: true; Layout.preferredWidth: 100; implicitHeight: planCol.implicitHeight + 32; radius: 7; color: win.c.panel
                                                border.color: store.plan === modelData.n ? win.c.focus : win.c.line2; border.width: store.plan === modelData.n ? 2 : 1
                                                ColumnLayout { id: planCol; x: 16; y: 16; width: parent.width - 32; spacing: 6
                                                    Eyebrow { text: modelData.n }
                                                    H2 { text: bridge.lang === "zh" ? modelData.zh : modelData.en }
                                                    Text { text: bridge.lang === "zh" ? modelData.pz : modelData.pe; font.pixelSize: 20; font.weight: Font.DemiBold; color: win.c.strong }
                                                    Note { text: bridge.lang === "zh" ? modelData.oz : modelData.oe }
                                                    RowLayout { Layout.fillWidth: true; Layout.topMargin: 4; spacing: 8
                                                        Text { text: t("适配度", "Fit"); font.pixelSize: 10; color: win.c.muted }
                                                        Rectangle { Layout.fillWidth: true; height: 2; color: win.c.line; Rectangle { width: parent.width * modelData.fit; height: 2; color: win.c.good } } }
                                                    Note { text: bridge.lang === "zh" ? modelData.fzh : modelData.fen } } } } }
                                    Note { text: t("适配度表示适用场景，不是性能百分比。", "Fit shows suitable scenarios, not performance.") }
                                    Card { Layout.fillWidth: true
                                        ColumnLayout { anchors.fill: parent; spacing: 10
                                            H2 { text: t("兑换 CDK", "Redeem CDK") }
                                            RowLayout { Layout.fillWidth: true
                                                TextField { id: cdkField; Layout.fillWidth: true; placeholderText: "VALDAL-PRO-XXXXXX-XXXXXX-X" }
                                                Pill { text: t("兑换", "Redeem"); primary: true; onClicked: win.redeemCdk(cdkField.text) } }
                                            Text { text: win.cdkMsg; visible: text !== ""; font.pixelSize: 11; color: store.code !== "" && win.cdkMsg.indexOf(win.cdkPlanName(store.plan)) >= 0 ? win.c.good : win.c.bad; wrapMode: Text.Wrap; Layout.fillWidth: true }
                                            Note { text: t("购买：joulyman@gmail.com · +1 316 872 5748（A测期人工开通）", "Buy: joulyman@gmail.com · +1 316 872 5748 (manual activation during alpha)") } } }
                                    Item { height: 24 } } }
                            // 2 knowledge
                            Item { id: kbPage
                                ColumnLayout { spacing: 12; width: Math.min(880, kbPage.width - 56); x: Math.max(28, (kbPage.width - width) / 2); height: kbPage.height
                                    Item { height: 6 }
                                    H1 { text: t("知识库", "Knowledge") }
                                    Note { text: bridge.knowledgeStats }
                                    Rectangle { Layout.fillWidth: true; Layout.fillHeight: true; radius: 7; color: win.c.panel; border.color: kbEdit.activeFocus ? win.c.focus : win.c.line2
                                        ScrollView { anchors.fill: parent; anchors.margins: 4
                                            TextArea { id: kbEdit; font.family: "Microsoft YaHei UI"; text: bridge.knowledgeText; wrapMode: TextArea.Wrap; color: win.c.text; font.pixelSize: 12; placeholderText: t("在此写入语料…", "Write corpus notes here…"); placeholderTextColor: win.c.low; background: Item {} } } }
                                    RowLayout { Layout.fillWidth: true; Layout.bottomMargin: 22; spacing: 8
                                        TextField { id: kbDomain; placeholderText: t("行业/领域（导入用）", "Domain (for import)"); Layout.preferredWidth: 220 }
                                        Pill { text: t("导入文件", "Import files"); ico: "\uE8B5"; onClicked: kbDlg.open() }
                                        Item { Layout.fillWidth: true }
                                        Pill { text: t("保存", "Save"); ico: "\uE74E"; primary: true; onClicked: bridge.saveKnowledge(kbEdit.text) } } } }
                            // 3 appearance & language
                            Item { id: apPage
                                ColumnLayout { spacing: 12; width: Math.min(880, apPage.width - 56); x: Math.max(28, (apPage.width - width) / 2); y: 18
                                    H1 { text: t("外观与语言", "Appearance & language") }
                                    Card { Layout.fillWidth: true
                                        ColumnLayout { anchors.fill: parent; spacing: 12
                                            RowLayout { Layout.fillWidth: true; spacing: 10; Ico { text: "\uE790"; font.pixelSize: 14 } Body { text: t("深色主题", "Dark theme") } Switch { checked: win.dark; onToggled: win.dark = checked } }
                                            Rule {}
                                            RowLayout { Layout.fillWidth: true; spacing: 10; Ico { text: "\uE774"; font.pixelSize: 14 } Body { text: t("语言", "Language") }
                                                ComboBox { model: [t("跟随系统", "System"), "中文", "English"]; currentIndex: bridge.languageIndex; onActivated: function(i){ bridge.setLanguage(i) } } } } } } }
                            // 4 accounts
                            ScrollView { id: svC; contentWidth: availableWidth
                                ColumnLayout { width: Math.min(880, svC.availableWidth - 56); x: Math.max(28, (svC.availableWidth - width) / 2); spacing: 12
                                    Item { height: 18 }
                                    H1 { text: t("账号", "Accounts") }
                                    Card { Layout.fillWidth: true
                                        ColumnLayout { anchors.fill: parent; spacing: 8
                                            RowLayout { Layout.fillWidth: true; spacing: 10
                                                Ico { text: "\uE72E"; font.pixelSize: 14 }
                                                Body { text: t("本地账号管理（企业版）", "Local account management (Enterprise)") }
                                                Switch { checked: bridge.accountsEnabled; onToggled: bridge.setAccountsEnabled(checked) } }
                                            Note { text: ((bridge.enterpriseActive || store.plan === "ENT") ? t("企业版已激活 · 不限人数", "Enterprise active · unlimited") : t("未激活 · 上限 3 人", "Inactive · max 3 accounts")) + "  ·  " + t("当前：", "Current: ") + bridge.currentUser + " (" + bridge.accountRole + ")" } } }
                                    Repeater { model: bridge.accounts
                                        Rectangle { required property var modelData; Layout.fillWidth: true; implicitHeight: 50; radius: 7; color: win.c.panel; border.color: win.c.line2
                                            RowLayout { anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 10; spacing: 10
                                                Rectangle { width: 26; height: 26; radius: 6; color: win.c.active; Text { anchors.centerIn: parent; text: modelData.name.substring(0, 1).toUpperCase(); color: win.c.text; font.pixelSize: 11; font.weight: Font.Bold } }
                                                Text { text: modelData.name + "  ·  " + modelData.role; font.pixelSize: 12; color: win.c.text; Layout.fillWidth: true; elide: Text.ElideRight }
                                                Switch { checked: modelData.enabled; onToggled: bridge.setAccountEnabled(modelData.name, checked); ToolTip.visible: hovered; ToolTip.text: t("启用/停用", "Enable/disable") }
                                                Ghost { ico: "\uE8D7"; size: 14; tip: t("重置密码", "Reset password"); onClicked: { resetDlg.user = modelData.name; resetDlg.open() } }
                                                Ghost { ico: "\uE74D"; size: 14; tip: t("删除账号", "Delete account"); onClicked: bridge.removeAccount(modelData.name) } } } }
                                    Card { Layout.fillWidth: true
                                        ColumnLayout { anchors.fill: parent; spacing: 10
                                            H2 { text: t("添加账号", "Add account") }
                                            RowLayout { Layout.fillWidth: true
                                                TextField { id: accName; placeholderText: t("账号名", "Account name"); Layout.fillWidth: true }
                                                TextField { id: accPass; placeholderText: t("密码", "Password"); echoMode: TextInput.Password; Layout.fillWidth: true }
                                                ComboBox { id: accRole; model: ["member", "admin"]; Layout.preferredWidth: 110 }
                                                Pill { text: t("添加", "Add"); ico: "\uE8FA"; enabled: bridge.accountRole === "admin" && accName.text.trim() !== ""; onClicked: { bridge.addAccount(accName.text, accPass.text, accRole.currentText); accPass.clear() } } }
                                            Rule {}
                                            H2 { text: t("登录", "Sign in") }
                                            RowLayout { Layout.fillWidth: true
                                                TextField { id: loginName; placeholderText: t("登录名", "Login name"); Layout.fillWidth: true }
                                                TextField { id: loginPass; placeholderText: t("密码", "Password"); echoMode: TextInput.Password; Layout.fillWidth: true }
                                                Pill { text: t("登录", "Sign in"); primary: true; onClicked: bridge.login(loginName.text, loginPass.text) }
                                                Ghost { ico: "\uE7E8"; size: 14; tip: t("退出登录", "Sign out"); onClicked: bridge.logout() } }
                                            Text { text: bridge.accountMsg; visible: text !== ""; font.pixelSize: 11; color: win.c.good; wrapMode: Text.Wrap; Layout.fillWidth: true } } }
                                    Item { height: 24 } } }
                            // 5 about
                            ScrollView { id: svD; contentWidth: availableWidth
                                ColumnLayout { width: Math.min(960, svD.availableWidth - 56); x: Math.max(28, (svD.availableWidth - width) / 2); spacing: 14
                                    Item { height: 18 }
                                    Rectangle { Layout.fillWidth: true; implicitHeight: heroRow.implicitHeight + 48; radius: 8; color: win.c.panel; border.color: win.c.line2
                                        RowLayout { id: heroRow; x: 24; y: 24; width: parent.width - 48; spacing: 22
                                            Rectangle { width: 72; height: 72; radius: 16; color: win.dark ? "#141516" : "#1d1f1e"; border.color: win.c.line; BrandMark { anchors.centerIn: parent; u: 9; ink: "#dce0db" } }
                                            ColumnLayout { spacing: 5; Layout.fillWidth: true
                                                RowLayout { spacing: 10
                                                    Text { text: "VAL–DAL"; font.pixelSize: 24; font.weight: Font.Bold; font.letterSpacing: 2; color: win.c.strong }
                                                    Text { text: "瓦序"; font.pixelSize: 13; font.letterSpacing: 2; color: win.c.muted } }
                                                Body { text: t("运行在你电脑上的智能体：先检索可核查的依据，再生成回答；需要时联网查找、识别屏幕、读取文件、操作电脑。", "An agent that runs on your PC: it retrieves checkable evidence before answering, and can search the web, read the screen and files, and operate the computer when needed.") }
                                                Note { text: t("A 测版 · Rogue Intelligence Inc.（美国特拉华州）", "Alpha · Rogue Intelligence Inc. (Delaware, USA)") } } } }

                                    Eyebrow { text: t("VALHALLA 管线", "VALHALLA PIPELINE"); Layout.topMargin: 8 }
                                    Rectangle { Layout.fillWidth: true; implicitHeight: pipeCol.implicitHeight + 40; radius: 8; color: win.c.panel; border.color: win.c.line2
                                        ColumnLayout { id: pipeCol; x: 20; y: 20; width: parent.width - 40; spacing: 16
                                            RowLayout { Layout.fillWidth: true; spacing: 0
                                                Repeater { model: [
                                                        { ico: "\uE8F2", zh: "理解问题", en: "Understand", dz: "意图与上下文", de: "Intent & context" },
                                                        { ico: "\uE721", zh: "结构检索", en: "Retrieve", dz: "从本地知识取依据", de: "Evidence from local knowledge" },
                                                        { ico: "\uE8AB", zh: "Fate 路由", en: "Fate routing", dz: "选择解码路径", de: "Picks the decode path" },
                                                        { ico: "\uE950", zh: "可换解码头", en: "Decode head", dz: "按模型更换", de: "Swappable per model" },
                                                        { ico: "\uE945", zh: "会话热驻留", en: "Warm session", dz: "多轮不重复加载", de: "No reload between turns" } ]
                                                    RowLayout { required property var modelData; required property int index; spacing: 0; Layout.fillWidth: true
                                                        ColumnLayout { spacing: 5; Layout.fillWidth: true
                                                            Rectangle { Layout.alignment: Qt.AlignHCenter; width: 40; height: 40; radius: 8; color: index === 1 || index === 2 ? win.c.accent : win.c.active
                                                                Ico { anchors.centerIn: parent; text: modelData.ico; font.pixelSize: 16; color: index === 1 || index === 2 ? win.c.ink : win.c.text } }
                                                            Text { Layout.alignment: Qt.AlignHCenter; text: bridge.lang === "zh" ? modelData.zh : modelData.en; font.pixelSize: 12; font.weight: Font.DemiBold; color: win.c.strong }
                                                            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: bridge.lang === "zh" ? modelData.dz : modelData.de; font.pixelSize: 10; color: win.c.muted; wrapMode: Text.Wrap } }
                                                        Rectangle { visible: index < 4; Layout.preferredWidth: 18; height: 1; color: win.c.line; Layout.alignment: Qt.AlignTop; Layout.topMargin: 20 } } } }
                                            Rule {}
                                            Body { text: t("回答之前先找依据，依据和来源可以核查；解码头可按模型更换，不绑定某一家模型；会话热驻留让多轮对话不必反复加载权重。本地版永久免费，数据不出本机。", "Evidence is found before answering, and sources can be checked. Decode heads are swappable, so no single model vendor is required. Warm sessions avoid reloading weights between turns. The local edition is free forever and data stays on this PC.") } } }

                                    Eyebrow { text: t("核心特性", "KEY FEATURES"); Layout.topMargin: 8 }
                                    GridLayout { columns: svD.availableWidth > 880 ? 3 : 2; columnSpacing: 12; rowSpacing: 12; Layout.fillWidth: true
                                        Repeater { model: [
                                                { ico: "\uE709", zh: "离线可用", en: "Works offline", dz: "本地模型，断网也能用", de: "Local model, no network needed" },
                                                { ico: "\uE72E", zh: "数据不出本机", en: "Data stays local", dz: "知识库与对话保存在本机", de: "Knowledge and chats stay on this PC" },
                                                { ico: "\uE721", zh: "可核查依据", en: "Checkable evidence", dz: "结构检索先于生成", de: "Retrieval runs before generation" },
                                                { ico: "\uE774", zh: "联网查找", en: "Web search", dz: "需要时检索最新来源", de: "Fresh sources on demand" },
                                                { ico: "\uE7F4", zh: "屏幕识别与 OCR", en: "Screen & OCR", dz: "读懂屏幕和图片文字", de: "Reads screens and images" },
                                                { ico: "\uE723", zh: "文件上下文", en: "File context", dz: "附加文本、代码、表格", de: "Attach text, code and tables" },
                                                { ico: "\uE7C9", zh: "电脑控制", en: "Computer control", dz: "确认后执行操作", de: "Runs actions after confirmation" },
                                                { ico: "\uE9D5", zh: "任务与定时", en: "Tasks & scheduling", dz: "执行并汇报，可定时运行", de: "Execute, report, or schedule" },
                                                { ico: "\uE8F1", zh: "长期记忆", en: "Long-term memory", dz: "回答可一键存入知识库", de: "Save answers into knowledge" },
                                                { ico: "\uE8B7", zh: "工作区与项目", en: "Workspaces & projects", dz: "按项目归档对话", de: "File chats by project" },
                                                { ico: "\uE716", zh: "企业本地账号", en: "Enterprise accounts", dz: "本地多账号与权限", de: "Local multi-user with roles" },
                                                { ico: "\uE950", zh: "多模型", en: "Many models", dz: "Qwen、Llama、Mistral、Gemma、Phi", de: "Qwen, Llama, Mistral, Gemma, Phi" } ]
                                            Rectangle { required property var modelData; Layout.fillWidth: true; implicitHeight: 62; radius: 7; color: win.c.panel; border.color: win.c.line2
                                                RowLayout { anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 12; spacing: 12
                                                    Rectangle { width: 32; height: 32; radius: 6; color: win.c.active; Ico { anchors.centerIn: parent; text: modelData.ico; font.pixelSize: 14; color: win.c.text } }
                                                    ColumnLayout { spacing: 2; Layout.fillWidth: true
                                                        Text { text: bridge.lang === "zh" ? modelData.zh : modelData.en; font.pixelSize: 12; font.weight: Font.DemiBold; color: win.c.strong }
                                                        Text { text: bridge.lang === "zh" ? modelData.dz : modelData.de; font.pixelSize: 10; color: win.c.muted; elide: Text.ElideRight; Layout.fillWidth: true } } } } } }

                                    Eyebrow { text: t("与同类产品对比", "COMPARED WITH SIMILAR PRODUCTS"); Layout.topMargin: 8 }
                                    Rectangle { id: cmpCard; Layout.fillWidth: true; implicitHeight: cmpCol.implicitHeight; radius: 8; color: win.c.panel; border.color: win.c.line2; clip: true
                                        property var cols: ["VAL-DAL", t("云端聊天助手", "Cloud chat assistants"), t("本地模型运行器", "Local model runners")]
                                        property var rows: [
                                            { zh: "离线可用", en: "Works offline", v: [2, 0, 2] },
                                            { zh: "数据不出本机", en: "Data stays on device", v: [2, 0, 2] },
                                            { zh: "回答前结构检索 · 依据可核查", en: "Structured retrieval · checkable evidence", v: [2, 1, 1] },
                                            { zh: "联网查找", en: "Web search", v: [2, 2, 1] },
                                            { zh: "屏幕识别与 OCR", en: "Screen recognition & OCR", v: [2, 1, 0] },
                                            { zh: "文件上下文", en: "File context", v: [2, 2, 1] },
                                            { zh: "电脑控制", en: "Computer control", v: [2, 1, 0] },
                                            { zh: "任务模式与定时执行", en: "Task mode & scheduling", v: [2, 1, 0] },
                                            { zh: "模型可更换", en: "Swappable models", v: [2, 0, 2] },
                                            { zh: "工作区与项目", en: "Workspaces & projects", v: [2, 1, 0] },
                                            { zh: "企业本地账号", en: "Local enterprise accounts", v: [2, 1, 0] },
                                            { zh: "本地版免费", en: "Free local edition", v: [2, 1, 2] } ]
                                        function score(k) { var s = 0; for (var i = 0; i < rows.length; i++) s += rows[i].v[k]; return s / (rows.length * 2) }
                                        ColumnLayout { id: cmpCol; width: parent.width; spacing: 0
                                            RowLayout { Layout.fillWidth: true; Layout.margins: 16; spacing: 0
                                                Text { text: t("功能", "Capability"); font.pixelSize: 11; color: win.c.muted; Layout.fillWidth: true; Layout.preferredWidth: 3 }
                                                Repeater { model: cmpCard.cols
                                                    Text { required property string modelData; required property int index; text: modelData; font.pixelSize: 11; font.weight: index === 0 ? Font.Bold : Font.Normal; color: index === 0 ? win.c.strong : win.c.muted; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true; Layout.preferredWidth: 2; wrapMode: Text.Wrap } } }
                                            Repeater { model: cmpCard.rows
                                                Rectangle { required property var modelData; required property int index; Layout.fillWidth: true; implicitHeight: 34; color: index % 2 === 0 ? (win.dark ? "#1b1d1d" : "#f4f5f2") : "transparent"
                                                    RowLayout { anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 0
                                                        Text { text: bridge.lang === "zh" ? modelData.zh : modelData.en; font.pixelSize: 12; color: win.c.text; Layout.fillWidth: true; Layout.preferredWidth: 3; elide: Text.ElideRight }
                                                        Repeater { model: modelData.v
                                                            Ico { required property int modelData; text: modelData === 2 ? "\uE73E" : modelData === 1 ? "\uE738" : "\uE711"; font.pixelSize: modelData === 2 ? 13 : 10; color: modelData === 2 ? win.c.good : modelData === 1 ? win.c.warn : win.c.low; Layout.fillWidth: true; Layout.preferredWidth: 2 } } } } }
                                            ColumnLayout { Layout.fillWidth: true; Layout.margins: 16; spacing: 10
                                                Text { text: t("功能覆盖（按上表统计）", "Coverage (from the table above)"); font.pixelSize: 11; color: win.c.muted }
                                                Repeater { model: cmpCard.cols
                                                    RowLayout { required property string modelData; required property int index; Layout.fillWidth: true; spacing: 12
                                                        Text { text: modelData; font.pixelSize: 11; color: win.c.text; Layout.preferredWidth: 130; elide: Text.ElideRight }
                                                        Rectangle { Layout.fillWidth: true; height: 6; radius: 3; color: win.c.active
                                                            Rectangle { width: parent.width * cmpCard.score(index); height: parent.height; radius: 3; color: index === 0 ? win.c.good : win.c.low } }
                                                        Text { text: Math.round(cmpCard.score(index) * 100) + "%"; font.pixelSize: 11; color: win.c.text; Layout.preferredWidth: 36; horizontalAlignment: Text.AlignRight } } }
                                                Note { text: t("✓ 支持  — 部分或视产品而定  ✕ 通常不支持。对比依据同类产品的典型形态，不针对具体品牌。", "✓ supported  — partial / varies  ✕ usually not. Based on typical product categories, not specific brands."); font.pixelSize: 10 } } } }
                                    Note { text: t("联系：joulyman@gmail.com · +1 316 872 5748", "Contact: joulyman@gmail.com · +1 316 872 5748"); Layout.bottomMargin: 28 } } }
                        }
                    }
                }
            }
        }
    }

    }

    // ===== 边栏 content: progress, context, permissions, schedule, quick tasks (no status duplication) =====
    Component { id: drawerContent
        Rectangle { color: win.dark ? "#161818" : "#fafaf8"
            Rectangle { width: 1; height: parent.height; color: win.c.line }
            ScrollView { id: dsv; anchors.fill: parent; anchors.margins: 22; anchors.topMargin: 23; contentWidth: availableWidth
                ColumnLayout { width: dsv.availableWidth; spacing: 0
                    RowLayout { Layout.fillWidth: true; Layout.bottomMargin: 24
                        Text { text: t("边栏", "Sidebar"); font.pixelSize: 12; font.weight: Font.DemiBold; color: win.c.strong; Layout.fillWidth: true }
                        Ghost { ico: "\uE711"; size: 11; implicitWidth: 26; implicitHeight: 26; tip: t("收起边栏", "Hide sidebar"); onClicked: win.sidebarOpen = false } }

                    Eyebrow { text: t("当前任务", "CURRENT TASK"); Layout.bottomMargin: 12 }
                    Text { text: bridge.chatTitle; font.pixelSize: 13; color: win.c.strong; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { text: bridge.busy ? t("正在生成回答…", "Generating…") : (bridge.webBusy ? t("正在联网查找…", "Searching the web…") : (bridge.turnCount > 0 ? t("上一轮已完成", "Last turn complete") : t("等待指令", "Waiting for a request"))); font.pixelSize: 11; color: win.c.muted; Layout.topMargin: 8 }
                    Rectangle { Layout.fillWidth: true; Layout.topMargin: 16; Layout.bottomMargin: 6; height: 2; color: win.c.line
                        Rectangle { width: parent.width * win.stagesDone() / 4; height: 2; color: win.c.good; Behavior on width { NumberAnimation { duration: 250 } } } }
                    Repeater { model: [t("理解问题", "Understand"), t("结构检索", "Retrieve"), t("组织依据", "Organize"), t("生成回答", "Answer")]
                        RowLayout { required property int index; required property string modelData; Layout.fillWidth: true; Layout.topMargin: 10; spacing: 10
                            Ico { text: win.stageState(index) === 2 ? "\uE73E" : (win.stageState(index) === 1 ? "\uE916" : "\uECCA"); font.pixelSize: 11; color: win.stageState(index) === 2 ? win.c.good : (win.stageState(index) === 1 ? win.c.warn : win.c.low) }
                            Text { text: modelData; font.pixelSize: 11; color: win.stageState(index) === 0 ? win.c.muted : win.c.text; Layout.fillWidth: true }
                            Text { text: win.stageState(index) === 2 ? t("完成", "Done") : (win.stageState(index) === 1 ? t("进行中", "Running") : "—"); font.pixelSize: 10; color: win.c.muted } } }
                    Line2 { Layout.topMargin: 14; k: t("步骤进度", "Progress"); v: win.stagesDone() + " / 4" + (bridge.lastElapsed && !bridge.busy ? " · " + bridge.lastElapsed : "") }

                    Rule { Layout.topMargin: 20; Layout.bottomMargin: 20 }
                    RowLayout { Layout.fillWidth: true; Layout.bottomMargin: 10
                        Eyebrow { text: t("上下文", "CONTEXT"); Layout.fillWidth: true }
                        Ghost { ico: "\uE894"; size: 11; implicitWidth: 24; implicitHeight: 24; tip: t("清空上下文", "Clear context"); onClicked: bridge.clearContext() } }
                    Note { visible: bridge.screenText === "" && bridge.webSources.length === 0 && bridge.attachments.length === 0; text: t("屏幕、OCR、文件与联网结果会出现在这里，并带入下一轮回答。", "Screen, OCR, files and web results appear here and feed the next answer.") }
                    Line2 { visible: bridge.screenText !== ""; k: t("屏幕 / OCR", "Screen / OCR"); v: bridge.screenMeta }
                    Repeater { model: bridge.attachments
                        Line2 { required property string modelData; k: t("文件", "File"); v: modelData; Layout.topMargin: 6 } }
                    Repeater { model: bridge.webSources
                        AbstractButton { id: src; required property var modelData; required property int index; Layout.fillWidth: true; Layout.topMargin: 8; implicitHeight: scol.implicitHeight + 14; hoverEnabled: true
                            onClicked: if (modelData.url.indexOf("http") === 0) Qt.openUrlExternally(modelData.url)
                            ToolTip.visible: hovered; ToolTip.text: modelData.url; ToolTip.delay: 500
                            background: Rectangle { radius: 6; color: src.hovered ? win.c.hover : "transparent"; border.color: win.c.line }
                            contentItem: Item { ColumnLayout { id: scol; x: 10; y: 7; width: parent.width - 20; spacing: 2
                                Text { text: "[" + (src.index + 1) + "] " + src.modelData.title; font.pixelSize: 11; color: win.c.text; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                                Text { text: src.modelData.url; font.pixelSize: 9; color: win.c.muted; Layout.fillWidth: true; elide: Text.ElideMiddle } } } } }

                    Rule { Layout.topMargin: 20; Layout.bottomMargin: 20 }
                    Eyebrow { text: t("权限", "PERMISSIONS"); Layout.bottomMargin: 4 }
                    Line2 { k: t("屏幕识别", "Screen recognition"); v: t("按需，每次点击时执行", "On demand, per click"); Layout.topMargin: 8; Layout.bottomMargin: 4 }
                    Perm { k: t("电脑控制", "Computer control"); checked: bridge.allowControl; onToggled: function(on) { if (on && !bridge.allowControl) ctlDlg.open(); else bridge.setAllowControl(on) } }
                    Perm { k: t("联网查找", "Web search"); checked: win.webMode; onToggled: function(on) { win.webMode = on } }
                    Perm { k: t("任务模式", "Task mode"); checked: bridge.taskMode; onToggled: function(on) { bridge.setTaskMode(on) } }
                    Perm { k: t("多轮会话驻留", "Keep session warm"); checked: bridge.keepSession; onToggled: function(on) { bridge.setKeepSession(on) } }

                    Rule { Layout.topMargin: 20; Layout.bottomMargin: 20 }
                    Eyebrow { text: t("计划任务", "SCHEDULED"); Layout.bottomMargin: 10 }
                    Note { visible: win.schedAt === 0; text: t("在输入框写好指令后，从「任务调度」选择定时执行。", "Write a request, then choose Schedule under Tasks.") }
                    ColumnLayout { visible: win.schedAt > 0; Layout.fillWidth: true; spacing: 8
                        Text { text: win.schedText; font.pixelSize: 11; color: win.c.text; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight }
                        Line2 { k: t("执行时间", "Runs at"); v: win.schedAt > 0 ? Qt.formatTime(new Date(win.schedAt), "HH:mm:ss") : "" }
                        Pill { text: t("取消定时", "Cancel"); ico: "\uE711"; onClicked: { win.schedAt = 0; win.schedText = "" } } }

                    Rule { Layout.topMargin: 20; Layout.bottomMargin: 20 }
                    Eyebrow { text: t("快捷任务", "QUICK TASKS"); Layout.bottomMargin: 6 }
                    Repeater { model: [
                            { ico: "\uE8FD", zh: "总结本对话", en: "Summarize this chat", pz: "总结目前这段对话的要点，并列出还没解决的问题。", pe: "Summarize the key points of this chat and list open questions." },
                            { ico: "\uE9D5", zh: "列出下一步行动", en: "List next actions", pz: "根据目前的对话，列出接下来要做的行动清单，按优先级排序。", pe: "Based on this chat, list the next actions in priority order." },
                            { ico: "\uE72A", zh: "继续上一回答", en: "Continue", pz: "继续。", pe: "Continue." },
                            { ico: "\uE8A5", zh: "写成正式文档", en: "Rewrite as a document", pz: "把上一条回答整理成结构清晰的正式文档。", pe: "Rewrite the last answer as a well-structured document." } ]
                        AbstractButton { id: qk; required property var modelData; Layout.fillWidth: true; implicitHeight: 32; hoverEnabled: true; enabled: !bridge.busy && msgList.count > 0
                            onClicked: bridge.send(bridge.lang === "zh" ? modelData.pz : modelData.pe)
                            background: Rectangle { radius: 5; color: qk.hovered ? win.c.hover : "transparent" }
                            contentItem: RowLayout { spacing: 10
                                Ico { text: qk.modelData.ico; font.pixelSize: 12; Layout.leftMargin: 6; color: qk.enabled ? win.c.soft : win.c.low }
                                Text { text: bridge.lang === "zh" ? qk.modelData.zh : qk.modelData.en; font.pixelSize: 11; color: qk.enabled ? win.c.text : win.c.low; Layout.fillWidth: true } } } }
                    Item { height: 10 }
                } } } }

    Dialog { id: ctlDlg; title: t("启用电脑控制？", "Enable computer control?"); modal: true; anchors.centerIn: parent; standardButtons: Dialog.Ok | Dialog.Cancel
        Text { text: t("开启后，回答中的控制动作会在本机执行。请确认你信任当前知识与提问内容。", "Control actions in answers will run on this PC. Confirm you trust the current knowledge and prompts."); wrapMode: Text.Wrap; width: 360; color: win.c.soft }
        onAccepted: bridge.setAllowControl(true); onRejected: bridge.setAllowControl(false) }
    Dialog { id: schedDlg; title: t("定时执行", "Schedule"); modal: true; anchors.centerIn: parent; standardButtons: Dialog.Ok | Dialog.Cancel
        ColumnLayout { spacing: 10; width: 340
            Text { text: t("在指定分钟后执行当前输入（软件需保持打开）：", "Run the current input after (app must stay open):"); wrapMode: Text.Wrap; Layout.fillWidth: true; color: win.c.soft; font.pixelSize: 12 }
            RowLayout { SpinBox { id: schedMin; from: 1; to: 1440; value: 10; editable: true } Text { text: t("分钟", "minutes"); color: win.c.soft } }
            Text { text: input.text; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight; Layout.fillWidth: true; color: win.c.muted; font.pixelSize: 11 } }
        onAccepted: if (input.text.trim() !== "") { win.schedText = input.text.trim(); win.schedAt = Date.now() + schedMin.value * 60000; input.clear() } }
    Dialog { id: resetDlg; property string user: ""; title: t("重置密码", "Reset password"); modal: true; anchors.centerIn: parent; standardButtons: Dialog.Ok | Dialog.Cancel
        TextField { id: resetPass; placeholderText: t("新密码", "New password"); echoMode: TextInput.Password; width: 260 }
        onAccepted: if (resetPass.text !== "") bridge.resetAccountPassword(user, resetPass.text) }
    Dialog { id: loginDlg; title: t("本地账号登录", "Local account login"); modal: true; anchors.centerIn: parent; closePolicy: Popup.CloseOnEscape
        ColumnLayout { spacing: 8; width: 300
            TextField { id: gateName; placeholderText: t("登录名", "Login name"); Layout.fillWidth: true }
            TextField { id: gatePass; placeholderText: t("密码", "Password"); echoMode: TextInput.Password; Layout.fillWidth: true }
            Pill { text: t("登录", "Sign in"); primary: true; Layout.fillWidth: true; onClicked: if (bridge.login(gateName.text, gatePass.text)) loginDlg.close() }
            Text { text: bridge.accountMsg; font.pixelSize: 11; color: win.c.bad; wrapMode: Text.Wrap; Layout.fillWidth: true } } }
    Dialog { id: buyInfoDlg; title: t("在线版说明", "About the online edition"); modal: true; anchors.centerIn: parent; standardButtons: Dialog.Close
        ColumnLayout { spacing: 12; width: 440
            Repeater { model: [
                    { ico: "\uE945", zh: "先走 Valhalla 管线结构检索，再交给云端模型", en: "Valhalla structured retrieval first, then the cloud model" },
                    { ico: "\uE709", zh: "本地版永久免费，在线版按需开通", en: "Local edition free forever; online on demand" },
                    { ico: "\uE9D9", zh: "快速推流，长回答更稳", en: "Fast streaming, steadier long answers" },
                    { ico: "\uE72E", zh: "A测期购买按现价锁定", en: "Alpha buyers keep the current price" } ]
                RowLayout { required property var modelData; spacing: 12; Layout.fillWidth: true
                    Ico { text: modelData.ico; font.pixelSize: 14 }
                    Body { text: bridge.lang === "zh" ? modelData.zh : modelData.en } } }
            Rule {}
            Body { text: t("购买流程：联系我们 → 付款 → 收到 CDK → 在「在线大模型」兑换。", "How to buy: contact us → pay → receive CDK → redeem under Online model.") }
            Text { text: "+1 316 872 5748 · joulyman@gmail.com"; font.pixelSize: 12; font.weight: Font.DemiBold; color: win.c.strong } } }
    FileDialog { id: ocrDlg; title: t("选择图片做 OCR", "Choose images for OCR"); fileMode: FileDialog.OpenFiles; nameFilters: ["Images (*.png *.jpg *.jpeg *.bmp *.webp)"]; onAccepted: bridge.ocrImport(selectedFiles) }
    FileDialog { id: attachDlg; title: t("附加文件到上下文", "Attach files to context"); fileMode: FileDialog.OpenFiles; nameFilters: [t("文本与代码", "Text & code") + " (*.txt *.md *.csv *.tsv *.json *.jsonl *.xml *.yaml *.yml *.ini *.toml *.log *.html *.htm *.py *.js *.ts *.c *.h *.cpp *.hpp *.cs *.java *.kt *.go *.rs *.sql *.sh *.ps1 *.bat)", t("所有文件", "All files") + " (*)"]; onAccepted: bridge.attachFiles(selectedFiles) }
    FileDialog { id: kbDlg; title: t("导入知识文件", "Import knowledge files"); fileMode: FileDialog.OpenFiles; onAccepted: bridge.importFiles(kbDomain.text, selectedFiles) }
    FileDialog { id: exportDlg; title: t("导出对话", "Export chat"); fileMode: FileDialog.SaveFile; defaultSuffix: "md"; nameFilters: ["Markdown (*.md)"]; onAccepted: bridge.exportChat(selectedFile) }
}
