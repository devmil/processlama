use super::*;
use processlama_domain::{HostOperatingSystem, ProcessRecord, ProcessStatus};
use std::cell::RefCell;
use std::rc::Rc;

#[derive(Default)]
struct Calls {
    cadences: Vec<Cadence>,
    samples: usize,
    details: Vec<(ProcessIdentity, u64)>,
}

struct FakeSource(Rc<RefCell<Calls>>);

impl SessionSource for FakeSource {
    fn set_cadence(&self, cadence: Cadence, _: u32) {
        self.0.borrow_mut().cadences.push(cadence);
    }
    fn sample_now(&self, _: u32) {
        self.0.borrow_mut().samples += 1;
    }
    fn fetch_detail(&self, identity: ProcessIdentity, generation: u64) {
        self.0.borrow_mut().details.push((identity, generation));
    }
}

fn session(os: HostOperatingSystem) -> (ProcessSession, Rc<RefCell<Calls>>) {
    let calls = Rc::new(RefCell::new(Calls::default()));
    let mut session = ProcessSession::new(
        Box::new(FakeSource(Rc::clone(&calls))),
        HostCapabilities::local(os),
        SourceState::LIVE,
        Cadence::Background(DEFAULT_BACKGROUND_REFRESH_MS),
    );
    session.initialize(&AppSettings::default(), 0);
    (session, calls)
}

fn record(pid: i32, ppid: i32, name: &str, cpu: f64) -> ProcessRecord {
    ProcessRecord {
        pid,
        ppid,
        name: name.into(),
        cpu_usage: cpu,
        tree_cpu_usage: cpu,
        start_time_unix_ms: 1000 + pid as u64,
        status: ProcessStatus::Running,
        ..ProcessRecord::default()
    }
}

fn snapshot(records: Vec<ProcessRecord>) -> Arc<ProcessSnapshot> {
    Arc::new(ProcessSnapshot {
        generated_at_unix_ms: 1,
        platform: "linux".into(),
        processes: records.into_iter().map(Arc::new).collect(),
        error: None,
        topology: None,
    })
}

fn names(session: &ProcessSession) -> Vec<String> {
    session
        .tree()
        .rows
        .iter()
        .map(|row| row.record.name.clone())
        .collect()
}

fn id(session: &ProcessSession, name: &str) -> ProcessIdentity {
    session
        .tree()
        .rows
        .iter()
        .find(|row| row.record.name == name)
        .map(|row| row.identity)
        .expect("row")
}

fn basic() -> Vec<ProcessRecord> {
    vec![
        record(1, 0, "init", 1.0),
        record(10, 1, "shell", 2.0),
        record(11, 10, "editor", 30.0),
        record(12, 1, "daemon", 5.0),
    ]
}

#[test]
fn synthesizes_a_parent_child_tree_with_roots_expanded() {
    let (mut session, _) = session(HostOperatingSystem::Linux);
    session.on_sample(snapshot(basic()), 0);
    // Tree CPU sort descending: shell (32) before daemon (5); editor is
    // hidden because shell is collapsed.
    assert_eq!(names(&session), vec!["init", "shell", "daemon"]);
    let init = &session.tree().rows[0];
    assert_eq!(init.depth, 0);
    assert!(init.has_children && init.is_expanded);
    assert_eq!(init.descendant_count, 3);
    assert!((init.tree_cpu - 38.0).abs() < 1e-9);
    assert_eq!(session.tree().selected, Some(init.identity));
}

#[test]
fn expands_the_systemd_user_manager_branch_on_linux() {
    let (mut session, _) = session(HostOperatingSystem::Linux);
    session.on_sample(
        snapshot(vec![
            record(1, 0, "systemd", 0.0),
            record(900, 1, "systemd", 0.0),
            record(901, 900, "app", 0.0),
        ]),
        0,
    );
    assert_eq!(names(&session), vec!["systemd", "systemd", "app"]);
}

#[test]
fn search_preserves_ancestors_and_force_expands() {
    let (mut session, _) = session(HostOperatingSystem::Linux);
    session.on_sample(snapshot(basic()), 0);
    session.set_filter("edit", 1);
    assert_eq!(names(&session), vec!["init", "shell", "editor"]);
    let shell = &session.tree().rows[1];
    assert!(shell.preserves_filter_branch && shell.is_expanded);
    assert!(session.tree().rows[2].matches_filter);
}

