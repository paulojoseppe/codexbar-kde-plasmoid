import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation
    switchWidth: Kirigami.Units.gridUnit * 18
    switchHeight: Kirigami.Units.gridUnit * 22

    property string packagePath: Qt.resolvedUrl("..").toString().replace("file://", "")
    property string scriptPath: packagePath + "/scripts/codexbar.sh"
    property string shellCommand: "CODEXBAR_PLASMA=1 \"" + scriptPath + "\""
    property string cacheCommand: "bash -lc 'cat \"${XDG_CACHE_HOME:-$HOME/.cache}/codexbar-waybar/last.json\" 2>/dev/null || printf \"[]\"'"
    property var barData: ({ text: "AI --", tooltip: "CodexBar: loading", className: "stale", percentage: 0 })
    property var providers: []
    property string activeProvider: ""
    property string barProvider: ""
    property string resetFormat: "provider"
    property bool refreshing: false
    property bool settingsOpen: false

    function providerName(pid) {
        var names = {
            codex: "Codex",
            claude: "Claude",
            gemini: "Gemini",
            copilot: "Copilot",
            cursor: "Cursor",
            vertexai: "Vertex AI",
            openrouter: "OpenRouter",
            openai: "OpenAI",
            kimik2: "Kimi K2",
            antigravity: "Antigravity"
        };
        return names[pid] || (pid ? pid.charAt(0).toUpperCase() + pid.slice(1) : "Provider");
    }

    function iconAlias(pid) {
        if (pid === "openai") {
            return "codex";
        }
        if (pid === "moonshot" || pid === "kimik2") {
            return "kimi";
        }
        return pid;
    }

    function iconSource(pid) {
        return Qt.resolvedUrl("../icons/providers/ProviderIcon-" + iconAlias(pid) + ".svg");
    }

    function maxPct(entry) {
        if (!entry || entry.error || !entry.usage) {
            return 0;
        }
        var cost = entry.usage.providerCost;
        if (cost && typeof cost.used === "number" && typeof cost.limit === "number" && cost.limit > 0) {
            return (cost.used / cost.limit) * 100;
        }
        var maxValue = 0;
        ["primary", "secondary", "tertiary"].forEach(function (key) {
            var pct = entry.usage[key] && entry.usage[key].usedPercent;
            if (typeof pct === "number" && pct > maxValue) {
                maxValue = pct;
            }
        });
        return maxValue;
    }

    function formatMoney(value) {
        if (typeof value !== "number") {
            return "$0.00";
        }
        return "$" + value.toFixed(2);
    }

    function compactNumber(value) {
        if (typeof value !== "number") {
            return "0";
        }
        if (value >= 1000000000) {
            return (value / 1000000000).toFixed(1).replace(/\.0$/, "") + "B";
        }
        if (value >= 1000000) {
            return (value / 1000000).toFixed(1).replace(/\.0$/, "") + "M";
        }
        if (value >= 1000) {
            return (value / 1000).toFixed(1).replace(/\.0$/, "") + "K";
        }
        return String(value);
    }

    function openAITotals(usage) {
        var totals = { costUSD: 0, requests: 0, totalTokens: 0, inputTokens: 0, outputTokens: 0, cachedInputTokens: 0 };
        var daily = usage && usage.openAIAPIUsage && usage.openAIAPIUsage.daily ? usage.openAIAPIUsage.daily : [];
        for (var i = 0; i < daily.length; i++) {
            totals.costUSD += daily[i].costUSD || 0;
            totals.requests += daily[i].requests || 0;
            totals.totalTokens += daily[i].totalTokens || 0;
            totals.inputTokens += daily[i].inputTokens || 0;
            totals.outputTokens += daily[i].outputTokens || 0;
            totals.cachedInputTokens += daily[i].cachedInputTokens || 0;
        }
        return totals;
    }

    function hasOpenAIUsage(usage) {
        return !!(usage && (usage.providerCost || usage.openAIAPIUsage));
    }

    function boundedPercent(value) {
        var pct = Number(value) || 0;
        return Math.max(0, Math.min(100, pct));
    }

    function statusColor(className) {
        if (className === "critical") {
            return Kirigami.Theme.negativeTextColor;
        }
        if (className === "warning") {
            return Kirigami.Theme.neutralTextColor;
        }
        if (className === "stale") {
            return Kirigami.Theme.disabledTextColor;
        }
        return Kirigami.Theme.positiveTextColor;
    }

    function percentColor(pct) {
        if (pct >= 90) {
            return Kirigami.Theme.negativeTextColor;
        }
        if (pct >= 70) {
            return Kirigami.Theme.neutralTextColor;
        }
        return Kirigami.Theme.positiveTextColor;
    }

    component UsageBar: Item {
        property real percent: 0
        property color accentColor: Kirigami.Theme.positiveTextColor

        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.smallSpacing * 2

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Kirigami.Theme.disabledTextColor
            opacity: 0.24
        }

        Rectangle {
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: parent.width * boundedPercent(percent) / 100
            radius: height / 2
            color: accentColor
            opacity: 0.92
        }
    }

    function pickDefaultProvider() {
        if (!providers.length) {
            activeProvider = "";
            return;
        }
        var best = providers[0];
        for (var i = 1; i < providers.length; i++) {
            if (maxPct(providers[i]) > maxPct(best)) {
                best = providers[i];
            }
        }
        activeProvider = best.provider || "";
    }

    function activeEntry() {
        for (var i = 0; i < providers.length; i++) {
            if (providers[i].provider === activeProvider) {
                return providers[i];
            }
        }
        return providers.length ? providers[0] : null;
    }

    function providerEntry(pid) {
        for (var i = 0; i < providers.length; i++) {
            if (providers[i].provider === pid) {
                return providers[i];
            }
        }
        return null;
    }

    function panelEntry() {
        if (barProvider) {
            var pinned = providerEntry(barProvider);
            if (pinned) {
                return pinned;
            }
        }
        return activeEntry();
    }

    function windowPercent(entry, key) {
        if (!entry || !entry.usage || !entry.usage[key] || typeof entry.usage[key].usedPercent !== "number") {
            return -1;
        }
        return boundedPercent(entry.usage[key].usedPercent);
    }

    function compactWindowText(entry, key, label) {
        var pct = windowPercent(entry, key);
        return label + " " + (pct >= 0 ? Math.floor(pct) + "%" : "--");
    }

    function remainingPercent(windowData) {
        if (!windowData) {
            return -1;
        }
        if (typeof windowData.remainingPercent === "number") {
            return boundedPercent(windowData.remainingPercent);
        }
        if (typeof windowData.usedPercent === "number") {
            return boundedPercent(100 - windowData.usedPercent);
        }
        return -1;
    }

    function usedPercent(windowData) {
        if (!windowData) {
            return -1;
        }
        if (typeof windowData.usedPercent === "number") {
            return boundedPercent(windowData.usedPercent);
        }
        if (typeof windowData.remainingPercent === "number") {
            return boundedPercent(100 - windowData.remainingPercent);
        }
        return -1;
    }

    function hasQuotaRows(usage) {
        return !!(usage && (usage.primary || usage.secondary || usage.tertiary));
    }

    function parseBarOutput(stdout) {
        var lines = stdout.trim().split(/\n/);
        var raw = lines.length ? lines[lines.length - 1] : "{}";
        try {
            var parsed = JSON.parse(raw);
            barData = {
                text: parsed.text || "AI --",
                tooltip: parsed.tooltip || "",
                className: parsed["class"] || "stale",
                percentage: parsed.percentage || 0
            };
        } catch (e) {
            barData = { text: "AI !", tooltip: "CodexBar: invalid backend output", className: "stale", percentage: 0 };
        }
    }

    function parseProviders(stdout) {
        try {
            var parsed = JSON.parse(stdout.trim() || "[]");
            providers = Array.isArray(parsed) ? parsed : [];
            if (!activeProvider || !activeEntry()) {
                pickDefaultProvider();
            }
        } catch (e) {
            providers = [];
            activeProvider = "";
        }
    }

    function refresh() {
        refreshing = true;
        barSource.connectSource(shellCommand);
    }

    function parseState(stdout) {
        try {
            var parsed = JSON.parse(stdout.trim() || "{}");
            barProvider = parsed.barProvider || "";
            resetFormat = parsed.resetTimeFormat || "provider";
        } catch (e) {
            barProvider = "";
            resetFormat = "provider";
        }
    }

    function writeState(provider, reset) {
        barProvider = provider || "";
        resetFormat = reset || "provider";
        var command = "bash -lc 'dir=\"${XDG_CONFIG_HOME:-$HOME/.config}/codexbar-waybar\"; "
            + "mkdir -p \"$dir\"; file=\"$dir/state.json\"; "
            + "jq -n --arg p \"" + barProvider + "\" --arg r \"" + resetFormat + "\" "
            + "\"{barProvider:(if \\$p == \\\"\\\" then null else \\$p end), "
            + "resetTimeFormat:(if \\$r == \\\"provider\\\" then null else \\$r end)} "
            + "| with_entries(select(.value != null))\" > \"$file\"'";
        settingsSource.connectSource(command);
    }

    function openCodexBarConfig() {
        settingsSource.connectSource("bash -lc 'mkdir -p \"$HOME/.codexbar\"; touch \"$HOME/.codexbar/config.json\"; xdg-open \"$HOME/.codexbar/config.json\" >/dev/null 2>&1 || true'");
    }

    Component.onCompleted: stateSource.connectSource("bash -lc 'cat \"${XDG_CONFIG_HOME:-$HOME/.config}/codexbar-waybar/state.json\" 2>/dev/null || printf \"{}\"'")

    Timer {
        interval: 30000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Plasma5Support.DataSource {
        id: barSource
        engine: "executable"
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            refreshing = false;
            root.parseBarOutput(data.stdout || "");
            cacheSource.connectSource(root.cacheCommand);
        }
    }

    Plasma5Support.DataSource {
        id: cacheSource
        engine: "executable"
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            root.parseProviders(data.stdout || "[]");
        }
    }

    Plasma5Support.DataSource {
        id: stateSource
        engine: "executable"
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            root.parseState(data.stdout || "{}");
        }
    }

    Plasma5Support.DataSource {
        id: settingsSource
        engine: "executable"
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            stateSource.connectSource("bash -lc 'cat \"${XDG_CONFIG_HOME:-$HOME/.config}/codexbar-waybar/state.json\" 2>/dev/null || printf \"{}\"'");
            root.refresh();
        }
    }

    compactRepresentation: MouseArea {
        id: compact
        implicitWidth: compactRow.implicitWidth + Kirigami.Units.largeSpacing
        implicitHeight: Kirigami.Units.gridUnit
        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.maximumWidth: implicitWidth
        Layout.minimumHeight: implicitHeight
        Layout.preferredHeight: implicitHeight
        clip: true
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        property var entry: panelEntry()
        property bool hasSessionWeekly: windowPercent(entry, "primary") >= 0 || windowPercent(entry, "secondary") >= 0
        property color fillColor: statusColor(barData.className)

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Kirigami.Units.smallSpacing
            color: compact.containsMouse ? Kirigami.Theme.hoverColor : "transparent"
            opacity: compact.containsMouse ? 0.25 : 0
        }

        RowLayout {
            id: compactRow
            anchors {
                fill: parent
                leftMargin: Kirigami.Units.smallSpacing
                rightMargin: Kirigami.Units.smallSpacing
            }
            clip: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: "🤖"
                textFormat: Text.PlainText
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.05
                verticalAlignment: Text.AlignVCenter
                maximumLineCount: 1
                Layout.fillWidth: false
            }

            PlasmaComponents.Label {
                text: compact.hasSessionWeekly ? compactWindowText(compact.entry, "primary", "S") : barData.text.replace("🤖", "AI")
                textFormat: Text.PlainText
                font.weight: Font.DemiBold
                color: compact.fillColor
                verticalAlignment: Text.AlignVCenter
                maximumLineCount: 1
                elide: Text.ElideRight
                Layout.fillWidth: false
                Layout.maximumWidth: Kirigami.Units.gridUnit * 4
            }

            PlasmaComponents.Label {
                visible: compact.hasSessionWeekly
                text: compactWindowText(compact.entry, "secondary", "W")
                textFormat: Text.PlainText
                font.weight: Font.DemiBold
                color: Kirigami.Theme.textColor
                verticalAlignment: Text.AlignVCenter
                maximumLineCount: 1
                elide: Text.ElideRight
                Layout.fillWidth: false
                Layout.maximumWidth: Kirigami.Units.gridUnit * 4
            }
        }
    }

    fullRepresentation: Item {
        id: popup
        implicitWidth: Kirigami.Units.gridUnit * 23
        implicitHeight: Kirigami.Units.gridUnit * 26

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: "CodexBar"
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.35
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }

                QQC2.ToolButton {
                    icon.name: "view-refresh"
                    enabled: !refreshing
                    onClicked: root.refresh()
                    QQC2.ToolTip.text: "Refresh"
                    QQC2.ToolTip.visible: hovered
                }

                QQC2.ToolButton {
                    icon.name: settingsOpen ? "go-previous" : "configure"
                    onClicked: settingsOpen = !settingsOpen
                    QQC2.ToolTip.text: settingsOpen ? "Back" : "Settings"
                    QQC2.ToolTip.visible: hovered
                }
            }

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                contentWidth: tabRow.implicitWidth
                clip: true

                RowLayout {
                    id: tabRow
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: providers
                        delegate: QQC2.Button {
                            required property var modelData
                            text: providerName(modelData.provider)
                            checkable: true
                            checked: modelData.provider === activeProvider
                            icon.source: iconSource(modelData.provider)
                            onClicked: activeProvider = modelData.provider
                        }
                    }
                }
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: settingsOpen ? settingsView : providers.length ? providerView : emptyView
            }
        }

        Component {
            id: emptyView

            PlasmaComponents.Label {
                text: refreshing ? "Loading usage..." : "No provider data"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: Kirigami.Theme.disabledTextColor
            }
        }

        Component {
            id: settingsView

            ColumnLayout {
                spacing: Kirigami.Units.largeSpacing

                PlasmaComponents.Label {
                    text: "Show in panel"
                    font.weight: Font.DemiBold
                }

                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                    contentWidth: panelProviderRow.implicitWidth
                    clip: true

                    RowLayout {
                        id: panelProviderRow
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Button {
                            text: "Highest"
                            checkable: true
                            checked: barProvider === ""
                            onClicked: writeState("", resetFormat)
                        }

                        Repeater {
                            model: providers
                            delegate: QQC2.Button {
                                required property var modelData
                                text: providerName(modelData.provider)
                                icon.source: iconSource(modelData.provider)
                                checkable: true
                                checked: barProvider === modelData.provider
                                onClicked: writeState(modelData.provider, resetFormat)
                            }
                        }
                    }
                }

                PlasmaComponents.Label {
                    text: "Reset times"
                    font.weight: Font.DemiBold
                }

                RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: [
                            { id: "provider", label: "Provider" },
                            { id: "local", label: "Local" },
                            { id: "utc", label: "UTC" }
                        ]

                        delegate: QQC2.Button {
                            required property var modelData
                            text: modelData.label
                            checkable: true
                            checked: resetFormat === modelData.id
                            onClicked: writeState(barProvider, modelData.id)
                        }
                    }
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: "Providers are read from ~/.codexbar/config.json."
                    color: Kirigami.Theme.disabledTextColor
                    wrapMode: Text.WordWrap
                }

                QQC2.Button {
                    text: "Open provider config"
                    icon.name: "document-edit"
                    onClicked: openCodexBarConfig()
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }

        Component {
            id: providerView

            ColumnLayout {
                id: providerColumn
                spacing: Kirigami.Units.largeSpacing

                property var entry: activeEntry()
                property var usage: entry && entry.usage ? entry.usage : ({})
                property var openAITotal: openAITotals(usage)

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        PlasmaComponents.Label {
                            text: providerName(providerColumn.entry.provider)
                            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.25
                            font.weight: Font.Bold
                        }

                        PlasmaComponents.Label {
                            text: providerColumn.entry && providerColumn.entry.stale ? "Cached - last refresh failed"
                                : providerColumn.entry && providerColumn.entry.error ? "Refresh failed"
                                : "Updated just now"
                            color: Kirigami.Theme.disabledTextColor
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        }
                    }

                    Kirigami.Icon {
                        source: iconSource(providerColumn.entry.provider)
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                    }
                }

                PlasmaComponents.Label {
                    visible: providerColumn.entry && providerColumn.entry.error
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Kirigami.Theme.negativeTextColor
                    text: providerColumn.entry && providerColumn.entry.error ? providerColumn.entry.error.message || "Unknown error" : ""
                }

                ColumnLayout {
                    visible: hasQuotaRows(providerColumn.usage) && !providerColumn.entry.error
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
                        text: "Quota"
                        font.weight: Font.DemiBold
                    }

                    Repeater {
                        model: [
                            { key: "primary", title: "Session" },
                            { key: "secondary", title: "Weekly" },
                            { key: "tertiary", title: "Monthly" }
                        ]

                        delegate: ColumnLayout {
                            required property var modelData
                            visible: providerColumn.usage && providerColumn.usage[modelData.key]
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            property var windowData: providerColumn.usage ? providerColumn.usage[modelData.key] : null
                            property real usedPct: usedPercent(windowData)
                            property real leftPct: remainingPercent(windowData)

                            RowLayout {
                                Layout.fillWidth: true

                                PlasmaComponents.Label {
                                    text: modelData.title
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                }

                                PlasmaComponents.Label {
                                    text: leftPct >= 0 ? Math.floor(leftPct) + "% left" : "--"
                                    color: usedPct >= 90 ? Kirigami.Theme.negativeTextColor
                                        : usedPct >= 70 ? Kirigami.Theme.neutralTextColor
                                        : Kirigami.Theme.textColor
                                }
                            }

                            UsageBar {
                                percent: leftPct >= 0 ? leftPct : 0
                                accentColor: percentColor(usedPct)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents.Label {
                                    text: usedPct >= 0 ? "Used " + Math.floor(usedPct) + "%" : ""
                                    visible: text.length > 0
                                    color: Kirigami.Theme.disabledTextColor
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                }

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: windowData && windowData.resetDescription ? windowData.resetDescription : ""
                                    visible: text.length > 0
                                    horizontalAlignment: Text.AlignRight
                                    color: Kirigami.Theme.disabledTextColor
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    visible: hasOpenAIUsage(providerColumn.usage) && !providerColumn.entry.error
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
                        text: "Usage summary"
                        font.weight: Font.DemiBold
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Kirigami.Units.largeSpacing
                        rowSpacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            text: "Cost"
                            color: Kirigami.Theme.disabledTextColor
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: providerColumn.usage.providerCost
                                ? formatMoney(providerColumn.usage.providerCost.used) + " - " + (providerColumn.usage.providerCost.period || "current period")
                                : formatMoney(providerColumn.openAITotal.costUSD)
                        }

                        PlasmaComponents.Label {
                            text: "Requests"
                            color: Kirigami.Theme.disabledTextColor
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: compactNumber(providerColumn.openAITotal.requests)
                        }

                        PlasmaComponents.Label {
                            text: "Tokens"
                            color: Kirigami.Theme.disabledTextColor
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: compactNumber(providerColumn.openAITotal.totalTokens)
                        }

                        PlasmaComponents.Label {
                            text: "Cached input"
                            color: Kirigami.Theme.disabledTextColor
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: compactNumber(providerColumn.openAITotal.cachedInputTokens)
                        }
                    }

                    UsageBar {
                        visible: providerColumn.usage.providerCost
                            && providerColumn.usage.providerCost.limit
                            && providerColumn.usage.providerCost.limit > 0
                        percent: providerColumn.usage.providerCost
                            ? boundedPercent(100 - ((providerColumn.usage.providerCost.used / providerColumn.usage.providerCost.limit) * 100))
                            : 0
                        accentColor: percentColor(providerColumn.usage.providerCost
                            ? (providerColumn.usage.providerCost.used / providerColumn.usage.providerCost.limit) * 100
                            : 0)
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        visible: providerColumn.usage.updatedAt
                        text: providerColumn.usage.updatedAt ? "Updated " + providerColumn.usage.updatedAt : ""
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        elide: Text.ElideRight
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }
}
