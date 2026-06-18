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
    property bool refreshing: false

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
        var maxValue = 0;
        ["primary", "secondary", "tertiary"].forEach(function (key) {
            var pct = entry.usage[key] && entry.usage[key].usedPercent;
            if (typeof pct === "number" && pct > maxValue) {
                maxValue = pct;
            }
        });
        return maxValue;
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

    compactRepresentation: MouseArea {
        id: compact
        implicitWidth: compactRow.implicitWidth + Kirigami.Units.smallSpacing * 2
        implicitHeight: Kirigami.Units.gridUnit
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "applications-development"
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
            }

            PlasmaComponents.Label {
                text: barData.text.replace("🤖", "AI")
                textFormat: Text.PlainText
                font.weight: Font.DemiBold
                color: barData.className === "critical" ? Kirigami.Theme.negativeTextColor
                    : barData.className === "warning" ? Kirigami.Theme.neutralTextColor
                    : barData.className === "stale" ? Kirigami.Theme.disabledTextColor
                    : Kirigami.Theme.positiveTextColor
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
                sourceComponent: providers.length ? providerView : emptyView
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
            id: providerView

            ColumnLayout {
                id: providerColumn
                spacing: Kirigami.Units.largeSpacing

                property var entry: activeEntry()
                property var usage: entry && entry.usage ? entry.usage : ({})

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

                Repeater {
                    model: [
                        { key: "primary", title: "Session" },
                        { key: "secondary", title: "Weekly" },
                        { key: "tertiary", title: "Monthly" }
                    ]

                    delegate: ColumnLayout {
                        required property var modelData
                        visible: providerColumn.usage && providerColumn.usage[modelData.key] && !providerColumn.entry.error
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        property var windowData: providerColumn.usage ? providerColumn.usage[modelData.key] : null
                        property real pct: windowData && typeof windowData.usedPercent === "number" ? windowData.usedPercent : 0

                        RowLayout {
                            Layout.fillWidth: true

                            PlasmaComponents.Label {
                                text: modelData.title
                                font.weight: Font.DemiBold
                                Layout.fillWidth: true
                            }

                            PlasmaComponents.Label {
                                text: Math.floor(pct) + "%"
                                color: pct >= 90 ? Kirigami.Theme.negativeTextColor
                                    : pct >= 70 ? Kirigami.Theme.neutralTextColor
                                    : Kirigami.Theme.textColor
                            }
                        }

                        QQC2.ProgressBar {
                            Layout.fillWidth: true
                            from: 0
                            to: 100
                            value: pct
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: windowData && windowData.resetDescription ? windowData.resetDescription : ""
                            visible: text.length > 0
                            color: Kirigami.Theme.disabledTextColor
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
