# QML port parity inventory (working notes)

Source of truth: Flutter implementation at origin/main 15f9a04 (v1.0.0-beta.38).
Each item must exist in the QML + Rust port. Check off with the file that implements it.

## Shell / window
- Default window 1180x760, min 900x560, centered. Title "ProcessLama".
- macOS: hidden title bar, unified toolbar; traffic lights end at 79pt; title inset 79+space7.
- Linux: frameless-ish CSD; own min/max/close icon buttons at the right of toolbar (minus, square, x).
  Window background follows Meridian `ground` (no flash in resize gaps).
- Windows: normal title bar.
- Toolbar area is drag-to-move (whole toolbar background), title text ignores pointer.
- F11 toggles fullscreen.
- Shortcuts (Cmd on mac, Ctrl elsewhere): F = tree search, T = open "+" tab menu, 1..9 activate tab index,
  Shift+[ / Shift+] cycle tabs back/forward.
- On window resize: setWindowResizing(true) pauses sampling; 200ms after last resize event -> resume + refresh.
- Bootstrap: loading screen = ground + spinner(space8); error screen = island, circleX icon (danger, emptyStateIconSize),
  title, description muted, selectable details on paneAlt radius md codeSm.
- macOS native launch screen dismissed after first frame.
- Settings flush on exit.

## Layout (top to bottom)
1. Toolbar (height MeridianSize.toolbar), padding start space6 (mac: 79+space7), end space5.
   - Title block (max 180): appTitle bodyStrong + source caption muted ("Live <platform>" or snapshot label).
   - space7, filter field (max 440, flexible) Search variant; placeholder per aspect (searchHint / searchPortHint / "<Aspect>…");
     clearLabel; trailing = aspect menu icon button (listFilter, small, active when aspect!=all||matchCase||wholeWord;
     label "Search aspect: X"). Menu: all aspects checked radio; divider + Match case (caseSensitive icon), Whole word (wholeWord icon) unless port aspect.
   - space2, bookmarkPlus icon button "Save current filter" (disabled when empty) -> addSavedFilter(options.savedQuery(filter)).
   - listFilter icon button "Saved filters" menu (disabled reason noSavedFilters) items checked when text+aspect match.
   - Spacer; MeridianSelect polling interval (500,1000,2000,5000 + current, sorted, "N ms").
   - space5; toolbar buttons (show labels when width >= 1120): Lock (lock/lockOpen, selected when frozen, tooltip lock/unlock),
     Snapshot (camera; split menu: Take snapshot / Open snapshot (folderOpen)), Updates (download; only if update supported),
     Inspector (panelRight, selected when open; tooltip hide/show), Preferences (settings; Linux: split menu "Install network telemetry").
   - Linux: space3 + minimize/maximize(toggle)/close icon buttons.
2. Workspace tab strip (height tabStripHeight, ground, padding h space3):
   - Local pill (width tabPillMinWidth, height tabPillHeight, monitor icon, selected = pane + shadowPane, hover groundHover with hover duration).
   - MeridianTabStrip of remote tabs (status dot leading w/ halo when live; tooltip "alias · platform · compat"; semantic label;
     close; reorder by drag; move left/right labels; not renamable). Max width = remaining.
   - Overflow chevronDown button when remote.length*tabPillMinWidth > stripWidth -> menu of all tabs (checked active).
   - "+" button (plus, small, onGround) -> menu: closed profiles (status dot leading, hint = phase), "No other hosts" when empty,
     divider, Add remote host (circlePlus), Manage remote hosts (server -> Preferences/Remote hosts).
   - Opening tab beyond limit -> error toast remoteTabLimit(max).
3. Remote tab banner (only for remote tab, hidden when snapshot loaded), padding (space3,0,space3,space3).
4. Body row, padding h space3: sidebar (216) | space3 | tree island (expanded) | resize handle (if inspector open; drag left widens; double-click reset) | inspector (animated width, emphasized, opacity, clip inflated by space2 for shadow).
5. Status bar.

## Sidebar (navigation_rail.dart)
- ListView padding bottom space3. Sections: Pinned (max 6; hint "Pin rows for quick access"), Snapshots (action: open + take icon buttons small;
  "Live <platform>" row with activity icon + trailing "now", selected when no snapshot; up to 6 snapshots history icon, count = processCount,
  selected when loaded; context menu Rename (pencil) / Export (download) / divider / Delete (trash2, danger)), Filters (max 8; listFilter icon,
  count = matching processes; selected when text+aspect match; context menu Delete filter).
