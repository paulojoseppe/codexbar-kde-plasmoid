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
    property string incidentsScriptPath: packagePath + "/scripts/codexbar-incidents.py"
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
    property bool incidentsOpen: false
    property bool configProvidersLoading: false
    property bool incidentsLoading: false
    property var incidents: []
    property string incidentsError: ""
    property color surfaceColor: "#111827"
    property color raisedSurfaceColor: "#1B2638"
    property color elevatedSurfaceColor: "#222E42"
    property color subtleBorderColor: "#344158"
    property color textColor: "#F8FAFC"
    property color mutedTextColor: "#A8B3C7"
    property color faintTextColor: "#6F7D93"
    property color healthyColor: "#2DD4BF"
    property color costColor: "#FB923C"
    property color criticalColor: "#F87171"

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

    function incidentDate(value) {
        if (!value) {
            return "";
        }
        var date = new Date(value);
        return isNaN(date.getTime()) ? value : Qt.formatDateTime(date, "dd MMM · HH:mm");
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
            return root.criticalColor;
        }
        if (className === "warning") {
            return root.costColor;
        }
        if (className === "stale") {
            return root.faintTextColor;
        }
        return root.healthyColor;
    }

    function percentColor(pct) {
        if (pct >= 90) {
            return root.criticalColor;
        }
        if (pct >= 70) {
            return root.costColor;
        }
        return root.healthyColor;
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

    component CostCard: Rectangle {
        property string title: ""
        property string value: "--"
        property string detail: ""
        property color accentColor: root.costColor

        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.gridUnit * 4.35
        radius: 8
        color: root.raisedSurfaceColor
        border.width: 1
        border.color: root.subtleBorderColor

        Rectangle {
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: 3
            radius: 2
            color: accentColor
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: Kirigami.Units.largeSpacing
            anchors.rightMargin: Kirigami.Units.largeSpacing
            anchors.topMargin: Kirigami.Units.smallSpacing * 1.6
            anchors.bottomMargin: Kirigami.Units.smallSpacing * 1.6
            spacing: 3

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
                color: root.textColor
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.55
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
        property color accentColor: root.healthyColor
        property real reservePercent: 0
        property real deficitPercent: 0

        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.smallSpacing * 1.7

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "#29364B"
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
            color: "#67E8F9"
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
            color: root.criticalColor
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
        implicitHeight: quotaCardColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
        radius: 8
        color: root.raisedSurfaceColor
        border.width: 1
        border.color: root.subtleBorderColor

        ColumnLayout {
            id: quotaCardColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Kirigami.Units.largeSpacing
            }
            spacing: Kirigami.Units.smallSpacing * 1.25

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: title
                    color: root.textColor
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.08
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                PlasmaComponents.Label {
                    text: quotaStatus(windowData)
                    color: percentColor(usedPct)
                    font.weight: Font.Bold
                }
            }

            UsageBar {
                percent: usedPct >= 0 ? usedPct : 0
                reservePercent: reservePct
                deficitPercent: deficitPct
                accentColor: percentColor(usedPct)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: leftPct >= 0 ? Math.floor(leftPct) + "% left" : "--"
                    color: root.textColor
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.08
                    font.weight: Font.DemiBold
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: windowData && windowData.resetDescription ? "Resets " + windowData.resetDescription : ""
                    color: root.mutedTextColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    visible: usedPct >= 0
                    text: Math.floor(usedPct) + "% used"
                    color: root.mutedTextColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }

                PlasmaComponents.Label {
                    visible: reservePct > 0
                    text: "· " + Math.floor(reservePct) + "% reserve"
                    color: "#67E8F9"
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }

                PlasmaComponents.Label {
                    visible: deficitPct > 0
                    text: "· " + Math.floor(deficitPct) + "% deficit"
                    color: root.criticalColor
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }

    component ProviderTab: Item {
        property string providerId: ""
        property string label: ""
        property bool selected: false

        implicitWidth: tabInner.implicitWidth + Kirigami.Units.largeSpacing * 1.6
        implicitHeight: Kirigami.Units.gridUnit * 2.2

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: selected ? root.elevatedSurfaceColor : tabMouse.containsMouse ? root.raisedSurfaceColor : "transparent"
            border.width: 1
            border.color: selected ? root.healthyColor : root.subtleBorderColor
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
            spacing: Kirigami.Units.smallSpacing * 1.25

            Kirigami.Icon {
                source: iconSource(providerId)
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                implicitHeight: Kirigami.Units.iconSizes.smallMedium
            }

            PlasmaComponents.Label {
                text: label
                color: selected ? root.textColor : root.mutedTextColor
                font.weight: selected ? Font.Bold : Font.Normal
            }
        }
    }

    component UsageTrendChart: Rectangle {
        property var costData: null
        property var rows: costTrendRows(costData)
        property real highestTokens: maxDailyTokens(costData)
        property real highestCost: maxDailyCost(costData)

        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.gridUnit * 8.4
        radius: 8
        color: root.raisedSurfaceColor
        border.width: 1
        border.color: root.subtleBorderColor

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: "Usage trend"
                    color: root.textColor
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.08
                    font.weight: Font.Bold
                }

                RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    Rectangle {
                        width: 7
                        height: 7
                        radius: 4
                        color: root.healthyColor
                    }

                    PlasmaComponents.Label {
                        text: "Tokens"
                        color: root.mutedTextColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }

                    Rectangle {
                        width: 7
                        height: 7
                        radius: 4
                        color: root.costColor
                    }

                    PlasmaComponents.Label {
                        text: "Cost"
                        color: root.mutedTextColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 3

                Repeater {
                    model: rows

                    delegate: Item {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        property real tokenRatio: highestTokens > 0 ? (modelData.totalTokens || 0) / highestTokens : 0
                        property real costRatio: highestCost > 0 ? (modelData.totalCost || 0) / highestCost : 0

                        Rectangle {
                            anchors {
                                left: parent.left
                                right: parent.horizontalCenter
                                rightMargin: 1
                                bottom: parent.bottom
                            }
                            height: Math.max(3, parent.height * tokenRatio)
                            radius: Math.min(width / 2, 4)
                            color: root.healthyColor
                            opacity: 0.92
                        }

                        Rectangle {
                            anchors {
                                left: parent.horizontalCenter
                                leftMargin: 1
                                right: parent.right
                                bottom: parent.bottom
                            }
                            height: Math.max(3, parent.height * costRatio)
                            radius: Math.min(width / 2, 4)
                            color: root.costColor
                            opacity: 0.92
                        }
                    }
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: rows.length ? shortDate(rows[0].date) + " — " + shortDate(rows[rows.length - 1].date) : ""
                color: root.faintTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                horizontalAlignment: Text.AlignRight
            }
        }
    }

    component RecentDaysList: Rectangle {
        property var costData: null
        property var rows: costDailyRows(costData)
        property real highestCost: maxDailyCost(costData)

        Layout.fillWidth: true
        implicitHeight: recentColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
        radius: 8
        color: root.raisedSurfaceColor
        border.width: 1
        border.color: root.subtleBorderColor

        ColumnLayout {
            id: recentColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Kirigami.Units.largeSpacing
            }
            spacing: Kirigami.Units.smallSpacing * 1.25

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: "Recent days"
                color: root.textColor
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.08
                font.weight: Font.Bold
            }

            Repeater {
                model: rows

                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 4

                    property real dayCost: modelData.totalCost || 0
                    property real dayRatio: highestCost > 0 ? dayCost / highestCost : 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                            text: shortDate(modelData.date)
                            color: root.mutedTextColor
                            font.weight: Font.DemiBold
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: compactNumber(modelData.totalTokens || 0) + " tokens"
                            color: root.faintTextColor
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            elide: Text.ElideRight
                        }

                        PlasmaComponents.Label {
                            text: formatMoney(dayCost)
                            color: root.costColor
                            font.weight: Font.DemiBold
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: Kirigami.Units.smallSpacing * 1.45

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: "#29364B"
                        }

                        Rectangle {
                            anchors {
                                left: parent.left
                                top: parent.top
                                bottom: parent.bottom
                            }
                            width: parent.width * Math.max(0, Math.min(1, dayRatio))
                            radius: height / 2

                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: root.healthyColor }
                                GradientStop { position: 0.62; color: "#67E8F9" }
                                GradientStop { position: 1.0; color: root.costColor }
                            }
                        }
                    }
                }
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
            color: selected ? root.elevatedSurfaceColor : "transparent"
            border.width: 1
            border.color: selected ? root.healthyColor : root.subtleBorderColor
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
                color: selected ? root.textColor : root.mutedTextColor
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

    function parseIncidents(stdout) {
        incidentsLoading = false;
        try {
            var parsed = JSON.parse(stdout.trim() || "{}");
            incidents = Array.isArray(parsed.items) ? parsed.items : [];
            incidentsError = parsed.error || "";
        } catch (e) {
            incidents = [];
            incidentsError = "Não foi possível interpretar o feed de incidentes.";
        }
    }

    function refreshIncidents() {
        incidentsLoading = true;
        incidentsError = "";
        incidentsSource.connectSource("python3 \"" + incidentsScriptPath + "\"");
    }

    function openIncidents() {
        settingsOpen = false;
        incidentsOpen = true;
        refreshIncidents();
    }

    function closeSecondaryPage() {
        settingsOpen = false;
        incidentsOpen = false;
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

    Plasma5Support.DataSource {
        id: incidentsSource
        engine: "executable"
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            root.parseIncidents(data.stdout || "{}");
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
        implicitWidth: Kirigami.Units.gridUnit * 25.5
        implicitHeight: Kirigami.Units.gridUnit * 31

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
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: "CodexBar"
                        color: root.textColor
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.32
                        font.weight: Font.Bold
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: "AI usage dashboard"
                        color: root.mutedTextColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    }
                }

                QQC2.ToolButton {
                    implicitWidth: Kirigami.Units.gridUnit * 1.55
                    implicitHeight: Kirigami.Units.gridUnit * 1.55
                    icon.name: "view-refresh"
                    icon.color: root.mutedTextColor
                    Accessible.name: "Atualizar dados"
                    enabled: !refreshing
                    onClicked: root.refresh()
                    QQC2.ToolTip.text: "Refresh"
                    QQC2.ToolTip.visible: hovered
                }

            }

            QQC2.ScrollView {
                visible: !settingsOpen && !incidentsOpen
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                contentWidth: tabRow.implicitWidth
                clip: true

                background: Rectangle {
                    radius: 8
                    color: "#151F2F"
                    border.width: 1
                    border.color: root.subtleBorderColor
                }

                RowLayout {
                    id: tabRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Kirigami.Units.smallSpacing

                    Item {
                        Layout.preferredWidth: 1
                    }

                    Repeater {
                        model: providers
                        delegate: ProviderTab {
                            required property var modelData
                            providerId: modelData.provider
                            label: providerName(modelData.provider)
                            selected: modelData.provider === activeProvider
                        }
                    }

                    Item {
                        Layout.preferredWidth: 1
                    }
                }
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: incidentsOpen
                    ? incidentsView
                    : settingsOpen
                        ? settingsView
                        : providers.length
                            ? providerView
                            : emptyView
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: footerActions.implicitHeight + Kirigami.Units.smallSpacing * 1.5
                color: "transparent"

                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: 1
                    color: root.subtleBorderColor
                }

                RowLayout {
                    id: footerActions
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Button {
                        flat: true
                        text: settingsOpen || incidentsOpen ? "Voltar" : "Configurações"
                        icon.name: settingsOpen || incidentsOpen ? "go-previous" : ""
                        palette.buttonText: root.mutedTextColor
                        onClicked: {
                            if (settingsOpen || incidentsOpen) {
                                root.closeSecondaryPage();
                            } else {
                                settingsOpen = true;
                            }
                        }
                    }

                    QQC2.Button {
                        visible: !settingsOpen && !incidentsOpen
                        flat: true
                        text: "Incidentes"
                        palette.buttonText: root.mutedTextColor
                        onClicked: root.openIncidents()
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }
            }
        }

        Component {
            id: incidentsView

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: Kirigami.Units.largeSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: "Incidentes"
                                color: root.textColor
                                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.35
                                font.weight: Font.Bold
                            }

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: "Status recente dos serviços ChatGPT/OpenAI e Claude."
                                color: root.mutedTextColor
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                wrapMode: Text.WordWrap
                            }
                        }

                        QQC2.ToolButton {
                            implicitWidth: Kirigami.Units.gridUnit * 1.7
                            implicitHeight: Kirigami.Units.gridUnit * 1.7
                            icon.name: "view-refresh"
                            icon.color: root.mutedTextColor
                            Accessible.name: "Atualizar incidentes"
                            enabled: !incidentsLoading
                            onClicked: root.refreshIncidents()
                            QQC2.ToolTip.text: "Atualizar incidentes"
                            QQC2.ToolTip.visible: hovered
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: width >= Kirigami.Units.gridUnit * 18 ? 2 : 1
                        columnSpacing: Kirigami.Units.largeSpacing
                        rowSpacing: Kirigami.Units.smallSpacing

                        Repeater {
                            model: [
                                {
                                    name: "ChatGPT / OpenAI",
                                    detail: "status.openai.com",
                                    provider: "openai",
                                    url: "https://status.openai.com/feed.rss",
                                    accent: root.healthyColor
                                },
                                {
                                    name: "Claude",
                                    detail: "status.claude.com",
                                    provider: "claude",
                                    url: "https://status.claude.com/history.rss",
                                    accent: root.costColor
                                }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: Kirigami.Units.gridUnit * 3.7
                                radius: 8
                                color: sourceMouse.containsMouse ? root.elevatedSurfaceColor : root.raisedSurfaceColor
                                border.width: 1
                                border.color: sourceMouse.containsMouse ? modelData.accent : root.subtleBorderColor

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Kirigami.Units.largeSpacing
                                    spacing: Kirigami.Units.smallSpacing

                                    Rectangle {
                                        Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                                        Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                                        radius: 8
                                        color: Qt.rgba(modelData.accent.r, modelData.accent.g, modelData.accent.b, 0.14)
                                        border.width: 1
                                        border.color: Qt.rgba(modelData.accent.r, modelData.accent.g, modelData.accent.b, 0.38)

                                        Kirigami.Icon {
                                            anchors.centerIn: parent
                                            source: iconSource(modelData.provider)
                                            width: Kirigami.Units.iconSizes.smallMedium
                                            height: Kirigami.Units.iconSizes.smallMedium
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        PlasmaComponents.Label {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            color: root.textColor
                                            font.weight: Font.Bold
                                            elide: Text.ElideRight
                                        }

                                        PlasmaComponents.Label {
                                            Layout.fillWidth: true
                                            text: modelData.detail
                                            color: root.mutedTextColor
                                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Kirigami.Icon {
                                        source: "open-link-symbolic"
                                        implicitWidth: Kirigami.Units.iconSizes.small
                                        implicitHeight: Kirigami.Units.iconSizes.small
                                        color: root.faintTextColor
                                    }
                                }

                                MouseArea {
                                    id: sourceMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally(modelData.url)
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: incidentsError.length > 0
                        Layout.fillWidth: true
                        implicitHeight: incidentErrorLabel.implicitHeight + Kirigami.Units.largeSpacing
                        radius: 7
                        color: Qt.rgba(root.criticalColor.r, root.criticalColor.g, root.criticalColor.b, 0.1)
                        border.width: 1
                        border.color: Qt.rgba(root.criticalColor.r, root.criticalColor.g, root.criticalColor.b, 0.35)

                        PlasmaComponents.Label {
                            id: incidentErrorLabel
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                margins: Kirigami.Units.smallSpacing
                            }
                            text: incidentsError
                            color: root.criticalColor
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: "Histórico recente"
                            color: root.textColor
                            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.12
                            font.weight: Font.Bold
                        }

                        PlasmaComponents.Label {
                            text: incidentsLoading ? "Atualizando..." : incidents.length + " eventos"
                            color: root.faintTextColor
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        }
                    }

                    QQC2.ScrollView {
                        id: incidentsPageScroll
                        implicitWidth: 0
                        implicitHeight: 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: availableWidth
                        clip: true

                        ColumnLayout {
                            width: Math.max(0, incidentsPageScroll.availableWidth - 2)
                            spacing: Kirigami.Units.smallSpacing

                            Rectangle {
                                visible: incidentsLoading || incidents.length === 0
                                Layout.fillWidth: true
                                implicitHeight: Kirigami.Units.gridUnit * 5
                                radius: 8
                                color: root.raisedSurfaceColor
                                border.width: 1
                                border.color: root.subtleBorderColor

                                PlasmaComponents.Label {
                                    anchors.centerIn: parent
                                    width: parent.width - Kirigami.Units.largeSpacing * 2
                                    text: incidentsLoading
                                        ? "Carregando incidentes..."
                                        : "Nenhum incidente encontrado nos feeds."
                                    color: root.mutedTextColor
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Repeater {
                                model: incidents

                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: incidentContent.implicitHeight + Kirigami.Units.largeSpacing * 2
                                    radius: 8
                                    color: incidentMouse.containsMouse ? root.elevatedSurfaceColor : root.raisedSurfaceColor
                                    border.width: 1
                                    border.color: incidentMouse.containsMouse
                                        ? (modelData.source === "OpenAI" ? root.healthyColor : root.costColor)
                                        : root.subtleBorderColor

                                    ColumnLayout {
                                        id: incidentContent
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            top: parent.top
                                            margins: Kirigami.Units.largeSpacing
                                        }
                                        spacing: Kirigami.Units.smallSpacing

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Kirigami.Units.smallSpacing

                                            Rectangle {
                                                Layout.preferredWidth: sourceLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                                                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.25
                                                radius: 6
                                                color: modelData.source === "OpenAI" ? "#173E3D" : "#452D22"
                                                border.width: 1
                                                border.color: modelData.source === "OpenAI" ? "#286D67" : "#845137"

                                                PlasmaComponents.Label {
                                                    id: sourceLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.source || "Status"
                                                    color: modelData.source === "OpenAI"
                                                        ? root.healthyColor
                                                        : root.costColor
                                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                                    font.weight: Font.DemiBold
                                                }
                                            }

                                            PlasmaComponents.Label {
                                                Layout.fillWidth: true
                                                text: incidentDate(modelData.published)
                                                color: root.faintTextColor
                                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                                horizontalAlignment: Text.AlignRight
                                                elide: Text.ElideRight
                                            }
                                        }

                                        PlasmaComponents.Label {
                                            Layout.fillWidth: true
                                            text: modelData.title || "Incidente sem título"
                                            color: root.textColor
                                            font.weight: Font.DemiBold
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 3
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: incidentMouse
                                        anchors.fill: parent
                                        enabled: !!modelData.link
                                        hoverEnabled: enabled
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: Qt.openUrlExternally(modelData.link)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Component {
            id: emptyView

            PlasmaComponents.Label {
                text: refreshing ? "Loading usage..." : "No provider data"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: root.faintTextColor
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
                                color: root.textColor
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
                            icon.color: root.mutedTextColor
                            Accessible.name: "Atualizar provedores"
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
                            color: root.textColor
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
                implicitWidth: 0
                implicitHeight: 0
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    id: providerColumn
                    width: Math.max(0, providerScroll.availableWidth - 2)
                    spacing: Kirigami.Units.largeSpacing * 1.35

                    property var entry: activeEntry()
                    property var usage: entry && entry.usage ? entry.usage : ({})
                    property var cost: entry && entry.cost ? entry.cost : null
                    property var openAITotal: openAITotals(usage)
                    property var latestCostDay: latestDaily(cost)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        visible: providerColumn.entry
                        source: providerColumn.entry ? iconSource(providerColumn.entry.provider) : ""
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                        Layout.alignment: Qt.AlignTop
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: providerColumn.entry ? providerName(providerColumn.entry.provider) : "Provider"
                            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.38
                            font.weight: Font.Bold
                            color: root.textColor
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
                            color: root.textColor
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
                            color: "#193D3D"
                            border.width: 1
                            border.color: "#2A716C"

                            PlasmaComponents.Label {
                                id: planLabel
                                anchors.centerIn: parent
                                text: loginMethod(providerColumn.usage)
                                color: root.healthyColor
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                PlasmaComponents.Label {
                    visible: !!(providerColumn.entry && providerColumn.entry.error)
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: root.criticalColor
                    text: providerColumn.entry && providerColumn.entry.error ? providerColumn.entry.error.message || "Unknown error" : ""
                }

                ColumnLayout {
                    visible: !!(hasQuotaRows(providerColumn.usage) && providerColumn.entry && !providerColumn.entry.error)
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
                        text: "Quota"
                        color: root.textColor
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.35
                        font.weight: Font.Bold
                    }

                    Repeater {
                        model: [
                            { key: "primary", title: "Session" },
                            { key: "secondary", title: "Weekly" },
                            { key: "tertiary", title: "Monthly" }
                        ]

                        delegate: QuotaCard {
                            required property var modelData
                            visible: !!(providerColumn.usage && providerColumn.usage[modelData.key])
                            Layout.fillWidth: true
                            title: modelData.title
                            windowData: providerColumn.usage ? providerColumn.usage[modelData.key] : null
                        }
                    }
                }

                ColumnLayout {
                    visible: !!(hasCostUsage(providerColumn.cost) && providerColumn.entry && !providerColumn.entry.error)
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    PlasmaComponents.Label {
                        text: "Cost"
                        color: root.textColor
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.35
                        font.weight: Font.Bold
                    }

                    GridLayout {
                        id: costCardsGrid
                        Layout.fillWidth: true
                        columns: width >= Kirigami.Units.gridUnit * 18 ? 2 : 1
                        columnSpacing: Kirigami.Units.largeSpacing
                        rowSpacing: Kirigami.Units.largeSpacing

                        CostCard {
                            title: "Today"
                            value: typeof latestDailyCost(providerColumn.cost) === "number"
                                ? formatMoney(latestDailyCost(providerColumn.cost))
                                : "--"
                            detail: typeof latestDailyTokens(providerColumn.cost) === "number"
                                ? compactNumber(latestDailyTokens(providerColumn.cost)) + " tokens"
                                : ""
                            accentColor: root.costColor
                        }

                        CostCard {
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
                            accentColor: "#FBBF24"
                        }
                    }

                    GridLayout {
                        visible: !!(providerColumn.cost && providerColumn.cost.daily && providerColumn.cost.daily.length > 0)
                        Layout.fillWidth: true
                        columns: width >= Kirigami.Units.gridUnit * 20 ? 2 : 1
                        columnSpacing: Kirigami.Units.largeSpacing
                        rowSpacing: Kirigami.Units.largeSpacing

                        UsageTrendChart {
                            Layout.fillHeight: true
                            costData: providerColumn.cost
                        }

                        RecentDaysList {
                            Layout.fillHeight: true
                            costData: providerColumn.cost
                        }
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        visible: !!(providerColumn.cost && providerColumn.cost.daily && providerColumn.cost.daily.length === 0)
                        text: "No daily cost data for this period"
                        color: root.faintTextColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    visible: !!(hasOpenAIUsage(providerColumn.usage) && providerColumn.entry && !providerColumn.entry.error)
                    Layout.fillWidth: true
                    implicitHeight: usageSummaryColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
                    radius: 8
                    color: root.raisedSurfaceColor
                    border.width: 1
                    border.color: root.subtleBorderColor

                    ColumnLayout {
                        id: usageSummaryColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: Kirigami.Units.largeSpacing
                        }
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            text: "Usage summary"
                            color: root.textColor
                            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.08
                            font.weight: Font.Bold
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: Kirigami.Units.largeSpacing
                            rowSpacing: Kirigami.Units.smallSpacing

                            PlasmaComponents.Label {
                                text: "Cost"
                                color: root.mutedTextColor
                            }

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                color: root.costColor
                                font.weight: Font.DemiBold
                                text: providerColumn.usage.providerCost
                                    ? formatMoney(providerColumn.usage.providerCost.used) + " - " + (providerColumn.usage.providerCost.period || "current period")
                                    : formatMoney(providerColumn.openAITotal.costUSD)
                            }

                            PlasmaComponents.Label {
                                text: "Requests"
                                color: root.mutedTextColor
                            }

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                color: root.textColor
                                text: compactNumber(providerColumn.openAITotal.requests)
                            }

                            PlasmaComponents.Label {
                                text: "Tokens"
                                color: root.mutedTextColor
                            }

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                color: root.textColor
                                text: compactNumber(providerColumn.openAITotal.totalTokens)
                            }

                            PlasmaComponents.Label {
                                text: "Cached input"
                                color: root.mutedTextColor
                            }

                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                color: root.textColor
                                text: compactNumber(providerColumn.openAITotal.cachedInputTokens)
                            }
                        }

                        UsageBar {
                            visible: !!(providerColumn.usage.providerCost
                                && typeof providerColumn.usage.providerCost.limit === "number"
                                && providerColumn.usage.providerCost.limit > 0)
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
                            color: root.faintTextColor
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            elide: Text.ElideRight
                        }
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
