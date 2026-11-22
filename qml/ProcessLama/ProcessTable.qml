pragma ComponentBehavior: Bound
import QtQuick
import QtQml.Models
import QtQuick.Templates as T
import QtQuick.Window
import Meridian

// The process tree as a flat table: a pinned header that sorts, reorders and
// resizes columns, rows with selection, hover, search and heat fills, the
// keyboard model of a tree, row and column menus, and the tree search
// overlay. Rows are recycled; cells redraw only the values that changed.
FocusScope {
    id: root

    /// Whether the island holds keyboard focus: its selection is then solid.
    property bool islandFocused: false

    readonly property var app: Store.app
    readonly property var model: Store.tree
    readonly property var session: Store.session
    readonly property var settings: Store.settings
    readonly property var columnIds: model ? model.columnIds : []
    readonly property int selectedRow: model ? model.selectedRow : -1
    readonly property real cpuScaleMax: model ? model.cpuScaleMax : 1
    readonly property bool heatmap: settings.rowHeatmap ?? false
    readonly property bool windowActive: Window.active
    readonly property real rowHeight: Theme.size.row
    readonly property real headerHeight: Theme.size.control
    readonly property string treeQuery: session.treeSearchQuery ?? ""
    property int hoveredRow: -1
    // When each spawned process first rose. Rows are positional, so a cell
    // can show another process after a poll; a process rises once, all of
    // its cells together.
    property var _riseStarts: ({})
    function riseStart(key) {
        const now = Date.now()
        const start = _riseStarts[key]
        if (start !== undefined)
            return start
        if (Object.keys(_riseStarts).length > 512)
            _riseStarts = {}
        _riseStarts[key] = now
        return now
    }
    property bool overlayVisible: false
    property bool revealing: false

    readonly property var columnWidths: {
        const stored = settings.columnWidths ?? {}
        const clamp = (id, value) => id === "name" ? Math.max(180, Math.min(960, value)) : Math.max(52, Math.min(360, value))
        // The flexible name column fills a narrow viewport up to 440 until
        // the user drags it.
        return columnIds.map(id => {
            if (stored[id] !== undefined)
                return clamp(id, stored[id])
            if (id === "name")
                return Math.min(Math.max(360, table.width), 440)
            return Labels.columnWidths[id]
        })
    }
    onColumnWidthsChanged: table.forceLayout()

    function columnWidth(id) {
        const index = columnIds.indexOf(id)
        return index >= 0 ? columnWidths[index] : 0
    }

    // Fills and inks of a row: selection, then hover, then a search match,
    // then the CPU heat tint.
    function strong(row) { return row === selectedRow && islandFocused && windowActive }
    function rowFill(row, rowMatch, heat) {
        if (row === selectedRow)
            return strong(row) ? Theme.colors.accent : Theme.colors.accentSoft
        if (row === hoveredRow)
            return Theme.colors.paneHover
        if (rowMatch)
            return AppTheme.searchMatchRow
        if (heatmap)
            return Qt.alpha(AppTheme.rowHeat, AppTheme.maxRowHeatOpacity * Math.max(0, Math.min(1, heat / 100)))
        return "transparent"
    }
    function primaryInk(row) { return strong(row) ? Theme.colors.inkOnAccent : Theme.colors.ink }
    function secondaryInk(row) { return strong(row) ? Theme.colors.inkOnAccentMuted : Theme.colors.inkMuted }
    function iconInk(row) { return strong(row) ? Theme.colors.inkOnAccent : Theme.colors.inkMuted }

    function nameCell(row) {
        const column = columnIds.indexOf("name")
        return column >= 0 ? table.itemAtCell(Qt.point(column, row)) : null
    }

    // Pointer handlers declared in the TableView attach to its content item,
    // so their `position` already scrolls with the rows. Map scene positions
    // explicitly instead of adding contentY to either.
    function rowAtScene(scenePosition) {
        const local = table.contentItem.mapFromItem(null, scenePosition.x, scenePosition.y)
        const row = Math.floor(local.y / rowHeight)
        return row >= 0 && row < table.rows ? row : -1
    }

    function selectRow(row) {
        const cell = nameCell(row)
        if (cell) {
            table.forceActiveFocus()
            app.selectProcess(cell.processKey)
        }
    }

    // Keeps the selected row in view after selection, search or row changes.
    function revealSelected() {
        if (selectedRow < 0)
            return
        const top = selectedRow * rowHeight
        const bottom = top + rowHeight
        let target = -1
        if (top < table.contentY)
            target = top
        else if (bottom > table.contentY + table.height)
            target = bottom - table.height
        if (target < 0)
            return
        target = Math.max(0, Math.min(target, Math.max(0, table.contentHeight - table.height)))
        if (Math.abs(target - table.contentY) < 0.5)
            return
        revealing = true
        table.contentY = target
        revealing = false
    }
    onSelectedRowChanged: Qt.callLater(revealSelected)
    onTreeQueryChanged: {
        // The session owns the query: adopt it when it changes elsewhere.
        if (searchField.text !== treeQuery && !searchField.activeFocus)
            searchField.text = treeQuery
        Qt.callLater(revealSelected)
    }
    Connections {
        target: root.model
        function onRowsChanged() { Qt.callLater(root.revealSelected) }
        function onSourceReplaced() {
            table.contentY = 0
            table.contentX = 0
            Qt.callLater(root.revealSelected)
        }
    }

    // Tree search

    readonly property bool searchActive: treeQuery.length > 0 || overlayVisible || searchField.activeFocus

    function openSearch(selectAll) {
        overlayVisible = true
        searchField.forceActiveFocus()
        if (selectAll)
            searchField.selectAll()
    }

    function stopSearch() {
        app.setTreeSearch("")
        searchField.text = ""
        overlayVisible = false
        table.forceActiveFocus()
    }

    Connections {
        target: Store
        function onTreeSearchRequested() { root.openSearch(true) }
    }

    function isSearchCharacter(event) {
        if (event.text.length === 0 || (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier)))
            return false
        for (let i = 0; i < event.text.length; ++i) {
            const code = event.text.charCodeAt(i)
            if (code < 0x20 || code === 0x7F)
                return false
        }
        return true
    }

    function handleKey(event) {
        const query = treeQuery
        const shift = event.modifiers & Qt.ShiftModifier
        const alt = event.modifiers & Qt.AltModifier
        switch (event.key) {
        case Qt.Key_Escape:
            if (searchActive) stopSearch()
            else app.popSubtreeFocus()
            return true
        case Qt.Key_Down: app.selectNextVisible(); return true
        case Qt.Key_Up: app.selectPreviousVisible(); return true
        case Qt.Key_Right:
            if (alt) app.expandSelectedSubtree()
            else app.expandSelected()
            return true
        case Qt.Key_Left:
            if (alt) app.collapseSelectedSubtree()
            else app.collapseSelected()
            return true
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (shift && query.length === 0) {
                app.focusSelectedSubtree()
                return true
            }
            if (query.length > 0) {
                if (shift) app.selectPreviousTreeSearchMatch()
                else app.selectNextTreeSearchMatch()
                return true
            }
            if (shift) {
                app.focusSelectedSubtree()
                return true
            }
            return false
        case Qt.Key_Backspace:
            if (query.length > 0) {
                const next = query.slice(0, -1)
                searchField.text = next
                app.setTreeSearch(next)
                return true
            }
            return false
        }
        if (isSearchCharacter(event)) {
            overlayVisible = true
            const next = query + event.text
            searchField.text = next
            app.setTreeSearch(next)
            return true
        }
        return false
    }

    // Context menus

    property var menuRow: ({})

    function openRowMenu(row, x, y) {
        selectRow(row)
        const cell = nameCell(row)
        if (!cell)
            return
        menuRow = {
            key: cell.processKey,
            name: cell.processName,
            pid: cell.pid,
            pinned: cell.pinned,
            hasChildren: cell.hasChildren,
            alive: cell.marker !== 2,
            stopped: cell.status === 2,
            executable: cell.executablePath
        }
        rowMenu.popup(table, x, y)
    }

    // The header

    Rectangle {
        id: headerBar
        x: Theme.space.s3
        y: Theme.space.s3
        width: parent.width - 2 * Theme.space.s3
        height: root.headerHeight
        radius: Theme.radius.sm
        color: Theme.colors.paneAlt
        clip: true

        Row {
            id: headerRow
            x: -table.contentX
            height: parent.height
            Repeater {
                model: root.columnIds
                HeaderCell {}
            }
        }
    }

    component HeaderCell: Item {
        id: headerCell
        required property string modelData
        required property int index
        readonly property string columnId: modelData
        readonly property bool numeric: columnId !== "name" && columnId !== "status"
        readonly property bool dropTarget: dragState.active && dragState.target === columnId && dragState.source !== columnId
        width: root.columnWidths[index] ?? 0
        height: parent.height
        // Earlier cells stack above later ones, so a grip's overhang past the
        // divider wins over the next column's reorder drag.
        z: root.columnIds.length - index

        MeridianColumnHeader {
            anchors.fill: parent
            opacity: dragState.active && dragState.source === headerCell.columnId ? AppTheme.dimmedRow : 1
            text: Labels.column(headerCell.columnId)
            alignEnd: headerCell.numeric
            sort: root.session.sortColumn !== headerCell.columnId ? MeridianColumnHeader.None
                : root.session.sortAscending ? MeridianColumnHeader.Ascending : MeridianColumnHeader.Descending
            sortedAscendingLabel: L10n.t("sortedAscending")
            sortedDescendingLabel: L10n.t("sortedDescending")
            onClicked: root.app.sortBy(headerCell.columnId)
            onContextMenuRequested: (x, y) => columnMenu.popup(this, x, y)
        }

        DragHandler {
            id: reorder
            target: null
            xAxis.enabled: true
            yAxis.enabled: false
            onActiveChanged: {
                if (active) {
                    dragState.source = headerCell.columnId
                    dragState.width = headerCell.columnId === "name" ? 180 : headerCell.width
                    dragState.active = true
                } else {
                    const from = dragState.source
                    const to = dragState.target
                    dragState.active = false
                    if (to.length > 0 && to !== from)
                        root.moveColumnBefore(from, to)
                }
            }
            onCentroidChanged: {
                if (!active)
                    return
                const point = headerRow.mapFromItem(headerCell, centroid.position.x, 0)
                dragState.x = root.mapFromItem(headerCell, centroid.position.x, 0).x - dragState.width / 2
                const hit = headerRow.childAt(point.x, headerRow.height / 2) as HeaderCell
                dragState.target = hit ? hit.columnId : ""
            }
        }

        MeridianHairline {
            visible: headerCell.index < root.columnIds.length - 1
            vertical: true
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: Theme.space.s3
            anchors.bottomMargin: Theme.space.s3
        }

        Rectangle {
            visible: headerCell.dropTarget
            width: Metrics.resizeRule
            height: parent.height
            color: Theme.colors.accent
        }

        // The resize grip, centred on the divider; a double-click restores
        // the default width.
        Item {
            objectName: "resizeGrip"
            anchors.right: parent.right
            anchors.rightMargin: -width / 2
            width: Theme.space.s6
            height: parent.height
            HoverHandler { cursorShape: Qt.SplitHCursor }
            TapHandler { onDoubleTapped: { root.app.markTreeInteraction(); root.app.resetColumnWidth(headerCell.columnId) } }
            DragHandler {
                id: grip
                property real startWidth: 0
                target: null
                yAxis.enabled: false
                cursorShape: Qt.SplitHCursor
                onActiveChanged: if (active) startWidth = headerCell.width
                onTranslationChanged: {
                    if (!active)
                        return
                    root.app.markTreeInteraction()
                    root.app.setColumnWidth(headerCell.columnId, startWidth + translation.x)
                }
            }
        }
    }

    QtObject {
        id: dragState
        property bool active: false
        property string source: ""
        property string target: ""
        property real x: 0
        property real width: 0
    }

    // The dragged column's floating header.
    Rectangle {
        visible: dragState.active
        z: 10
        x: dragState.x
        y: headerBar.y
        width: dragState.width
        height: root.headerHeight
        radius: Theme.radius.sm
        color: Theme.colors.raised
        MeridianShadow {
            anchors.fill: parent
            z: -1
            layers: Theme.shadows.float
            radius: Theme.radius.sm
        }
        MeridianColumnHeader {
            anchors.fill: parent
            pressable: false
            text: Labels.column(dragState.source)
            alignEnd: dragState.source !== "name" && dragState.source !== "status"
        }
    }

    function moveColumnBefore(from, to) {
        const next = columnIds.slice()
        const fromIndex = next.indexOf(from)
        const toIndex = next.indexOf(to)
        if (fromIndex < 0 || toIndex < 0)
            return
        next.splice(fromIndex, 1)
        next.splice(fromIndex < toIndex ? toIndex - 1 : toIndex, 0, from)
        app.setVisibleColumns(next)
    }

    function toggleColumn(id) {
        if (id === "name")
            return
        const next = columnIds.slice()
        const index = next.indexOf(id)
        if (index >= 0)
            next.splice(index, 1)
        else
            next.push(id)
        app.setVisibleColumns(next)
    }

    // The rows

    TableView {
        id: table
        x: Theme.space.s3
        y: headerBar.y + headerBar.height
        width: parent.width - 2 * Theme.space.s3
        height: parent.height - y - Theme.space.s3
        model: root.model
        clip: true
        focus: true
        reuseItems: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.AutoFlickIfNeeded
        pixelAligned: true
        columnSpacing: 0
        rowSpacing: 0
        rowHeightProvider: () => root.rowHeight
        columnWidthProvider: column => root.columnWidths[column] ?? 0
        T.ScrollBar.vertical: MeridianScrollBar {}
        T.ScrollBar.horizontal: MeridianScrollBar {}
        MeridianWheelScroll { flickable: table; lineHeight: root.rowHeight }

        // The tree takes keyboard focus when the window opens.
        Component.onCompleted: forceActiveFocus()
        onContentYChanged: if (!root.revealing) root.app.markTreeInteraction()
        onContentXChanged: if (!root.revealing) root.app.markTreeInteraction()

        Keys.onPressed: event => {
            if (root.handleKey(event))
                event.accepted = true
        }

        HoverHandler {
            id: hover
            onPointChanged: root.hoveredRow = hovered ? root.rowAtScene(point.scenePosition) : -1
            onHoveredChanged: {
                root.app.setTreeHovering(hovered)
                if (!hovered)
                    root.hoveredRow = -1
            }
        }
        Connections {
            target: table
            function onContentYChanged() {
                if (hover.hovered)
                    root.hoveredRow = root.rowAtScene(hover.point.scenePosition)
            }
        }
        // A primary press selects the row; a secondary click opens its menu.
        PointHandler {
            acceptedButtons: Qt.LeftButton
            onActiveChanged: if (active) {
                const row = root.rowAtScene(point.scenePosition)
                if (row >= 0)
                    root.selectRow(row)
            }
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: (point) => {
                const row = root.rowAtScene(point.scenePosition)
                if (row >= 0) {
                    const at = table.mapFromItem(null, point.scenePosition.x, point.scenePosition.y)
                    root.openRowMenu(row, at.x, at.y)
                }
            }
        }

        delegate: DelegateChooser {
            role: "columnId"
            DelegateChoice { roleValue: "name"; NameCell {} }
            DelegateChoice { roleValue: "cpu"; MeterCell {} }
            DelegateChoice { roleValue: "treeCpu"; MeterCell {} }
            DelegateChoice { roleValue: "status"; StatusCell {} }
            DelegateChoice { TextCell {} }
        }
    }

    // A cell's share of its row's rounded bar, plus the spawn rise.
    component CellBase: Item {
        id: cell
        required property int row
        required property int column
        required property int marker
        required property string processKey
        required property bool rowMatch
        required property real heat
        required property bool cellMatch
        required property int matchStart
        required property int matchEnd
        readonly property bool first: column === 0
        readonly property bool last: column === root.columnIds.length - 1
        readonly property bool selected: row === root.selectedRow
        readonly property bool hovered: row === root.hoveredRow
        readonly property bool strong: root.strong(row)
        readonly property color primary: root.primaryInk(row)
        readonly property color secondary: root.secondaryInk(row)
        default property alias content: body.data
        property real slide: 0

        implicitHeight: root.rowHeight

        Rectangle {
            anchors.fill: parent
            color: root.rowFill(cell.row, cell.rowMatch, cell.heat)
            topLeftRadius: cell.first ? Theme.radius.sm : 0
            bottomLeftRadius: cell.first ? Theme.radius.sm : 0
            topRightRadius: cell.last ? Theme.radius.sm : 0
            bottomRightRadius: cell.last ? Theme.radius.sm : 0
        }
        Item {
            id: body
            anchors.fill: parent
            opacity: cell.marker === 2 ? AppTheme.dimmedRow : 1
            transform: Translate { y: cell.slide }
        }

        // Spawned rows rise into place.
        NumberAnimation {
            id: rise
            target: cell
            property: "slide"
            from: Theme.space.s3
            to: 0
            duration: Motion.emphasized
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.standard
        }
        function _rise() {
            // Within one frame of the process's first rise: its other cells.
            if (marker === 1 && !Motion.reduced && Date.now() - root.riseStart(processKey) < 50)
                rise.restart()
            else if (marker !== 1 || Motion.reduced) {
                rise.stop()
                slide = 0
            }
        }
        onMarkerChanged: _rise()
        onProcessKeyChanged: _rise()
        Component.onCompleted: _rise()
        TableView.onReused: _rise()
    }

    // The matched span of a tree search, painted behind the text.
    component MatchHighlight: Rectangle {
        id: highlight
        required property Text label
        required property int start
        required property int end
        visible: start >= 0 && end > start
        color: AppTheme.searchHighlight
        TextMetrics { id: before; font: highlight.label.font; text: highlight.label.text.substring(0, highlight.start) }
        TextMetrics { id: match; font: highlight.label.font; text: highlight.label.text.substring(highlight.start, highlight.end) }
        readonly property real offset: highlight.label.horizontalAlignment === Text.AlignRight
            ? highlight.label.width - highlight.label.contentWidth : 0
        x: highlight.label.x + offset + before.advanceWidth
        y: highlight.label.y + (highlight.label.height - height) / 2
        width: Math.min(match.advanceWidth, Math.max(0, highlight.label.width - offset - before.advanceWidth))
        height: highlight.label.contentHeight
    }

    component TextCell: CellBase {
        id: textCell
        required property string cellText
        required property bool numeric
        MatchHighlight {
            label: valueText
            start: textCell.cellMatch ? textCell.matchStart : -1
            end: textCell.matchEnd
        }
        MeridianText {
            id: valueText
            anchors.fill: parent
            anchors.leftMargin: Theme.space.s4
            anchors.rightMargin: Theme.space.s4
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: textCell.numeric ? Text.AlignRight : Text.AlignLeft
            role: MeridianText.Code
            tabular: true
            color: textCell.secondary
            elide: Text.ElideRight
            text: textCell.cellText
        }
    }

    component MeterCell: CellBase {
        id: meterCell
        required property string cellText
        required property real usage
        MeridianMeter {
            anchors.left: parent.left
            anchors.leftMargin: Theme.space.s4
            anchors.right: meterValue.left
            anchors.rightMargin: Theme.space.s3
            anchors.verticalCenter: parent.verticalCenter
            // Telemetry is sampled, not an interaction: no tween between polls.
            animated: false
            value: meterCell.usage / 100
            warningAt: 0.5
            color: meterCell.strong ? meterCell.primary : "transparent"
        }
        MeridianText {
            id: meterValue
            anchors.right: parent.right
            anchors.rightMargin: Theme.space.s4
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            horizontalAlignment: Text.AlignRight
            role: MeridianText.Code
            tabular: true
            elide: Text.ElideRight
            color: meterCell.usage >= 50 && !meterCell.strong ? Theme.colors.warning : meterCell.secondary
            fontWeight: meterCell.usage >= 10 ? Font.DemiBold : -1
            text: meterCell.cellText
        }
    }

    component StatusCell: CellBase {
        id: statusCell
        required property string cellText
        required property int status
        MeridianStatusDot {
            id: statusDot
            anchors.left: parent.left
            anchors.leftMargin: Theme.space.s4
            anchors.verticalCenter: parent.verticalCenter
            tone: statusCell.status === 0 ? MeridianStatusDot.Success
                : statusCell.status === 2 ? MeridianStatusDot.Warning
                : statusCell.status === 3 ? MeridianStatusDot.Danger : MeridianStatusDot.Neutral
            halo: statusCell.status === 0
        }
        MatchHighlight {
            label: statusText
            start: statusCell.cellMatch ? statusCell.matchStart : -1
            end: statusCell.matchEnd
        }
        MeridianText {
            id: statusText
            anchors.left: statusDot.right
            anchors.leftMargin: Theme.space.s3
            anchors.right: parent.right
            anchors.rightMargin: Theme.space.s4
            anchors.verticalCenter: parent.verticalCenter
            color: statusCell.secondary
            elide: Text.ElideRight
            text: statusCell.cellText
        }
    }

    component NameCell: CellBase {
        id: nameCell
        required property string processName
        required property string iconUrl
        required property int depth
        required property bool hasChildren
        required property bool expanded
        required property int descendants
        required property var history
        required property bool pinned
        required property int pid
        required property int status
        required property string executablePath
        readonly property bool showPin: pinned || hovered || selected

        Item {
            id: indent
            width: Theme.space.s3 + nameCell.depth * Metrics.treeIndent
            height: parent.height
        }

        // The change marker.
        Item {
            id: markerSlot
            anchors.left: indent.right
            width: Metrics.navChevronTarget
            height: parent.height
            MeridianIcon {
                id: markerIcon
                anchors.centerIn: parent
                visible: nameCell.marker !== 0
                name: nameCell.marker === 1 ? "circle-plus" : "circle-minus"
                iconSize: MeridianIcon.Small
                color: nameCell.strong ? root.iconInk(nameCell.row)
                     : nameCell.marker === 1 ? Theme.colors.success : Theme.colors.danger
                HoverHandler { id: markerHover }
                MeridianTooltip {
                    text: nameCell.marker === 1 ? L10n.t("spawned") : L10n.t("terminated")
                    shown: markerHover.hovered && markerIcon.visible
                }
            }
        }

        Item {
            id: chevronSlot
            anchors.left: markerSlot.right
            width: Metrics.navChevronTarget
            height: parent.height
            MeridianIconButton {
                anchors.centerIn: parent
                visible: nameCell.hasChildren
                text: nameCell.expanded ? L10n.t("collapse") : L10n.t("expand")
                iconName: nameCell.expanded ? "chevron-down" : "chevron-right"
                controlSize: MeridianButton.Small
                iconColorOverride: root.iconInk(nameCell.row)
                surfaceColor: root.rowFill(nameCell.row, nameCell.rowMatch, nameCell.heat)
                focusPolicy: Qt.NoFocus
                showTooltip: false
                onPressed: root.selectRow(nameCell.row)
                onClicked: root.app.toggleExpansion(nameCell.processKey)
            }
        }

        // Icon, name, descendants and the CPU sparkline; a double-click
        // focuses the subtree.
        Item {
            id: nameArea
            anchors.left: chevronSlot.right
            anchors.leftMargin: Theme.space.s1
            anchors.right: pinSlot.left
            anchors.rightMargin: Theme.space.s2
            height: parent.height

            TapHandler {
                onDoubleTapped: if (nameCell.marker !== 2) root.app.focusSubtree(nameCell.processKey)
            }

            ProcessIcon {
                id: icon
                anchors.verticalCenter: parent.verticalCenter
                name: nameCell.processName
                iconUrl: nameCell.iconUrl
            }
            MatchHighlight {
                label: nameText
                start: nameCell.cellMatch ? nameCell.matchStart : -1
                end: nameCell.matchEnd
            }
            MeridianText {
                id: nameText
                anchors.left: icon.right
                anchors.leftMargin: Theme.space.s4
                anchors.right: descendantsText.visible ? descendantsText.left : sparkline.left
                anchors.rightMargin: descendantsText.visible ? Theme.space.s3 : Theme.space.s4
                anchors.verticalCenter: parent.verticalCenter
                role: nameCell.selected ? MeridianText.BodyStrong : MeridianText.Body
                color: nameCell.primary
                strikeout: nameCell.marker === 2
                elide: Text.ElideRight
                text: nameCell.processName
            }
            MeridianText {
                id: descendantsText
                visible: nameCell.descendants > 0
                anchors.right: sparkline.left
                anchors.rightMargin: Theme.space.s4
                anchors.verticalCenter: parent.verticalCenter
                role: MeridianText.CodeSm
                tabular: true
                color: nameCell.secondary
                text: nameCell.descendants
            }
            Sparkline {
                id: sparkline
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                samples: nameCell.history
                maxValue: root.cpuScaleMax
                lineColor: nameCell.strong ? nameCell.primary : AppTheme.chartLine
                endpointColor: nameCell.strong ? nameCell.primary : Theme.colors.accent
            }
        }

        Item {
            id: pinSlot
            anchors.right: parent.right
            anchors.rightMargin: Theme.space.s2
            width: Theme.size.controlSmall
            height: parent.height
            MeridianIconButton {
                anchors.centerIn: parent
                visible: nameCell.showPin
                text: nameCell.pinned ? L10n.t("unpinProcess") : L10n.t("pinProcess")
                iconName: "pin"
                controlSize: MeridianButton.Small
                iconColorOverride: nameCell.pinned && !nameCell.strong ? Theme.colors.accentInk : root.iconInk(nameCell.row)
                surfaceColor: root.rowFill(nameCell.row, nameCell.rowMatch, nameCell.heat)
                focusPolicy: Qt.NoFocus
                showTooltip: false
                onPressed: root.selectRow(nameCell.row)
                onClicked: root.app.togglePin(nameCell.processKey)
            }
        }
    }

    // The tree search overlay.
    Rectangle {
        id: overlay
        visible: root.searchActive
        anchors.right: parent.right
        anchors.rightMargin: Theme.space.s6
        y: Theme.space.s3 + root.headerHeight
        z: 20
        width: overlayRow.width + 2 * Theme.space.s2
        height: overlayRow.height + 2 * Theme.space.s2
        radius: Theme.radius.lg
        color: Theme.colors.raised
        MeridianShadow {
            anchors.fill: parent
            z: -1
            layers: Theme.shadows.float
            radius: Theme.radius.lg
        }
        Row {
            id: overlayRow
            x: Theme.space.s2
            y: Theme.space.s2
            spacing: Theme.space.s2
            readonly property int current: (root.session.treeSearchMatchIndex ?? -1) < 0 ? 0 : root.session.treeSearchMatchIndex + 1
            readonly property int count: root.session.treeSearchMatchCount ?? 0
            MeridianTextField {
                id: searchField
                width: 200
                variant: MeridianTextField.Search
                trailingText: overlayRow.current + "/" + overlayRow.count
                Accessible.description: L10n.t("searchMatchPosition", [overlayRow.current, overlayRow.count])
                onTextEdited: root.app.setTreeSearch(text)
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.stopSearch()
                        event.accepted = true
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && text.length > 0) {
                        if (event.modifiers & Qt.ShiftModifier) root.app.selectPreviousTreeSearchMatch()
                        else root.app.selectNextTreeSearchMatch()
                        event.accepted = true
                    }
                }
                onActiveFocusChanged: if (!activeFocus && text.length === 0) root.overlayVisible = false
            }
            MeridianIconButton {
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.t("previousSearchMatch")
                iconName: "chevron-up"
                focusPolicy: Qt.NoFocus
                enabled: overlayRow.count > 0
                onClicked: root.app.selectPreviousTreeSearchMatch()
            }
            MeridianIconButton {
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.t("nextSearchMatch")
                iconName: "chevron-down"
                focusPolicy: Qt.NoFocus
                enabled: overlayRow.count > 0
                onClicked: root.app.selectNextTreeSearchMatch()
            }
            MeridianIconButton {
                anchors.verticalCenter: parent.verticalCenter
                text: L10n.t("clearSearch")
                iconName: "x"
                focusPolicy: Qt.NoFocus
                onClicked: root.stopSearch()
            }
        }
    }

    MeridianMenu {
        id: rowMenu
        onOpened: root.app.setTreeContextMenuOpen(true)
        onClosed: root.app.setTreeContextMenuOpen(false)
        MeridianMenuItem {
            text: root.menuRow.pinned ? L10n.t("unpinProcessMenu") : L10n.t("pinProcessMenu")
            iconName: root.menuRow.pinned ? "pin-off" : "pin"
            onTriggered: root.app.togglePin(root.menuRow.key)
        }
        MeridianMenuSeparator {}
        MeridianMenuItem {
            text: L10n.t("focusSubtree")
            iconName: "focus"
            shortcut: Store.isMac ? "⇧↵" : "Shift+Enter"
            enabled: root.menuRow.alive ?? false
            onTriggered: root.app.focusSubtree(root.menuRow.key)
        }
        MeridianMenuItem {
            text: L10n.t("expandSubtree")
            iconName: "chevrons-up-down"
            enabled: root.menuRow.hasChildren ?? false
            onTriggered: root.app.expandSelectedSubtree()
        }
        MeridianMenuItem {
            text: L10n.t("collapseSubtree")
            iconName: "chevrons-down-up"
            enabled: root.menuRow.hasChildren ?? false
            onTriggered: root.app.collapseSelectedSubtree()
        }
        MeridianMenuSeparator {}
        MeridianMenuItem {
            text: L10n.t("copyPid", [root.menuRow.pid ?? ""])
            iconName: "copy"
            onTriggered: Store.actions.copy(String(root.menuRow.pid))
        }
        MeridianMenuItem {
            text: L10n.t("copyName", [root.menuRow.name ?? ""])
            iconName: "copy"
            onTriggered: Store.actions.copy(root.menuRow.name)
        }
        MeridianMenuItem {
            text: L10n.t("copyExecutablePath")
            iconName: "copy"
            enabled: (root.menuRow.executable ?? "").length > 0
            onTriggered: Store.actions.copy(root.menuRow.executable)
        }
        MeridianMenuSeparator {}
        MeridianMenuItem {
            text: root.menuRow.stopped ? L10n.t("resumeProcessMenu") : L10n.t("suspendProcessMenu")
            iconName: root.menuRow.stopped ? "circle-play" : "circle-pause"
            enabled: root.menuRow.alive ?? false
            onTriggered: Store.actions.signalProcess(root.menuRow.key, root.menuRow.stopped ? "resume" : "suspend",
                                                     root.menuRow.name, String(root.menuRow.pid))
        }
        MeridianMenuItem {
            text: L10n.t("terminateProcessMenu")
            iconName: "circle-stop"
            danger: true
            enabled: root.menuRow.alive ?? false
            onTriggered: Store.actions.signalProcess(root.menuRow.key, "terminate", root.menuRow.name, String(root.menuRow.pid))
        }
        MeridianMenuItem {
            text: L10n.t("killProcessMenu")
            iconName: "octagon-x"
            danger: true
            enabled: root.menuRow.alive ?? false
            onTriggered: Store.actions.signalProcess(root.menuRow.key, "kill", root.menuRow.name, String(root.menuRow.pid))
        }
    }

    MeridianMenu {
        id: columnMenu
        MeridianMenuHeader { text: L10n.t("columns") }
        Instantiator {
            model: Labels.availableColumns
            delegate: MeridianMenuItem {
                required property string modelData
                text: Labels.column(modelData)
                checked: root.columnIds.indexOf(modelData) >= 0
                enabled: modelData !== "name"
                onTriggered: root.toggleColumn(modelData)
            }
            onObjectAdded: (index, object) => columnMenu.insertItem(index + 1, object)
            onObjectRemoved: (index, object) => columnMenu.removeItem(object)
        }
        MeridianMenuSeparator {}
        MeridianMenuItem {
            text: L10n.t("showAllColumns")
            onTriggered: root.app.setVisibleColumns(Labels.availableColumns)
        }
        MeridianMenuItem {
            text: L10n.t("resetColumnOrder")
            onTriggered: root.app.setVisibleColumns(Labels.availableColumns)
        }
    }
}