- Pinned rows: NavRow label displayName, leading process icon (density iconSmallSize), trailing pid (codeSm numeric), selected.
- Bottom-left brand button (control x control) lama-signature.svg height icon size, inkFaint -> inkMuted on hover/focus,
  hover fill groundHover; tooltip brandTooltip; semantics "About ProcessLama" -> About dialog.

## Tree island
- Subtree focus bar (height islandHeader, accentSoft, bottom line): listTree icon accentInk small, "Focused on <name>" bodyStrong,
  icon button back (arrowLeft) / leave (x) depending on stack, space1, quiet small button "Show full tree" (listTree).
- Empty: lama-resting.svg (height 48) + EmptyState textSearch "No processes match filter"/help.
- Pinned strip (when pinned rows visible): horizontal chips (pin icon, selected) height chipHeight+2*space3, padding space3 (no bottom), gap space3.
- Table: padding space3 inset, header row pinned (height MeridianSize.control) paneAlt rounded sm; rows height density.rowExtent;
  row fill = selection/hover (MeridianRowColors, focused => solid accent), else search match row (warningBg), else heat (accent * 0.12 * treeCpu/100) when heatmap.
  Rows rounded radius.sm. Scrollbar thumb (MeridianScrollbarThumb). Horizontal scroll.
- Column widths: name flex default 360 (min of max(360, remaining), 440) until dragged; others fixed; clamp name 180..960, others 52..360.
- Header cell: MeridianColumnHeader (alignEnd numeric, sort arrow, sorted asc/desc labels), click sorts, drag to reorder (feedback raised + shadowFloat, child dimmed while dragging; drop target shows accent start border resizeRule),
  hairline separators (vertical, top/bottom space3) except last, resize grip width space4 (resizeColumn cursor; double-click resets), context menu = column menu
  (header "Columns", every column checkable (name disabled), divider, Show all columns, Reset column order).
- Cell: hover tracking per row identity; primary pointer down selects; secondary click opens row menu (selects first; marks context menu open for order lock).
- Spawned rows: slide from +space3 to 0 (emphasized) unless reduced motion; terminated rows dimmedRow opacity + name strikethrough.
- Name cell: indent space3 + depth*treeIndent; change marker icon (circlePlus success / circleMinus danger, tooltip Spawned/Terminated, navChevronTarget wide);
  chevron icon button (expand/collapse, small) when children; space1; double-click name area focuses subtree (not terminated); icon avatarSmall; name (bodyStrong when selected,
  primary color, highlight matched search span); descendant count codeSm secondary; sparkline 52x14 (cpu history, scale max = global cpuScaleMax, line chartLine 1px round, endpoint circle r1.6 accent, NaN gaps lift pen; color override when strong selection);
  pin button (controlSm wide) shown when pinned||hovered||selected (accentInk when pinned & not strong).
- CPU/TreeCPU cells: MeridianMeter (warningAt 0.5, color primary when strong; no animation) + space3 + 44px right-aligned value; warning color when >=50% and not strong; w600 when >=10%.
- Status cell: status dot (running success+halo, stopped warning, zombie danger, else neutral) + Capitalized label.
- Other cells: numeric right aligned code font tabular secondary; search highlight background on first match.
- Formatting: bytes 'B','KB','MB','GB','TB' 1024 with 0 decimals for B else 1; rate = bytes + '/s'; percent '0.0%' when <=0, else 1 decimal under 10 else 0; start time HH:mm:ss local; ports "8080, 5432 +12"; '-' when storage unavailable / ports unknown.
- Keyboard (tree focused): Cmd/Ctrl+F open search overlay (select all); Esc: stop search if active else pop subtree focus; Down/Up select next/prev (skip terminated);
  Alt+Right/Left expand/collapse subtree; Right expand / Left collapse-or-select-parent; Shift+Enter focus subtree; Backspace trims search; Enter/Shift+Enter next/prev match;
  printable chars (no ctrl/meta/alt) type-to-search (opens overlay).
- Reveal selected row: after selection/search/visible-count change, jump so the row sits below the pinned header.
- Tree search overlay: top = space3 + header height, end space6; raised, radius lg, shadowFloat, padding space2; search field width 200 with trailing "cur/count";
  chevronUp prev / chevronDown next (disabled when no match), x clear; non focusable buttons; Enter / Shift+Enter navigate; Esc clears.
- Row context menu: Pin/Unpin (pin/pinOff), divider, Focus subtree (focus icon, shortcut ⇧↵ / Shift Enter, disabled for terminated), Expand subtree (chevronsUpDown) / Collapse subtree (chevronsDownUp) (disabled w/o children),
  divider, Copy PID, Copy name, Copy executable path (disabled when empty), divider, Resume (circlePlay; if stopped) or Suspend (circlePause), Terminate (circleStop, danger), Kill (octagonX, danger).