#[test]
fn typed_port_prefixes_apply_only_to_their_query() {
    let (mut session, _) = session(HostOperatingSystem::Linux);
    session.on_sample(snapshot(basic()), 0);
    session.set_filter(":8080", 1);
    assert_eq!(session.search_options().aspect, SearchAspect::Port);
    assert_eq!(session.filter(), "8080");
    session.set_filter("", 2);
    assert_eq!(session.search_options().aspect, SearchAspect::All);
    session.show_port(5432, 3);
    assert_eq!(session.search_options().aspect, SearchAspect::Port);
    session.set_filter("abc", 4);
    assert_eq!(session.search_options().aspect, SearchAspect::All);
}

#[test]
fn tree_search_highlights_without_filtering_and_cycles() {
    let (mut session, _) = session(HostOperatingSystem::Linux);
    let mut records = basic();
    records.push(record(13, 1, "editor-helper", 0.0));
    session.on_sample(snapshot(records), 0);
    session.set_tree_search("edit", 1);
    // Rows stay; the shell branch opens to reveal its matching child.
    assert_eq!(
        names(&session),
        vec!["init", "shell", "editor", "daemon", "editor-helper"]
    );
    assert_eq!(session.tree().tree_search_match_count, 2);
    let editor = id(&session, "editor");
    assert_eq!(session.tree().selected, Some(editor));
    assert_eq!(session.tree().tree_search_selected_match_index, 0);
    session.select_next_tree_search_match(2);
    assert_eq!(session.tree().selected, Some(id(&session, "editor-helper")));
    session.select_next_tree_search_match(3);
    assert_eq!(session.tree().selected, Some(editor));
    session.select_previous_tree_search_match(4);
    assert_eq!(session.tree().selected, Some(id(&session, "editor-helper")));
}

#[test]
fn selection_survives_metric_only_refreshes() {
    let (mut session, _) = session(HostOperatingSystem::Linux);
    session.on_sample(snapshot(basic()), 0);
    let daemon = id(&session, "daemon");
    session.select_process(daemon, 1);
    let mut next = basic();
    next[3].cpu_usage = 90.0;
    next[3].tree_cpu_usage = 90.0;
    // Past the interaction hold, the tree resorts but keeps the selection.
    session.on_sample(snapshot(next), 10_000);
    session.on_time(10_200);
    assert_eq!(session.tree().selected, Some(daemon));
}

#[test]
fn interaction_keeps_the_visible_order_until_the_hold_expires() {
    let (mut session, _) = session(HostOperatingSystem::Linux);
    session.on_sample(snapshot(basic()), 0);
    session.set_tree_hovering(true, 1);
    let mut next = basic();
    next[3].cpu_usage = 90.0;
    next[3].tree_cpu_usage = 90.0;
    session.on_sample(snapshot(next.clone()), 2);
    assert_eq!(names(&session), vec!["init", "shell", "daemon"]);
    assert!(session.tree().lock.is_order_locked_by_interaction);
    session.set_tree_hovering(false, 3);
    session.on_time(3 + crate::order_lock::ORDER_LOCK_RELEASE_MS);
    session.on_sample(snapshot(next), 500);
    assert_eq!(names(&session), vec!["init", "daemon", "shell"]);
}

#[test]
fn freeze_queues_structural_changes_and_keeps_metrics_flowing() {
    let (mut session, _) = session(HostOperatingSystem::Linux);
    session.on_sample(snapshot(basic()), 0);
    session.toggle_frozen(1);
    let mut next = basic();
    next.push(record(20, 1, "newcomer", 0.0));
    next[0].cpu_usage = 50.0;
    next[0].tree_cpu_usage = 50.0;
    session.on_sample(snapshot(next), 2);
    let tree = session.tree();
    assert!(tree.lock.is_frozen);
    assert!(tree.lock.has_queued_structural_mutations);
    assert_eq!(tree.lock.queued_process_count, 5);
    assert!(!names(&session).contains(&"newcomer".to_owned()));
    assert!((session.tree().rows[0].record.cpu_usage - 50.0).abs() < 1e-9);
    session.toggle_frozen(3);
    assert!(names(&session).contains(&"newcomer".to_owned()));
    assert_eq!(
        session
            .tree()
            .rows
            .iter()
            .find(|r| r.record.name == "newcomer")
            .unwrap()
            .change_marker,
        ChangeMarker::Spawned
    );
}

