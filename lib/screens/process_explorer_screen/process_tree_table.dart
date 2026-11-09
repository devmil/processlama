part of '../process_explorer_screen.dart';

const double _processHeaderHeight = MeridianSize.control;

// The flexible process-name column uses these until the user drags a divider.
// It fills leftover horizontal space (so narrow windows stay full) but is
// capped so it cannot dominate the table on wide windows.
const double _defaultFlexColumnWidth = 360;
const double _maxInitialFlexColumnWidth = 440;

void _logTreeSearchFocus(
  String event, {
  String? detail,
  TextEditingController? controller,
  FocusNode? treeFocusNode,
  FocusNode? searchFocusNode,
  bool? overlayVisible,
  bool? editorActive,
  String? query,
  KeyEvent? keyEvent,
}) {
  if (!kDebugMode) {
    return;
  }
  recordDiagnostic(
    const DiagnosticEvent(
      'processlama.process_tree_table.diagnostic',
      detailed: true,
    ),
  );
}

class _ProcessTreeTable extends StatefulWidget {
  const _ProcessTreeTable({
    required this.tree,
    required this.settings,
    required this.selectedIdentity,
    required this.treeSearchRequestSerial,
    required this.onSelected,
    required this.onSelectNext,
    required this.onSelectPrevious,
    required this.onExpandSelected,
    required this.onCollapseSelected,
    required this.onExpandSelectedSubtree,
    required this.onCollapseSelectedSubtree,
    required this.onFocusSelectedSubtree,
    required this.onPopSubtreeFocus,
    required this.onTreeSearchChanged,
    required this.onSelectNextTreeSearchMatch,
    required this.onSelectPreviousTreeSearchMatch,
    required this.onToggleExpanded,
    required this.onSort,
    required this.onTogglePin,
    required this.onFocusSubtree,
    required this.onTerminateProcess,
    required this.onKillProcess,
    required this.onSuspendProcess,
    required this.onResumeProcess,
    required this.onExpandSubtree,
    required this.onCollapseSubtree,
    required this.onTreeHoverChanged,
    required this.onTreeContextMenuChanged,
    required this.onTreeInteraction,
    required this.onVisibleColumnsChanged,
    required this.onColumnWidthsChanged,
  });

  final ProcessTreeView tree;
  final AppSettings settings;
  final ValueListenable<ProcessIdentity?> selectedIdentity;
  final int treeSearchRequestSerial;
  final ValueChanged<ProcessIdentity> onSelected;
  final VoidCallback onSelectNext;
  final VoidCallback onSelectPrevious;
  final VoidCallback onExpandSelected;
  final VoidCallback onCollapseSelected;
  final VoidCallback onExpandSelectedSubtree;
  final VoidCallback onCollapseSelectedSubtree;
  final VoidCallback onFocusSelectedSubtree;
  final VoidCallback onPopSubtreeFocus;
  final ValueChanged<String> onTreeSearchChanged;
  final VoidCallback onSelectNextTreeSearchMatch;
  final VoidCallback onSelectPreviousTreeSearchMatch;
  final ValueChanged<ProcessIdentity> onToggleExpanded;
  final ValueChanged<ProcessSortColumn> onSort;
  final ValueChanged<ProcessIdentity> onTogglePin;
  final ValueChanged<ProcessIdentity> onFocusSubtree;
  final Future<void> Function(ProcessIdentity identity) onTerminateProcess;
  final Future<void> Function(ProcessIdentity identity) onKillProcess;
  final Future<void> Function(ProcessIdentity identity) onSuspendProcess;
  final Future<void> Function(ProcessIdentity identity) onResumeProcess;
  final ValueChanged<ProcessIdentity> onExpandSubtree;
  final ValueChanged<ProcessIdentity> onCollapseSubtree;
  final ValueChanged<bool> onTreeHoverChanged;
  final ValueChanged<bool> onTreeContextMenuChanged;
  final VoidCallback onTreeInteraction;
  final ValueChanged<List<String>> onVisibleColumnsChanged;
  final ValueChanged<Map<String, double>> onColumnWidthsChanged;

  @override
  State<_ProcessTreeTable> createState() => _ProcessTreeTableState();
}

