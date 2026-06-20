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
    property string configProviderScriptPath: packagePath + "/scripts/codexbar-config-provider.sh"
    property string shellCommand: "CODEXBAR_PLASMA=1 \"" + scriptPath + "\""
    property string cacheCommand: "bash -lc 'cat \"${XDG_CACHE_HOME:-$HOME/.cache}/codexbar-waybar/last.json\" 2>/dev/null || printf \"[]\"'"
    property var barData: ({ text: "AI --", tooltip: "CodexBar: loading", className: "stale", percentage: 0 })
    property var providers: []
    property var configProviders: []
    property string activeProvider: ""
    property string barProvider: ""
    property string resetFormat: "provider"
    property bool refreshing: false
    property bool settingsOpen: false
    property bool configProvidersLoading: false
    property color surfaceColor: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.92)
    property color raisedSurfaceColor: Qt.rgba(Kirigami.Theme.alternateBackgroundColor.r, Kirigami.Theme.alternateBackgroundColor.g, Kirigami.Theme.alternateBackgroundColor.b, 0.68)
    property color subtleBorderColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
    property color mutedTextColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.62)
    property color faintTextColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.42)

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

    function codexbarCommand(args) {
        return "bash -lc 'bin=\"${CODEXBAR_BIN:-$HOME/.local/bin/codexbar}\"; "
            + "if [ -x \"$bin\" ]; then \"$bin\" " + args + "; "
            + "else codexbar " + args + "; fi'";
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

    function hasCostUsage(cost) {
        return !!(cost && (typeof cost.sessionCostUSD === "number"
            || typeof cost.last30DaysCostUSD === "number"
            || (cost.daily && cost.daily.length > 0)));
    }

    function costDailyRows(cost) {
        var daily = cost && cost.daily ? cost.daily : [];
        return daily.slice().reverse().slice(0, 5);
    }

    function costTrendRows(cost) {
        var daily = cost && cost.daily ? cost.daily : [];
        return daily.slice().slice(-30);
    }

    function maxDailyCost(cost) {
        var daily = cost && cost.daily ? cost.daily : [];
        var maxValue = 0;
        for (var i = 0; i < daily.length; i++) {
            var value = daily[i].totalCost || 0;
            if (value > maxValue) {
                maxValue = value;
            }
        }
        return maxValue;
    }

    function maxDailyTokens(cost) {
        var daily = cost && cost.daily ? cost.daily : [];
        var maxValue = 0;
        for (var i = 0; i < daily.length; i++) {
            var value = daily[i].totalTokens || 0;
            if (value > maxValue) {
                maxValue = value;
            }
        }
        return maxValue;
    }

    function latestDaily(cost) {
        var daily = cost && cost.daily ? cost.daily : [];
        return daily.length > 0 ? daily[daily.length - 1] : null;
    }

    function latestDailyCost(cost) {
        if (!cost) {
            return null;
        }
        var latest = latestDaily(cost);
        if (latest && typeof latest.totalCost === "number") {
            return latest.totalCost;
        }
        return typeof cost.sessionCostUSD === "number" ? cost.sessionCostUSD : null;
    }

    function latestDailyTokens(cost) {
        if (!cost) {
            return null;
        }
        var latest = latestDaily(cost);
        if (latest && typeof latest.totalTokens === "number") {
            return latest.totalTokens;
        }
        return typeof cost.sessionTokens === "number" ? cost.sessionTokens : null;
    }

    function shortDate(value) {
        if (!value || value.length < 10) {
            return "";
        }
        var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        var month = Number(value.slice(5, 7)) - 1;
        var day = Number(value.slice(8, 10));
        if (month < 0 || month > 11 || !day) {
            return value.slice(5, 10);
        }
        return months[month] + " " + day;
    }

    function hasOpenAIUsage(usage) {
        return !!(usage && (usage.providerCost || usage.openAIAPIUsage));
    }

    function accountEmail(usage) {
        var identity = usage && usage.identity ? usage.identity : null;
        return usage && usage.accountEmail ? usage.accountEmail
            : identity && identity.accountEmail ? identity.accountEmail
            : "";
    }

    function loginMethod(usage) {
        var identity = usage && usage.identity ? usage.identity : null;
        var value = usage && usage.loginMethod ? usage.loginMethod
            : identity && identity.loginMethod ? identity.loginMethod
            : "";
        return value ? value.charAt(0).toUpperCase() + value.slice(1) : "";
    }

    function providerUpdateText(entry) {
        return entry && entry.stale ? "Cached - last refresh failed"
            : entry && entry.error ? "Refresh failed"
            : "Updated just now";
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

    function quotaStatus(windowData) {
        var deficit = deficitPercent(windowData);
        var used = usedPercent(windowData);
        if (deficit > 0) {
            return "In deficit";
        }
        if (used >= 90) {
            return "Critical";
        }
        if (used >= 70) {
            return "Attention";
        }
        return "Healthy";
    }

    function reservePercent(windowData) {
        if (!windowData) {
            return 0;
        }
        var keys = ["reservePercent", "inReservePercent", "reservedPercent"];
        for (var i = 0; i < keys.length; i++) {
            if (typeof windowData[keys[i]] === "number") {
                return boundedPercent(windowData[keys[i]]);
            }
        }
        return 0;
    }

    function deficitPercent(windowData) {
        if (!windowData) {
            return 0;
        }
        var keys = ["deficitPercent", "overagePercent", "exceededPercent"];
        for (var i = 0; i < keys.length; i++) {
            if (typeof windowData[keys[i]] === "number") {
                return Math.max(0, Number(windowData[keys[i]]) || 0);
            }
        }
        return 0;
    }

    component MetricTile: Rectangle {
        property string title: ""
        property string value: "--"
        property string detail: ""

        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.gridUnit * 3.6
        radius: 6
        color: root.raisedSurfaceColor
        border.width: 1
        border.color: root.subtleBorderColor

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing * 1.5
            spacing: 2

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: title
                color: root.mutedTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: value
                color: Kirigami.Theme.textColor
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.22
                font.weight: Font.Bold
                elide: Text.ElideRight
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: detail
                visible: detail.length > 0
                color: root.mutedTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                elide: Text.ElideRight
            }
        }
    }

    component UsageBar: Item {
        property real percent: 0
        property color accentColor: Kirigami.Theme.positiveTextColor
        property real reservePercent: 0
        property real deficitPercent: 0

        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.smallSpacing * 1.45

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.subtleBorderColor
        }

        Rectangle {
            id: usedFill
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

        Rectangle {
            visible: reservePercent > 0
            anchors {
                left: usedFill.right
                top: parent.top
                bottom: parent.bottom
            }
            width: parent.width * Math.max(0, Math.min(100 - boundedPercent(percent), boundedPercent(reservePercent))) / 100
            radius: height / 2
            color: "#5ac8d8"
            opacity: 0.82
        }

        Rectangle {
            visible: deficitPercent > 0
            anchors {
                right: parent.right
                top: parent.top
                bottom: parent.bottom
            }
            width: parent.width * Math.min(100, deficitPercent) / 100
            radius: height / 2
            color: Kirigami.Theme.negativeTextColor
            opacity: 0.9
        }
    }

    component QuotaCard: Rectangle {
        property string title: ""
        property var windowData: null
        property real usedPct: usedPercent(windowData)
        property real leftPct: remainingPercent(windowData)
        property real reservePct: reservePercent(windowData)
        property real deficitPct: deficitPercent(windowData)

        Layout.fillWidth: true
        implicitHeight: quotaCardColumn.implicitHeight + Kirigami.Units.smallSpacing * 3
        radius: 6
        color: root.raisedSurfaceColor
        border.width: 1
        border.color: root.subtleBorderColor

        ColumnLayout {
            id: quotaCardColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Kirigami.Units.smallSpacing * 1.5
            }
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: title
                    color: Kirigami.Theme.textColor
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label {
                    text: leftPct >= 0 ? Math.floor(leftPct) + "% left" : "--"
                    color: percentColor(usedPct)
                    font.weight: Font.Bold
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: usedPct >= 0 ? "Used " + Math.floor(usedPct) + "%" : "Usage unknown"
                    color: root.mutedTextColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }

                PlasmaComponents.Label {
                    visible: reservePct > 0
                    text: "Reserve " + Math.floor(reservePct) + "%"
                    color: "#5ac8d8"
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }

                PlasmaComponents.Label {
                    visible: deficitPct > 0
                    text: "Deficit " + Math.floor(deficitPct) + "%"
                    color: Kirigami.Theme.negativeTextColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: quotaStatus(windowData)
                    color: percentColor(usedPct)
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    elide: Text.ElideRight
                }
            }

            UsageBar {
                percent: usedPct >= 0 ? usedPct : 0
                reservePercent: reservePct
                deficitPercent: deficitPct
                accentColor: percentColor(usedPct)
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: windowData && windowData.resetDescription ? "Resets " + windowData.resetDescription : ""
                visible: text.length > 0
                color: root.mutedTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }
    }

    component ProviderTab: Item {
        property string providerId: ""
        property string label: ""
        property bool selected: false

        implicitWidth: tabInner.implicitWidth + Kirigami.Units.largeSpacing * 1.35
        implicitHeight: Kirigami.Units.gridUnit * 1.45

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: selected ? Kirigami.Theme.highlightColor : tabMouse.containsMouse ? root.raisedSurfaceColor : "transparent"
            border.width: 1
            border.color: selected ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.8) : root.subtleBorderColor
            opacity: selected ? 0.92 : 1
        }

        MouseArea {
            id: tabMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: activeProvider = providerId
        }

        RowLayout {
            id: tabInner
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: iconSource(providerId)
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
            }

            PlasmaComponents.Label {
                text: label
                color: selected ? Kirigami.Theme.highlightedTextColor : root.mutedTextColor
                font.weight: selected ? Font.DemiBold : Font.Normal
            }
        }
    }

    component ProviderToggleRow: Item {
        property string providerId: ""
        property string label: providerName(providerId)
        property bool providerEnabled: false

        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.gridUnit * 2.05

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: providerEnabled ? Qt.rgba(0.06, 0.73, 0.51, 0.14) : toggleHover.containsMouse ? root.raisedSurfaceColor : "transparent"
            border.width: 1
            border.color: providerEnabled ? "#10B981" : root.subtleBorderColor
        }

        MouseArea {
            id: toggleHover
            anchors.fill: parent
            hoverEnabled: true
        }

        RowLayout {
            id: toggleRow
            anchors {
                fill: parent
                leftMargin: Kirigami.Units.smallSpacing * 1.5
                rightMargin: Kirigami.Units.smallSpacing * 1.5
                topMargin: 2
                bottomMargin: 2
            }
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: iconSource(providerId)
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
                Layout.alignment: Qt.AlignVCenter
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: label
                color: providerEnabled ? "#d1fae5" : root.mutedTextColor
                font.weight: providerEnabled ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }

            Item {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                Layout.fillWidth: false
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.4
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.2

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: providerEnabled ? "#10B981" : "#3a4260"
                    border.width: 1
                    border.color: providerEnabled ? "#34D399" : "#4b5572"
                }

                Rectangle {
                    width: parent.height - 6
                    height: parent.height - 6
                    radius: height / 2
                    y: 3
                    x: providerEnabled ? parent.width - width - 3 : 3
                    color: providerEnabled ? "#ecfdf5" : "#c8d0e6"

                    Behavior on x {
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: setProviderEnabled(providerId, !providerEnabled)
                }
            }
        }
    }

    component ProviderPill: Item {
        property string providerId: ""
        property string label: ""
        property bool selected: false

        implicitWidth: pillRow.implicitWidth + Kirigami.Units.largeSpacing
        implicitHeight: Kirigami.Units.gridUnit * 1.45

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: selected ? Kirigami.Theme.highlightColor : "transparent"
            border.width: 1
            border.color: selected ? Kirigami.Theme.highlightColor : root.subtleBorderColor
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: writeState(providerId, resetFormat)
        }

        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                visible: providerId !== ""
                source: iconSource(providerId)
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
            }

            PlasmaComponents.Label {
                text: label
                color: selected ? Kirigami.Theme.highlightedTextColor : root.mutedTextColor
                font.weight: selected ? Font.DemiBold : Font.Normal
            }
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

    function configProviderEntry(pid) {
        for (var i = 0; i < configProviders.length; i++) {
            if (configProviders[i].provider === pid) {
                return configProviders[i];
            }
        }
        return null;
    }

    function configProviderEnabled(pid) {
        var entry = configProviderEntry(pid);
        return !!(entry && entry.enabled);
    }

    function configProviderDisplayName(pid) {
        var entry = configProviderEntry(pid);
        return entry && entry.displayName ? entry.displayName : providerName(pid);
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

    function parseConfigProviders(stdout) {
        configProvidersLoading = false;
        try {
            var parsed = JSON.parse(stdout.trim() || "[]");
            configProviders = Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            configProviders = [];
        }
    }

    function refresh() {
        refreshing = true;
        barSource.connectSource(shellCommand);
    }

    function refreshConfigProviders() {
        configProvidersLoading = true;
        configProvidersSource.connectSource(codexbarCommand("config providers --json"));
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
        settingsSource.connectSource("bash -lc 'dir=\"${XDG_CONFIG_HOME:-$HOME/.config}/codexbar\"; mkdir -p \"$dir\"; touch \"$dir/config.json\"; xdg-open \"$dir/config.json\" >/dev/null 2>&1 || true'");
    }

    function setProviderEnabled(provider, enabled) {
        providerToggleSource.connectSource("bash -lc '\"" + configProviderScriptPath + "\" " + provider + " " + (enabled ? "true" : "false") + "'");
    }

    Component.onCompleted: {
        stateSource.connectSource("bash -lc 'cat \"${XDG_CONFIG_HOME:-$HOME/.config}/codexbar-waybar/state.json\" 2>/dev/null || printf \"{}\"'");
        refreshConfigProviders();
    }

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

    Plasma5Support.DataSource {
        id: configProvidersSource
        engine: "executable"
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            root.parseConfigProviders(data.stdout || "[]");
        }
    }

    Plasma5Support.DataSource {
        id: providerToggleSource
        engine: "executable"
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            root.refreshConfigProviders();
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

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: root.surfaceColor
            border.width: 1
            border.color: root.subtleBorderColor
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing * 1.5

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: "CodexBar"
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.18
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }

                QQC2.ToolButton {
                    implicitWidth: Kirigami.Units.gridUnit * 1.55
                    implicitHeight: Kirigami.Units.gridUnit * 1.55
                    icon.name: "view-refresh"
                    enabled: !refreshing
                    onClicked: root.refresh()
                    QQC2.ToolTip.text: "Refresh"
                    QQC2.ToolTip.visible: hovered
                }

                QQC2.ToolButton {
                    implicitWidth: Kirigami.Units.gridUnit * 1.55
                    implicitHeight: Kirigami.Units.gridUnit * 1.55
                    icon.name: settingsOpen ? "go-previous" : "configure"
                    onClicked: settingsOpen = !settingsOpen
                    QQC2.ToolTip.text: settingsOpen ? "Back" : "Settings"
                    QQC2.ToolTip.visible: hovered
                }
            }

            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.8
                contentWidth: tabRow.implicitWidth
                clip: true

                background: Rectangle {
                    radius: 7
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                    border.width: 1
                    border.color: root.subtleBorderColor
                }

                RowLayout {
                    id: tabRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: providers
                        delegate: ProviderTab {
                            required property var modelData
                            providerId: modelData.provider
                            label: providerName(modelData.provider)
                            selected: modelData.provider === activeProvider
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

            Item {
                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: "transparent"
                    border.width: 1
                    border.color: root.subtleBorderColor
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing * 1.5
                    spacing: Kirigami.Units.smallSpacing * 1.5

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            PlasmaComponents.Label {
                                text: "Provedores"
                                color: Kirigami.Theme.textColor
                                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.12
                                font.weight: Font.Bold
                            }

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: "Alterne quais provedores alimentam a barra e o pop-up."
                                color: root.mutedTextColor
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                wrapMode: Text.WordWrap
                            }
                        }

                        QQC2.ToolButton {
                            implicitWidth: Kirigami.Units.gridUnit * 1.55
                            implicitHeight: Kirigami.Units.gridUnit * 1.55
                            icon.name: "view-refresh"
                            enabled: !configProvidersLoading
                            onClicked: refreshConfigProviders()
                            QQC2.ToolTip.text: "Atualizar provedores"
                            QQC2.ToolTip.visible: hovered
                        }
                    }

                    QQC2.ScrollView {
                        id: providerListScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: availableWidth
                        clip: true

                        ColumnLayout {
                            id: providerListColumn
                            width: Math.max(0, providerListScroll.availableWidth - 2)
                            spacing: Kirigami.Units.smallSpacing

                            PlasmaComponents.Label {
                                visible: configProvidersLoading || configProviders.length === 0
                                Layout.fillWidth: true
                                text: configProvidersLoading ? "Carregando provedores..." : "Nenhum provedor encontrado"
                                color: root.mutedTextColor
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            }

                            Repeater {
                                model: configProviders

                                delegate: ProviderToggleRow {
                                    required property var modelData
                                    width: providerListColumn.width
                                    Layout.preferredWidth: providerListColumn.width
                                    providerId: modelData.provider
                                    label: modelData.displayName || providerName(modelData.provider)
                                    providerEnabled: !!modelData.enabled
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            text: "Seleção de modelo padrão"
                            color: Kirigami.Theme.textColor
                            font.weight: Font.DemiBold
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            Repeater {
                                model: [
                                    { id: "", label: "Highest" },
                                    { id: "codex", label: "Codex" },
                                    { id: "gemini", label: "Gemini" },
                                    { id: "openai", label: "OpenAI" }
                                ]

                                delegate: ProviderPill {
                                    required property var modelData
                                    providerId: modelData.id
                                    label: modelData.label
                                    selected: barProvider === modelData.id
                                }
                            }
                        }
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: "~/.config/codexbar/config.json"
                        color: root.faintTextColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Component {
            id: providerView

            QQC2.ScrollView {
                id: providerScroll
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    id: providerColumn
                    width: Math.max(0, providerScroll.availableWidth - 2)
                    spacing: Kirigami.Units.largeSpacing

                property var entry: activeEntry()
                property var usage: entry && entry.usage ? entry.usage : ({})
                property var cost: entry && entry.cost ? entry.cost : null
                property var openAITotal: openAITotals(usage)
                property var latestCostDay: latestDaily(cost)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        visible: providerColumn.entry
                        source: providerColumn.entry ? iconSource(providerColumn.entry.provider) : ""
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: Kirigami.Units.iconSizes.smallMedium
                        Layout.alignment: Qt.AlignTop
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: providerColumn.entry ? providerName(providerColumn.entry.provider) : "Provider"
                            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.2
                            font.weight: Font.Bold
                            color: Kirigami.Theme.textColor
                            elide: Text.ElideRight
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: providerUpdateText(providerColumn.entry)
                            color: root.mutedTextColor
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            elide: Text.ElideRight
                        }
                    }

                    ColumnLayout {
                        visible: accountEmail(providerColumn.usage).length > 0 || loginMethod(providerColumn.usage).length > 0
                        Layout.fillWidth: true
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 10
                        spacing: 0

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: accountEmail(providerColumn.usage)
                            color: Kirigami.Theme.textColor
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            visible: loginMethod(providerColumn.usage).length > 0
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: planLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.05
                            radius: 5
                            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.16)
                            border.width: 1
                            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.3)

                            PlasmaComponents.Label {
                                id: planLabel
                                anchors.centerIn: parent
                                text: loginMethod(providerColumn.usage)
                                color: Kirigami.Theme.highlightColor
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                font.weight: Font.DemiBold
                            }
                        }

                        PlasmaComponents.Label {
                            visible: false
                            Layout.fillWidth: true
                            text: loginMethod(providerColumn.usage)
                            color: root.mutedTextColor
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                        }
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
                        color: Kirigami.Theme.textColor
                    }

                    Repeater {
                        model: [
                            { key: "primary", title: "Session" },
                            { key: "secondary", title: "Weekly" },
                            { key: "tertiary", title: "Monthly" }
                        ]

                        delegate: QuotaCard {
                            required property var modelData
                            visible: providerColumn.usage && providerColumn.usage[modelData.key]
                            Layout.fillWidth: true
                            title: modelData.title
                            windowData: providerColumn.usage ? providerColumn.usage[modelData.key] : null
                        }
                    }
                }

                ColumnLayout {
                    visible: hasCostUsage(providerColumn.cost) && !providerColumn.entry.error
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
                        text: "Cost"
                        font.weight: Font.DemiBold
                        color: Kirigami.Theme.textColor
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Kirigami.Units.largeSpacing
                        rowSpacing: Kirigami.Units.smallSpacing

                        MetricTile {
                            title: "Today"
                            value: typeof latestDailyCost(providerColumn.cost) === "number"
                                ? formatMoney(latestDailyCost(providerColumn.cost))
                                : "--"
                            detail: typeof latestDailyTokens(providerColumn.cost) === "number"
                                ? compactNumber(latestDailyTokens(providerColumn.cost)) + " tokens"
                                : ""
                        }

                        MetricTile {
                            title: providerColumn.cost.historyDays ? providerColumn.cost.historyDays + "d cost" : "30d cost"
                            value: typeof providerColumn.cost.last30DaysCostUSD === "number"
                                ? formatMoney(providerColumn.cost.last30DaysCostUSD)
                                : (providerColumn.cost.totals && typeof providerColumn.cost.totals.totalCost === "number"
                                    ? formatMoney(providerColumn.cost.totals.totalCost)
                                    : "--")
                            detail: typeof providerColumn.cost.last30DaysTokens === "number"
                                ? compactNumber(providerColumn.cost.last30DaysTokens) + " tokens"
                                : (providerColumn.cost.totals && typeof providerColumn.cost.totals.totalTokens === "number"
                                    ? compactNumber(providerColumn.cost.totals.totalTokens) + " tokens"
                                    : "")
                        }
                    }

                    ColumnLayout {
                        visible: providerColumn.cost.daily && providerColumn.cost.daily.length > 0
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: "Usage trend"
                            color: root.mutedTextColor
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            font.weight: Font.DemiBold
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.75
                            spacing: 2

                            Repeater {
                                model: costTrendRows(providerColumn.cost)

                                delegate: Item {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    property real maxTokens: maxDailyTokens(providerColumn.cost)
                                    property real tokenPct: maxTokens > 0 ? (modelData.totalTokens || 0) / maxTokens : 0

                                    Rectangle {
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            bottom: parent.bottom
                                        }
                                        height: Math.max(3, parent.height * tokenPct)
                                        radius: 2
                                        color: "#d89a3a"
                                        opacity: 0.84
                                    }
                                }
                            }
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: providerColumn.cost.daily.length ? "Latest: " + shortDate(providerColumn.cost.daily[providerColumn.cost.daily.length - 1].date) : ""
                            color: root.faintTextColor
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            horizontalAlignment: Text.AlignRight
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: "Recent days"
                            color: Kirigami.Theme.textColor
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: costDailyRows(providerColumn.cost)

                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 2

                                property real maxCost: maxDailyCost(providerColumn.cost)
                                property real dayCost: modelData.totalCost || 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing

                                    PlasmaComponents.Label {
                                        text: shortDate(modelData.date)
                                        color: Kirigami.Theme.disabledTextColor
                                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    }

                                    PlasmaComponents.Label {
                                        Layout.fillWidth: true
                                        text: compactNumber(modelData.totalTokens || 0) + " tokens"
                                        color: Kirigami.Theme.disabledTextColor
                                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                        elide: Text.ElideRight
                                    }

                                    PlasmaComponents.Label {
                                        text: formatMoney(dayCost)
                                        color: Kirigami.Theme.textColor
                                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    }
                                }

                                UsageBar {
                                    percent: maxCost > 0 ? (dayCost / maxCost) * 100 : 0
                                    accentColor: "#34D399"
                                }
                            }
                        }
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        visible: providerColumn.cost.daily && providerColumn.cost.daily.length === 0
                        text: "No daily cost data for this period"
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        elide: Text.ElideRight
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
                            ? boundedPercent((providerColumn.usage.providerCost.used / providerColumn.usage.providerCost.limit) * 100)
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
}
