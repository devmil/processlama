//! Per-process metric histories.

use std::sync::Arc;

/// Samples a history keeps; charts show one bar per sample, right-aligned.
pub const HISTORY_CAPACITY: usize = 60;

/// A fixed-capacity ring of samples. Appends are O(1), the maximum is kept
/// incrementally and the list form is built only when a view asks for it.
/// A gap (an outage) is stored as NaN, so charts lift the pen across it.
#[derive(Clone, Debug)]
pub struct MetricHistory {
    buffer: [f32; HISTORY_CAPACITY],
    head: usize,
    count: usize,
    max: f32,
    snapshot: Option<Arc<[f32]>>,
}

impl Default for MetricHistory {
    fn default() -> Self {
        Self {
            buffer: [0.0; HISTORY_CAPACITY],
            head: 0,
            count: 0,
            max: 0.0,
            snapshot: None,
        }
    }
}

impl MetricHistory {
    pub fn len(&self) -> usize {
        self.count
    }

    pub fn is_empty(&self) -> bool {
        self.count == 0
    }

    pub fn max(&self) -> f32 {
        self.max
    }

    pub fn add_gap(&mut self) {
        self.add(f32::NAN);
    }

    pub fn add(&mut self, value: f32) {
        self.snapshot = None;
        if self.count < HISTORY_CAPACITY {
            self.buffer[self.head] = value;
            if value > self.max {
                self.max = value;
            }
            self.head = (self.head + 1) % HISTORY_CAPACITY;
            self.count += 1;
            return;
        }
        let evicted = self.buffer[self.head];
        self.buffer[self.head] = value;
        self.head = (self.head + 1) % HISTORY_CAPACITY;
        if value >= self.max {
            self.max = value;
        } else if evicted >= self.max {
            // Samples are never negative; a gap's NaN never compares greater.
            self.max = self
                .buffer
                .iter()
                .copied()
                .filter(|sample| sample.is_finite())
                .fold(0.0, f32::max);
        }
    }

    /// Oldest first. Cached until the next append.
    pub fn as_list(&mut self) -> Arc<[f32]> {
        if let Some(snapshot) = &self.snapshot {
            return Arc::clone(snapshot);
        }
        let start = (self.head + HISTORY_CAPACITY - self.count) % HISTORY_CAPACITY;
        let list: Arc<[f32]> = (0..self.count)
            .map(|index| self.buffer[(start + index) % HISTORY_CAPACITY])
            .collect();
        self.snapshot = Some(Arc::clone(&list));
        list
    }
}

/// The histories one process keeps: its subtree's and its own.
#[derive(Clone, Debug, Default)]
pub struct HistorySet {
    pub tree_cpu: MetricHistory,
    pub tree_gpu: MetricHistory,
    pub tree_rss: MetricHistory,
    pub tree_network_in: MetricHistory,
    pub tree_network_out: MetricHistory,
    pub tree_storage_read: MetricHistory,
    pub tree_storage_write: MetricHistory,
    pub cpu: MetricHistory,
    pub gpu: MetricHistory,
    pub rss: MetricHistory,
    pub network_in: MetricHistory,
    pub network_out: MetricHistory,
    pub storage_read: MetricHistory,
    pub storage_write: MetricHistory,
}

impl HistorySet {
    pub fn add_gap(&mut self) {
        for history in self.all_mut() {
            history.add_gap();
        }
    }

    fn all_mut(&mut self) -> [&mut MetricHistory; 14] {
        [
            &mut self.tree_cpu,
            &mut self.tree_gpu,
            &mut self.tree_rss,
            &mut self.tree_network_in,
            &mut self.tree_network_out,
            &mut self.tree_storage_read,
            &mut self.tree_storage_write,
            &mut self.cpu,
            &mut self.gpu,
            &mut self.rss,
            &mut self.network_in,
            &mut self.network_out,
            &mut self.storage_read,
            &mut self.storage_write,
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ring_keeps_the_newest_samples_and_their_maximum() {
        let mut history = MetricHistory::default();
        for value in 0..70 {
            history.add(value as f32);
        }
        assert_eq!(history.len(), HISTORY_CAPACITY);
        let list = history.as_list();
        assert_eq!(list[0], 10.0);
        assert_eq!(list[59], 69.0);
        assert_eq!(history.max(), 69.0);
    }

    #[test]
    fn maximum_recomputes_when_evicted() {
        let mut history = MetricHistory::default();
        history.add(100.0);
        for _ in 0..HISTORY_CAPACITY {
            history.add(1.0);
        }
        assert_eq!(history.max(), 1.0);
    }

    #[test]
    fn gaps_are_nan_and_ignored_by_the_maximum() {
        let mut history = MetricHistory::default();
        history.add(3.0);
        history.add_gap();
        history.add(2.0);
        let list = history.as_list();
        assert!(list[1].is_nan());
        assert_eq!(history.max(), 3.0);
    }
}