class _ProcessTreeTableState extends State<_ProcessTreeTable> {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'process-tree-table');
  final TextEditingController _treeSearchController = TextEditingController();
  final FocusNode _treeSearchFocusNode = FocusNode(
    debugLabel: 'tree-search-overlay',
  );
  bool _revealSelectedRowScheduled = false;
  int _revealSelectedRowRetryCount = 0;
  bool _treeSearchOverlayVisible = false;
  bool _treeSearchEditorActive = false;
  ProcessIdentity? _hoveredIdentity;

  /// Row height for the active density; read in [build].
  double _rowExtent = MeridianSize.rowCompact;

  @override
  void initState() {
    super.initState();
    _treeSearchController.text = widget.tree.treeSearchQuery;
    _treeSearchFocusNode.addListener(_handleTreeSearchFocusChanged);
    _logTreeSearchFocus(
      'initState',
      controller: _treeSearchController,
      treeFocusNode: _focusNode,
      searchFocusNode: _treeSearchFocusNode,
      overlayVisible: _treeSearchOverlayVisible,
      editorActive: _treeSearchEditorActive,
      query: widget.tree.treeSearchQuery,
    );
    _scheduleRevealSelectedRow();
  }

  @override
  void didUpdateWidget(covariant _ProcessTreeTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    final searchShouldKeepFocus =
        _treeSearchEditorActive || _treeSearchFocusNode.hasFocus;
    _logTreeSearchFocus(
      'didUpdateWidget:start',
      detail:
          'oldQuery="${oldWidget.tree.treeSearchQuery}" oldSelected=${oldWidget.tree.selectedIdentity} newSelected=${widget.tree.selectedIdentity} keepFocus=$searchShouldKeepFocus',
      controller: _treeSearchController,
      treeFocusNode: _focusNode,
      searchFocusNode: _treeSearchFocusNode,
      overlayVisible: _treeSearchOverlayVisible,
      editorActive: _treeSearchEditorActive,
      query: widget.tree.treeSearchQuery,
    );
    if (oldWidget.tree.treeSearchQuery != widget.tree.treeSearchQuery &&
        _treeSearchController.text != widget.tree.treeSearchQuery) {
      _logTreeSearchFocus(
        'didUpdateWidget:syncController',
        detail: 'from="${_treeSearchController.text}"',
        controller: _treeSearchController,
        treeFocusNode: _focusNode,
        searchFocusNode: _treeSearchFocusNode,
        overlayVisible: _treeSearchOverlayVisible,
        editorActive: _treeSearchEditorActive,
        query: widget.tree.treeSearchQuery,
      );
      _treeSearchController.value = TextEditingValue(
        text: widget.tree.treeSearchQuery,
        selection: TextSelection.collapsed(
          offset: widget.tree.treeSearchQuery.length,
        ),
      );
    }
    if (oldWidget.treeSearchRequestSerial != widget.treeSearchRequestSerial) {
      _logTreeSearchFocus(
        'didUpdateWidget:requestSerialChanged',
        detail:
            '${oldWidget.treeSearchRequestSerial}->${widget.treeSearchRequestSerial}',
        controller: _treeSearchController,
        treeFocusNode: _focusNode,
        searchFocusNode: _treeSearchFocusNode,
        overlayVisible: _treeSearchOverlayVisible,
        editorActive: _treeSearchEditorActive,
        query: widget.tree.treeSearchQuery,
      );
      _openTreeSearchOverlay(selectAll: true);
    }
    if (oldWidget.tree.selectedIdentity != widget.tree.selectedIdentity ||
        oldWidget.tree.treeSearchQuery != widget.tree.treeSearchQuery ||
        oldWidget.tree.visibleRows.length != widget.tree.visibleRows.length) {
      _scheduleRevealSelectedRow(resetRetryCount: true);
    }
    if (searchShouldKeepFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _logTreeSearchFocus(
          'didUpdateWidget:postFrameKeepFocus',
          detail: mounted ? 'mounted' : 'unmounted',
          controller: _treeSearchController,
          treeFocusNode: _focusNode,
          searchFocusNode: _treeSearchFocusNode,
          overlayVisible: _treeSearchOverlayVisible,
          editorActive: _treeSearchEditorActive,
          query: widget.tree.treeSearchQuery,
        );
        if (mounted &&
            _shouldShowTreeSearchOverlay &&
            !_treeSearchFocusNode.hasFocus) {
          _logTreeSearchFocus(
            'didUpdateWidget:restoreSearchFocus',
            controller: _treeSearchController,
            treeFocusNode: _focusNode,
            searchFocusNode: _treeSearchFocusNode,
            overlayVisible: _treeSearchOverlayVisible,
            editorActive: _treeSearchEditorActive,
            query: widget.tree.treeSearchQuery,
          );
          _treeSearchFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.onTreeHoverChanged(false);
    widget.onTreeContextMenuChanged(false);
    _treeSearchFocusNode.removeListener(_handleTreeSearchFocusChanged);
    _treeSearchFocusNode.dispose();
    _treeSearchController.dispose();
    _focusNode.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.tree.visibleRows;
    final columns = _visibleColumnDefinitions(widget.settings);
    if (rows.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                'resources/brand/lama-resting.svg',
                height: ProcessLamaTheme.emptyLamaHeight,
                excludeFromSemantics: true,
              ),
              MeridianEmptyState(
                icon: MeridianIcons.textSearch,
                title: context.l10n.noProcessesMatchFilter,
                message: context.l10n.filterNoMatchesHelp,
              ),
            ],
          ),
        ),
      );
    }

    final pinnedRows = rows
        .where((row) => widget.tree.pinnedIdentities.contains(row.identity))
        .toList(growable: false);

    final meridian = context.meridian;
    _rowExtent = meridian.density.rowExtent;
    final cpuScaleMax = widget.tree.cpuScaleMax;
    final visibleColumnIds = _normalizedVisibleColumnIds(
      widget.settings.visibleColumns,
    );
    // Whether the tree island has keyboard focus: its selection is then
    // solid accent.
    final islandFocused = MeridianSurfaceScope.maybeOf(context)?.focused;

    return MouseRegion(
      onEnter: (_) => widget.onTreeHoverChanged(true),
      onExit: (_) => widget.onTreeHoverChanged(false),
      child: Column(
        children: [
          if (pinnedRows.isNotEmpty)
            _PinnedProcessStrip(
              rows: pinnedRows,
              selectedIdentity: widget.selectedIdentity,
              onSelected: _selectRow,
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  key: const ValueKey('tree-table-focus'),
                  child: Focus(
                    focusNode: _focusNode,
                    autofocus: true,
                    onKeyEvent: _handleKeyEvent,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is UserScrollNotification ||
                            notification is ScrollStartNotification ||
                            notification is ScrollUpdateNotification) {
                          widget.onTreeInteraction();
                        }
                        return false;
                      },
                      child: Scrollbar(
                        controller: _verticalScrollController,
                        child: Padding(
                          // The Meridian list inset: the rounded selection
                          // bar never touches the island edge.
                          padding: const EdgeInsets.all(MeridianSpace.space3),
                          child: TableView.builder(
                            verticalDetails: ScrollableDetails.vertical(
                              controller: _verticalScrollController,
                            ),
                            horizontalDetails: ScrollableDetails.horizontal(
                              controller: _horizontalScrollController,
                            ),
                            pinnedRowCount: 1,
                            columnCount: columns.length,
                            rowCount: rows.length + 1,
                            cacheExtent: _rowExtent * 6,
                            columnBuilder: (index) =>
                                _buildColumnSpan(columns[index]),
                            rowBuilder: (index) => _buildRowSpan(
                              index,
                              rows: rows,
                              meridian: meridian,
                              islandFocused: islandFocused,
                            ),
                            cellBuilder: (context, vicinity) {
                              final column = columns[vicinity.column];
                              if (vicinity.row == 0) {
                                return TableViewCell(
                                  child: _TableHeaderCell(
                                    column: column,
                                    isLast:
                                        vicinity.column == columns.length - 1,
                                    sortColumn: widget.tree.sortColumn,
                                    sortDirection: widget.tree.sortDirection,
                                    onSort: widget.onSort,
                                    onMoveColumn: (from, to) {
                                      widget.onVisibleColumnsChanged(
                                        _moveColumnBefore(
                                          visibleColumnIds,
                                          from,
                                          to,
                                        ),
                                      );
                                    },
                                    onResizeColumn: _resizeColumn,
                                    onResetColumnWidth: _resetColumnWidth,
                                    columnMenuEntries: () => _columnMenuEntries(
                                      context: context,
                                      settings: widget.settings,
                                      onChanged: widget.onVisibleColumnsChanged,
                                    ),
                                  ),
                                );
                              }

                              final row = rows[vicinity.row - 1];
                              final isSelected =
                                  row.identity == widget.tree.selectedIdentity;
                              final isPinned = widget.tree.pinnedIdentities
                                  .contains(row.identity);
                              final isHovered =
                                  row.identity == _hoveredIdentity;
                              return TableViewCell(
                                child: _ProcessTableViewCell(
                                  rowFill: _processRowFill(
                                    context,
                                    row: row,
                                    settings: widget.settings,
                                    selected: isSelected,
                                    hovered: isHovered,
                                    focused: islandFocused,
                                  ),
                                  row: row,
                                  column: column,
                                  cpuScaleMax: cpuScaleMax,
                                  isSelected: isSelected,
                                  isHovered: isHovered,
                                  isPinned: isPinned,
                                  islandFocused: islandFocused,
                                  treeSearchQuery: widget.tree.treeSearchQuery,
                                  searchOptions: widget.tree.searchOptions,
                                  onSelected: _selectRow,
                                  onHoverChanged: _setHoveredRow,
                                  onToggleExpanded: widget.onToggleExpanded,
                                  onTogglePin: widget.onTogglePin,
                                  onFocusSubtree: widget.onFocusSubtree,
                                  onContextMenu: (position) =>
                                      _showRowMenu(row, isPinned, position),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_shouldShowTreeSearchOverlay)
                  PositionedDirectional(
                    key: const ValueKey('tree-search-overlay'),
                    top: MeridianSpace.space3 + _processHeaderHeight,
                    end: MeridianSpace.space6,
                    child: _TreeSearchOverlay(
                      controller: _treeSearchController,
                      focusNode: _treeSearchFocusNode,
                      currentMatchIndex:
                          widget.tree.treeSearchSelectedMatchIndex,
                      matchCount: widget.tree.treeSearchMatchCount,
                      onChanged: widget.onTreeSearchChanged,
                      onNext: widget.onSelectNextTreeSearchMatch,
                      onPrevious: widget.onSelectPreviousTreeSearchMatch,
                      onClear: _clearTreeSearchOverlay,
                      onEditingStarted: _activateTreeSearchEditor,
                      onEditingFinished: _deactivateTreeSearchEditor,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRowMenu(
    ProcessTreeRow row,
    bool isPinned,
    Offset position,
  ) async {
    _selectRow(row.identity);
    final onMenuChanged = widget.onTreeContextMenuChanged;
    onMenuChanged(true);
    try {
      await showMeridianContextMenu(
        context,
        globalPosition: position,
        entries: _processMenuEntries(
          context: context,
          row: row,
          isPinned: isPinned,
          onTogglePin: widget.onTogglePin,
          onFocusSubtree: widget.onFocusSubtree,
          onTerminateProcess: widget.onTerminateProcess,
          onKillProcess: widget.onKillProcess,
          onSuspendProcess: widget.onSuspendProcess,
          onResumeProcess: widget.onResumeProcess,
          onExpandSubtree: widget.onExpandSubtree,
          onCollapseSubtree: widget.onCollapseSubtree,
        ),
      );
    } finally {
      if (mounted) {
        onMenuChanged(false);
      }
    }
  }

  void _selectRow(ProcessIdentity identity) {
    _logTreeSearchFocus(
      'selectRow',
      detail: '$identity',
      controller: _treeSearchController,
      treeFocusNode: _focusNode,
      searchFocusNode: _treeSearchFocusNode,
      overlayVisible: _treeSearchOverlayVisible,
      editorActive: _treeSearchEditorActive,
      query: widget.tree.treeSearchQuery,
    );
    _treeSearchEditorActive = false;
    _focusNode.requestFocus();
    widget.onSelected(identity);
  }

  void _setHoveredRow(ProcessIdentity identity, bool hovered) {
    final next = hovered
        ? identity
        : _hoveredIdentity == identity
        ? null
        : _hoveredIdentity;
    if (next == _hoveredIdentity) {
      return;
    }
    setState(() => _hoveredIdentity = next);
  }

  bool get _shouldShowTreeSearchOverlay {
    return _isTreeSearchActive;
  }

  bool get _isTreeSearchActive {
    return widget.tree.treeSearchQuery.isNotEmpty ||
        _treeSearchOverlayVisible ||
        _treeSearchFocusNode.hasFocus;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    _logTreeSearchFocus(
      'handleKeyEvent:entry',
      controller: _treeSearchController,
      treeFocusNode: _focusNode,
      searchFocusNode: _treeSearchFocusNode,
      overlayVisible: _treeSearchOverlayVisible,
      editorActive: _treeSearchEditorActive,
      query: widget.tree.treeSearchQuery,
      keyEvent: event,
    );
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      _logTreeSearchFocus('handleKeyEvent:ignoredNonDown', keyEvent: event);
      return KeyEventResult.ignored;
    }

    final query = widget.tree.treeSearchQuery;
    final key = event.logicalKey;
    if (_isFindShortcut(event)) {
      _logTreeSearchFocus(
        'handleKeyEvent:findShortcut',
        controller: _treeSearchController,
        treeFocusNode: _focusNode,
        searchFocusNode: _treeSearchFocusNode,
        overlayVisible: _treeSearchOverlayVisible,
        editorActive: _treeSearchEditorActive,
        query: query,
        keyEvent: event,
      );
      _openTreeSearchOverlay(selectAll: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _logTreeSearchFocus(
        'handleKeyEvent:escape',
        detail: 'searchActive=$_isTreeSearchActive',
        controller: _treeSearchController,
        treeFocusNode: _focusNode,
        searchFocusNode: _treeSearchFocusNode,
        overlayVisible: _treeSearchOverlayVisible,
        editorActive: _treeSearchEditorActive,
        query: query,
        keyEvent: event,
      );
      if (_isTreeSearchActive) {
        _stopTreeSearch();
      } else {
        widget.onPopSubtreeFocus();
      }
      return KeyEventResult.handled;
    }
    if (_treeSearchFocusNode.hasFocus) {
      if (key == LogicalKeyboardKey.enter && query.isNotEmpty) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          widget.onSelectPreviousTreeSearchMatch();
        } else {
          widget.onSelectNextTreeSearchMatch();
        }
        return KeyEventResult.handled;
      }
      _logTreeSearchFocus(
        'handleKeyEvent:searchFieldHasFocusSkipRemaining',
        controller: _treeSearchController,
        treeFocusNode: _focusNode,
        searchFocusNode: _treeSearchFocusNode,
        overlayVisible: _treeSearchOverlayVisible,
        editorActive: _treeSearchEditorActive,
        query: query,
        keyEvent: event,
      );
      return KeyEventResult.skipRemainingHandlers;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      widget.onSelectNext();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.onSelectPrevious();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight &&
        HardwareKeyboard.instance.isAltPressed) {
      widget.onExpandSelectedSubtree();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft &&
        HardwareKeyboard.instance.isAltPressed) {
      widget.onCollapseSelectedSubtree();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onExpandSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onCollapseSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isShiftPressed) {
      widget.onFocusSelectedSubtree();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace && query.isNotEmpty) {
      widget.onTreeSearchChanged(query.substring(0, query.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && query.isNotEmpty) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        widget.onSelectPreviousTreeSearchMatch();
      } else {
        widget.onSelectNextTreeSearchMatch();
      }
      return KeyEventResult.handled;
    }

    final character = event.character;
    if (_isTreeSearchCharacter(character)) {
      _logTreeSearchFocus(
        'handleKeyEvent:typeToSearch',
        detail: 'append="$character"',
        controller: _treeSearchController,
        treeFocusNode: _focusNode,
        searchFocusNode: _treeSearchFocusNode,
        overlayVisible: _treeSearchOverlayVisible,
        editorActive: _treeSearchEditorActive,
        query: query,
        keyEvent: event,
      );
      _showTreeSearchOverlay();
      widget.onTreeSearchChanged(query + character!);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _isFindShortcut(KeyEvent event) {
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    return event.logicalKey == LogicalKeyboardKey.keyF &&
        (isMac
            ? HardwareKeyboard.instance.isMetaPressed
            : HardwareKeyboard.instance.isControlPressed);
  }

  bool _isTreeSearchCharacter(String? character) {
    if (character == null ||
        character.isEmpty ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return false;
    }
    return !character.codeUnits.any((unit) => unit < 0x20 || unit == 0x7F);
  }

  void _openTreeSearchOverlay({bool selectAll = false}) {
    _logTreeSearchFocus(
      'openOverlay',
      detail: 'selectAll=$selectAll',
      controller: _treeSearchController,
      treeFocusNode: _focusNode,
      searchFocusNode: _treeSearchFocusNode,
      overlayVisible: _treeSearchOverlayVisible,
      editorActive: _treeSearchEditorActive,
      query: widget.tree.treeSearchQuery,
    );
    _showTreeSearchOverlay();
    _treeSearchEditorActive = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logTreeSearchFocus(
        'openOverlay:postFrame',
        detail: 'selectAll=$selectAll mounted=$mounted',
        controller: _treeSearchController,
        treeFocusNode: _focusNode,
        searchFocusNode: _treeSearchFocusNode,
        overlayVisible: _treeSearchOverlayVisible,
        editorActive: _treeSearchEditorActive,
        query: widget.tree.treeSearchQuery,
      );
      if (!mounted) {
        return;
      }
      if (!_treeSearchFocusNode.hasFocus) {
        _logTreeSearchFocus(
          'openOverlay:requestSearchFocus',
          controller: _treeSearchController,
          treeFocusNode: _focusNode,
          searchFocusNode: _treeSearchFocusNode,
          overlayVisible: _treeSearchOverlayVisible,
          editorActive: _treeSearchEditorActive,
          query: widget.tree.treeSearchQuery,
        );
        _treeSearchFocusNode.requestFocus();
      }
      if (selectAll) {
        _treeSearchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _treeSearchController.text.length,
        );
      }
    });
  }

  void _showTreeSearchOverlay() {
    _logTreeSearchFocus(
      'showOverlay',
      controller: _treeSearchController,
      treeFocusNode: _focusNode,
      searchFocusNode: _treeSearchFocusNode,
      overlayVisible: _treeSearchOverlayVisible,
      editorActive: _treeSearchEditorActive,
      query: widget.tree.treeSearchQuery,
    );
    if (!_treeSearchOverlayVisible) {
      setState(() => _treeSearchOverlayVisible = true);
    }
  }

  void _clearTreeSearchOverlay() {
    _logTreeSearchFocus(
      'clearOverlay',
      controller: _treeSearchController,
      treeFocusNode: _focusNode,
      searchFocusNode: _treeSearchFocusNode,
      overlayVisible: _treeSearchOverlayVisible,
      editorActive: _treeSearchEditorActive,
      query: widget.tree.treeSearchQuery,
    );
    _stopTreeSearch();
  }

  void _stopTreeSearch() {
    _logTreeSearchFocus(
      'stopSearch',
      controller: _treeSearchController,
      treeFocusNode: _focusNode,
      searchFocusNode: _treeSearchFocusNode,
      overlayVisible: _treeSearchOverlayVisible,
      editorActive: _treeSearchEditorActive,
      query: widget.tree.treeSearchQuery,
    );
    _treeSearchController.clear();
    widget.onTreeSearchChanged('');
    _hideTreeSearchOverlay();
  }

  void _hideTreeSearchOverlay() {
    _logTreeSearchFocus(
      'hideOverlay',
      controller: _treeSearchController,
      treeFocusNode: _focusNode,
      searchFocusNode: _treeSearchFocusNode,
      overlayVisible: _treeSearchOverlayVisible,
      editorActive: _treeSearchEditorActive,
      query: widget.tree.treeSearchQuery,
    );
    _treeSearchEditorActive = false;
    if (_treeSearchOverlayVisible) {
      setState(() => _treeSearchOverlayVisible = false);
    }
    _focusNode.requestFocus();
  }

  void _activateTreeSearchEditor() {
    _logTreeSearchFocus(
      'activateEditor',
      controller: _treeSearchController,
      treeFocusNode: _focusNode,
      searchFocusNode: _treeSearchFocusNode,
      overlayVisible: _treeSearchOverlayVisible,
      editorActive: _treeSearchEditorActive,
      query: widget.tree.treeSearchQuery,
    );
    _treeSearchEditorActive = true;
  }

  void _deactivateTreeSearchEditor() {
    _logTreeSearchFocus(
      'deactivateEditor',
      controller: _treeSearchController,
      treeFocusNode: _focusNode,
      searchFocusNode: _treeSearchFocusNode,
      overlayVisible: _treeSearchOverlayVisible,
      editorActive: _treeSearchEditorActive,
      query: widget.tree.treeSearchQuery,
    );
    _treeSearchEditorActive = false;
  }

  void _handleTreeSearchFocusChanged() {
    _logTreeSearchFocus(
      'searchFocusChanged',
      controller: _treeSearchController,
      treeFocusNode: _focusNode,
      searchFocusNode: _treeSearchFocusNode,
      overlayVisible: _treeSearchOverlayVisible,
      editorActive: _treeSearchEditorActive,
      query: widget.tree.treeSearchQuery,
    );
    if (_treeSearchFocusNode.hasFocus) {
      _treeSearchEditorActive = true;
      return;
    }
    if (_treeSearchEditorActive && _shouldShowTreeSearchOverlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _logTreeSearchFocus(
          'searchFocusChanged:postFrameRestoreCheck',
          detail: mounted ? 'mounted' : 'unmounted',
          controller: _treeSearchController,
          treeFocusNode: _focusNode,
          searchFocusNode: _treeSearchFocusNode,
          overlayVisible: _treeSearchOverlayVisible,
          editorActive: _treeSearchEditorActive,
          query: widget.tree.treeSearchQuery,
        );
        if (mounted &&
            _treeSearchEditorActive &&
            _shouldShowTreeSearchOverlay &&
            !_treeSearchFocusNode.hasFocus) {
          _logTreeSearchFocus(
            'searchFocusChanged:restoreSearchFocus',
            controller: _treeSearchController,
            treeFocusNode: _focusNode,
            searchFocusNode: _treeSearchFocusNode,
            overlayVisible: _treeSearchOverlayVisible,
            editorActive: _treeSearchEditorActive,
            query: widget.tree.treeSearchQuery,
          );
          _treeSearchFocusNode.requestFocus();
        }
      });
      return;
    }
    if (!_treeSearchFocusNode.hasFocus &&
        _treeSearchController.text.isEmpty &&
        _treeSearchOverlayVisible) {
      setState(() => _treeSearchOverlayVisible = false);
    }
  }

  void _resizeColumn(String columnId, double width) {
    widget.onTreeInteraction();
    widget.onColumnWidthsChanged({
      ...widget.settings.columnWidths,
      columnId: _clampColumnWidth(columnId, width),
    });
  }

  void _resetColumnWidth(String columnId) {
    widget.onTreeInteraction();
    final next = Map<String, double>.of(widget.settings.columnWidths)
      ..remove(columnId);
    widget.onColumnWidthsChanged(next);
  }

  double _columnWidth(_ProcessColumn column) {
    final width = widget.settings.columnWidths[column.id];
    if (width == null) {
      return column.flex > 0 ? _defaultFlexColumnWidth : column.width;
    }
    return _clampColumnWidth(column.id, width);
  }

  double _clampColumnWidth(String columnId, double width) {
    return width.clamp(
      columnId == 'name' ? 180.0 : 52.0,
      columnId == 'name' ? 960.0 : 360.0,
    );
  }

  void _scheduleRevealSelectedRow({bool resetRetryCount = false}) {
    if (resetRetryCount) {
      _revealSelectedRowRetryCount = 0;
    }
    if (_revealSelectedRowScheduled) {
      return;
    }
    _revealSelectedRowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealSelectedRowScheduled = false;
      if (!mounted) {
        return;
      }
      _revealSelectedRow();
    });
  }

  void _revealSelectedRow() {
    final selected = widget.tree.selectedIdentity;
    if (selected == null) {
      return;
    }
    if (!_verticalScrollController.hasClients ||
        !_verticalScrollController.position.hasContentDimensions) {
      if (kDebugMode) {
        recordDiagnostic(
          const DiagnosticEvent(
            'processlama.process_tree_table.diagnostic',
            detailed: true,
          ),
        );
      }
      if (_revealSelectedRowRetryCount < 4) {
        _revealSelectedRowRetryCount++;
        _scheduleRevealSelectedRow();
      }
      return;
    }

    final index = widget.tree.visibleRows.indexWhere(
      (row) => row.identity == selected,
    );
    if (index < 0) {
      if (kDebugMode) {
        recordDiagnostic(
          const DiagnosticEvent(
            'processlama.process_tree_table.diagnostic',
            detailed: true,
          ),
        );
      }
      return;
    }

    final position = _verticalScrollController.position;
    // TableView scroll offsets are in full-content coordinates, including the
    // pinned header. Keep the selected row below that header when revealing it.
    final viewportHeaderBottom = position.pixels + _processHeaderHeight;
    final viewportBottom = position.pixels + position.viewportDimension;
    final rowTop = _processHeaderHeight + index * _rowExtent;
    final rowBottom = rowTop + _rowExtent;

    double? target;
    if (rowTop < viewportHeaderBottom) {
      target = rowTop - _processHeaderHeight;
    } else if (rowBottom > viewportBottom) {
      target = rowBottom - position.viewportDimension;
    }
    if (kDebugMode) {
      recordDiagnostic(
        const DiagnosticEvent(
          'processlama.process_tree_table.diagnostic',
          detailed: true,
        ),
      );
    }
    if (target == null) {
      return;
    }

    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clamped - position.pixels).abs() < 0.5) {
      return;
    }
    _verticalScrollController.jumpTo(clamped);
  }

  TableSpan _buildColumnSpan(_ProcessColumn column) {
    final storedWidth = widget.settings.columnWidths[column.id];
    final extent = column.flex > 0 && storedWidth == null
        ? const MinTableSpanExtent(
            MaxTableSpanExtent(
              FixedTableSpanExtent(_defaultFlexColumnWidth),
              RemainingTableSpanExtent(),
            ),
            FixedTableSpanExtent(_maxInitialFlexColumnWidth),
          )
        : FixedTableSpanExtent(_columnWidth(column));
    return TableSpan(extent: extent);
  }

  /// The header is a `pane-alt` bar; a process row paints its selection,
  /// hover, search match or CPU heat as one inset rounded bar.
  TableSpan _buildRowSpan(
    int index, {
    required List<ProcessTreeRow> rows,
    required MeridianTheme meridian,
    required bool? islandFocused,
  }) {
    final radius = BorderRadius.circular(meridian.radius.sm);
    if (index == 0) {
      return TableSpan(
        extent: const FixedTableSpanExtent(_processHeaderHeight),
        backgroundDecoration: TableSpanDecoration(
          color: meridian.colors.paneAlt,
          borderRadius: radius,
        ),
      );
    }
    final row = rows[index - 1];
    final fill = _processRowFill(
      context,
      row: row,
      settings: widget.settings,
      selected: row.identity == widget.tree.selectedIdentity,
      hovered: row.identity == _hoveredIdentity,
      focused: islandFocused,
    );
    return TableSpan(
      extent: FixedTableSpanExtent(_rowExtent),
      backgroundDecoration: fill.a == 0
          ? null
          : TableSpanDecoration(color: fill, borderRadius: radius),
    );
  }
}

