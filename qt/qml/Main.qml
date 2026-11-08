import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtCore

ApplicationWindow {
    id: win
    width: 1360
    height: 860
    minimumWidth: 980
    minimumHeight: 640
    visible: true
    title: "瓦序 VAL-DAL"
    color: bg
    font.family: "SimHei"

    property bool showSettings: false
    property int settingsSection: 0
    property bool panelOpen: true
    property bool light: false
    property string pinnedNote: ""
    property bool panelFlash: false
    property bool panelNudge: false

    function flashPanel() { panelFlash = true; flashTimer.restart() }
    Timer { id: flashTimer; interval: 1400; onTriggered: win.panelFlash = false }
    Connections {
        target: bridge
        function onTurnChanged() {
            if (bridge.turnCount > 0) { win.flashPanel(); if (!win.panelOpen) win.panelNudge = true }
        }
        function onScreenChanged() { win.flashPanel() }
    }

    property string selText: ""
    property var selItem: null
    Timer { id: selTimer; interval: 450; onTriggered: win.openSelBar() }
    function noteSelection(item) {
        selItem = item
        if (item.selectedText.trim().length > 0) selTimer.restart()
        else selTimer.stop()
    }
    function openSelBar() {
        if (!selItem || selItem.selectedText.trim().length === 0) return
        selText = selItem.selectedText
        var r = selItem.positionToRectangle(selItem.selectionStart)
        var p = selItem.mapToItem(win.contentItem, r.x, r.y)
        selBar.x = Math.max(8, Math.min(p.x, win.width - 400))
        selBar.y = Math.max(8, p.y - 58)
        if (!selBar.visible) selBar.open()
    }

    function t(zh, en) { return bridge.lang === "zh" ? zh : en }

    Settings { id: store; category: "valdal-online"; property string plan: ""; property string code: "" }

    property string cdkMsg: ""
    function cdkPlanName(p) { return p === "MAX" ? t("Max \u4e13\u4e1a\u7248", "Max Pro") : p === "ENT" ? t("\u4f01\u4e1a\u5b9a\u5236\u7248", "Enterprise") : t("Pro \u4e2a\u4eba\u7248", "Pro") }
    function redeemCdk(raw) {
        var code = raw.toUpperCase().replace(/\s/g, "")
        var parts = code.split("-")
        if (parts.length !== 5 || parts[0] !== "VALDAL" || (parts[1] !== "PRO" && parts[1] !== "MAX" && parts[1] !== "ENT")) { win.cdkMsg = t("\u5151\u6362\u7801\u683c\u5f0f\u4e0d\u6b63\u786e\uff0c\u5e94\u4e3a VALDAL-PRO-\u2026\u2026", "Invalid code format (VALDAL-PRO-...)"); return }
        var flat = code.replace(/-/g, "")
        var body = flat.substring(0, flat.length - 1)
        var sum = 0
        for (var i = 0; i < body.length; i++) sum += body.charCodeAt(i)
        var cs = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        if (cs.charAt((sum * 31 + 17) % 36) !== flat.charAt(flat.length - 1)) { win.cdkMsg = t("\u5151\u6362\u7801\u65e0\u6548\uff0c\u8bf7\u68c0\u67e5\u540e\u91cd\u8bd5\uff0c\u6216\u8054\u7cfb joulyman@gmail.com", "Code not recognized. Check it, or contact joulyman@gmail.com"); return }
        store.plan = parts[1]; store.code = code
        win.cdkMsg = t("\u5151\u6362\u6210\u529f\uff0c\u5df2\u5f00\u901a ", "Redeemed: ") + win.cdkPlanName(parts[1])
    }
    function currentModelLabel() {
        for (var i = 0; i < bridge.models.length; i++)
            if (bridge.models[i].current) return bridge.models[i].label
        return "—"
    }

    property color bg: light ? "#fbfbfa" : "#0a0a0c"
    property color rail: light ? "#f2f2f0" : "#0d0d10"
    property color card: light ? "#eeeeeb" : "#15151a"
    property color cardHi: light ? "#e2e2dd" : "#1e1e25"
    property color line: light ? "#deded8" : "#23232b"
    property color ink: light ? "#16161a" : "#f2f2f4"
    property color muted: light ? "#6f6f76" : "#9898a3"
    property color accent: light ? "#16161a" : "#f2f2f4"
    property color primaryBg: light ? "#16161a" : "#f2f2f4"
    property color primaryInk: light ? "#ffffff" : "#0a0a0c"
    property color bubbleBg: light ? "#e7e7ef" : "#26262e"
    property color flash: "#6c8cff"

    component GhostButton: Button {
        id: gb
        property bool active: false
        implicitHeight: 32
        contentItem: Text {
            text: gb.text
            color: gb.active ? win.primaryInk : (gb.hovered || gb.pressed ? win.ink : win.muted)
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 9
            color: gb.active ? win.accent : (gb.pressed ? win.cardHi : (gb.hovered ? win.cardHi : win.card))
            border.color: gb.active ? win.accent : win.line
            opacity: gb.enabled ? 1 : 0.45
        }
    }
    component PrimaryButton: Button {
        id: pb
        implicitHeight: 36
        contentItem: Text { text: pb.text; color: win.primaryInk; font.pixelSize: 13; font.weight: Font.DemiBold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { radius: 9; color: pb.pressed ? win.cardHi : win.primaryBg; opacity: pb.enabled ? (pb.hovered ? 0.88 : 1) : 0.45; border.color: win.primaryBg }
    }
    component DangerButton: Button {
        id: db
        implicitHeight: 32
        contentItem: Text { text: db.text; color: "#ffffff"; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { radius: 9; color: db.pressed ? "#8f2d2d" : (db.hovered ? "#b23a3a" : "#9e3434"); opacity: db.enabled ? 1 : 0.45 }
    }
    // Dot-matrix signal row: lit dots = active/ok, dim = standby/weak
    component SignalDots: RowLayout {
        property int lit: 0
        property int total: 5
        property string caption: ""
        spacing: 5
        Repeater {
            model: total
            delegate: Rectangle { required property int index; width: 8; height: 8; radius: 4; color: index < lit ? win.flash : win.line; opacity: index < lit ? 1 : 0.55 }
        }
        Text { text: caption; color: muted; font.pixelSize: 11; Layout.leftMargin: 4 }
    }
    function pipelineLit() {
        if (!bridge.busy) return bridge.lastPath !== "" ? 5 : 2
        return 3
    }
    function pipelineStage() {
        if (bridge.busy) return t("理解 → 检索 → 组织 → 回答（处理中）", "Understand → Retrieve → Organize → Answer (working)")
        return bridge.lastPath !== "" ? (t("已完成 · ", "Done · ") + bridge.lastPath) : t("待机", "Standby")
    }

    component KV: RowLayout {
        property string name: ""
        property string value: ""
        Layout.fillWidth: true
        Text { text: name; color: win.muted; font.pixelSize: 12 }
        Item { Layout.fillWidth: true }
        Text {
            text: value === "" ? "—" : value
            color: win.ink
            font.pixelSize: 12
            elide: Text.ElideRight
            Layout.maximumWidth: 170
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---------- Sidebar ----------
        Rectangle {
            Layout.preferredWidth: 252
            Layout.fillHeight: true
            color: rail
            visible: !win.showSettings

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 9
                    Image {
                        source: win.light ? "../logo-black.png" : "../logo-white.png"
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        fillMode: Image.PreserveAspectFit
                    }
                    ColumnLayout {
                        spacing: 0
                        RowLayout {
                            spacing: 6
                            Text { text: "\u74e6\u5e8f"; color: ink; font.pixelSize: 16; font.weight: Font.DemiBold }
                            Text { text: "VAL-DAL"; color: muted; font.pixelSize: 10; font.weight: Font.DemiBold }
                        }
                        Text { text: t("本地智能体", "Local agent"); color: muted; font.pixelSize: 10 }
                    }
                    Item { Layout.fillWidth: true }
                }

                Button {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    text: "＋  " + t("新建任务", "New task")
                    onClicked: bridge.newChat()
                    contentItem: Text {
                        text: parent.text
                        color: win.primaryInk
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle { radius: 10; color: win.primaryBg; opacity: parent.hovered ? 0.85 : 1.0 }
                }

                TextField {
                    id: search
                    Layout.fillWidth: true
                    placeholderText: t("搜索任务", "Search tasks")
                    placeholderTextColor: muted
                    color: ink
                    font.pixelSize: 12
                    onTextChanged: bridge.setSearch(text)
                    background: Rectangle { radius: 9; color: card; border.color: line }
                }

                Text { text: t("任务", "Tasks"); color: muted; font.pixelSize: 11; Layout.topMargin: 4 }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: bridge.conversations
                    spacing: 2
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: 34
                        radius: 8
                        color: modelData.active ? cardHi : (hover.hovered ? card : "transparent")
                        HoverHandler { id: hover }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            Text {
                                text: modelData.title
                                color: modelData.active ? ink : muted
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: "✕"
                                color: muted
                                font.pixelSize: 11
                                visible: hover.hovered
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    onClicked: bridge.deleteChat(modelData.id)
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            z: -1
                            onClicked: bridge.openChat(modelData.id)
                        }
                    }
                }


            }
        }

        Rectangle { width: 1; Layout.fillHeight: true; color: line; visible: !win.showSettings }

        // ---------- Chat ----------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            visible: !win.showSettings

            // Header
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 22
                Layout.rightMargin: 16
                Layout.topMargin: 12
                Layout.bottomMargin: 10
                Text {
                    text: bridge.chatTitle
                    color: ink
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.maximumWidth: 420
                }
                Item { Layout.fillWidth: true }
                Rectangle { radius: 8; color: card; border.color: line; implicitWidth: modeLabel.width + 16; implicitHeight: 24
                    Text { id: modeLabel; anchors.centerIn: parent; text: "Valhalla " + t("模式", "Mode"); color: muted; font.pixelSize: 11; font.weight: Font.DemiBold } }
                GhostButton {
                    text: win.light ? t("黑", "Dark") : t("白", "Light")
                    implicitWidth: 52
                    onClicked: win.light = !win.light
                }
                Button {
                    id: gearTop
                    implicitWidth: 36; implicitHeight: 32
                    text: "⚙"
                    onClicked: { win.settingsSection = 0; win.showSettings = true }
                    contentItem: Text { text: parent.text; color: parent.hovered ? ink : muted; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 9; color: parent.hovered ? cardHi : card; border.color: line }
                    ToolTip.visible: hovered; ToolTip.text: t("设置", "Settings")
                }
                GhostButton {
                    text: win.panelOpen ? t("隐藏右栏", "Hide panel") : t("显示右栏", "Show panel")
                    active: win.panelOpen
                    implicitWidth: 84
                    onClicked: win.panelOpen = !win.panelOpen
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: line }

            // Thread
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: thread
                    anchors.fill: parent
                    anchors.leftMargin: 22
                    anchors.rightMargin: 22
                    clip: true
                    spacing: 18
                    model: bridge.messages
                    onCountChanged: positionViewAtEnd()
                    topMargin: 18
                    bottomMargin: 12

                    delegate: Item {
                        required property var modelData
                        width: ListView.view.width
                        height: modelData.user ? bubble.height : assistantCol.height

                        Rectangle {
                            id: bubble
                            visible: modelData.user
                            anchors.right: parent.right
                            width: Math.min(parent.width * 0.72, userText.implicitWidth + 28)
                            height: userText.height + 20
                            radius: 16
                            color: bubbleBg
                            Text {
                                id: userText
                                anchors.centerIn: parent
                                width: Math.min(parent.width - 28, implicitWidth)
                                text: modelData.text
                                color: ink
                                font.pixelSize: 14
                                wrapMode: Text.Wrap
                            }
                        }

                        ColumnLayout {
                            id: assistantCol
                            visible: !modelData.user
                            width: Math.min(parent.width, 768)
                            spacing: 5
                            RowLayout {
                                spacing: 8
                                Text { text: "\u74e6\u5e8f VAL-DAL"; color: muted; font.pixelSize: 11; font.weight: Font.DemiBold }
                                Rectangle {
                                    visible: modelData.badge !== ""
                                    radius: 8
                                    color: card
                                    border.color: line
                                    implicitWidth: badgeText.width + 14
                                    implicitHeight: 17
                                    Text { id: badgeText; anchors.centerIn: parent; text: modelData.badge; color: muted; font.pixelSize: 10 }
                                }
                            }
                            TextEdit {
                                id: msgEdit
                                text: modelData.text
                                readOnly: true
                                selectByMouse: true
                                color: ink
                                font.pixelSize: 14
                                wrapMode: TextEdit.Wrap
                                Layout.fillWidth: true
                                onSelectedTextChanged: win.noteSelection(msgEdit)
                            }
                            RowLayout {
                                spacing: 6
                                GhostButton {
                                    text: t("右栏查看", "View in panel")
                                    implicitHeight: 26
                                    onClicked: { win.panelOpen = true; win.panelNudge = false; win.flashPanel() }
                                }
                                GhostButton {
                                    text: t("固定到右栏", "Pin to panel")
                                    implicitHeight: 26
                                    onClicked: { win.pinnedNote = modelData.text; win.panelOpen = true; win.panelNudge = false; win.flashPanel() }
                                }
                                GhostButton {
                                    text: t("朗读", "Read aloud")
                                    implicitHeight: 26
                                    onClicked: bridge.speakText(modelData.text)
                                }
                                GhostButton {
                                    visible: modelData.error === true
                                    text: t("重试", "Retry")
                                    implicitHeight: 26
                                    enabled: !bridge.busy
                                    onClicked: bridge.retryLast()
                                }
                            }
                            Text {
                                visible: modelData.path !== ""
                                text: modelData.path
                                color: muted
                                font.pixelSize: 10
                                font.family: "Cascadia Mono"
                                wrapMode: Text.WrapAnywhere
                                Layout.fillWidth: true
                            }
                            Item { height: 2 }
                        }
                    }

                    footer: RowLayout {
                        width: thread.width
                        height: bridge.busy ? 26 : 0
                        visible: bridge.busy
                        spacing: 8
                        Text { text: "\u74e6\u5e8f VAL-DAL"; color: muted; font.pixelSize: 11; font.weight: Font.DemiBold }
                        Text {
                            text: win.pipelineStage()
                            color: muted
                            font.pixelSize: 13
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 600 }
                                NumberAnimation { to: 1.0; duration: 600 }
                            }
                        }
                    }
                }

                // Empty state
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 80, 560)
                    spacing: 14
                    visible: bridge.messages.length === 0 && !bridge.busy

                    Image {
                        source: win.light ? "../logo-black.png" : "../logo-white.png"
                        Layout.preferredWidth: 54
                        Layout.preferredHeight: 54
                        Layout.alignment: Qt.AlignHCenter
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        text: "\u74e6\u5e8f VAL-DAL"
                        color: ink
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: t("问一件事，或直接布置任务。", "Ask something, or give it a task.")
                        color: muted
                        font.pixelSize: 14
                        Layout.alignment: Qt.AlignHCenter
                    }
                    SignalDots { lit: bridge.enginePresent ? 4 : 1; caption: "Valhalla " + t("管线", "pipeline"); Layout.alignment: Qt.AlignHCenter }
                    Text {
                        text: t("快捷入口", "Quick actions")
                        color: muted
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 10
                    }
                    GridLayout {
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 10
                        Layout.alignment: Qt.AlignHCenter

                        Repeater {
                            model: [
                                { "title": t("识别屏幕", "Recognize screen"), "sub": t("把当前屏幕带入对话", "Bring the screen into the chat"), "act": 0 },
                                { "title": t("OCR 导入", "OCR import"), "sub": t("导入图片并识别文字", "Import an image and OCR it"), "act": 4 },
                                { "title": t("电脑控制", "Computer control"), "sub": t("在下方对话框开关中开启", "Toggle it in the composer below"), "act": 3 },
                                { "title": "Valhalla " + t("模式", "Mode"), "sub": t("固定混合管线，不可切换", "Fixed hybrid pipeline"), "act": 5 }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                implicitWidth: 230
                                implicitHeight: 64
                                radius: 14
                                color: cardHover.hovered ? cardHi : card
                                border.color: line
                                HoverHandler { id: cardHover }
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 2
                                    Text { text: modelData.title; color: ink; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Text { text: modelData.sub; color: muted; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (modelData.act === 0) bridge.recognize()
                                        else if (modelData.act === 4) ocrImportDialog.open()
                                        else if (modelData.act === 3) bridge.setAllowControl(!bridge.allowControl)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                text: bridge.statusText
                color: muted
                font.pixelSize: 11
                Layout.leftMargin: 26
                Layout.bottomMargin: 4
                visible: text !== ""
                elide: Text.ElideRight
                Layout.maximumWidth: 760
            }

            // Nudge: chat events ask to open the right panel
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: (win.panelNudge && !win.panelOpen) ? 34 : 0
                visible: win.panelNudge && !win.panelOpen
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitHeight: 30
                    text: t("上下文已更新，点开右栏查看  →", "Context updated — open the panel  →")
                    onClicked: { win.panelOpen = true; win.panelNudge = false; win.flashPanel() }
                    contentItem: Text {
                        text: parent.text; color: win.flash; font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle { radius: 15; color: card; border.color: win.flash }
                }
            }

            // Composer
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: composerCard.height + 22

                Rectangle {
                    id: composerCard
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    width: Math.min(parent.width - 44, 768)
                    height: composerCol.height + 20
                    radius: 20
                    color: card
                    border.color: line

                    ColumnLayout {
                        id: composerCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Rectangle { radius: 7; color: cardHi; border.color: line; implicitWidth: vmLabel.width + 12; implicitHeight: 20
                                Text { id: vmLabel; anchors.centerIn: parent; text: "Valhalla " + t("模式", "Mode"); color: muted; font.pixelSize: 10; font.weight: Font.DemiBold } }
                            GhostButton { text: t("识别屏幕", "Recognize screen"); implicitHeight: 26; enabled: !bridge.busy; onClicked: bridge.recognize() }
                            GhostButton { text: t("OCR 导入", "OCR import"); implicitHeight: 26; enabled: !bridge.busy; onClicked: ocrImportDialog.open() }
                            GhostButton { text: t("电脑控制", "Computer control"); implicitHeight: 26; active: bridge.allowControl; onClicked: bridge.setAllowControl(!bridge.allowControl) }
                            Item { Layout.fillWidth: true }
                            Text { text: bridge.busy ? win.pipelineStage() : ""; color: muted; font.pixelSize: 10; elide: Text.ElideRight; Layout.maximumWidth: 260 }
                        }
                        TextArea {
                            id: composer
                            Layout.fillWidth: true
                            placeholderText: t("输入消息，Enter 发送，Shift+Enter 换行", "Message. Enter sends, Shift+Enter adds a line")
                            placeholderTextColor: muted
                            color: ink
                            font.pixelSize: 14
                            wrapMode: Text.Wrap
                            background: null
                            Keys.onPressed: (event) => {
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                    bridge.send(composer.text)
                                    composer.text = ""
                                    event.accepted = true
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            GhostButton {
                                text: t("任务布置", "Task")
                                active: bridge.taskMode
                                onClicked: bridge.setTaskMode(!bridge.taskMode)
                            }
                            Item { Layout.fillWidth: true }
                            Button {
                                implicitWidth: 38
                                implicitHeight: 38
                                enabled: !bridge.busy && composer.text.trim() !== ""
                                text: "↑"
                                onClicked: { bridge.send(composer.text); composer.text = "" }
                                contentItem: Text {
                                    text: parent.text
                                    color: parent.enabled ? "#0b0b0d" : muted
                                    font.pixelSize: 17
                                    font.weight: Font.Bold
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    radius: 19
                                    color: parent.enabled ? "#ececf1" : cardHi
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---------- Settings ----------
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
            visible: win.showSettings

            Rectangle {
                Layout.preferredWidth: 208
                Layout.fillHeight: true
                color: rail

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 6

                    Button {
                        text: "←  " + t("返回", "Back")
                        onClicked: win.showSettings = false
                        contentItem: Text { text: parent.text; color: ink; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: 9; color: parent.hovered ? cardHi : card }
                        implicitHeight: 36
                        Layout.fillWidth: true
                    }
                    Text { text: t("设置", "Settings"); color: ink; font.pixelSize: 17; font.weight: Font.DemiBold; Layout.topMargin: 8; Layout.bottomMargin: 6 }
                    Repeater {
                        model: [t("Valhalla 管线", "Valhalla pipeline"), t("模型与下载", "Models & download"), t("在线大模型", "Online model"), t("知识库", "Knowledge"), t("外观与语言", "Appearance & language"), t("数据与关于", "Data & about")]
                        delegate: Button {
                            required property int index
                            required property string modelData
                            Layout.fillWidth: true
                            implicitHeight: 38
                            text: modelData
                            onClicked: win.settingsSection = index
                            contentItem: Text {
                                text: parent.text
                                color: win.settingsSection === index ? ink : muted
                                font.pixelSize: 13
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 10
                            }
                            background: Rectangle {
                                radius: 9
                                color: win.settingsSection === index ? cardHi : (parent.hovered ? card : "transparent")
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            Rectangle { width: 1; Layout.fillHeight: true; color: line }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: win.settingsSection === 1 ? 2 : win.settingsSection === 2 ? 3 : win.settingsSection === 3 ? 1 : win.settingsSection


                // Pipeline (section 0)
                Item {
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 22; spacing: 12
                    Text { text: t("Valhalla 管线", "Valhalla pipeline"); color: ink; font.pixelSize: 18; font.weight: Font.DemiBold }
                    SignalDots { lit: bridge.enginePresent ? (bridge.busy ? 3 : 5) : 1; caption: win.pipelineStage() }
                    Text { text: t("修复 / 初始化会自检引擎（含 .enc）、CUDA 与模型，清模型解密缓存、停 warm 进程、重新预热并跑 feature check。异步执行，不卡界面。", "Repair/init checks the engine (incl. .enc), CUDA and model, clears the decrypt cache, stops warm, re-warms and runs the feature check. Async."); color: muted; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    RowLayout { spacing: 8
                        PrimaryButton { text: bridge.pipelineBusy ? t("处理中…", "Working...") : t("修复 / 初始化 Valhalla 管线", "Repair / initialize Valhalla pipeline"); enabled: !bridge.pipelineBusy && !bridge.busy; implicitWidth: 240; onClicked: bridge.repairPipeline() }
                        GhostButton { text: t("检查运行时", "Probe runtime"); enabled: !bridge.busy; onClicked: bridge.probe() }
                        GhostButton { text: t("一键配置环境", "Set up environment"); enabled: !bridge.envReady; onClicked: bridge.setupEnvironment() }
                    }
                    Text { text: t("管线报告", "Pipeline report"); color: muted; font.pixelSize: 12 }
                    ScrollView { Layout.fillWidth: true; Layout.fillHeight: true
                        TextArea { text: bridge.pipelineReport === "" ? bridge.envReport : bridge.pipelineReport; readOnly: true; color: ink; font.pixelSize: 12; wrapMode: Text.Wrap; background: Rectangle { color: card; radius: 12; border.color: line } } }
                    Text { text: bridge.runtimeText; color: muted; font.pixelSize: 11; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true }
                }
                }

                // Knowledge (section 3, stack index shifted by pipeline+online inserts below)
                Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 10
                    Text { text: t("知识库", "Knowledge"); color: ink; font.pixelSize: 18; font.weight: Font.DemiBold }
                    Text { text: t("手写语料一行一条。行业资料用下方按钮导入，导入内容标记为待核对。", "One fact per line. Imported industry files stay pending review."); color: muted; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Text { text: bridge.knowledgeStats; color: muted; font.pixelSize: 12 }
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        TextArea {
                            id: knowledgeArea
                            text: bridge.knowledgeText
                            selectByMouse: true
                            onSelectedTextChanged: win.noteSelection(knowledgeArea)
                            color: ink
                            font.pixelSize: 13
                            wrapMode: Text.Wrap
                            background: Rectangle { color: card; radius: 12; border.color: line }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        TextField {
                            id: domainField
                            placeholderText: t("行业名，如 医疗", "Industry, e.g. medical")
                            placeholderTextColor: muted
                            color: ink
                            font.pixelSize: 12
                            implicitWidth: 200
                            background: Rectangle { radius: 9; color: card; border.color: line }
                        }
                        GhostButton { text: t("导入行业资料", "Import files"); onClicked: importDialog.open() }
                        Item { Layout.fillWidth: true }
                        Button {
                            text: t("保存", "Save")
                            implicitHeight: 34
                            implicitWidth: 96
                            onClicked: bridge.saveKnowledge(knowledgeArea.text)
                            contentItem: Text { text: parent.text; color: "#0b0b0d"; font.pixelSize: 13; font.weight: Font.DemiBold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { radius: 9; color: parent.hovered ? "#ffffff" : "#e4e4e9" }
                        }
                    }
                    Text { text: bridge.statusText; color: muted; font.pixelSize: 11; visible: text !== "" }
                }
                }

                // Models
                ScrollView {
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: parent.width
                        spacing: 10
                        Text { text: t("模型", "Models"); color: ink; font.pixelSize: 18; font.weight: Font.DemiBold; Layout.leftMargin: 22; Layout.topMargin: 22 }
                        RowLayout { Layout.leftMargin: 22; Layout.rightMargin: 22; spacing: 8
                            Text { text: t("瓦序 VAL-DAL · Valhalla 管线可选解码头（下载仍走本地下载通道）", "VAL-DAL · optional decode heads for the Valhalla pipeline"); color: muted; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.Wrap }
                            GhostButton { text: t("更新列表", "Update list"); enabled: !bridge.busy; onClicked: bridge.updateModelCatalog() }
                        }
                        Text { text: bridge.catalogStatus; color: muted; font.pixelSize: 11; Layout.leftMargin: 22 }
                        Repeater {
                            model: bridge.models
                            delegate: Rectangle {
                                required property int index
                                required property var modelData
                                Layout.leftMargin: 22
                                Layout.rightMargin: 22
                                Layout.fillWidth: true
                                implicitHeight: 84
                                radius: 14
                                color: card
                                border.color: modelData.current ? "#4c8dff" : line
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 12
                                    ColumnLayout {
                                        spacing: 3
                                        Layout.fillWidth: true
                                        Text {
                                            text: modelData.family + " · " + modelData.label + "   ·   " + modelData.size + "   ·   " + (modelData.installed ? t("已安装", "Installed") : t("未下载", "Not downloaded")) + (modelData.current ? "   ·   " + t("当前", "In use") : "")
                                            color: ink; font.pixelSize: 14; font.weight: Font.DemiBold
                                        }
                                        Text { text: modelData.note; color: muted; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
                                    }
                                    Button {
                                        visible: !modelData.current
                                        enabled: !bridge.busy
                                        text: modelData.installed ? t("使用", "Use") : t("下载", "Download")
                                        onClicked: bridge.useOrDownloadModel(index)
                                        contentItem: Text { text: parent.text; color: ink; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        background: Rectangle { radius: 9; color: parent.hovered ? cardHi : "#26262e"; border.color: line }
                                        implicitWidth: 84
                                        implicitHeight: 34
                                    }
                                }
                            }
                        }
                        Item { height: 16 }
                    }
                }


                // Online model (section 2)
                Item {
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 22; spacing: 12
                    Text { text: t("在线大模型", "Online model"); color: ink; font.pixelSize: 18; font.weight: Font.DemiBold }
                    SignalDots { lit: store.plan === "" ? 1 : 5; total: 5; caption: store.plan === "" ? t("未配置（本地版可离线使用）", "Not configured (local works offline)") : (t("已配置：", "Configured: ") + win.cdkPlanName(store.plan)) }
                    Text { text: store.plan === "" ? t("当前未开通在线版。购买/CDK 兑换后显示已配置。", "Online edition not active. It shows as configured after CDK redemption.") : (t("已开通：", "Active: ") + win.cdkPlanName(store.plan)); color: ink; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    PrimaryButton { text: t("购买 / 兑换 CDK", "Buy / Redeem CDK"); implicitWidth: 200; onClicked: buyDialog.open() }
                    Item { Layout.fillHeight: true }
                }
                }

                // Appearance & language (was General)
                Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 12
                    Text { text: t("外观与语言", "Appearance & language"); color: ink; font.pixelSize: 18; font.weight: Font.DemiBold }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: 12
                        color: card
                        border.color: line
                        implicitHeight: envCol.implicitHeight + 24
                        ColumnLayout {
                            id: envCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 8
                            Text { text: t("运行环境（CUDA 等）", "Environment (CUDA etc.)"); color: ink; font.pixelSize: 14; font.weight: Font.DemiBold }
                            Text { text: bridge.envReport; color: muted; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            RowLayout {
                                spacing: 8
                                GhostButton {
                                    text: bridge.envReady ? t("环境已就位", "Ready") : t("一键配置环境", "Set up environment")
                                    enabled: !bridge.envReady
                                    implicitWidth: 130
                                    onClicked: bridge.setupEnvironment()
                                }
                                GhostButton {
                                    text: t("官方 CUDA 安装", "Official CUDA installer")
                                    implicitWidth: 150
                                    onClicked: bridge.installCudaOfficial()
                                }
                            }
                            Text {
                                text: t("本地有 CUDA 运行库包时一键配置不用联网；没有英伟达显卡会走 CPU 模式，不用装。", "With a local CUDA bundle this needs no network. Without an NVIDIA GPU the CPU path needs none of this.")
                                color: muted; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true
                            }
                        }
                    }
                    Text { text: t("语言", "Language"); color: muted; font.pixelSize: 12 }
                    ComboBox {
                        model: [t("跟随系统", "Match system"), "中文", "English"]
                        currentIndex: bridge.languageIndex
                        onActivated: (i) => bridge.setLanguage(i)
                        implicitWidth: 240
                        contentItem: Text { text: parent.displayText; color: ink; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter; leftPadding: 10 }
                        background: Rectangle { radius: 9; color: card; border.color: line }
                        popup.background: Rectangle { color: cardHi; radius: 9; border.color: line }
                        delegate: ItemDelegate {
                            required property var modelData
                            width: parent ? parent.width : 220
                            contentItem: Text { text: modelData; color: ink; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { color: hovered ? card : "transparent" }
                        }
                    }
                    RowLayout { spacing: 10
                        Text { text: t("主题", "Theme"); color: ink; font.pixelSize: 13 }
                        GhostButton { text: win.light ? t("白色（当前）· 切到黑色", "Light (current) · Dark") : t("黑色（当前）· 切到白色", "Dark (current) · Light"); onClicked: win.light = !win.light }
                    }
                    RowLayout {
                        spacing: 10
                        Switch {
                            checked: bridge.keepSession
                            onToggled: bridge.setKeepSession(checked)
                        }
                        Text { text: t("多轮沿用上一轮会话", "Keep the session across turns"); color: ink; font.pixelSize: 13 }
                    }
                    Text { text: t("打开后，后面的问题带着上一轮结构会话。", "Later questions reuse the previous structure session."); color: muted; font.pixelSize: 12 }
                    Text { text: bridge.runtimeText; color: muted; font.pixelSize: 11; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true; Layout.topMargin: 10 }
                    GhostButton {
                        text: t("检查运行时", "Probe runtime")
                        enabled: !bridge.busy
                        implicitWidth: 132
                        onClicked: bridge.probe()
                    }
                    Item { Layout.fillHeight: true }
                }
                }

                // Desktop
                Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 12
                    Text { text: t("数据与关于", "Data & about"); color: ink; font.pixelSize: 18; font.weight: Font.DemiBold }
                    RowLayout { spacing: 8
                        GhostButton { text: t("关于瓦序", "About VAL-DAL"); onClicked: aboutDialog.open() }
                        Text { text: "Rogue Intelligence Inc. · Delaware, USA"; color: muted; font.pixelSize: 11 }
                    }
                    Text { text: t("屏幕与控制", "Screen and control"); color: ink; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text {
                        text: t("识别会暂时让出窗口，截取当前桌面，用 Windows OCR 读出文字，并列出控件坐标。计算机控制默认关闭，打开后才会执行点击、输入和按键。",
                                "Recognize steps aside, captures the desktop, reads it with Windows OCR, and lists control coordinates. Computer control stays off until you turn it on.")
                        color: muted; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
                    }
                    RowLayout {
                        spacing: 8
                        GhostButton { text: t("识别屏幕", "Recognize"); onClicked: bridge.recognize() }
                        GhostButton {
                            text: bridge.allowControl ? t("控制已打开", "Control is on") : t("允许控制电脑", "Allow computer control")
                            active: bridge.allowControl
                            onClicked: bridge.setAllowControl(!bridge.allowControl)
                        }
                    }
                    Text { text: bridge.screenMeta; color: ink; font.pixelSize: 12 }
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        TextArea {
                            text: bridge.screenText
                            readOnly: true
                            color: ink
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            background: Rectangle { color: card; radius: 12; border.color: line }
                        }
                    }
                }
                }
            }
        }
        Rectangle { width: 1; Layout.fillHeight: true; color: line; visible: win.panelOpen && win.width >= 1080 }

        // ---------- Context panel ----------
        Rectangle {
            Layout.preferredWidth: 296
            Layout.fillHeight: true
            color: rail
            border.width: win.panelFlash ? 2 : 0
            border.color: win.flash
            visible: win.panelOpen && win.width >= 1080

            ScrollView {
                anchors.fill: parent
                contentWidth: availableWidth

                ColumnLayout {
                    width: parent.width
                    spacing: 12

                    Text {
                        text: t("上下文", "Context")
                        color: ink
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        Layout.leftMargin: 16
                        Layout.topMargin: 16
                    }

                    Rectangle {
                        visible: win.pinnedNote !== ""
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        Layout.fillWidth: true
                        radius: 12
                        color: card
                        border.color: flash
                        border.width: 1
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6
                            Text { text: t("来自对话 · 已固定", "Pinned from chat"); color: muted; font.pixelSize: 11; font.weight: Font.DemiBold }
                            Text {
                                text: win.pinnedNote
                                color: ink; font.pixelSize: 12; wrapMode: Text.Wrap
                                elide: Text.ElideRight; maximumLineCount: 8
                                Layout.fillWidth: true
                            }
                            GhostButton {
                                text: t("清除固定", "Unpin")
                                implicitHeight: 26
                                onClicked: win.pinnedNote = ""
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.leftMargin: 16; Layout.rightMargin: 16; spacing: 7
                        Text { text: t("Valhalla 管线", "Valhalla pipeline"); color: ink; font.pixelSize: 12; font.weight: Font.DemiBold }
                        SignalDots { lit: win.pipelineLit(); caption: bridge.busy ? t("处理中", "Working") : (bridge.lastPath !== "" ? t("已输出", "Done") : t("待机", "Standby")) }
                        Text { text: t("输入 → 结构检索 → Fate 路由 → 本地解码 → 输出", "Input → Retrieval → Fate routing → Local decode → Output"); color: muted; font.pixelSize: 10; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        Text { text: win.pipelineStage(); color: muted; font.pixelSize: 10; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                    ColumnLayout {
                        Layout.leftMargin: 16; Layout.rightMargin: 16; spacing: 7
                        Text { text: t("模型状态（本地）", "Model (local)"); color: ink; font.pixelSize: 12; font.weight: Font.DemiBold }
                        SignalDots { lit: bridge.modelLoaded ? 5 : (bridge.modelInstalled ? 3 : 1); caption: bridge.modelLoaded ? t("已加载", "Loaded") : (bridge.modelInstalled ? t("已下载·未常驻", "Downloaded · not resident") : t("未下载", "Not downloaded")) }
                        KV { name: t("当前模型", "Model"); value: win.currentModelLabel() }
                        KV { name: t("已加载", "Resident"); value: bridge.modelLoaded ? t("是", "Yes") : t("否", "No") }
                        KV { name: "GPU/CPU"; value: bridge.computeDevice }
                        KV { name: t("轮次", "Turns"); value: String(bridge.turnCount) }
                        KV { name: t("耗时", "Elapsed"); value: bridge.lastElapsed }
                    }
                    ColumnLayout {
                        Layout.leftMargin: 16; Layout.rightMargin: 16; spacing: 7
                        Text { text: t("连接状态", "Connection"); color: ink; font.pixelSize: 12; font.weight: Font.DemiBold }
                        SignalDots { lit: (bridge.enginePresent ? 2 : 0) + (store.plan === "" ? 1 : 3); caption: bridge.enginePresent ? t("引擎在", "Engine present") : t("引擎不在", "Engine missing") }
                        KV { name: t("引擎进程", "Engine"); value: bridge.enginePresent ? t("在", "Present") : t("不在", "Missing") }
                        KV { name: t("在线大模型", "Online model"); value: store.plan === "" ? t("未配置", "Not configured") : win.cdkPlanName(store.plan) }
                        KV { name: t("屏幕", "Screen"); value: bridge.screenMeta }
                        KV { name: t("控制", "Control"); value: bridge.allowControl ? t("开", "On") : t("关", "Off") }
                    }
                    Item { height: 12 }
                }
            }
        }

    }

    Popup {
        id: selBar
        modal: false
        focus: false
        padding: 6
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: 12; color: cardHi; border.color: flash; border.width: 1 }
        contentItem: RowLayout {
            spacing: 6
            GhostButton { text: t("朗读选段", "Read aloud"); implicitHeight: 26; onClicked: { bridge.speakText(win.selText); selBar.close() } }
            GhostButton { text: t("翻译英文", "Translate"); implicitHeight: 26; onClicked: { selBar.close(); win.showSettings = false; bridge.askSelection("translate", win.selText) } }
            GhostButton { text: t("AI 解释", "Explain"); implicitHeight: 26; onClicked: { selBar.close(); win.showSettings = false; bridge.askSelection("explain", win.selText) } }
            GhostButton {
                text: t("与 AI 讨论", "Discuss")
                implicitHeight: 26
                onClicked: {
                    selBar.close()
                    win.showSettings = false
                    composer.text = t("我想讨论这段内容：", "I want to discuss this: ") + win.selText
                    composer.forceActiveFocus()
                    composer.cursorPosition = composer.length
                }
            }
        }
    }

    Dialog {
        id: envDialog
        modal: true
        anchors.centerIn: parent
        width: 480
        closePolicy: Popup.NoAutoClose
        background: Rectangle { radius: 16; color: cardHi; border.color: line }
        header: Text {
            text: t("先配置一下运行环境", "Set up the runtime first")
            color: ink; font.pixelSize: 16; font.weight: Font.DemiBold
            padding: 18
        }
        contentItem: ColumnLayout {
            spacing: 10
            Text {
                text: t("检测到本地运行环境还没配好（多半是 CUDA 运行库）。点一键配置即可，不用联网；跳过也能用，只是本地模型会慢或不可用。", "The local runtime is not set up yet (usually the CUDA libraries). One click fixes it offline. Skipping is fine, but the local model may be slow or unavailable.")
                color: muted; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
            }
            Text { text: bridge.envReport; color: ink; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
        }
        footer: RowLayout {
            spacing: 8
            Item { Layout.fillWidth: true }
            GhostButton { text: t("稍后再说", "Later"); onClicked: envDialog.close() }
            GhostButton { text: t("不再提醒", "Don't ask again"); onClicked: { bridge.dismissEnvSetup(); envDialog.close() } }
            GhostButton {
                text: t("一键配置环境", "Set up now")
                active: true
                implicitWidth: 130
                onClicked: { bridge.setupEnvironment(); envDialog.close() }
            }
        }
    }

    Component.onCompleted: {
        if (!bridge.envReady && !bridge.envDismissed) envDialog.open()
    }



    Dialog {
        id: buyDialog
        modal: true
        anchors.centerIn: parent
        width: 600
        background: Rectangle { radius: 16; color: cardHi; border.color: line }
        header: RowLayout {
            spacing: 10
            Text { text: "\u26a1 " + t("\u5b98\u65b9\u5728\u7ebf\u5927\u6a21\u578b", "Official online large model"); color: ink; font.pixelSize: 17; font.weight: Font.DemiBold; Layout.leftMargin: 18; Layout.topMargin: 16; Layout.bottomMargin: 6 }
            Item { Layout.fillWidth: true }
            Text { text: "A\u6d4b\u4f18\u60e0\u4ef7"; color: flash; font.pixelSize: 12; font.weight: Font.DemiBold; Layout.rightMargin: 18; Layout.topMargin: 16 }
        }
        ColumnLayout {
            spacing: 9
            width: 552
            Text {
                text: t("\u4e91\u7aef\u65d7\u8230\u5927\u6a21\u578b + Valhalla \u4f18\u5316\u63a8\u6d41\uff1a\u9996\u54cd\u66f4\u5feb\u3001\u6d41\u5f0f\u8f93\u51fa\u4e0d\u65ad\u6863\u3001\u957f\u56de\u7b54\u66f4\u7a33\u3002\u672c\u5730\u79bb\u7ebf\u7248\u6c38\u4e45\u514d\u8d39\uff0c\u5728\u7ebf\u7248\u6309\u5957\u9910\u5f00\u901a\u3002", "Cloud flagship model + Valhalla-optimized streaming: faster first token, smooth streaming, stable long answers. The local offline edition stays free; the online edition is plan-based.")
                color: muted; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
            }
            Rectangle { Layout.fillWidth: true; radius: 10; color: card; border.color: line; implicitHeight: planCol1.implicitHeight + 24
                ColumnLayout { id: planCol1; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12; spacing: 3
                    Text { text: "Pro " + t("\u4e2a\u4eba\u7248", "Personal") + "  \u00b7  A\u6d4b\u4ef7 \u00a529/\u6708\uff08\u539f\u4ef7 \u00a579/\u6708\uff09"; color: ink; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Text { text: t("\u4e91\u7aef\u5927\u6a21\u578b\u5bf9\u8bdd \u00b7 \u6bcf\u65e5 500 \u6b21 \u00b7 Valhalla \u4f18\u5316\u63a8\u6d41", "Cloud large-model chat - 500/day - Valhalla-optimized streaming"); color: muted; font.pixelSize: 11; Layout.fillWidth: true }
                }
            }
            Rectangle { Layout.fillWidth: true; radius: 10; color: card; border.color: flash; implicitHeight: planCol2.implicitHeight + 24
                ColumnLayout { id: planCol2; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12; spacing: 3
                    Text { text: "Max " + t("\u4e13\u4e1a\u7248", "Professional") + "  \u00b7  A\u6d4b\u4ef7 \u00a579/\u6708\uff08\u539f\u4ef7 \u00a5199/\u6708\uff09"; color: ink; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Text { text: t("\u65d7\u8230\u5927\u6a21\u578b \u00b7 \u6bcf\u65e5 2000 \u6b21 \u00b7 \u4f18\u5148\u63a8\u6d41\u901a\u9053 \u00b7 \u66f4\u957f\u4e0a\u4e0b\u6587", "Flagship model - 2000/day - priority streaming - longer context"); color: muted; font.pixelSize: 11; Layout.fillWidth: true }
                }
            }
            Rectangle { Layout.fillWidth: true; radius: 10; color: card; border.color: line; implicitHeight: planCol3.implicitHeight + 24
                ColumnLayout { id: planCol3; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12; spacing: 3
                    Text { text: t("\u4f01\u4e1a\u79c1\u4eba Agent \u5b9a\u5236", "Enterprise private Agent") + "  \u00b7  \u00a512,800/\u5e74 \u8d77"; color: ink; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Text { text: t("\u79c1\u6709\u670d\u52a1\u5668\u90e8\u7f72 \u00b7 \u4e13\u5c5e\u77e5\u8bc6\u5e93\u4e0e Agent \u5b9a\u5236 \u00b7 \u8054\u7cfb\uff1a+1 316 872 5748 \u00b7 joulyman@gmail.com", "Private server deployment - custom knowledge & Agent - +1 316 872 5748 - joulyman@gmail.com"); color: muted; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
                }
            }
            Text { text: t("A\u6d4b\u4f18\u60e0\u6301\u7eed\u4fdd\u6301\uff1aA\u6d4b\u671f\u5f00\u901a\u7684\u7528\u6237\uff0c\u6b63\u5f0f\u7248\u7eed\u8d39\u4ecd\u4eab A\u6d4b\u4ef7\u3002", "Alpha pricing stays: users who join during the alpha keep the alpha price on renewal."); color: flash; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
            Text { text: store.plan === "" ? t("\u5f53\u524d\u672a\u5f00\u901a\u5728\u7ebf\u7248\uff08\u672c\u5730\u7248\u53ef\u6b63\u5e38\u79bb\u7ebf\u4f7f\u7528\uff09\u3002", "Online edition not active (the local edition works offline as usual).") : t("\u5f53\u524d\u5df2\u5f00\u901a\uff1a", "Active plan: ") + win.cdkPlanName(store.plan); color: ink; font.pixelSize: 12; Layout.fillWidth: true }
            Rectangle {
                Layout.fillWidth: true
                radius: 10; color: card; border.color: flash
                implicitHeight: contactCol.implicitHeight + 24
                ColumnLayout {
                    id: contactCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 3
                    Text { text: t("购买开通（通过联系方式）", "How to buy (contact us)"); color: ink; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Text { text: t("电话 +1 316 872 5748 · 邮箱 joulyman@gmail.com —— 告诉我们要 Pro / Max / 企业定制，付款后把 CDK 发给你，回来填到下面兑换即可。企业私人 Agent 定制也走这个联系方式。", "Call +1 316 872 5748 or email joulyman@gmail.com - tell us Pro / Max / Enterprise, we send your CDK after payment; redeem it below. Enterprise private Agent customization uses the same contact."); color: muted; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: cdkInput
                    Layout.fillWidth: true
                    color: ink; font.pixelSize: 13
                    placeholderText: "CDK: VALDAL-PRO-XXXXXX-XXXXXX-X"
                    background: Rectangle { radius: 9; color: card; border.color: line }
                }
                GhostButton { text: t("\u5151\u6362", "Redeem"); onClicked: win.redeemCdk(cdkInput.text) }
            }
            Text { text: win.cdkMsg; color: flash; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true; visible: win.cdkMsg !== "" }
            Text { text: t("\u8d2d\u4e70 CDK\uff1a\u53d1\u90ae\u4ef6 joulyman@gmail.com \u6216\u81f4\u7535 +1 316 872 5748\uff08A\u6d4b\u671f\u4eba\u5de5\u5f00\u901a\uff0c\u542b\u4f01\u4e1a\u5b9a\u5236\u54a8\u8be2\uff09\u3002", "To buy a CDK: email joulyman@gmail.com or call +1 316 872 5748 (manual activation during alpha; enterprise customization included)."); color: muted; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
            RowLayout {
                Item { Layout.fillWidth: true }
                GhostButton { text: t("\u5173\u95ed", "Close"); implicitWidth: 84; onClicked: buyDialog.close() }
            }
        }
    }

    Dialog {
        id: aboutDialog
        modal: true
        anchors.centerIn: parent
        width: 540
        background: Rectangle { radius: 16; color: cardHi; border.color: line }
        header: RowLayout {
            spacing: 10
            Image {
                source: win.light ? "../logo-black.png" : "../logo-white.png"
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                Layout.leftMargin: 18
                Layout.topMargin: 16
                fillMode: Image.PreserveAspectFit
            }
            ColumnLayout {
                spacing: 1
                Layout.topMargin: 16
                RowLayout {
                    spacing: 8
                    Text { text: "瓦序 VAL-DAL"; color: ink; font.pixelSize: 17; font.weight: Font.DemiBold }
                    Rectangle {
                        radius: 8; color: flash; implicitWidth: 74; implicitHeight: 20
                        Text { anchors.centerIn: parent; text: "A测版 Alpha"; color: "#ffffff"; font.pixelSize: 10; font.weight: Font.DemiBold }
                    }
                }
                Text { text: "Rogue Intelligence Inc."; color: muted; font.pixelSize: 11 }
            }
        }
        contentItem: ColumnLayout {
            spacing: 10
            Text {
                text: "Rogue Intelligence Inc. 是一家注册于美国特拉华州（Delaware, USA）的美国公司。瓦序 VAL-DAL 是我们的自有算法产品：以自研加速运行时为核心，让本地大模型先检索、再融合、后开口——在普通个人电脑上跑出更稳、更快的本地智能。数据不出本机，不联网也能工作。"
                color: ink; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
            }
            Text { text: "增强能力（内部实测）"; color: ink; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.topMargin: 4 }
            Repeater {
                model: [
                    { "label": "知识记忆准确率（喂过的不遗忘）", "value": 100 },
                    { "label": "跨平台一致性（与 Linux 版 40 项逐项相同）", "value": 100 },
                    { "label": "选择题混合解码（0.5B 小模型）", "value": 63 }
                ]
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 3
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: modelData.label; color: muted; font.pixelSize: 11; Layout.fillWidth: true }
                        Text { text: modelData.value + "%"; color: ink; font.pixelSize: 11; font.weight: Font.DemiBold }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 8
                        radius: 4
                        color: card
                        Rectangle {
                            width: parent.width * modelData.value / 100
                            height: parent.height
                            radius: 4
                            color: flash
                        }
                    }
                }
            }
            Text {
                text: "融合生长实测：连续 20 轮对话中，知识结构持续生长（19 → 34 个结构片段），不回退、不遗忘；轮次越多，答得越准。"
                color: muted; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true
            }
            Text {
                text: "产品家族：主程序 · 教育版 · 学生版 · 手机版，均由同一自有引擎驱动。"
                color: muted; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true
            }
            Text {
                text: "测试环境：RTX 4090 · Qwen2.5-0.5B；A测数据，正式版以官方基准为准。\n© 2026 Rogue Intelligence Inc.（Delaware, USA）保留所有权利。"
                color: muted; font.pixelSize: 10; wrapMode: Text.Wrap; Layout.fillWidth: true
            }
        }
        footer: RowLayout {
            Item { Layout.fillWidth: true }
            GhostButton { text: "关闭"; implicitWidth: 84; onClicked: aboutDialog.close() }
        }
    }

    FileDialog {
        id: ocrImportDialog
        title: t("OCR 导入", "OCR import")
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Images (*.png *.jpg *.jpeg *.bmp *.webp)", "All files (*)"]
        onAccepted: bridge.ocrImport(selectedFiles)
    }
    FileDialog {
        id: importDialog
        title: t("导入行业资料", "Import industry files")
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Industry files (*.txt *.md *.csv *.tsv *.json *.jsonl *.html *.htm *.xml *.rtf *.log *.docx *.xlsx *.pptx *.pdf)", "All files (*)"]
        onAccepted: bridge.importFiles(domainField.text, selectedFiles)
    }
}