#[test]
fn spawned_and_terminated_rows_are_marked_for_one_publication() {
    let (mut session, _) = session(HostOperatingSystem::Linux);
    session.on_sample(snapshot(basic()), 0);
    let mut next = basic();
    next.remove(3);
    next.push(record(30, 1, "fresh", 0.0));
    session.on_sample(snapshot(next.clone()), 10_000);
    let marker = |name: &str| {
        session
            .tree()
            .rows
            .iter()
            .find(|r| r.record.name == name)
            .map(|r| r.change_marker)
    };
    assert_eq!(marker("daemon"), Some(ChangeMarker::Terminated));
    assert_eq!(marker("fresh"), Some(ChangeMarker::Spawned));
    session.on_sample(snapshot(next), 20_000);
    assert_eq!(
        session
            .tree()
            .rows
            .iter()
            .find(|r| r.record.name == "daemon")
            .map(|r| r.change_marker),
        None
    );
}

#[test]
fn subtree_focus_nests_and_steps_back() {
    let (mut session, _) = session(HostOperatingSystem::Linux);
    session.on_sample(snapshot(basic()), 0);
    let shell = id(&session, "shell");
    session.focus_subtree(shell, 1);
    assert_eq!(names(&session), vec!["shell", "editor"]);
    let editor = id(&session, "editor");
    session.focus_subtree(editor, 2);
    assert_eq!(names(&session), vec!["editor"]);
    assert_eq!(session.tree().focus_stack_depth, 1);
    session.pop_subtree_focus(3);
    assert_eq!(names(&session), vec!["shell", "editor"]);
    session.clear_subtree_focus(4);
    assert_eq!(session.tree().focused, None);
    assert_eq!(session.tree().selected, Some(shell));
}

#[test]
fn an_outage_leaves_a_gap_in_the_histories() {
    let (mut session, _) = session(HostOperatingSystem::Linux);
    session.on_sample(snapshot(basic()), 0);
    session.set_source_state(SourceState {
        phase: SourcePhase::Stale,
        last_sample_at_ms: None,
        failure: None,
    });
    session.on_sample(snapshot(basic()), 1);
    let history = &session.tree().rows[0].cpu_history;
    assert_eq!(history.len(), 3);
    assert!(history[1].is_nan());
}

#[test]
fn sorting_flips_and_uses_column_defaults() {
    let (mut session, _) = session(HostOperatingSystem::Linux);
    session.on_sample(snapshot(basic()), 0);
    assert_eq!(
        session.sort_by(SortColumn::Name, 1),
        (SortColumn::Name, SortDirection::Ascending)
    );
    assert_eq!(names(&session), vec!["init", "daemon", "shell"]);
    assert_eq!(
        session.sort_by(SortColumn::Name, 2),
        (SortColumn::Name, SortDirection::Descending)
    );
    assert_eq!(names(&session), vec!["init", "shell", "daemon"]);
}

#[test]
fn keyboard_navigation_moves_and_collapses_to_the_parent() {
    let (mut session, _) = session(HostOperatingSystem::Linux);
    session.on_sample(snapshot(basic()), 0);
    session.select_next_visible(1);
    assert_eq!(session.tree().selected, Some(id(&session, "shell")));
    session.expand_selected(2);
    assert_eq!(names(&session), vec!["init", "shell", "editor", "daemon"]);
    session.select_next_visible(3);
    session.collapse_selected(4);
    assert_eq!(session.tree().selected, Some(id(&session, "shell")));
}

#[test]
fn selecting_requests_detail_and_ignores_stale_generations() {
    let (mut session, calls) = session(HostOperatingSystem::Linux);
    session.on_sample(snapshot(basic()), 0);
    let daemon = id(&session, "daemon");
    session.select_process(daemon, 1);
    let (identity, generation) = *calls.borrow().details.last().unwrap();
    assert_eq!(identity, daemon);
    let detail = ProcessDetail {
        identity: daemon,
        files: DetailSection::Available(Vec::new()),
        sockets: DetailSection::Unsupported("x".into()),
        threads: DetailSection::NotFound("x".into()),
        security: DetailSection::Restricted("x".into()),
    };
    session.on_detail(daemon, generation + 1, Some(detail.clone()));
    assert!(session.inspector().detail.is_none());
    session.on_detail(daemon, generation, Some(detail));
    assert!(session.inspector().detail.is_some());
}

#[test]
fn hidden_and_resizing_sessions_change_cadence() {
    let (mut session, calls) = session(HostOperatingSystem::Linux);
    assert_eq!(calls.borrow().cadences.last(), Some(&Cadence::Live(1000)));
    session.set_active(false, 0);
    assert_eq!(
        calls.borrow().cadences.last(),
        Some(&Cadence::Background(DEFAULT_BACKGROUND_REFRESH_MS))
    );
    session.set_active(true, 0);
    session.set_window_resizing(true);
    assert_eq!(calls.borrow().cadences.last(), Some(&Cadence::Paused));
}