/// The fill of a process row: selection, then hover, then a tree search
/// match, then the CPU heat tint.
Color _processRowFill(
  BuildContext context, {
  required ProcessTreeRow row,
  required AppSettings settings,
  required bool selected,
  required bool hovered,
  required bool? focused,
}) {
  final app = ProcessLamaTheme.of(context);
  if (selected || hovered) {
    return MeridianRowColors.resolve(
      context,
      selected: selected,
      hovered: hovered,
      focused: focused,
    ).fill;
  }
  if (row.matchesTreeSearch) {
    return app.searchMatchRow;
  }
  final heat = settings.rowHeatmap
      ? (row.treeCpuUsage / 100).clamp(0.0, 1.0)
      : 0.0;
  return app.rowHeat.withValues(
    alpha: ProcessLamaTheme.maxRowHeatOpacity * heat,
  );
}

class _PinnedProcessStrip extends StatelessWidget {
  const _PinnedProcessStrip({
    required this.rows,
    required this.selectedIdentity,
    required this.onSelected,
  });

  final List<ProcessTreeRow> rows;
  final ValueListenable<ProcessIdentity?> selectedIdentity;
  final ValueChanged<ProcessIdentity> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MeridianLayout.chipHeight + MeridianSpace.space3 * 2,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          MeridianSpace.space3,
          MeridianSpace.space3,
          MeridianSpace.space3,
          0,
        ),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(width: MeridianSpace.space3),
        itemBuilder: (context, index) {
          final row = rows[index];
          return _SelectionAwareBuilder(
            identity: row.identity,
            selectedIdentity: selectedIdentity,
            builder: (context, isSelected) => MeridianChip(
              label: row.record.displayName,
              icon: MeridianIcons.pin,
              selected: isSelected,
              onPressed: () => onSelected(row.identity),
            ),
          );
        },
      ),
    );
  }
}

