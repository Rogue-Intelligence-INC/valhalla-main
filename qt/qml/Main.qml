import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtCore

// VAL-DAL main edition — FluentWinUI3 (Qt Quick Controls native Win11 style).
// One settings entry (navigation pane footer), fixed Valhalla mode (no
// strategy/mode selector anywhere), one status-signal group (inspector).
ApplicationWindow {
    id: win
    width: 1360; height: 860; minimumWidth: 1020; minimumHeight: 640
    visible: true
    title: "VAL-DAL"
    color: dark ? "#202020" : "#f9f9f9"

    property bool dark: true
    property int page: 0            // 0 chat, 1 workspace, 2 settings
    property int settingsSection: 0 // fixed order: pipeline, online, knowledge, appearance, account/about
    property bool inspectorOpen: true
    property bool buyInfoOpen: false
    property string cdkMsg: ""
    property string grabName: "grab.png"

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
    // Status-signal mapping (single group, inspector only): 0 red, 1 yellow, 2 green
    function sigPipeline() { return bridge.pipelineBusy ? 1 : (bridge.enginePresent && bridge.modelInstalled ? 2 : (bridge.enginePresent ? 1 : 0)) }
    function sigModel() { return bridge.modelLoaded ? 2 : (bridge.modelInstalled ? 1 : 0) }
    function sigLink() { return !bridge.enginePresent ? 0 : (store.plan !== "" ? 2 : 1) }
    function sigColor(s) { return s === 2 ? "#0f7b0f" : s === 1 ? "#c19c00" : "#c42b1c" }
    function stageState(i) { // vertical timeline from busy/lastPath only
        if (bridge.busy) return i === 0 ? 1 : 0
        if (bridge.turnCount === 0) return 0
        var p = (bridge.lastPath || "").toLowerCase()
        if (i === 0) return 2
        if (i === 1) return (p.indexOf("retriev") >= 0 || p.indexOf("phrase") >= 0 || p.indexOf("native") >= 0 || p.indexOf("mcq") >= 0 || p.indexOf("logprob") >= 0) ? 2 : 1
        if (i === 2) return 2
        return 2
    }

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
        // Hidden verification hooks (no UI): --light, --page=N, --section=N, --buyinfo
        var args = Qt.application.arguments
        for (var i = 0; i < args.length; i++) {
            if (args[i] === "--light") win.dark = false
            else if (args[i] === "--dark") win.dark = true
            else if (args[i].indexOf("--page=") === 0) win.page = parseInt(args[i].substring(7))
            else if (args[i].indexOf("--section=") === 0) win.settingsSection = parseInt(args[i].substring(10))
            else if (args[i].indexOf("--grabname=") === 0) win.grabName = args[i].substring(11)
            else if (args[i] === "--buyinfo") { win.page = 2; win.settingsSection = 1; buyInfoDlg.open() }
        }
        applyTheme(); if (bridge.accountsEnabled) loginDlg.open()
    }
    onDarkChanged: { store.darkTheme = win.dark; applyTheme() }

    component NavItem: Button {
        property string glyph: ""; property bool current: false
        Layout.fillWidth: true; flat: !current; highlighted: current
        contentItem: RowLayout { spacing: 10
            Text { text: glyph; font.pixelSize: 16 }
            Text { text: parent.parent.text; color: win.dark ? "#ffffff" : "#1b1b1b"; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
        }
    }
    component SigRow: ColumnLayout {
        property string name: ""; property int state: 0; property string detail: ""
        spacing: 2; Layout.fillWidth: true
        RowLayout { spacing: 8
            Rectangle { width: 10; height: 10; radius: 5; color: win.sigColor(state) }
            Text { text: name; font.pixelSize: 12; font.weight: Font.DemiBold; color: win.dark ? "#fff" : "#1b1b1b" } }
        Text { text: detail; font.pixelSize: 11; color: win.dark ? "#c8c8c8" : "#5d5d5d"; Layout.fillWidth: true; Layout.leftMargin: 18; wrapMode: Text.Wrap }
    }

    Timer { id: grabTimer; interval: 2500; onTriggered: rootRow.grabToImage(function(r){ r.saveToFile("C:/Ai/rogue-products/valhalla-windows/qt/shots/" + win.grabName); console.log("GRABBED") }, Qt.size(1360, 860)) }

    RowLayout { id: rootRow
        anchors.fill: parent; spacing: 0

        // ===== Navigation pane (NavigationView-style, Fluent controls) =====
        Pane {
            Layout.preferredWidth: 248; Layout.fillHeight: true; padding: 10
            ColumnLayout {
                anchors.fill: parent; spacing: 4
                RowLayout { Layout.fillWidth: true; spacing: 8
                    Image { source: win.dark ? "qrc:/qt/qml/Valhalla/logo-white.png" : "qrc:/qt/qml/Valhalla/logo-black.png"; Layout.preferredWidth: 28; Layout.preferredHeight: 28; fillMode: Image.PreserveAspectFit }
                    ColumnLayout { spacing: 0; Layout.fillWidth: true
                        Text { text: "VAL-DAL"; font.pixelSize: 14; font.weight: Font.DemiBold; color: win.dark ? "#fff" : "#1b1b1b" }
                        Text { text: t("Valhalla 模式", "Valhalla mode"); font.pixelSize: 10; color: win.dark ? "#c8c8c8" : "#5d5d5d" }
                    }
                }
                MenuSeparator { Layout.fillWidth: true }
                NavItem { glyph: "💬"; text: t("对话", "Chat"); current: win.page === 0; onClicked: win.page = 0 }
                NavItem { glyph: "🗂"; text: t("工作区", "Workspace"); current: win.page === 1; onClicked: win.page = 1 }
                NavItem { glyph: "📚"; text: t("知识库", "Knowledge"); current: win.page === 2 && win.settingsSection === 2; onClicked: win.goSettings(2) }
                Item { Layout.fillHeight: true }
                // compact status signal (same mapping as inspector group)
                RowLayout { Layout.fillWidth: true; spacing: 5
                    Repeater { model: [win.sigPipeline(), win.sigModel(), win.sigLink()]
                        Rectangle { required property int modelData; width: 8; height: 8; radius: 4; color: win.sigColor(modelData) } }
                    Text { text: bridge.busy ? t("忙", "Busy") : t("状态", "Status"); font.pixelSize: 10; color: win.dark ? "#c8c8c8" : "#5d5d5d"; Layout.fillWidth: true }
                }
                RowLayout { Layout.fillWidth: true; spacing: 8
                    Text { text: "👤"; font.pixelSize: 15 }
                    Text { text: bridge.currentUser + " · " + bridge.accountRole; font.pixelSize: 11; color: win.dark ? "#e8e8e8" : "#333"; Layout.fillWidth: true; elide: Text.ElideRight; wrapMode: Text.Wrap }
                }
                NavItem { glyph: "⚙"; text: t("设置", "Settings"); current: win.page === 2; onClicked: win.goSettings(win.settingsSection) }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0

            // ===== Top bar: breadcrumb + theme + local/online badge (no second settings entry) =====
            Pane { Layout.fillWidth: true; padding: 8
                RowLayout { anchors.fill: parent; spacing: 8
                    Text { text: (win.page === 2 ? t("设置", "Settings") : win.page === 1 ? t("工作区", "Workspace") : (bridge.currentWorkspace + " / " + bridge.currentProject + " / " + bridge.chatTitle)); font.pixelSize: 12; color: win.dark ? "#e8e8e8" : "#333"; Layout.maximumWidth: 520; elide: Text.ElideRight; wrapMode: Text.Wrap }
                    Item { Layout.fillWidth: true }
                    Text { text: store.plan !== "" ? t("在线", "Online") : t("本地", "Local"); font.pixelSize: 11; font.weight: Font.DemiBold; color: store.plan !== "" ? "#0f7b0f" : (win.dark ? "#c8c8c8" : "#5d5d5d"); wrapMode: Text.Wrap }
                    ToolButton { text: win.dark ? "☀" : "☾"; ToolTip.visible: hovered; ToolTip.text: t("切换浅色/深色主题", "Toggle light/dark theme"); onClicked: win.dark = !win.dark }
                    ToolButton { text: "▤"; visible: win.page === 0; ToolTip.visible: hovered; ToolTip.text: t("状态面板", "Status panel"); onClicked: win.inspectorOpen = !win.inspectorOpen }
                }
            }

            StackLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: win.page

                // ===== Chat page =====
                RowLayout { spacing: 0
                    ColumnLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: 6
                        // environment banner (existing bridge capability)
                        Frame { Layout.fillWidth: true; visible: !bridge.envReady && !bridge.envDismissed; padding: 8
                            RowLayout { anchors.fill: parent
                                Text { text: t("运行环境未就绪：", "Runtime not ready: ") + bridge.envReport; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true; color: win.dark ? "#e8e8e8" : "#333" }
                                Button { text: t("一键配置", "Set up"); onClicked: bridge.setupEnvironment() }
                                Button { text: t("关闭", "Dismiss"); flat: true; onClicked: bridge.dismissEnvSetup() }
                            }
                        }
                        ListView {
                            id: msgList; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 10
                            model: bridge.messages
                            delegate: Frame {
                                required property var modelData; required property int index
                                width: Math.min(760, msgList.width - 48); x: (msgList.width - width) / 2; padding: 10
                                ColumnLayout { anchors.fill: parent; spacing: 4
                                    Text { text: modelData.user ? bridge.currentUser : "VAL-DAL"; font.pixelSize: 10; font.weight: Font.DemiBold; color: win.dark ? "#c8c8c8" : "#5d5d5d" }
                                    TextEdit { text: modelData.text; readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; font.pixelSize: 13; color: modelData.error ? "#c42b1c" : (win.dark ? "#fff" : "#1b1b1b"); Layout.fillWidth: true; id: msgText }
                                    RowLayout { visible: !modelData.user; spacing: 4
                                        Text { visible: text !== ""; text: modelData.badge ? (modelData.badge + (bridge.lastElapsed ? " · " + bridge.lastElapsed : "")) : ""; font.pixelSize: 10; color: win.dark ? "#c8c8c8" : "#5d5d5d" }
                                        ToolButton { text: "🔊"; ToolTip.visible: hovered; ToolTip.text: t("朗读", "Read aloud"); onClicked: bridge.speakText(msgText.text) }
                                        ToolButton { text: "✕"; ToolTip.visible: hovered; ToolTip.text: t("停止朗读", "Stop reading"); onClicked: bridge.stopSpeak() }
                                        ToolButton { text: t("译选中", "Translate selection"); visible: msgText.selectedText !== ""; onClicked: bridge.askSelection("translate", msgText.selectedText) }
                                        ToolButton { text: t("释选中", "Explain selection"); visible: msgText.selectedText !== ""; onClicked: bridge.askSelection("explain", msgText.selectedText) }
                                        Button { text: t("重试", "Retry"); visible: modelData.error; enabled: !bridge.busy; onClicked: bridge.retryLast() }
                                    }
                                }
                            }
                            onCountChanged: Qt.callLater(function(){ msgList.positionViewAtEnd() })
                        }
                        Text { visible: bridge.statusText !== ""; text: bridge.statusText; font.pixelSize: 11; color: win.dark ? "#c8c8c8" : "#5d5d5d"; wrapMode: Text.Wrap; Layout.fillWidth: true; leftPadding: 12 }
                        // input card (centered, width-limited)
                        Frame { Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; Layout.maximumWidth: 780; padding: 8
                            ColumnLayout { anchors.fill: parent; spacing: 4
                                TextArea { id: input; Layout.fillWidth: true; Layout.preferredHeight: 64; placeholderText: t("输入消息…（Valhalla 模式）", "Message… (Valhalla mode)"); wrapMode: TextArea.Wrap }
                                RowLayout { Layout.fillWidth: true; spacing: 2
                                    ToolButton { text: "📷"; ToolTip.visible: hovered; ToolTip.text: t("识别屏幕", "Recognize screen"); enabled: !bridge.busy; onClicked: bridge.recognize() }
                                    ToolButton { text: "🖼"; ToolTip.visible: hovered; ToolTip.text: t("OCR 导入图片", "OCR import images"); enabled: !bridge.busy; onClicked: ocrDlg.open() }
                                    Switch { id: ctlSwitch; text: t("电脑控制", "Computer control"); checked: bridge.allowControl; ToolTip.visible: hovered; ToolTip.text: t("允许执行电脑控制动作（需确认）", "Allow computer-control actions (confirmation required)")
                                        onToggled: { if (checked && !bridge.allowControl) ctlDlg.open(); else bridge.setAllowControl(checked) } }
                                    Text { text: bridge.screenMeta; font.pixelSize: 10; color: win.dark ? "#c8c8c8" : "#5d5d5d"; elide: Text.ElideRight; Layout.maximumWidth: 180 }
                                    Item { Layout.fillWidth: true }
                                    Text { text: t("Valhalla 模式", "Valhalla mode"); font.pixelSize: 10; color: win.dark ? "#c8c8c8" : "#5d5d5d" }
                                    Button { text: bridge.busy ? t("生成中…", "Working…") : t("发送", "Send"); highlighted: true; enabled: !bridge.busy && input.text.trim() !== ""; onClicked: { bridge.send(input.text); input.clear() } }
                                }
                            }
                        }
                    }
                    // ===== Inspector: the single status-signal group + vertical timeline =====
                    Pane { visible: win.inspectorOpen; Layout.preferredWidth: 272; Layout.fillHeight: true; padding: 10
                        ColumnLayout { anchors.fill: parent; spacing: 8
                            Text { text: t("状态信号", "Status signals"); font.pixelSize: 13; font.weight: Font.DemiBold; color: win.dark ? "#fff" : "#1b1b1b" }
                            SigRow { name: t("Valhalla 管线", "Valhalla pipeline"); state: win.sigPipeline(); detail: bridge.enginePresent ? t("引擎在 · 五段管线", "Engine present · 5-stage pipeline") : t("引擎不在", "Engine missing") }
                            SigRow { name: t("本地模型", "Local model"); state: win.sigModel(); detail: bridge.currentModelName + " · " + (bridge.modelLoaded ? t("已加载", "Loaded") : t("未加载", "Not loaded")) + " · " + bridge.computeDevice }
                            SigRow { name: t("连接", "Connection"); state: win.sigLink(); detail: (bridge.enginePresent ? t("引擎在", "Engine present") : t("引擎不在", "Engine missing")) + " · " + (store.plan !== "" ? (t("在线 ", "Online ") + win.cdkPlanName(store.plan)) : t("本地（在线未配置）", "Local (online not configured)")) }
                            Text { text: t("图例：● 绿 正常 · 黄 忙/未配置 · 红 异常", "Legend: green OK · yellow busy/unconfigured · red error"); font.pixelSize: 10; color: win.dark ? "#c8c8c8" : "#5d5d5d"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            MenuSeparator { Layout.fillWidth: true }
                            Text { text: t("执行阶段", "Execution stages"); font.pixelSize: 13; font.weight: Font.DemiBold; color: win.dark ? "#fff" : "#1b1b1b" }
                            Repeater { model: [t("理解", "Understand"), t("检索", "Retrieve"), t("组织", "Organize"), t("回答", "Answer")]
                                RowLayout { required property int index; required property string modelData; spacing: 8
                                    Rectangle { width: 10; height: 10; radius: 5; color: win.stageState(index) === 2 ? "#0f7b0f" : win.stageState(index) === 1 ? "#c19c00" : (win.dark ? "#5d5d5d" : "#c8c8c8") }
                                    Text { text: modelData + (win.stageState(index) === 1 && bridge.busy ? " …" : ""); font.pixelSize: 12; color: win.dark ? "#e8e8e8" : "#333" }
                                } }
                            Text { text: bridge.lastBadge ? (t("最近路径：", "Last path: ") + bridge.lastBadge + " · " + bridge.lastElapsed) : t("尚无已完成轮次", "No completed turn yet"); font.pixelSize: 10; color: win.dark ? "#c8c8c8" : "#5d5d5d"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            MenuSeparator { Layout.fillWidth: true }
                            Text { text: bridge.runtimeText; font.pixelSize: 10; color: win.dark ? "#c8c8c8" : "#5d5d5d"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            Button { text: t("检查运行时", "Probe runtime"); enabled: !bridge.busy; onClicked: bridge.probe() }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }

                // ===== Workspace page =====
                Pane { padding: 12
                    ColumnLayout { anchors.fill: parent; spacing: 8
                        Text { text: t("工作区", "Workspaces"); font.pixelSize: 16; font.weight: Font.DemiBold; color: win.dark ? "#fff" : "#1b1b1b" }
                        RowLayout { Layout.fillWidth: true
                            ComboBox { id: wsBox; Layout.fillWidth: true; model: bridge.workspaces; textRole: "name"; currentIndex: { for (var i=0;i<bridge.workspaces.length;i++) if (bridge.workspaces[i].name===bridge.currentWorkspace) return i; return 0 } onActivated: bridge.switchWorkspace(currentText) }
                            TextField { id: wsName; placeholderText: t("新工作区名", "New workspace name"); Layout.preferredWidth: 180 }
                            Button { text: t("新建工作区", "New workspace"); onClicked: if (wsName.text.trim() !== "") { bridge.addWorkspace(wsName.text); wsName.clear() } }
                        }
                        RowLayout { Layout.fillWidth: true
                            ComboBox { id: pjBox; Layout.fillWidth: true; model: bridge.projects; textRole: "name"; currentIndex: { for (var i=0;i<bridge.projects.length;i++) if (bridge.projects[i].name===bridge.currentProject) return i; return 0 } onActivated: bridge.switchProject(currentText) }
                            TextField { id: pjName; placeholderText: t("新项目名", "New project name"); Layout.preferredWidth: 180 }
                            Button { text: t("新建项目", "New project"); onClicked: if (pjName.text.trim() !== "") { bridge.addProject(pjName.text); pjName.clear() } }
                        }
                        RowLayout { Layout.fillWidth: true
                            TextField { Layout.fillWidth: true; placeholderText: t("搜索对话", "Search chats"); onTextChanged: bridge.setSearch(text) }
                            Button { text: t("新建对话", "New chat"); highlighted: true; enabled: !bridge.busy; onClicked: { bridge.newChat(); win.page = 0 } }
                        }
                        ListView { Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 2; model: bridge.conversations
                            section.property: "project"; section.delegate: Text { required property string section; text: section; font.pixelSize: 11; font.weight: Font.DemiBold; color: win.dark ? "#c8c8c8" : "#5d5d5d"; topPadding: 8; bottomPadding: 2 }
                            delegate: ItemDelegate { required property var modelData; width: ListView.view.width; highlighted: modelData.active
                                contentItem: RowLayout { Text { text: modelData.title; font.pixelSize: 12; color: win.dark ? "#fff" : "#1b1b1b"; Layout.fillWidth: true; elide: Text.ElideRight } ToolButton { text: "🗑"; onClicked: bridge.deleteChat(modelData.id) } }
                                onClicked: { bridge.openChat(modelData.id); win.page = 0 } }
                        }
                    }
                }

                // ===== Settings page (single, full-screen; 5 fixed sections) =====
                RowLayout { spacing: 0
                    Pane { Layout.preferredWidth: 210; Layout.fillHeight: true; padding: 8
                        ListView { anchors.fill: parent; clip: true; model: [t("管线与模型", "Pipeline & models"), t("在线大模型", "Online model"), t("知识库", "Knowledge"), t("外观与语言", "Appearance & language"), t("账号与关于", "Account & about")]
                            delegate: ItemDelegate { required property int index; required property string modelData; width: ListView.view.width; text: (index + 1) + "  " + modelData; highlighted: win.settingsSection === index; onClicked: win.settingsSection = index } }
                    }
                    StackLayout { Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: win.settingsSection
                        // 1 pipeline & models
                        ScrollView { id: svA
                            ColumnLayout { width: svA.availableWidth - 16; spacing: 8
                                Text { text: t("管线与模型", "Pipeline & models"); font.pixelSize: 16; font.weight: Font.DemiBold; color: win.dark ? "#fff" : "#1b1b1b" }
                                Button { text: bridge.pipelineBusy ? t("处理中…", "Working…") : t("修复 / 初始化管线", "Repair / initialize pipeline"); highlighted: true; enabled: !bridge.pipelineBusy; onClicked: bridge.repairPipeline() }
                                Text { text: bridge.pipelineReport; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true; color: win.dark ? "#e8e8e8" : "#333" }
                                RowLayout { Text { text: bridge.catalogStatus; font.pixelSize: 11; color: win.dark ? "#c8c8c8" : "#5d5d5d"; Layout.fillWidth: true; wrapMode: Text.Wrap } Button { text: t("更新列表", "Update list"); onClicked: bridge.updateModelCatalog() } }
                                Repeater { model: bridge.models
                                    Frame { required property var modelData; required property int index; Layout.fillWidth: true; padding: 8
                                        RowLayout { anchors.fill: parent
                                            ColumnLayout { Layout.fillWidth: true; spacing: 0
                                                Text { text: modelData.label + " · " + modelData.size + (modelData.current ? (" · " + t("当前", "Current")) : ""); font.pixelSize: 12; font.weight: Font.DemiBold; color: win.dark ? "#fff" : "#1b1b1b"; wrapMode: Text.Wrap }
                                                Text { text: modelData.note; font.pixelSize: 10; color: win.dark ? "#c8c8c8" : "#5d5d5d"; wrapMode: Text.Wrap } }
                                            Button { text: modelData.installed ? t("使用", "Use") : t("下载", "Download"); enabled: !bridge.busy; onClicked: bridge.useOrDownloadModel(index) } } } }
                            } }
                        // 2 online model
                        ScrollView { id: svB
                            ColumnLayout { width: svB.availableWidth - 16; spacing: 8
                                RowLayout { Layout.fillWidth: true
                                    Text { text: t("在线大模型", "Online model"); font.pixelSize: 16; font.weight: Font.DemiBold; color: win.dark ? "#fff" : "#1b1b1b"; Layout.fillWidth: true }
                                    Button { text: t("说明", "About"); onClicked: buyInfoDlg.open() } }
                                Text { text: store.plan === "" ? t("当前未开通在线版（本地版可离线使用）。", "Online edition not active (local edition works offline).") : (t("已开通：", "Active: ") + win.cdkPlanName(store.plan)); font.pixelSize: 12; color: win.dark ? "#e8e8e8" : "#333"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                                Repeater { model: [{n:"Pro", zh:"个人版 · A测价 ¥29/月（原价 ¥79/月）", en:"Personal · Alpha ¥29/mo (was ¥79/mo)", fit:0.5, fzh:"个人学习 / 轻任务", fen:"Personal study / light tasks"}, {n:"Max", zh:"专业版 · A测价 ¥79/月（原价 ¥199/月）", en:"Professional · Alpha ¥79/mo (was ¥199/mo)", fit:0.8, fzh:"长回答 / 高并发", fen:"Long answers / high concurrency"}, {n:"ENT", zh:"企业定制版 · 联系开通", en:"Enterprise · Contact us", fit:1.0, fzh:"私有部署 / 团队定制", fen:"Private deployment / team customization"}]
                                    Frame { required property var modelData; Layout.fillWidth: true; padding: 10
                                        ColumnLayout { anchors.fill: parent; spacing: 4
                                            Text { text: modelData.n + " " + (bridge.lang === "zh" ? modelData.zh : modelData.en); font.pixelSize: 13; font.weight: Font.DemiBold; color: win.dark ? "#fff" : "#1b1b1b"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                                            ProgressBar { value: modelData.fit; Layout.fillWidth: true }
                                            Text { text: t("适配：", "Fit: ") + (bridge.lang === "zh" ? modelData.fzh : modelData.fen); font.pixelSize: 10; color: win.dark ? "#c8c8c8" : "#5d5d5d" } } } }
                                Text { text: t("套餐适配度仅表示适用场景，不是性能百分比。", "Fit shows suitable scenarios, not performance percentages."); font.pixelSize: 10; color: win.dark ? "#c8c8c8" : "#5d5d5d"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                                RowLayout { Layout.fillWidth: true
                                    TextField { id: cdkField; Layout.fillWidth: true; placeholderText: "VALDAL-PRO-…" }
                                    Button { text: t("兑换 CDK", "Redeem CDK"); onClicked: win.redeemCdk(cdkField.text) } }
                                Text { text: win.cdkMsg; font.pixelSize: 11; color: "#0f7b0f"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                                Text { text: t("购买 CDK：发邮件 joulyman@gmail.com 或致电 +1 316 872 5748（A测期人工开通，含企业定制咨询）。", "To buy a CDK: email joulyman@gmail.com or call +1 316 872 5748 (manual activation during alpha; enterprise customization included)."); font.pixelSize: 11; color: win.dark ? "#c8c8c8" : "#5d5d5d"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            } }
                        // 3 knowledge
                        ColumnLayout { spacing: 8
                            Text { text: t("知识库", "Knowledge"); font.pixelSize: 16; font.weight: Font.DemiBold; color: win.dark ? "#fff" : "#1b1b1b" }
                            Text { text: bridge.knowledgeStats; font.pixelSize: 11; color: win.dark ? "#c8c8c8" : "#5d5d5d"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            TextArea { id: kbEdit; Layout.fillWidth: true; Layout.fillHeight: true; text: bridge.knowledgeText; wrapMode: TextArea.Wrap; placeholderText: t("在此写入语料…", "Write corpus notes here…") }
                            RowLayout { Layout.fillWidth: true
                                TextField { id: kbDomain; placeholderText: t("行业/领域（导入用）", "Domain (for import)"); Layout.preferredWidth: 200 }
                                Button { text: t("导入文件", "Import files"); onClicked: kbDlg.open() }
                                Item { Layout.fillWidth: true }
                                Button { text: t("保存知识库", "Save knowledge"); highlighted: true; onClicked: bridge.saveKnowledge(kbEdit.text) } }
                        }
                        // 4 appearance & language (only place for language)
                        ColumnLayout { spacing: 10
                            Text { text: t("外观与语言", "Appearance & language"); font.pixelSize: 16; font.weight: Font.DemiBold; color: win.dark ? "#fff" : "#1b1b1b" }
                            Switch { text: t("深色主题", "Dark theme"); checked: win.dark; onToggled: win.dark = checked }
                            RowLayout { Text { text: t("语言 / Language", "Language"); font.pixelSize: 12; color: win.dark ? "#e8e8e8" : "#333" }
                                ComboBox { model: [t("跟随系统", "System"), "中文", "English"]; currentIndex: bridge.languageIndex; onActivated: function(i){ bridge.setLanguage(i) } } }
                            Item { Layout.fillHeight: true }
                        }
                        // 5 account & about
                        ScrollView { id: svC
                            ColumnLayout { width: svC.availableWidth - 16; spacing: 8
                                Text { text: t("账号与关于", "Account & about"); font.pixelSize: 16; font.weight: Font.DemiBold; color: win.dark ? "#fff" : "#1b1b1b" }
                                Switch { text: t("启用本地账号管理（企业版）", "Enable local account management (Enterprise)"); checked: bridge.accountsEnabled; onToggled: bridge.setAccountsEnabled(checked) }
                                Text { text: (bridge.enterpriseActive || store.plan === "ENT") ? t("企业版已激活 · 不限人数", "Enterprise active · unlimited accounts") : t("未激活 · 上限 3 人", "Inactive · max 3 accounts"); font.pixelSize: 11; color: (bridge.enterpriseActive || store.plan === "ENT") ? "#0f7b0f" : (win.dark ? "#c8c8c8" : "#5d5d5d") }
                                Text { text: t("当前用户：", "Current user: ") + bridge.currentUser + " · " + bridge.accountRole; font.pixelSize: 12; color: win.dark ? "#e8e8e8" : "#333" }
                                Repeater { model: bridge.accounts
                                    Frame { required property var modelData; Layout.fillWidth: true; padding: 6
                                        RowLayout { anchors.fill: parent
                                            Text { text: modelData.name + " · " + modelData.role; font.pixelSize: 12; color: win.dark ? "#fff" : "#1b1b1b"; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                            Switch { checked: modelData.enabled; onToggled: bridge.setAccountEnabled(modelData.name, checked) }
                                            ToolButton { text: "🔑"; ToolTip.visible: hovered; ToolTip.text: t("重置密码", "Reset password"); onClicked: { resetDlg.user = modelData.name; resetDlg.open() } }
                                            ToolButton { text: "🗑"; ToolTip.visible: hovered; ToolTip.text: t("删除账号", "Delete account"); onClicked: bridge.removeAccount(modelData.name) } } } }
                                RowLayout { Layout.fillWidth: true
                                    TextField { id: accName; placeholderText: t("新账号名", "New account name"); Layout.fillWidth: true }
                                    TextField { id: accPass; placeholderText: t("密码", "Password"); echoMode: TextInput.Password; Layout.fillWidth: true }
                                    ComboBox { id: accRole; model: ["member", "admin"]; Layout.preferredWidth: 110 }
                                    Button { text: t("添加账号", "Add account"); enabled: bridge.accountRole === "admin"; onClicked: if (accName.text.trim() !== "") { bridge.addAccount(accName.text, accPass.text, accRole.currentText); accPass.clear() } } }
                                RowLayout { Layout.fillWidth: true
                                    TextField { id: loginName; placeholderText: t("登录名", "Login name"); Layout.fillWidth: true }
                                    TextField { id: loginPass; placeholderText: t("密码", "Password"); echoMode: TextInput.Password; Layout.fillWidth: true }
                                    Button { text: t("登录", "Log in"); onClicked: bridge.login(loginName.text, loginPass.text) }
                                    Button { text: t("退出", "Log out"); flat: true; onClicked: bridge.logout() } }
                                Text { text: bridge.accountMsg; font.pixelSize: 11; color: "#0f7b0f"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                                MenuSeparator { Layout.fillWidth: true }
                                Text { text: t("关于 VAL-DAL", "About VAL-DAL"); font.pixelSize: 14; font.weight: Font.DemiBold; color: win.dark ? "#fff" : "#1b1b1b" }
                                Text { text: t("Valhalla 管线：先用结构检索从本地知识中取出可核查的依据，再由 Fate 路由选择解码路径，解码头可按模型更换，会话热驻留让多轮对话不必反复加载权重。本地版永久免费，数据不出本机。", "The Valhalla pipeline retrieves checkable evidence from local knowledge with structured retrieval, routes decoding through Fate, supports swappable decode heads per model, and keeps sessions warm so multi-turn chat does not reload weights. The local edition is free forever; data stays on this PC."); font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true; color: win.dark ? "#e8e8e8" : "#333" }
                                Text { text: "• " + t("结构检索", "Structured retrieval") + "\n• Fate " + t("路由", "routing") + "\n• " + t("解码头可换", "Swappable decode heads") + "\n• " + t("会话热驻留", "Warm session residency") + "\n\nRogue Intelligence Inc. (Delaware, USA)"; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true; color: win.dark ? "#c8c8c8" : "#5d5d5d" }
                            } }
                    }
                }
            }
        }
    }

    Dialog { id: ctlDlg; title: t("启用电脑控制？", "Enable computer control?"); modal: true; standardButtons: Dialog.Ok | Dialog.Cancel
        Text { text: t("开启后，回答中的控制动作会在本机执行。请确认你信任当前知识与提问内容。", "Control actions in answers will run on this PC. Confirm you trust the current knowledge and prompts."); wrapMode: Text.Wrap; width: 360; color: win.dark ? "#e8e8e8" : "#333" }
        onAccepted: bridge.setAllowControl(true); onRejected: { ctlSwitch.checked = false; bridge.setAllowControl(false) } }
    Dialog { id: resetDlg; property string user: ""; title: t("重置密码", "Reset password"); modal: true; standardButtons: Dialog.Ok | Dialog.Cancel
        TextField { id: resetPass; placeholderText: t("新密码", "New password"); echoMode: TextInput.Password; width: 260 }
        onAccepted: if (resetPass.text !== "") bridge.resetAccountPassword(user, resetPass.text) }
    Dialog { id: loginDlg; title: t("本地账号登录", "Local account login"); modal: true; closePolicy: Popup.CloseOnEscape
        ColumnLayout { spacing: 8; width: 300
            TextField { id: gateName; placeholderText: t("登录名", "Login name"); Layout.fillWidth: true }
            TextField { id: gatePass; placeholderText: t("密码", "Password"); echoMode: TextInput.Password; Layout.fillWidth: true }
            Button { text: t("登录", "Log in"); highlighted: true; Layout.fillWidth: true; onClicked: if (bridge.login(gateName.text, gatePass.text)) loginDlg.close() }
            Text { text: bridge.accountMsg; font.pixelSize: 11; color: "#c42b1c"; wrapMode: Text.Wrap; Layout.fillWidth: true } } }
    Dialog { id: buyInfoDlg; title: t("在线版说明", "About the online edition"); modal: true; standardButtons: Dialog.Close
        ColumnLayout { spacing: 6; width: 420
            Text { text: t("优势：先走 Valhalla 管线结构检索再上云；本地版永久免费；快速推流；长回答更稳；A测价锁定（A测期购买按现价锁定）。", "Advantages: Valhalla structured retrieval runs first, then the cloud model; local edition free forever; fast streaming; stable long answers; alpha pricing locked for buyers."); wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: 12; color: win.dark ? "#e8e8e8" : "#333" }
            Text { text: t("购买流程：联系我们 → 付款 → 收到 CDK → 在「在线大模型」页兑换。", "How to buy: contact us → pay → receive CDK → redeem on the Online model page."); wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: 12; color: win.dark ? "#e8e8e8" : "#333" }
            Text { text: "+1 316 872 5748 · joulyman@gmail.com"; font.pixelSize: 12; font.weight: Font.DemiBold; color: win.dark ? "#fff" : "#1b1b1b" } } }
    FileDialog { id: ocrDlg; title: t("选择图片做 OCR", "Choose images for OCR"); fileMode: FileDialog.OpenFiles; nameFilters: ["Images (*.png *.jpg *.jpeg *.bmp *.webp)"]; onAccepted: bridge.ocrImport(selectedFiles) }
    FileDialog { id: kbDlg; title: t("导入知识文件", "Import knowledge files"); fileMode: FileDialog.OpenFiles; onAccepted: bridge.importFiles(kbDomain.text, selectedFiles) }
}