- Destructive confirmation dialogs (remote variants mention host); kill = destructive confirm; toasts on result; signal outcomes denied/notFound/unknown.

## Inspector island
- Header (padding space6, space6, space6, space4): process icon avatarLarge, title heading, "PID n · platform" codeSm muted.
- MeridianTabs (padding h space5): Overview, Details, Network, Threads, Files & sockets; hairline.
- Snapshot error banner (warning) "bootstrap mode".
- Empty: activity icon "No process selected".
- Overview: segmented small Tree/Process (only when row visible); tile grid 2-col (CPU warning>=50, Memory, GPU, Network (unavailable -> clickable tile arrowRight -> install), Storage, Descendants (tree));
  MeridianDisclosure "Occupied ports" with MeridianCount trailing (— when unknown); port chips (listening accent, other neutral; click -> showPort filter);
  history charts (60 slots right aligned bars width 0.7 slot, history opacity 0.55, latest/hovered bar accent; hover label raised xs radius shadowFloat codeSm; scale labels max/half/0 width 64)
  CPU (44h), RSS, GPU, Network diverging (56h, out up/in down, axis lineStrong), Storage diverging (read up/write down).
- Details: property list (Parent PID, User (name (uid)), Status, Listening ports, Other local ports, Threads, Open files, Virtual memory, Nice, Priority, GPU, Net in/out, Storage read/write, totals, Identity pid@start, Executable, Application bundle, Command line), Security section (signing, authority, team id, bundle id, entitlements, origin, sandbox, hardened runtime, architecture, rosetta).
- Network: banner (attention, shieldAlert) when unavailable: local -> install action; remote -> copy install cmd + guide; properties net in/out/total in/out; diverging chart (tree values).
- Threads: summary (~n threads · ~m mach syscalls) + per thread "tid N" -> "~x% · state".
- Files & sockets: files list (fd · kind -> path) + truncated banner at 500; Occupied ports chips + explanation; Sockets section endpoints "local -> remote · state"; socket peers buttons ":port · Go to name (pid)" -> select process.
- Detail sections: available / restricted (attention shieldAlert "Restricted by macOS: reason") / unsupported (ban) / not found (info) / pending (info).
- Inspector detail refresh every 2000ms while active and live.

## Status bar (MeridianStatusBar)
- Leading: frozen -> status dot "Tree locked"; remote -> live halo dot "Refresh <s>s" or phase-tone dot with phase label; local -> success halo "Polling every N ms" (static).
- Remote host line: "Connected to H for D" or "H · last updated hh:mm:ss" or host.
- Order lock hint (pause icon + "Live ordering paused", tooltip) when isOrderLockedByInteraction.
- Trailing: "N processes" + " · M queued" when frozen with structural changes.

## Remote tab banner
- live + hidepid -> info banner; live but no sample -> info loaderCircle "Connecting to H"; idle/probing/installing/handshaking -> info loader (installing message);
  reconnecting/disconnected/failed: no sample -> warning/error cloudOff title + reason + reconnect/install button; with sample -> warning wifiOff stale title + "Last update hh:mm:ss. reason" + button.

## Dialogs
- About: tile-mimameidr.svg 96, product name bodyStrong, maker line, version caption, "Lama family" + list; buttons Licenses (secondary) / Close (autofocus).
- Licenses: Meridian license dialog with app name/version/icon 40 and package list from bundled license assets.
- Preferences: MeridianSettingsDialog pages Appearance (theme segmented, row density segmented), Process tree (polling slider 250..10000 step 250, remember expansion switch, heatmap switch),
  Columns (checkbox per column + move up/down), Remote hosts, Updates (release channel stable/beta), Diagnostics (devmil logging controls).
- Rename snapshot (text field autofocus, submit), Install network telemetry confirm, Update available (Later / Open downloads w/ externalLink).
- Remote host editor, helper install dialog, helper removal confirm, remove host confirm.

## Services (Rust)
- ProcessSession per tab (see process_session.dart): filter/search/aspect prefix logic, tree build w/ filter & tree search, initial expansion (roots + systemd/systemd on linux),
  change markers (spawned/terminated keep one publish), freeze w/ queued snapshot + metric merge, order lock (hover/context menu/modal/interaction), sort defaults per column,
  metric histories (60 ring, gaps on stale), cpuScaleMax, ports merge, loopback peers, detail refresh generations, cadences.
