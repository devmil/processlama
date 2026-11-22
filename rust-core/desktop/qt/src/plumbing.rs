//! The event inbox, the worker pool, the clock and the timer thread.
//!
//! Every thread posts [`CoreEvent`]s into the [`Inbox`]; the GUI thread
//! drains it in the pump slot. Notifications coalesce: at most one pump call
//! is queued at a time.

use processlama_application::{Clock, CoreEvent, EventSink, Executor};
use qtbridge::{QmlMethodInvoker, invoke_method};
use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Sender};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub struct Inbox {
    events: Mutex<VecDeque<CoreEvent>>,
    queued: AtomicBool,
    invoker: Mutex<Option<QmlMethodInvoker>>,
}

impl Inbox {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            events: Mutex::new(VecDeque::new()),
            queued: AtomicBool::new(false),
            invoker: Mutex::new(None),
        })
    }

    /// Connects the inbox to the pump; queued events are delivered then.
    pub fn bind(&self, invoker: QmlMethodInvoker) {
        if let Ok(mut slot) = self.invoker.lock() {
            *slot = Some(invoker);
        }
        self.notify();
    }

    pub fn take(&self) -> VecDeque<CoreEvent> {
        self.queued.store(false, Ordering::Release);
        self.events
            .lock()
            .map(|mut events| std::mem::take(&mut *events))
            .unwrap_or_default()
    }

    fn notify(&self) {
        if self.queued.swap(true, Ordering::AcqRel) {
            return;
        }
        let invoked = self
            .invoker
            .lock()
            .ok()
            .and_then(|invoker| {
                invoker
                    .as_ref()
                    .map(|invoker| invoke_method!(invoker, "pump"))
            })
            .unwrap_or(false);
        if !invoked {
            self.queued.store(false, Ordering::Release);
        }
    }
}

impl EventSink for Inbox {
    fn post(&self, event: CoreEvent) {
        if let Ok(mut events) = self.events.lock() {
            events.push_back(event);
        }
        self.notify();
    }
}

/// A small fixed pool for finite blocking work.
/// Work the pool runs on one of its threads.
type Job = Box<dyn FnOnce() + Send>;

pub struct WorkerPool {
    jobs: Mutex<Option<Sender<Job>>>,
}

impl WorkerPool {
    pub fn new(threads: usize) -> Arc<Self> {
        let (sender, receiver) = mpsc::channel::<Box<dyn FnOnce() + Send>>();
        let receiver = Arc::new(Mutex::new(receiver));
        for index in 0..threads.max(1) {
            let receiver = Arc::clone(&receiver);
            thread::Builder::new()
                .name(format!("processlama-worker-{index}"))
                .spawn(move || {
                    loop {
                        let job = match receiver.lock() {
                            Ok(receiver) => receiver.recv(),
                            Err(_) => return,
                        };
                        match job {
                            Ok(job) => {
                                // A panicking job must not take the worker down.
                                let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(job));
                            }
                            Err(_) => return,
                        }
                    }
                })
                .expect("start a worker thread");
        }
        Arc::new(Self {
            jobs: Mutex::new(Some(sender)),
        })
    }

    pub fn shutdown(&self) {
        if let Ok(mut jobs) = self.jobs.lock() {
            jobs.take();
        }
    }
}

impl Executor for WorkerPool {
    fn spawn(&self, job: Box<dyn FnOnce() + Send>) {
        if let Ok(jobs) = self.jobs.lock()
            && let Some(sender) = jobs.as_ref()
        {
            let _ = sender.send(job);
        }
    }
}

pub struct SystemClock {
    start: Instant,
}

impl SystemClock {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            start: Instant::now(),
        })
    }

    pub fn instant_at(&self, monotonic_ms: u64) -> Instant {
        self.start + Duration::from_millis(monotonic_ms)
    }
}

impl Clock for SystemClock {
    fn monotonic_ms(&self) -> u64 {
        self.start.elapsed().as_millis() as u64
    }

    fn wall_ms(&self) -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |duration| duration.as_millis() as u64)
    }
}

/// Posts a Tick when the core's next deadline is reached.
pub struct TimerThread {
    state: Arc<(Mutex<TimerState>, Condvar)>,
}

#[derive(Default)]
struct TimerState {
    deadline: Option<Instant>,
    stopped: bool,
}

impl TimerThread {
    pub fn start(sink: Arc<dyn EventSink>) -> Self {
        let state = Arc::new((Mutex::new(TimerState::default()), Condvar::new()));
        let worker = Arc::clone(&state);
        thread::Builder::new()
            .name("processlama-timers".into())
            .spawn(move || {
                let (lock, signal) = &*worker;
                let Ok(mut state) = lock.lock() else {
                    return;
                };
                loop {
                    if state.stopped {
                        return;
                    }
                    match state.deadline {
                        None => {
                            state = match signal.wait(state) {
                                Ok(state) => state,
                                Err(_) => return,
                            };
                        }
                        Some(deadline) => {
                            let now = Instant::now();
                            if deadline <= now {
                                state.deadline = None;
                                drop(state);
                                sink.post(CoreEvent::Tick);
                                state = match lock.lock() {
                                    Ok(state) => state,
                                    Err(_) => return,
                                };
                            } else {
                                state = match signal.wait_timeout(state, deadline - now) {
                                    Ok((state, _)) => state,
                                    Err(_) => return,
                                };
                            }
                        }
                    }
                }
            })
            .expect("start the timer thread");
        Self { state }
    }

    pub fn schedule(&self, deadline: Option<Instant>) {
        let (lock, signal) = &*self.state;
        if let Ok(mut state) = lock.lock()
            && state.deadline != deadline
        {
            state.deadline = deadline;
            signal.notify_one();
        }
    }

    pub fn stop(&self) {
        let (lock, signal) = &*self.state;
        if let Ok(mut state) = lock.lock() {
            state.stopped = true;
            signal.notify_one();
        }
    }
}