class _TreeSearchOverlay extends StatefulWidget {
  const _TreeSearchOverlay({
    required this.controller,
    required this.focusNode,
    required this.currentMatchIndex,
    required this.matchCount,
    required this.onChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClear,
    required this.onEditingStarted,
    required this.onEditingFinished,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int currentMatchIndex;
  final int matchCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClear;
  final VoidCallback onEditingStarted;
  final VoidCallback onEditingFinished;

  @override
  State<_TreeSearchOverlay> createState() => _TreeSearchOverlayState();
}

class _TreeSearchOverlayState extends State<_TreeSearchOverlay> {
  static const double _fieldWidth = 200;

  @override
  Widget build(BuildContext context) {
    final meridian = context.meridian;
    final l10n = context.l10n;
    final current = widget.currentMatchIndex < 0
        ? 0
        : widget.currentMatchIndex + 1;
    final canNavigate = widget.matchCount > 0;
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    return MeridianTextScope(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: meridian.colors.raised,
          borderRadius: BorderRadius.circular(meridian.radius.lg),
          boxShadow: meridian.shadows.shadowFloat,
        ),
        child: Padding(
          padding: const EdgeInsets.all(MeridianSpace.space2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CallbackShortcuts(
                bindings: {
                  SingleActivator(
                    LogicalKeyboardKey.keyF,
                    meta: isMac,
                    control: !isMac,
                  ): _handleFindShortcut,
                  const SingleActivator(LogicalKeyboardKey.escape): () {
                    _logOverlay('escape');
                    widget.onClear();
                  },
                  const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                      _handleEnter(shift: true),
                  const SingleActivator(LogicalKeyboardKey.enter): _handleEnter(
                    shift: false,
                  ),
                },
                child: Semantics(
                  value: l10n.searchMatchPosition(
                    '$current',
                    '${widget.matchCount}',
                  ),
                  child: MeridianTextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    variant: MeridianTextFieldVariant.search,
                    width: _fieldWidth,
                    trailingText: '$current/${widget.matchCount}',
                    onChanged: (value) {
                      _logOverlay(
                        'textField:onChanged',
                        detail: 'value="$value"',
                      );
                      widget.onChanged(value);
                    },
                  ),
                ),
              ),
              const SizedBox(width: MeridianSpace.space2),
              MeridianIconButton(
                label: l10n.previousSearchMatch,
                icon: MeridianIcons.chevronUp,
                canRequestFocus: false,
                onPressed: canNavigate ? widget.onPrevious : null,
              ),
              MeridianIconButton(
                label: l10n.nextSearchMatch,
                icon: MeridianIcons.chevronDown,
                canRequestFocus: false,
                onPressed: canNavigate ? widget.onNext : null,
              ),
              MeridianIconButton(
                label: l10n.clearSearch,
                icon: MeridianIcons.x,
                canRequestFocus: false,
                onPressed: widget.onClear,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleFindShortcut() {
    _logOverlay('findShortcut');
    widget.focusNode.requestFocus();
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.controller.text.length,
    );
  }

  VoidCallback _handleEnter({required bool shift}) {
    return () {
      if (widget.controller.text.isEmpty) {
        return;
      }
      _logOverlay('enter', detail: 'shift=$shift');
      if (shift) {
        widget.onPrevious();
      } else {
        widget.onNext();
      }
    };
  }

  void _logOverlay(String event, {String? detail}) {
    _logTreeSearchFocus(
      event,
      detail: detail,
      controller: widget.controller,
      searchFocusNode: widget.focusNode,
    );
  }
}

class _ProcessTableViewCell extends StatelessWidget {
  const _ProcessTableViewCell({
    required this.rowFill,
    required this.row,
    required this.column,
    required this.cpuScaleMax,
    required this.isSelected,
    required this.isHovered,
    required this.isPinned,
    required this.islandFocused,
    required this.treeSearchQuery,
    required this.searchOptions,
    required this.onSelected,
    required this.onHoverChanged,
    required this.onToggleExpanded,
    required this.onTogglePin,
    required this.onFocusSubtree,
    required this.onContextMenu,
  });

  /// The row's bar (selection, hover, match or heat), painted by the table.
  /// Controls in the cell hover relative to it.
  final Color rowFill;
  final ProcessTreeRow row;
  final _ProcessColumn column;
  final double cpuScaleMax;
  final bool isSelected;
  final bool isHovered;
  final bool isPinned;
  final bool? islandFocused;
  final String treeSearchQuery;
  final ProcessSearchOptions searchOptions;
  final ValueChanged<ProcessIdentity> onSelected;
  final void Function(ProcessIdentity identity, bool hovered) onHoverChanged;
  final ValueChanged<ProcessIdentity> onToggleExpanded;
  final ValueChanged<ProcessIdentity> onTogglePin;
  final ValueChanged<ProcessIdentity> onFocusSubtree;
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final rowColors = MeridianRowColors.resolve(
      context,
      selected: isSelected,
      hovered: isHovered,
      focused: islandFocused,
    );
    return MouseRegion(
      onEnter: (_) => onHoverChanged(row.identity, true),
      onExit: (_) => onHoverChanged(row.identity, false),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons & kPrimaryButton != 0) {
            onSelected(row.identity);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapUp: (details) => onContextMenu(details.globalPosition),
          child: _StructuralRowTransition(
            changeMarker: row.changeMarker,
            child: MeridianSurfaceScope.withFill(
              context,
              fill: rowFill,
              child: _ProcessCell(
                column: column,
                row: row,
                cpuScaleMax: cpuScaleMax,
                rowColors: rowColors,
                isSelected: isSelected,
                isHovered: isHovered,
                isPinned: isPinned,
                treeSearchQuery: treeSearchQuery,
                searchOptions: searchOptions,
                onToggleExpanded: onToggleExpanded,
                onTogglePin: onTogglePin,
                onFocusSubtree: onFocusSubtree,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Spawned rows rise into place; terminated rows fade before they leave.
class _StructuralRowTransition extends StatelessWidget {
  const _StructuralRowTransition({
    required this.changeMarker,
    required this.child,
  });

  final ProcessChangeMarker changeMarker;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final content = changeMarker == ProcessChangeMarker.terminated
        ? Opacity(opacity: MeridianOpacity.dimmedRow, child: child)
        : child;
    if (MeridianMotion.reduced(context) ||
        changeMarker != ProcessChangeMarker.spawned) {
      return content;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: MeridianSpace.space3, end: 0),
      duration: MeridianDurations.emphasized,
      curve: MeridianDurations.emphasizedCurve,
      builder: (context, slide, child) {
        return Transform.translate(offset: Offset(0, slide), child: child);
      },
      child: content,
    );
  }
}

/// A column heading: sorts on click, reorders by dragging, resizes from
/// its trailing grip, and opens the column menu on secondary click.
class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell({
    required this.column,
    required this.isLast,
    required this.sortColumn,
    required this.sortDirection,
    required this.onSort,
    required this.onMoveColumn,
    required this.onResizeColumn,
    required this.onResetColumnWidth,
    required this.columnMenuEntries,
  });

  static const double _gripWidth = MeridianSpace.space4;

  final _ProcessColumn column;
  final bool isLast;
  final ProcessSortColumn sortColumn;
  final ProcessSortDirection sortDirection;
  final ValueChanged<ProcessSortColumn> onSort;
  final void Function(String fromColumnId, String toColumnId) onMoveColumn;
  final void Function(String columnId, double width) onResizeColumn;
  final ValueChanged<String> onResetColumnWidth;
  final List<MeridianMenuEntry> Function() columnMenuEntries;

  @override
  Widget build(BuildContext context) {
    final meridian = context.meridian;
    final colors = meridian.colors;
    final l10n = context.l10n;
    final direction = sortColumn == column.sortColumn
        ? (sortDirection == ProcessSortDirection.ascending
              ? MeridianSortDirection.ascending
              : MeridianSortDirection.descending)
        : null;
    Widget header({VoidCallback? onPressed}) => MeridianColumnHeader(
      label: _columnLabel(context, column.id),
      alignEnd: column.numeric,
      sortDirection: direction,
      sortedAscendingLabel: l10n.sortedAscending,
      sortedDescendingLabel: l10n.sortedDescending,
      onPressed: onPressed,
      onContextMenu: (position) => showMeridianContextMenu(
        context,
        globalPosition: position,
        entries: columnMenuEntries(),
      ),
    );

    return DragTarget<String>(
      onAcceptWithDetails: (details) {
        if (details.data != column.id) {
          onMoveColumn(details.data, column.id);
        }
      },
      builder: (context, candidateData, _) {
        final highlighted = candidateData.any((id) => id != column.id);
        return LayoutBuilder(
          builder: (context, constraints) {
            return DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: highlighted
                    ? BorderDirectional(
                        start: BorderSide(
                          color: colors.accent,
                          width: MeridianLayout.resizeRule,
                        ),
                      )
                    : null,
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Draggable<String>(
                      data: column.id,
                      axis: Axis.horizontal,
                      feedback: MeridianTextScope(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.raised,
                            borderRadius: BorderRadius.circular(
                              meridian.radius.sm,
                            ),
                            boxShadow: meridian.shadows.shadowFloat,
                          ),
                          child: SizedBox(
                            width: _columnDragWidth(column),
                            height: _processHeaderHeight,
                            child: header(),
                          ),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: MeridianOpacity.dimmedRow,
                        child: header(),
                      ),
                      child: header(onPressed: () => onSort(column.sortColumn)),
                    ),
                  ),
                  if (!isLast)
                    PositionedDirectional(
                      top: MeridianSpace.space3,
                      bottom: MeridianSpace.space3,
                      end: 0,
                      child: const MeridianHairline(axis: Axis.vertical),
                    ),
                  PositionedDirectional(
                    top: 0,
                    end: 0,
                    bottom: 0,
                    width: _gripWidth,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onDoubleTap: () => onResetColumnWidth(column.id),
                        onHorizontalDragUpdate: (details) {
                          onResizeColumn(
                            column.id,
                            constraints.maxWidth + details.delta.dx,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
