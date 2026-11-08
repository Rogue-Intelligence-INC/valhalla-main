import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtCore

// VAL-DAL main edition — FluentWinUI3 (Qt Quick Controls native Win11 style).
// Fixed Valhalla mode; one status light (bottom-left, opens the status popup);
// full-screen settings page; right panel is the 边栏.
ApplicationWindow {
    id: win
    width: 1360; height: 860; minimumWidth: 1020; minimumHeight: 640
    visible: true
    title: "VAL-DAL"
    color: dark ? "#202020" : "#f7f7f7"

    property bool dark: true
    property int page: 0            // 0 chat, 1 workspace, 2 settings (full screen)
    property int settingsSection: 0 // pipeline, online, knowledge, appearance, account, about
    property bool sidebarOpen: true
    property bool webMode: false
    property string cdkMsg: ""
    property string grabName: "grab.png"

    readonly property color fg: dark ? "#ffffff" : "#1b1b1b"
    readonly property color fg2: dark ? "#e4e4e4" : "#333333"
    readonly property color muted: dark ? "#a6a6a6" : "#616161"
    readonly property color accent: dark ? "#60cdff" : "#005fb8"
    readonly property color accentFg: dark ? "#00243a" : "#ffffff"
    readonly property color card: dark ? "#2b2b2b" : "#ffffff"
    readonly property color cardAlt: dark ? "#333333" : "#f0f0f0"
    readonly property color stroke: dark ? "#3a3a3a" : "#e2e2e2"
    readonly property color navBg: dark ? "#1b1b1b" : "#eeeeee"
    readonly property color userBubble: dark ? "#16384d" : "#dcebf8"
    readonly property string logo: dark ? "qrc:/qt/qml/Valhalla/logo-white.png" : "qrc:/qt/qml/Valhalla/logo-black.png"

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
    function sigColor(s) { return s === 2 ? "#13a10e" : s === 1 ? "#d5a000" : "#d13438" }
    function sigWord(s) { return s === 2 ? t("运行正常", "All good") : s === 1 ? t("需要注意", "Attention") : t("异常", "Problem") }
    function stageState(i) {
        if (bridge.busy) return i === 0 ? 1 : 0
        if (bridge.turnCount === 0) return 0
        var p = (bridge.lastPath || "").toLowerCase()
        if (i === 1) return (p.indexOf("retriev") >= 0 || p.indexOf("phrase") >= 0 || p.indexOf("native") >= 0 || p.indexOf("mcq") >= 0 || p.indexOf("logprob") >= 0) ? 2 : 1
        return 2
    }
    function doSend() {
        var q = input.text.trim()
        if (q === "" || bridge.busy || bridge.webBusy) return
        if (win.webMode) bridge.webSearch(q, true); else bridge.send(q)
        input.clear()
    }
    function prefill(s) { input.text = s; input.cursorPosition = s.length; input.forceActiveFocus(); win.page = 0 }

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
            else if (args[i] === "--buyinfo") { win.page = 2; win.settingsSection = 1; buyInfoDlg.open() }
        }
        applyTheme(); if (bridge.accountsEnabled) loginDlg.open()
    }
    onDarkChanged: { store.darkTheme = win.dark; applyTheme() }

    // ===== shared components =====
    component Ico: Text { font.family: "Segoe Fluent Icons"; font.pixelSize: 16; color: win.fg; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
    component IconBtn: ToolButton {
        property string ico: ""; property string tip: ""; property color tint: win.fg
        implicitWidth: 34; implicitHeight: 34
        contentItem: Ico { text: parent.ico; color: !parent.enabled ? win.muted : (parent.checked ? win.accent : parent.tint) }
        ToolTip.visible: hovered && tip !== ""; ToolTip.text: tip; ToolTip.delay: 350
    }
    component NavItem: Button {
        property string ico: ""; property bool current: false
        Layout.fillWidth: true; flat: !current; implicitHeight: 38
        contentItem: RowLayout { spacing: 12
            Rectangle { width: 3; height: 16; radius: 1.5; color: parent.parent.current ? win.accent : "transparent" }
            Ico { text: parent.parent.ico; font.pixelSize: 16; color: parent.parent.current ? win.accent : win.fg }
            Text { text: parent.parent.text; color: win.fg; font.pixelSize: 13; font.weight: parent.parent.current ? Font.DemiBold : Font.Normal; Layout.fillWidth: true; elide: Text.ElideRight }
        }
    }
    component Card: Frame {
        padding: 16
        background: Rectangle { radius: 8; color: win.card; border.color: win.stroke }
    }
    component H1: Text { font.pixelSize: 20; font.weight: Font.DemiBold; color: win.fg; Layout.fillWidth: true; wrapMode: Text.Wrap }
    component H2: Text { font.pixelSize: 14; font.weight: Font.DemiBold; color: win.fg; Layout.fillWidth: true; wrapMode: Text.Wrap }
    component Body: Text { font.pixelSize: 12; color: win.fg2; Layout.fillWidth: true; wrapMode: Text.Wrap; lineHeight: 1.15 }
    component Note: Text { font.pixelSize: 11; color: win.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    component SigRow: RowLayout {
        property string ico: ""; property string name: ""; property int level: 0; property string detail: ""
        spacing: 10; Layout.fillWidth: true
        Rectangle { Layout.alignment: Qt.AlignTop; width: 32; height: 32; radius: 6; color: win.cardAlt
            Ico { anchors.centerIn: parent; text: ico; font.pixelSize: 15 }
            Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: -2; width: 10; height: 10; radius: 5; color: win.sigColor(level); border.color: win.card; border.width: 2 } }
        ColumnLayout { spacing: 1; Layout.fillWidth: true
            Text { text: name; font.pixelSize: 12; font.weight: Font.DemiBold; color: win.fg }
            Note { text: detail } }
    }
    component Chip: Button {
        property string ico: ""; property string sub: ""
        flat: true; implicitHeight: 64; Layout.fillWidth: true
        background: Rectangle { radius: 8; color: parent.hovered ? win.cardAlt : win.card; border.color: win.stroke }
        contentItem: RowLayout { spacing: 10
            Ico { text: parent.parent.ico; color: win.accent; font.pixelSize: 18; Layout.preferredWidth: 24 }
            ColumnLayout { spacing: 1; Layout.fillWidth: true
                Text { text: parent.parent.parent.text; font.pixelSize: 12; font.weight: Font.DemiBold; color: win.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                Text { text: parent.parent.parent.sub; font.pixelSize: 10; color: win.muted; Layout.fillWidth: true; elide: Text.ElideRight } } }
    }

    // ===== status popup: the only place pipeline/model/connection detail lives =====
    Popup { id: statusPopup; x: 12; y: win.height - height - 12; width: 340; padding: 16
        height: statusCol.implicitHeight + 32; modal: false; focus: true; closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        ColumnLayout { id: statusCol; anchors.fill: parent; spacing: 12
            RowLayout { Layout.fillWidth: true
                Rectangle { width: 10; height: 10; radius: 5; color: win.sigColor(win.sigAll()) }
                H2 { text: t("状态", "Status") + " · " + win.sigWord(win.sigAll()) }
                IconBtn { ico: "\uE711"; tip: t("关闭", "Close"); onClicked: statusPopup.close() } }
            SigRow { ico: "\uE945"; name: t("Valhalla 管线", "Valhalla pipeline"); level: win.sigPipeline(); detail: bridge.enginePresent ? t("引擎就绪 · 五段管线", "Engine ready · 5-stage pipeline") : t("未找到引擎", "Engine missing") }
            SigRow { ico: "\uE950"; name: t("本地模型", "Local model"); level: win.sigModel(); detail: bridge.currentModelName + " · " + (bridge.modelLoaded ? t("已加载", "Loaded") : t("未加载", "Not loaded")) + " · " + bridge.computeDevice }
            SigRow { ico: "\uE753"; name: t("连接", "Connection"); level: win.sigLink(); detail: store.plan !== "" ? (t("在线 · ", "Online · ") + win.cdkPlanName(store.plan)) : t("本地运行 · 在线版未开通", "Local · online not activated") }
            Note { text: bridge.runtimeText; font.pixelSize: 10; visible: text !== "" }
            RowLayout { Layout.fillWidth: true
                Button { text: t("检查运行时", "Probe runtime"); enabled: !bridge.busy; onClicked: bridge.probe() }
                Button { text: t("修复管线", "Repair pipeline"); flat: true; enabled: !bridge.pipelineBusy; onClicked: { statusPopup.close(); win.goSettings(0); bridge.repairPipeline() } } }
        }
    }

    Timer { id: grabTimer; interval: 2500; onTriggered: rootRow.grabToImage(function(r){ r.saveToFile("C:/Ai/rogue-products/valhalla-windows/qt/shots/" + win.grabName); console.log("GRABBED") }, Qt.size(1360, 860)) }

    RowLayout { id: rootRow
        anchors.fill: parent; spacing: 0

        // ===== navigation pane (hidden on the full-screen settings page) =====
        Pane { visible: win.page !== 2
            Layout.preferredWidth: 236; Layout.fillHeight: true; padding: 12
            background: Rectangle { color: win.navBg; Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: win.stroke } }
            ColumnLayout { anchors.fill: parent; spacing: 4
                RowLayout { Layout.fillWidth: true; spacing: 10; Layout.bottomMargin: 8
                    Image { source: win.logo; Layout.preferredWidth: 30; Layout.preferredHeight: 30; fillMode: Image.PreserveAspectFit }
                    ColumnLayout { spacing: 0; Layout.fillWidth: true
                        Text { text: "VAL-DAL"; font.pixelSize: 15; font.weight: Font.Bold; font.letterSpacing: 0.5; color: win.fg }
                        Text { text: t("瓦序 · Valhalla 模式", "Valhalla mode"); font.pixelSize: 10; color: win.muted } } }
                Button { Layout.fillWidth: true; highlighted: true; implicitHeight: 38; enabled: !bridge.busy; onClicked: { bridge.newChat(); win.page = 0 }
                    ToolTip.visible: hovered; ToolTip.text: t("新建对话", "New chat"); ToolTip.delay: 350
                    contentItem: RowLayout { spacing: 8
                        Item { Layout.fillWidth: true }
                        Ico { text: "\uE710"; font.pixelSize: 14; color: win.accentFg }
                        Text { text: t("新建对话", "New chat"); font.pixelSize: 13; font.weight: Font.DemiBold; color: win.accentFg }
                        Item { Layout.fillWidth: true } } }
                Item { height: 6 }
                NavItem { ico: "\uE8F2"; text: t("对话", "Chat"); current: win.page === 0; onClicked: win.page = 0 }
                NavItem { ico: "\uE8B7"; text: t("工作区", "Workspace"); current: win.page === 1; onClicked: win.page = 1 }
                Item { Layout.fillHeight: true }
                // single status light → status popup
                Button { Layout.fillWidth: true; flat: true; implicitHeight: 52
                    ToolTip.visible: hovered; ToolTip.text: t("查看管线、模型与连接状态", "Pipeline, model and connection status"); ToolTip.delay: 350
                    onClicked: statusPopup.open()
                    contentItem: RowLayout { spacing: 10
                        Rectangle { width: 32; height: 32; radius: 16; color: win.cardAlt
                            Ico { anchors.centerIn: parent; text: "\uE77B"; font.pixelSize: 14 }
                            Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; width: 11; height: 11; radius: 5.5; color: win.sigColor(win.sigAll()); border.color: win.navBg; border.width: 2
                                SequentialAnimation on opacity { running: bridge.busy || bridge.webBusy; loops: Animation.Infinite; NumberAnimation { to: 0.35; duration: 600 } NumberAnimation { to: 1; duration: 600 } } } }
                        ColumnLayout { spacing: 0; Layout.fillWidth: true
                            Text { text: bridge.currentUser; font.pixelSize: 12; font.weight: Font.DemiBold; color: win.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                            Text { text: (bridge.busy ? t("处理中", "Working") : win.sigWord(win.sigAll())) + " · " + (store.plan !== "" ? t("在线", "Online") : t("本地", "Local")); font.pixelSize: 10; color: win.muted; Layout.fillWidth: true; elide: Text.ElideRight } }
                        Ico { text: "\uE76C"; font.pixelSize: 10; color: win.muted } } }
                NavItem { ico: "\uE713"; text: t("设置", "Settings"); current: false; onClicked: win.goSettings(win.settingsSection) }
            }
        }

        StackLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: win.page

            // ===== chat page =====
            ColumnLayout { spacing: 0
                // top bar
                RowLayout { Layout.fillWidth: true; Layout.margins: 10; Layout.leftMargin: 20; spacing: 4
                    ColumnLayout { spacing: 0; Layout.fillWidth: true
                        Text { text: bridge.currentWorkspace + "  /  " + bridge.currentProject; font.pixelSize: 10; font.letterSpacing: 0.4; color: win.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: bridge.chatTitle; font.pixelSize: 17; font.weight: Font.DemiBold; color: win.fg; Layout.fillWidth: true; elide: Text.ElideRight } }
                    IconBtn { ico: "\uE78C"; tip: t("导出对话（Markdown）", "Export chat (Markdown)"); enabled: msgList.count > 0; onClicked: exportDlg.open() }
                    IconBtn { ico: win.dark ? "\uE706" : "\uE708"; tip: t("切换浅色/深色", "Toggle light/dark"); onClicked: win.dark = !win.dark }
                    IconBtn { ico: win.sidebarOpen ? "\uE89F" : "\uE8A0"; tip: t("边栏", "Sidebar"); tint: win.sidebarOpen ? win.accent : win.fg; onClicked: win.sidebarOpen = !win.sidebarOpen }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: win.stroke }

                RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                    ColumnLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 8
                        Card { Layout.fillWidth: true; Layout.margins: 12; Layout.bottomMargin: 0; visible: !bridge.envReady && !bridge.envDismissed; padding: 10
                            RowLayout { anchors.fill: parent; spacing: 8
                                Ico { text: "\uE7BA"; color: "#d5a000" }
                                Body { text: t("运行环境未就绪：", "Runtime not ready: ") + bridge.envReport }
                                Button { text: t("一键配置", "Set up"); highlighted: true; onClicked: bridge.setupEnvironment() }
                                IconBtn { ico: "\uE711"; tip: t("关闭", "Dismiss"); onClicked: bridge.dismissEnvSetup() } } }

                        Item { Layout.fillWidth: true; Layout.fillHeight: true
                            ListView {
                                id: msgList; anchors.fill: parent; anchors.topMargin: 12; clip: true; spacing: 14
                                model: bridge.messages
                                ScrollBar.vertical: ScrollBar {}
                                delegate: Item {
                                    required property var modelData; required property int index
                                    width: msgList.width; height: row.implicitHeight
                                    Text { id: meas; visible: false; text: modelData.text; font.pixelSize: 13 }
                                    RowLayout { id: row; width: Math.min(820, msgList.width - 48); x: (msgList.width - width) / 2; spacing: 10
                                        layoutDirection: modelData.user ? Qt.RightToLeft : Qt.LeftToRight
                                        Rectangle { Layout.alignment: Qt.AlignTop; width: 30; height: 30; radius: 15; color: modelData.user ? win.accent : win.cardAlt
                                            Image { visible: !modelData.user && modelData.path !== "web"; anchors.centerIn: parent; width: 18; height: 18; source: win.logo; fillMode: Image.PreserveAspectFit }
                                            Ico { visible: modelData.user || modelData.path === "web"; anchors.centerIn: parent; text: modelData.user ? "\uE77B" : "\uE774"; font.pixelSize: 14; color: modelData.user ? win.accentFg : win.accent } }
                                        Rectangle {
                                            Layout.preferredWidth: modelData.user ? Math.min(row.width * 0.72, meas.implicitWidth + 30) : row.width - 40
                                            Layout.preferredHeight: bcol.implicitHeight + 22
                                            radius: 10; color: modelData.user ? win.userBubble : win.card; border.color: modelData.user ? "transparent" : (modelData.error ? "#d13438" : win.stroke)
                                            ColumnLayout { id: bcol; x: 15; y: 11; width: parent.width - 30; spacing: 6
                                                Text { visible: !modelData.user && modelData.badge !== ""; text: (modelData.path === "web" ? "" : "VALHALLA · ") + modelData.badge; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 0.6; color: win.accent }
                                                TextEdit { id: msgText; text: modelData.text; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; font.pixelSize: modelData.path === "web" ? 11 : 13; Layout.fillWidth: true
                                                    color: modelData.error ? "#d13438" : (modelData.path === "web" ? win.fg2 : win.fg); selectionColor: win.accent; selectedTextColor: win.accentFg }
                                                RowLayout { visible: !modelData.user; spacing: 0
                                                    IconBtn { ico: "\uE8C8"; tip: t("复制", "Copy"); implicitWidth: 28; implicitHeight: 28; tint: win.muted; onClicked: bridge.copyText(msgText.text) }
                                                    IconBtn { ico: "\uE767"; tip: t("朗读", "Read aloud"); implicitWidth: 28; implicitHeight: 28; tint: win.muted; visible: modelData.path !== "web"; onClicked: bridge.speakText(msgText.text) }
                                                    IconBtn { ico: "\uE71A"; tip: t("停止朗读", "Stop reading"); implicitWidth: 28; implicitHeight: 28; tint: win.muted; visible: modelData.path !== "web"; onClicked: bridge.stopSpeak() }
                                                    IconBtn { ico: "\uE72C"; tip: t("重新生成", "Regenerate"); implicitWidth: 28; implicitHeight: 28; tint: win.muted; visible: modelData.path !== "web" && index === msgList.count - 1; enabled: !bridge.busy; onClicked: bridge.retryLast() }
                                                    IconBtn { ico: "\uE8C1"; tip: t("翻译选中内容", "Translate selection"); implicitWidth: 28; implicitHeight: 28; tint: win.accent; visible: msgText.selectedText !== ""; onClicked: bridge.askSelection("translate", msgText.selectedText) }
                                                    IconBtn { ico: "\uE82F"; tip: t("解释选中内容", "Explain selection"); implicitWidth: 28; implicitHeight: 28; tint: win.accent; visible: msgText.selectedText !== ""; onClicked: bridge.askSelection("explain", msgText.selectedText) }
                                                    Item { Layout.fillWidth: true } } } }
                                        Item { Layout.fillWidth: true } } }
                                onCountChanged: Qt.callLater(function(){ msgList.positionViewAtEnd() })
                            }
                            // empty state with agent quick starts
                            ColumnLayout { visible: msgList.count === 0; anchors.centerIn: parent; width: Math.min(620, parent.width - 48); spacing: 14
                                Image { source: win.logo; Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 48; Layout.preferredHeight: 48; fillMode: Image.PreserveAspectFit; opacity: 0.9 }
                                Text { text: t("今天要完成什么？", "What shall we get done?"); font.pixelSize: 24; font.weight: Font.DemiBold; color: win.fg; Layout.alignment: Qt.AlignHCenter }
                                Text { text: t("本地运行 · 依据可核查 · 可联网查找", "Runs locally · checkable evidence · web search on demand"); font.pixelSize: 12; color: win.muted; Layout.alignment: Qt.AlignHCenter }
                                GridLayout { columns: 2; columnSpacing: 10; rowSpacing: 10; Layout.fillWidth: true; Layout.topMargin: 8
                                    Chip { ico: "\uE7F4"; text: t("读懂当前屏幕", "Explain my screen"); sub: t("识别屏幕后说明内容与可做操作", "Recognize, then explain and suggest actions"); onClicked: { bridge.recognize(); win.prefill(t("说明当前屏幕上的内容，并指出可以进行的操作。", "Explain what is on the screen and what I can do next.")) } }
                                    Chip { ico: "\uE774"; text: t("联网查找", "Search the web"); sub: t("先查最新来源，再结合本地知识回答", "Fetch fresh sources, then answer with local knowledge"); onClicked: { win.webMode = true; win.prefill("") } }
                                    Chip { ico: "\uE9D5"; text: t("拆解任务", "Break down a task"); sub: t("把目标拆成可执行步骤", "Turn a goal into executable steps"); onClicked: win.prefill(t("把这个任务拆解为可执行的步骤：", "Break this task into executable steps: ")) }
                                    Chip { ico: "\uE91B"; text: t("图片文字识别", "Read an image"); sub: t("OCR 导入图片后提问", "OCR images, then ask about them"); onClicked: ocrDlg.open() } } }
                        }

                        Text { visible: bridge.statusText !== ""; text: bridge.statusText; font.pixelSize: 11; color: win.muted; Layout.alignment: Qt.AlignHCenter; Layout.maximumWidth: 780; elide: Text.ElideRight }
                        // input card
                        Rectangle { Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; Layout.maximumWidth: 820; Layout.leftMargin: 24; Layout.rightMargin: 24; Layout.bottomMargin: 16
                            Layout.preferredHeight: icol.implicitHeight + 16; radius: 12; color: win.card; border.color: input.activeFocus ? win.accent : win.stroke
                            ColumnLayout { id: icol; x: 8; y: 8; width: parent.width - 16; spacing: 2
                                RowLayout { visible: win.webMode || bridge.taskMode || bridge.screenText !== "" || bridge.webSources.length > 0; Layout.leftMargin: 6; spacing: 6
                                    Repeater { model: [
                                            { on: win.webMode, ico: "\uE774", zh: "联网查找", en: "Web search" },
                                            { on: bridge.taskMode, ico: "\uE9D5", zh: "任务模式", en: "Task mode" },
                                            { on: bridge.screenText !== "", ico: "\uE7F4", zh: bridge.screenMeta, en: bridge.screenMeta },
                                            { on: bridge.webSources.length > 0, ico: "\uE71B", zh: bridge.webSources.length + " 条来源", en: bridge.webSources.length + " sources" } ]
                                        Rectangle { required property var modelData; visible: modelData.on; radius: 10; height: 22; width: crow.implicitWidth + 16; color: win.cardAlt
                                            RowLayout { id: crow; anchors.centerIn: parent; spacing: 4
                                                Ico { text: modelData.ico; font.pixelSize: 11; color: win.accent }
                                                Text { text: bridge.lang === "zh" ? modelData.zh : modelData.en; font.pixelSize: 10; color: win.fg2; Layout.maximumWidth: 220; elide: Text.ElideRight } } } }
                                    IconBtn { ico: "\uE894"; tip: t("清空上下文", "Clear context"); implicitWidth: 24; implicitHeight: 24; tint: win.muted; visible: bridge.screenText !== "" || bridge.webSources.length > 0; onClicked: bridge.clearContext() } }
                                TextArea { id: input; Layout.fillWidth: true; Layout.preferredHeight: Math.min(160, Math.max(52, contentHeight + 20)); wrapMode: TextArea.Wrap
                                    placeholderText: win.webMode ? t("输入要联网查找的问题…", "Ask something to search the web for…") : t("输入消息，Enter 发送，Shift+Enter 换行", "Message — Enter to send, Shift+Enter for newline")
                                    background: Item {}
                                    Keys.onPressed: function(e) { if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) { win.doSend(); e.accepted = true } } }
                                RowLayout { Layout.fillWidth: true; spacing: 2
                                    IconBtn { ico: "\uE7F4"; tip: t("识别屏幕", "Recognize screen"); enabled: !bridge.busy; onClicked: bridge.recognize() }
                                    IconBtn { ico: "\uE91B"; tip: t("OCR 导入图片", "OCR import images"); enabled: !bridge.busy; onClicked: ocrDlg.open() }
                                    IconBtn { ico: "\uE774"; tip: t("联网查找（发送前先搜索来源）", "Web search (fetch sources before answering)"); checkable: true; checked: win.webMode; onClicked: win.webMode = !win.webMode }
                                    IconBtn { ico: "\uE9D5"; tip: t("任务模式（直接执行并汇报结果）", "Task mode (do it and report)"); checkable: true; checked: bridge.taskMode; onClicked: bridge.setTaskMode(!bridge.taskMode) }
                                    IconBtn { id: ctlBtn; ico: "\uE7C9"; tip: t("电脑控制（需确认）", "Computer control (needs confirmation)"); checkable: true; checked: bridge.allowControl
                                        onClicked: { if (checked && !bridge.allowControl) ctlDlg.open(); else bridge.setAllowControl(checked) } }
                                    Item { Layout.fillWidth: true }
                                    BusyIndicator { running: bridge.busy || bridge.webBusy; visible: running; implicitWidth: 24; implicitHeight: 24 }
                                    RoundButton { highlighted: true; implicitWidth: 36; implicitHeight: 36; enabled: !bridge.busy && !bridge.webBusy && input.text.trim() !== ""; onClicked: win.doSend()
                                        ToolTip.visible: hovered; ToolTip.text: win.webMode ? t("联网查找并回答", "Search and answer") : t("发送", "Send"); ToolTip.delay: 350
                                        contentItem: Ico { text: win.webMode ? "\uE721" : "\uE724"; font.pixelSize: 14; color: parent.enabled ? win.accentFg : win.muted } } } } }
                    }

                    // ===== 边栏 =====
                    Pane { visible: win.sidebarOpen; Layout.preferredWidth: 290; Layout.fillHeight: true; padding: 16
                        background: Rectangle { color: win.navBg; Rectangle { width: 1; height: parent.height; color: win.stroke } }
                        ScrollView { id: sideSv; anchors.fill: parent; contentWidth: availableWidth
                            ColumnLayout { width: sideSv.availableWidth; spacing: 14
                                RowLayout { Layout.fillWidth: true
                                    H2 { text: t("边栏", "Sidebar") }
                                    IconBtn { ico: "\uE711"; tip: t("收起边栏", "Hide sidebar"); implicitWidth: 28; implicitHeight: 28; onClicked: win.sidebarOpen = false } }

                                Text { text: t("执行阶段", "EXECUTION"); font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.8; color: win.muted }
                                ColumnLayout { spacing: 0; Layout.fillWidth: true
                                    Repeater { model: [t("理解问题", "Understand"), t("结构检索", "Retrieve"), t("组织依据", "Organize"), t("生成回答", "Answer")]
                                        RowLayout { required property int index; required property string modelData; spacing: 10; Layout.fillWidth: true
                                            ColumnLayout { spacing: 0; Layout.preferredWidth: 14
                                                Rectangle { Layout.alignment: Qt.AlignHCenter; width: 12; height: 12; radius: 6; color: win.stageState(index) === 2 ? "#13a10e" : win.stageState(index) === 1 ? "#d5a000" : "transparent"; border.color: win.stageState(index) === 0 ? win.muted : "transparent"; border.width: 1.5 }
                                                Rectangle { Layout.alignment: Qt.AlignHCenter; width: 2; height: 20; color: win.stroke; visible: index < 3 } }
                                            Text { Layout.alignment: Qt.AlignTop; text: modelData + (win.stageState(index) === 1 && bridge.busy ? "  …" : ""); font.pixelSize: 12; color: win.stageState(index) === 0 ? win.muted : win.fg } } } }
                                Note { text: bridge.lastBadge ? (bridge.lastBadge + " · " + bridge.lastElapsed) : t("尚无已完成轮次", "No completed turn yet"); font.pixelSize: 10 }

                                Rectangle { Layout.fillWidth: true; height: 1; color: win.stroke }
                                RowLayout { Layout.fillWidth: true
                                    Text { text: t("上下文", "CONTEXT"); font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.8; color: win.muted; Layout.fillWidth: true }
                                    IconBtn { ico: "\uE894"; tip: t("清空上下文", "Clear context"); implicitWidth: 26; implicitHeight: 26; tint: win.muted; onClicked: bridge.clearContext() } }
                                Note { visible: bridge.screenText === "" && bridge.webSources.length === 0; text: t("识别屏幕、OCR 或联网查找的内容会出现在这里，并带入下一轮回答。", "Screen, OCR and web results appear here and feed the next answer.") }
                                RowLayout { visible: bridge.screenText !== ""; spacing: 8; Layout.fillWidth: true
                                    Ico { text: "\uE7F4"; font.pixelSize: 13; color: win.accent }
                                    Body { text: bridge.screenMeta; font.pixelSize: 11 } }
                                Repeater { model: bridge.webSources
                                    Rectangle { required property var modelData; required property int index; Layout.fillWidth: true; radius: 6; color: win.card; border.color: win.stroke; implicitHeight: scol.implicitHeight + 14
                                        ColumnLayout { id: scol; x: 10; y: 7; width: parent.width - 20; spacing: 2
                                            Text { text: "[" + (index + 1) + "] " + modelData.title; font.pixelSize: 11; font.weight: Font.DemiBold; color: win.fg; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
                                            Text { text: modelData.url; font.pixelSize: 9; color: win.accent; Layout.fillWidth: true; elide: Text.ElideMiddle } }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (modelData.url.indexOf("http") === 0) Qt.openUrlExternally(modelData.url) } } }

                                Rectangle { Layout.fillWidth: true; height: 1; color: win.stroke }
                                Text { text: t("快捷任务", "QUICK TASKS"); font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.8; color: win.muted }
                                Repeater { model: [
                                        { ico: "\uE8FD", zh: "总结本对话", en: "Summarize this chat", pz: "总结目前这段对话的要点，并列出还没解决的问题。", pe: "Summarize the key points of this chat and list open questions.", go: true },
                                        { ico: "\uE9D5", zh: "列出下一步行动", en: "List next actions", pz: "根据目前的对话，列出接下来要做的行动清单，按优先级排序。", pe: "Based on this chat, list the next actions in priority order.", go: true },
                                        { ico: "\uE72A", zh: "继续上一回答", en: "Continue", pz: "继续。", pe: "Continue.", go: true },
                                        { ico: "\uE8A5", zh: "写成正式文档", en: "Rewrite as a document", pz: "把上一条回答整理成结构清晰的正式文档。", pe: "Rewrite the last answer as a well-structured document.", go: true } ]
                                    Button { required property var modelData; Layout.fillWidth: true; flat: true; implicitHeight: 34; enabled: !bridge.busy && msgList.count > 0
                                        onClicked: bridge.send(bridge.lang === "zh" ? modelData.pz : modelData.pe)
                                        contentItem: RowLayout { spacing: 10
                                            Ico { text: modelData.ico; font.pixelSize: 13; color: parent.parent.enabled ? win.accent : win.muted }
                                            Text { text: bridge.lang === "zh" ? modelData.zh : modelData.en; font.pixelSize: 12; color: parent.parent.enabled ? win.fg : win.muted; Layout.fillWidth: true } } } }
                            } } }
                }
            }

            // ===== workspace page =====
            ColumnLayout { spacing: 0
                RowLayout { Layout.fillWidth: true; Layout.margins: 10; Layout.leftMargin: 20
                    H1 { text: t("工作区", "Workspace") }
                    IconBtn { ico: win.dark ? "\uE706" : "\uE708"; tip: t("切换浅色/深色", "Toggle light/dark"); onClicked: win.dark = !win.dark } }
                Rectangle { Layout.fillWidth: true; height: 1; color: win.stroke }
                ColumnLayout { Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 20; spacing: 12
                    RowLayout { Layout.fillWidth: true; spacing: 12
                        Card { Layout.fillWidth: true
                            ColumnLayout { anchors.fill: parent; spacing: 8
                                RowLayout { Ico { text: "\uE8B7"; color: win.accent } H2 { text: t("工作区", "Workspaces") } }
                                ComboBox { id: wsBox; Layout.fillWidth: true; model: bridge.workspaces; textRole: "name"; currentIndex: { for (var i=0;i<bridge.workspaces.length;i++) if (bridge.workspaces[i].name===bridge.currentWorkspace) return i; return 0 } onActivated: bridge.switchWorkspace(currentText) }
                                RowLayout { Layout.fillWidth: true
                                    TextField { id: wsName; placeholderText: t("新工作区名", "New workspace name"); Layout.fillWidth: true }
                                    IconBtn { ico: "\uE710"; tip: t("新建工作区", "New workspace"); onClicked: if (wsName.text.trim() !== "") { bridge.addWorkspace(wsName.text); wsName.clear() } } } } }
                        Card { Layout.fillWidth: true
                            ColumnLayout { anchors.fill: parent; spacing: 8
                                RowLayout { Ico { text: "\uE8F1"; color: win.accent } H2 { text: t("项目", "Projects") } }
                                ComboBox { id: pjBox; Layout.fillWidth: true; model: bridge.projects; textRole: "name"; currentIndex: { for (var i=0;i<bridge.projects.length;i++) if (bridge.projects[i].name===bridge.currentProject) return i; return 0 } onActivated: bridge.switchProject(currentText) }
                                RowLayout { Layout.fillWidth: true
                                    TextField { id: pjName; placeholderText: t("新项目名", "New project name"); Layout.fillWidth: true }
                                    IconBtn { ico: "\uE710"; tip: t("新建项目", "New project"); onClicked: if (pjName.text.trim() !== "") { bridge.addProject(pjName.text); pjName.clear() } } } } } }
                    Card { Layout.fillWidth: true; Layout.fillHeight: true
                        ColumnLayout { anchors.fill: parent; spacing: 8
                            RowLayout { Layout.fillWidth: true
                                Ico { text: "\uE8F2"; color: win.accent }
                                H2 { text: t("对话记录", "Conversations") }
                                TextField { Layout.preferredWidth: 260; placeholderText: t("搜索对话", "Search chats"); onTextChanged: bridge.setSearch(text) } }
                            ListView { Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 2; model: bridge.conversations
                                ScrollBar.vertical: ScrollBar {}
                                section.property: "project"; section.delegate: Text { required property string section; text: section; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.6; color: win.muted; topPadding: 10; bottomPadding: 4 }
                                delegate: ItemDelegate { required property var modelData; width: ListView.view.width; highlighted: modelData.active; implicitHeight: 38
                                    contentItem: RowLayout { spacing: 10
                                        Ico { text: "\uE8BD"; font.pixelSize: 13; color: win.muted }
                                        Text { text: modelData.title; font.pixelSize: 12; color: win.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                                        IconBtn { ico: "\uE74D"; tip: t("删除对话", "Delete chat"); implicitWidth: 28; implicitHeight: 28; tint: win.muted; onClicked: bridge.deleteChat(modelData.id) } }
                                    onClicked: { bridge.openChat(modelData.id); win.page = 0 } } } } }
                }
            }

            // ===== settings page (full screen) =====
            ColumnLayout { spacing: 0
                RowLayout { Layout.fillWidth: true; Layout.margins: 10; Layout.leftMargin: 14; spacing: 8
                    IconBtn { ico: "\uE72B"; tip: t("返回", "Back"); onClicked: win.page = 0 }
                    Image { source: win.logo; Layout.preferredWidth: 22; Layout.preferredHeight: 22; fillMode: Image.PreserveAspectFit }
                    H1 { text: t("设置", "Settings") }
                    IconBtn { ico: win.dark ? "\uE706" : "\uE708"; tip: t("切换浅色/深色", "Toggle light/dark"); onClicked: win.dark = !win.dark } }
                Rectangle { Layout.fillWidth: true; height: 1; color: win.stroke }
                RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                    Pane { Layout.preferredWidth: 240; Layout.fillHeight: true; padding: 12
                        background: Rectangle { color: win.navBg; Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: win.stroke } }
                        ColumnLayout { anchors.fill: parent; spacing: 2
                            Repeater { model: [
                                    { ico: "\uE945", zh: "管线与模型", en: "Pipeline & models" },
                                    { ico: "\uE753", zh: "在线大模型", en: "Online model" },
                                    { ico: "\uE8F1", zh: "知识库", en: "Knowledge" },
                                    { ico: "\uE790", zh: "外观与语言", en: "Appearance & language" },
                                    { ico: "\uE716", zh: "账号", en: "Accounts" },
                                    { ico: "\uE946", zh: "关于 VAL-DAL", en: "About VAL-DAL" } ]
                                NavItem { required property var modelData; required property int index; ico: modelData.ico; text: bridge.lang === "zh" ? modelData.zh : modelData.en; current: win.settingsSection === index; onClicked: win.settingsSection = index } }
                            Item { Layout.fillHeight: true } } }

                    StackLayout { Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: win.settingsSection
                        // 0 pipeline & models
                        ScrollView { id: svA; contentWidth: availableWidth
                            ColumnLayout { width: Math.min(900, svA.availableWidth - 56); x: Math.max(28, (svA.availableWidth - width) / 2); spacing: 12
                                Item { height: 12 }
                                H1 { text: t("管线与模型", "Pipeline & models") }
                                Card { Layout.fillWidth: true
                                    ColumnLayout { anchors.fill: parent; spacing: 10
                                        RowLayout { Layout.fillWidth: true; spacing: 10
                                            Rectangle { width: 10; height: 10; radius: 5; color: win.sigColor(win.sigPipeline()) }
                                            H2 { text: t("Valhalla 管线", "Valhalla pipeline") }
                                            Button { highlighted: true; enabled: !bridge.pipelineBusy; onClicked: bridge.repairPipeline()
                                                contentItem: RowLayout { spacing: 6; Ico { text: "\uE90F"; font.pixelSize: 13; color: win.accentFg } Text { text: bridge.pipelineBusy ? t("处理中…", "Working…") : t("修复 / 初始化", "Repair / initialize"); color: win.accentFg; font.pixelSize: 12 } } } }
                                        Body { text: bridge.pipelineReport; visible: text !== ""; font.pixelSize: 11 } } }
                                RowLayout { Layout.fillWidth: true; Layout.topMargin: 6
                                    H2 { text: t("模型目录", "Model catalog") }
                                    Note { text: bridge.catalogStatus; horizontalAlignment: Text.AlignRight }
                                    IconBtn { ico: "\uE895"; tip: t("更新模型列表", "Update model list"); onClicked: bridge.updateModelCatalog() } }
                                Repeater { model: bridge.models
                                    Card { required property var modelData; required property int index; Layout.fillWidth: true; padding: 12
                                        RowLayout { anchors.fill: parent; spacing: 12
                                            Rectangle { width: 36; height: 36; radius: 8; color: modelData.current ? win.accent : win.cardAlt
                                                Text { anchors.centerIn: parent; text: (modelData.family || "?").substring(0, 2); font.pixelSize: 12; font.weight: Font.Bold; color: modelData.current ? win.accentFg : win.fg } }
                                            ColumnLayout { Layout.fillWidth: true; spacing: 1
                                                Text { text: modelData.label + (modelData.current ? ("  ·  " + t("当前", "Current")) : ""); font.pixelSize: 13; font.weight: Font.DemiBold; color: win.fg; wrapMode: Text.Wrap; Layout.fillWidth: true }
                                                Note { text: modelData.note + " · " + modelData.size } }
                                            Button { text: modelData.current ? t("使用中", "In use") : (modelData.installed ? t("使用", "Use") : t("下载", "Download")); enabled: !bridge.busy && !modelData.current; flat: modelData.installed; onClicked: bridge.useOrDownloadModel(index) } } } }
                                Item { height: 20 }
                            } }
                        // 1 online model
                        ScrollView { id: svB; contentWidth: availableWidth
                            ColumnLayout { width: Math.min(900, svB.availableWidth - 56); x: Math.max(28, (svB.availableWidth - width) / 2); spacing: 12
                                Item { height: 12 }
                                RowLayout { Layout.fillWidth: true
                                    H1 { text: t("在线大模型", "Online model") }
                                    Button { onClicked: buyInfoDlg.open()
                                        contentItem: RowLayout { spacing: 6; Ico { text: "\uE946"; font.pixelSize: 13 } Text { text: t("说明", "About"); color: win.fg; font.pixelSize: 12 } } } }
                                Body { text: store.plan === "" ? t("当前未开通在线版，本地版可离线使用。", "Online edition not active; the local edition works offline.") : (t("已开通：", "Active: ") + win.cdkPlanName(store.plan)) }
                                GridLayout { columns: svB.availableWidth > 900 ? 3 : 1; columnSpacing: 12; rowSpacing: 12; Layout.fillWidth: true
                                    Repeater { model: [{n:"Pro", zh:"个人版", en:"Personal", pz:"A测价 ¥29/月", pe:"Alpha ¥29/mo", oz:"原价 ¥79/月", oe:"was ¥79/mo", fit:0.5, fzh:"个人学习 / 轻任务", fen:"Personal study / light tasks"}, {n:"Max", zh:"专业版", en:"Professional", pz:"A测价 ¥79/月", pe:"Alpha ¥79/mo", oz:"原价 ¥199/月", oe:"was ¥199/mo", fit:0.8, fzh:"长回答 / 高并发", fen:"Long answers / high concurrency"}, {n:"ENT", zh:"企业定制版", en:"Enterprise", pz:"联系开通", pe:"Contact us", oz:"私有部署可选", oe:"Private deployment available", fit:1.0, fzh:"私有部署 / 团队定制", fen:"Private deployment / team customization"}]
                                        Card { required property var modelData; Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 100
                                            background: Rectangle { radius: 8; color: win.card; border.color: store.plan === modelData.n ? win.accent : win.stroke; border.width: store.plan === modelData.n ? 2 : 1 }
                                            ColumnLayout { anchors.fill: parent; spacing: 6
                                                Text { text: modelData.n; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1; color: win.accent }
                                                H2 { text: bridge.lang === "zh" ? modelData.zh : modelData.en }
                                                Text { text: bridge.lang === "zh" ? modelData.pz : modelData.pe; font.pixelSize: 18; font.weight: Font.DemiBold; color: win.fg }
                                                Note { text: bridge.lang === "zh" ? modelData.oz : modelData.oe; font.strikeout: modelData.n !== "ENT" }
                                                RowLayout { Layout.fillWidth: true; Text { text: t("适配度", "Fit"); font.pixelSize: 10; color: win.muted } ProgressBar { value: modelData.fit; Layout.fillWidth: true } }
                                                Note { text: bridge.lang === "zh" ? modelData.fzh : modelData.fen } } } } }
                                Note { text: t("适配度表示适用场景，不是性能百分比。", "Fit shows suitable scenarios, not performance.") }
                                Card { Layout.fillWidth: true
                                    ColumnLayout { anchors.fill: parent; spacing: 8
                                        H2 { text: t("兑换 CDK", "Redeem CDK") }
                                        RowLayout { Layout.fillWidth: true
                                            TextField { id: cdkField; Layout.fillWidth: true; placeholderText: "VALDAL-PRO-XXXXXX-XXXXXX-X" }
                                            Button { text: t("兑换", "Redeem"); highlighted: true; onClicked: win.redeemCdk(cdkField.text) } }
                                        Text { text: win.cdkMsg; visible: text !== ""; font.pixelSize: 11; color: win.cdkMsg.indexOf("成功") >= 0 || win.cdkMsg.indexOf("Redeemed") === 0 ? "#13a10e" : "#d13438"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                                        Note { text: t("购买：joulyman@gmail.com · +1 316 872 5748（A测期人工开通）", "Buy: joulyman@gmail.com · +1 316 872 5748 (manual activation during alpha)") } } }
                                Item { height: 20 }
                            } }
                        // 2 knowledge
                        Item { id: kbPage
                        ColumnLayout { spacing: 12; width: Math.min(900, kbPage.width - 56); x: Math.max(28, (kbPage.width - width) / 2); height: kbPage.height
                            Item { height: 12 }
                            H1 { text: t("知识库", "Knowledge") }
                            Note { text: bridge.knowledgeStats }
                            Card { Layout.fillWidth: true; Layout.fillHeight: true; padding: 4
                                TextArea { id: kbEdit; anchors.fill: parent; text: bridge.knowledgeText; wrapMode: TextArea.Wrap; placeholderText: t("在此写入语料…", "Write corpus notes here…"); background: Item {} } }
                            RowLayout { Layout.fillWidth: true; Layout.bottomMargin: 20
                                TextField { id: kbDomain; placeholderText: t("行业/领域（导入用）", "Domain (for import)"); Layout.preferredWidth: 220 }
                                Button { onClicked: kbDlg.open(); contentItem: RowLayout { spacing: 6; Ico { text: "\uE8B5"; font.pixelSize: 13 } Text { text: t("导入文件", "Import files"); color: win.fg; font.pixelSize: 12 } } }
                                Item { Layout.fillWidth: true }
                                Button { highlighted: true; onClicked: bridge.saveKnowledge(kbEdit.text); contentItem: RowLayout { spacing: 6; Ico { text: "\uE74E"; font.pixelSize: 13; color: win.accentFg } Text { text: t("保存", "Save"); color: win.accentFg; font.pixelSize: 12 } } } }
                        } }
                        // 3 appearance & language
                        Item { id: apPage
                        ColumnLayout { spacing: 12; width: Math.min(900, apPage.width - 56); x: Math.max(28, (apPage.width - width) / 2); height: apPage.height
                            Item { height: 12 }
                            H1 { text: t("外观与语言", "Appearance & language") }
                            Card { Layout.fillWidth: true
                                ColumnLayout { anchors.fill: parent; spacing: 12
                                    RowLayout { Layout.fillWidth: true; Ico { text: "\uE790"; color: win.accent } Body { text: t("深色主题", "Dark theme") } Switch { checked: win.dark; onToggled: win.dark = checked } }
                                    Rectangle { Layout.fillWidth: true; height: 1; color: win.stroke }
                                    RowLayout { Layout.fillWidth: true; Ico { text: "\uE774"; color: win.accent } Body { text: t("语言", "Language") }
                                        ComboBox { model: [t("跟随系统", "System"), "中文", "English"]; currentIndex: bridge.languageIndex; onActivated: function(i){ bridge.setLanguage(i) } } } } }
                            Item { Layout.fillHeight: true }
                        } }
                        // 4 accounts
                        ScrollView { id: svC; contentWidth: availableWidth
                            ColumnLayout { width: Math.min(900, svC.availableWidth - 56); x: Math.max(28, (svC.availableWidth - width) / 2); spacing: 12
                                Item { height: 12 }
                                H1 { text: t("账号", "Accounts") }
                                Card { Layout.fillWidth: true
                                    ColumnLayout { anchors.fill: parent; spacing: 8
                                        RowLayout { Layout.fillWidth: true
                                            Ico { text: "\uE72E"; color: win.accent }
                                            Body { text: t("本地账号管理（企业版）", "Local account management (Enterprise)") }
                                            Switch { checked: bridge.accountsEnabled; onToggled: bridge.setAccountsEnabled(checked) } }
                                        Note { text: ((bridge.enterpriseActive || store.plan === "ENT") ? t("企业版已激活 · 不限人数", "Enterprise active · unlimited") : t("未激活 · 上限 3 人", "Inactive · max 3 accounts")) + "  ·  " + t("当前：", "Current: ") + bridge.currentUser + " (" + bridge.accountRole + ")" } } }
                                Repeater { model: bridge.accounts
                                    Card { required property var modelData; Layout.fillWidth: true; padding: 10
                                        RowLayout { anchors.fill: parent; spacing: 10
                                            Rectangle { width: 30; height: 30; radius: 15; color: win.cardAlt; Text { anchors.centerIn: parent; text: modelData.name.substring(0, 1).toUpperCase(); color: win.fg; font.pixelSize: 12; font.weight: Font.DemiBold } }
                                            Text { text: modelData.name + "  ·  " + modelData.role; font.pixelSize: 12; color: win.fg; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                            Switch { checked: modelData.enabled; onToggled: bridge.setAccountEnabled(modelData.name, checked); ToolTip.visible: hovered; ToolTip.text: t("启用/停用", "Enable/disable") }
                                            IconBtn { ico: "\uE8D7"; tip: t("重置密码", "Reset password"); onClicked: { resetDlg.user = modelData.name; resetDlg.open() } }
                                            IconBtn { ico: "\uE74D"; tip: t("删除账号", "Delete account"); onClicked: bridge.removeAccount(modelData.name) } } } }
                                Card { Layout.fillWidth: true
                                    ColumnLayout { anchors.fill: parent; spacing: 8
                                        H2 { text: t("添加账号", "Add account") }
                                        RowLayout { Layout.fillWidth: true
                                            TextField { id: accName; placeholderText: t("账号名", "Account name"); Layout.fillWidth: true }
                                            TextField { id: accPass; placeholderText: t("密码", "Password"); echoMode: TextInput.Password; Layout.fillWidth: true }
                                            ComboBox { id: accRole; model: ["member", "admin"]; Layout.preferredWidth: 110 }
                                            IconBtn { ico: "\uE8FA"; tip: t("添加账号（需管理员）", "Add account (admin only)"); enabled: bridge.accountRole === "admin"; onClicked: if (accName.text.trim() !== "") { bridge.addAccount(accName.text, accPass.text, accRole.currentText); accPass.clear() } } }
                                        Rectangle { Layout.fillWidth: true; height: 1; color: win.stroke }
                                        H2 { text: t("登录", "Sign in") }
                                        RowLayout { Layout.fillWidth: true
                                            TextField { id: loginName; placeholderText: t("登录名", "Login name"); Layout.fillWidth: true }
                                            TextField { id: loginPass; placeholderText: t("密码", "Password"); echoMode: TextInput.Password; Layout.fillWidth: true }
                                            Button { text: t("登录", "Sign in"); highlighted: true; onClicked: bridge.login(loginName.text, loginPass.text) }
                                            IconBtn { ico: "\uE7E8"; tip: t("退出登录", "Sign out"); onClicked: bridge.logout() } }
                                        Text { text: bridge.accountMsg; visible: text !== ""; font.pixelSize: 11; color: "#13a10e"; wrapMode: Text.Wrap; Layout.fillWidth: true } } }
                                Item { height: 20 }
                            } }
                        // 5 about
                        ScrollView { id: svD; contentWidth: availableWidth
                            ColumnLayout { width: Math.min(980, svD.availableWidth - 56); x: Math.max(28, (svD.availableWidth - width) / 2); spacing: 14
                                Item { height: 12 }
                                // hero
                                Card { Layout.fillWidth: true; padding: 22
                                    RowLayout { anchors.fill: parent; spacing: 18
                                        Image { source: win.logo; Layout.preferredWidth: 64; Layout.preferredHeight: 64; fillMode: Image.PreserveAspectFit }
                                        ColumnLayout { spacing: 4; Layout.fillWidth: true
                                            Text { text: "瓦序 VAL-DAL"; font.pixelSize: 24; font.weight: Font.Bold; color: win.fg }
                                            Body { text: t("运行在你电脑上的智能体：先检索可核查的依据，再生成回答；需要时联网查找、识别屏幕、操作电脑。", "An agent that runs on your PC: it retrieves checkable evidence before answering, and can search the web, read the screen and operate the computer when needed.") }
                                            Note { text: t("A 测版 · Rogue Intelligence Inc.（美国特拉华州）", "Alpha · Rogue Intelligence Inc. (Delaware, USA)") } } } }

                                // pipeline diagram
                                H2 { text: t("Valhalla 管线", "Valhalla pipeline"); Layout.topMargin: 4 }
                                Card { Layout.fillWidth: true
                                    ColumnLayout { anchors.fill: parent; spacing: 12
                                        RowLayout { Layout.fillWidth: true; spacing: 0
                                            Repeater { model: [
                                                    { ico: "\uE8F2", zh: "理解问题", en: "Understand", dz: "解析意图与上下文", de: "Intent & context" },
                                                    { ico: "\uE721", zh: "结构检索", en: "Retrieve", dz: "从本地知识取依据", de: "Evidence from local knowledge" },
                                                    { ico: "\uE8AB", zh: "Fate 路由", en: "Fate routing", dz: "选择解码路径", de: "Picks the decode path" },
                                                    { ico: "\uE950", zh: "可换解码头", en: "Decode head", dz: "按模型更换", de: "Swappable per model" },
                                                    { ico: "\uE945", zh: "会话热驻留", en: "Warm session", dz: "多轮不重复加载", de: "No reload between turns" } ]
                                                RowLayout { required property var modelData; required property int index; spacing: 0; Layout.fillWidth: true
                                                    ColumnLayout { spacing: 4; Layout.fillWidth: true
                                                        Rectangle { Layout.alignment: Qt.AlignHCenter; width: 44; height: 44; radius: 22; color: index === 1 || index === 2 ? win.accent : win.cardAlt
                                                            Ico { anchors.centerIn: parent; text: modelData.ico; font.pixelSize: 18; color: index === 1 || index === 2 ? win.accentFg : win.fg } }
                                                        Text { Layout.alignment: Qt.AlignHCenter; text: bridge.lang === "zh" ? modelData.zh : modelData.en; font.pixelSize: 12; font.weight: Font.DemiBold; color: win.fg }
                                                        Text { Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: bridge.lang === "zh" ? modelData.dz : modelData.de; font.pixelSize: 10; color: win.muted; wrapMode: Text.Wrap } }
                                                    Ico { visible: index < 4; text: "\uE76C"; font.pixelSize: 12; color: win.muted; Layout.alignment: Qt.AlignTop; Layout.topMargin: 14 } } } }
                                        Body { text: t("回答之前先找依据，依据和来源可以核查；解码头可按模型更换，不绑定某一家模型；会话热驻留让多轮对话不必反复加载权重。本地版永久免费，数据不出本机。", "Evidence is found before answering, and sources can be checked. Decode heads are swappable, so no single model vendor is required. Warm sessions avoid reloading weights between turns. The local edition is free forever and data stays on this PC.") } } }

                                // features
                                H2 { text: t("核心特性", "Key features"); Layout.topMargin: 4 }
                                GridLayout { columns: svD.availableWidth > 900 ? 3 : 2; columnSpacing: 12; rowSpacing: 12; Layout.fillWidth: true
                                    Repeater { model: [
                                            { ico: "\uE709", zh: "离线可用", en: "Works offline", dz: "本地模型，断网也能用", de: "Local model, no network needed" },
                                            { ico: "\uE72E", zh: "数据不出本机", en: "Data stays local", dz: "知识库与对话保存在本机", de: "Knowledge and chats stay on this PC" },
                                            { ico: "\uE721", zh: "可核查依据", en: "Checkable evidence", dz: "结构检索先于生成", de: "Retrieval runs before generation" },
                                            { ico: "\uE774", zh: "联网查找", en: "Web search", dz: "需要时检索最新来源", de: "Fresh sources on demand" },
                                            { ico: "\uE7F4", zh: "屏幕识别与 OCR", en: "Screen & OCR", dz: "读懂屏幕和图片文字", de: "Reads screens and images" },
                                            { ico: "\uE7C9", zh: "电脑控制", en: "Computer control", dz: "确认后执行操作", de: "Runs actions after confirmation" },
                                            { ico: "\uE9D5", zh: "任务模式", en: "Task mode", dz: "直接完成并汇报结果", de: "Does the task and reports" },
                                            { ico: "\uE8B7", zh: "工作区与项目", en: "Workspaces & projects", dz: "按项目整理对话", de: "Organize chats by project" },
                                            { ico: "\uE716", zh: "企业本地账号", en: "Enterprise accounts", dz: "本地多账号与权限", de: "Local multi-user with roles" } ]
                                        Card { required property var modelData; Layout.fillWidth: true; padding: 14
                                            RowLayout { anchors.fill: parent; spacing: 12
                                                Rectangle { width: 36; height: 36; radius: 8; color: win.cardAlt; Ico { anchors.centerIn: parent; text: modelData.ico; color: win.accent } }
                                                ColumnLayout { spacing: 1; Layout.fillWidth: true
                                                    Text { text: bridge.lang === "zh" ? modelData.zh : modelData.en; font.pixelSize: 13; font.weight: Font.DemiBold; color: win.fg }
                                                    Note { text: bridge.lang === "zh" ? modelData.dz : modelData.de } } } } } }

                                // comparison
                                H2 { text: t("与同类产品对比", "Compared with similar products"); Layout.topMargin: 4 }
                                Card { id: cmpCard; Layout.fillWidth: true; padding: 0
                                    property var cols: [t("VAL-DAL", "VAL-DAL"), t("云端聊天助手", "Cloud chat assistants"), t("本地模型运行器", "Local model runners")]
                                    property var rows: [
                                        { zh: "离线可用", en: "Works offline", v: [2, 0, 2] },
                                        { zh: "数据不出本机", en: "Data stays on device", v: [2, 0, 2] },
                                        { zh: "回答前结构检索 · 依据可核查", en: "Structured retrieval · checkable evidence", v: [2, 1, 1] },
                                        { zh: "联网查找", en: "Web search", v: [2, 2, 1] },
                                        { zh: "屏幕识别与 OCR", en: "Screen recognition & OCR", v: [2, 1, 0] },
                                        { zh: "电脑控制", en: "Computer control", v: [2, 1, 0] },
                                        { zh: "模型可更换", en: "Swappable models", v: [2, 0, 2] },
                                        { zh: "工作区与项目", en: "Workspaces & projects", v: [2, 1, 0] },
                                        { zh: "企业本地账号", en: "Local enterprise accounts", v: [2, 1, 0] },
                                        { zh: "本地版免费", en: "Free local edition", v: [2, 1, 2] } ]
                                    function score(c) { var s = 0; for (var i = 0; i < rows.length; i++) s += rows[i].v[c]; return s / (rows.length * 2) }
                                    ColumnLayout { anchors.fill: parent; spacing: 0
                                        RowLayout { Layout.fillWidth: true; Layout.margins: 14; spacing: 0
                                            Text { text: t("功能", "Capability"); font.pixelSize: 11; font.weight: Font.DemiBold; color: win.muted; Layout.fillWidth: true; Layout.preferredWidth: 3 }
                                            Repeater { model: cmpCard.cols
                                                Text { required property string modelData; required property int index; text: modelData; font.pixelSize: 11; font.weight: Font.DemiBold; color: index === 0 ? win.accent : win.muted; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true; Layout.preferredWidth: 2; wrapMode: Text.Wrap } } }
                                        Repeater { model: cmpCard.rows
                                            Rectangle { required property var modelData; required property int index; Layout.fillWidth: true; implicitHeight: 36; color: index % 2 === 0 ? win.cardAlt : "transparent"
                                                RowLayout { anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 0
                                                    Text { text: bridge.lang === "zh" ? modelData.zh : modelData.en; font.pixelSize: 12; color: win.fg; Layout.fillWidth: true; Layout.preferredWidth: 3; elide: Text.ElideRight }
                                                    Repeater { model: modelData.v
                                                        Ico { required property int modelData; text: modelData === 2 ? "\uE73E" : modelData === 1 ? "\uE738" : "\uE711"; font.pixelSize: modelData === 2 ? 14 : 11; color: modelData === 2 ? "#13a10e" : modelData === 1 ? "#d5a000" : win.muted; Layout.fillWidth: true; Layout.preferredWidth: 2 } } } } }
                                        // coverage chart derived from the table above
                                        ColumnLayout { Layout.fillWidth: true; Layout.margins: 14; spacing: 8
                                            Text { text: t("功能覆盖（按上表统计）", "Coverage (from the table above)"); font.pixelSize: 11; font.weight: Font.DemiBold; color: win.muted }
                                            Repeater { model: cmpCard.cols
                                                RowLayout { required property string modelData; required property int index; Layout.fillWidth: true; spacing: 10
                                                    Text { text: modelData; font.pixelSize: 11; color: win.fg; Layout.preferredWidth: 130; elide: Text.ElideRight }
                                                    Rectangle { Layout.fillWidth: true; height: 10; radius: 5; color: win.cardAlt
                                                        Rectangle { width: parent.width * cmpCard.score(index); height: parent.height; radius: 5; color: index === 0 ? win.accent : win.muted } }
                                                    Text { text: Math.round(cmpCard.score(index) * 100) + "%"; font.pixelSize: 11; color: win.fg; Layout.preferredWidth: 36; horizontalAlignment: Text.AlignRight } } }
                                            Note { text: t("✓ 支持  — 部分或视产品而定  ✕ 通常不支持。对比依据同类产品的典型形态，不针对具体品牌。", "✓ supported  — partial / varies  ✕ usually not. Based on typical product categories, not specific brands."); font.pixelSize: 10 } } } }
                                Note { text: t("联系：joulyman@gmail.com · +1 316 872 5748", "Contact: joulyman@gmail.com · +1 316 872 5748"); Layout.bottomMargin: 24 }
                            } }
                    }
                }
            }
        }
    }

    Dialog { id: ctlDlg; title: t("启用电脑控制？", "Enable computer control?"); modal: true; anchors.centerIn: parent; standardButtons: Dialog.Ok | Dialog.Cancel
        Text { text: t("开启后，回答中的控制动作会在本机执行。请确认你信任当前知识与提问内容。", "Control actions in answers will run on this PC. Confirm you trust the current knowledge and prompts."); wrapMode: Text.Wrap; width: 360; color: win.fg2 }
        onAccepted: bridge.setAllowControl(true); onRejected: { ctlBtn.checked = false; bridge.setAllowControl(false) } }
    Dialog { id: resetDlg; property string user: ""; title: t("重置密码", "Reset password"); modal: true; anchors.centerIn: parent; standardButtons: Dialog.Ok | Dialog.Cancel
        TextField { id: resetPass; placeholderText: t("新密码", "New password"); echoMode: TextInput.Password; width: 260 }
        onAccepted: if (resetPass.text !== "") bridge.resetAccountPassword(user, resetPass.text) }
    Dialog { id: loginDlg; title: t("本地账号登录", "Local account login"); modal: true; anchors.centerIn: parent; closePolicy: Popup.CloseOnEscape
        ColumnLayout { spacing: 8; width: 300
            TextField { id: gateName; placeholderText: t("登录名", "Login name"); Layout.fillWidth: true }
            TextField { id: gatePass; placeholderText: t("密码", "Password"); echoMode: TextInput.Password; Layout.fillWidth: true }
            Button { text: t("登录", "Sign in"); highlighted: true; Layout.fillWidth: true; onClicked: if (bridge.login(gateName.text, gatePass.text)) loginDlg.close() }
            Text { text: bridge.accountMsg; font.pixelSize: 11; color: "#d13438"; wrapMode: Text.Wrap; Layout.fillWidth: true } } }
    Dialog { id: buyInfoDlg; title: t("在线版说明", "About the online edition"); modal: true; anchors.centerIn: parent; standardButtons: Dialog.Close
        ColumnLayout { spacing: 10; width: 440
            Repeater { model: [
                    { ico: "\uE945", zh: "先走 Valhalla 管线结构检索，再交给云端模型", en: "Valhalla structured retrieval first, then the cloud model" },
                    { ico: "\uE709", zh: "本地版永久免费，在线版按需开通", en: "Local edition free forever; online on demand" },
                    { ico: "\uE945", zh: "快速推流，长回答更稳", en: "Fast streaming, steadier long answers" },
                    { ico: "\uE72E", zh: "A测期购买按现价锁定", en: "Alpha buyers keep the current price" } ]
                RowLayout { required property var modelData; spacing: 10; Layout.fillWidth: true
                    Ico { text: modelData.ico; color: win.accent; font.pixelSize: 14 }
                    Body { text: bridge.lang === "zh" ? modelData.zh : modelData.en } } }
            Rectangle { Layout.fillWidth: true; height: 1; color: win.stroke }
            Body { text: t("购买流程：联系我们 → 付款 → 收到 CDK → 在「在线大模型」兑换。", "How to buy: contact us → pay → receive CDK → redeem under Online model.") }
            Text { text: "+1 316 872 5748 · joulyman@gmail.com"; font.pixelSize: 12; font.weight: Font.DemiBold; color: win.fg } } }
    FileDialog { id: ocrDlg; title: t("选择图片做 OCR", "Choose images for OCR"); fileMode: FileDialog.OpenFiles; nameFilters: ["Images (*.png *.jpg *.jpeg *.bmp *.webp)"]; onAccepted: bridge.ocrImport(selectedFiles) }
    FileDialog { id: kbDlg; title: t("导入知识文件", "Import knowledge files"); fileMode: FileDialog.OpenFiles; onAccepted: bridge.importFiles(kbDomain.text, selectedFiles) }
    FileDialog { id: exportDlg; title: t("导出对话", "Export chat"); fileMode: FileDialog.SaveFile; defaultSuffix: "md"; nameFilters: ["Markdown (*.md)"]; onAccepted: bridge.exportChat(selectedFile) }
}
