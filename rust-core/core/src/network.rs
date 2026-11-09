#[derive(Debug, Clone)]
pub struct NetworkStreamConfig {
    pub polling_interval_ms: u64,
    pub include_loopback: bool,
}

impl Default for NetworkStreamConfig {
    fn default() -> Self {
        Self {
            polling_interval_ms: 1_000,
            include_loopback: false,
        }
    }
}

#[derive(Debug, Clone)]
pub struct NetworkStreamControl {
    pub config: NetworkStreamConfig,
    pub started_at_unix_ms: u64,
}

impl NetworkStreamControl {
    pub fn new(config: NetworkStreamConfig) -> Self {
        Self {
            config,
            started_at_unix_ms: crate::process_backend::unix_now_ms(),
        }
    }

    pub fn status(&self) -> NetworkStreamStatus {
        NetworkStreamStatus {
            started_at_unix_ms: self.started_at_unix_ms,
            polling_interval_ms: self.config.polling_interval_ms,
            running: true,
        }
    }

    pub fn poll_once(&self) -> Result<NetworkEventBatch, String> {
        let mut events =
            processlama_telemetry::latest_network_rates(self.config.polling_interval_ms)
                .into_iter()
                .map(|(pid, rate)| ProcessNetworkEvent {
                    pid,
                    process_start_time_unix_ms: 0,
                    bytes_in_per_second: rate.bytes_in_per_second.max(0.0).round() as u64,
                    bytes_out_per_second: rate.bytes_out_per_second.max(0.0).round() as u64,
                    connection_count: 0,
                })
                .collect::<Vec<_>>();
        events.sort_by_key(|event| event.pid);
        Ok(NetworkEventBatch {
            generated_at_unix_ms: crate::process_backend::unix_now_ms(),
            events,
        })
    }
}

#[derive(Debug, Clone)]
pub struct NetworkStreamStatus {
    pub started_at_unix_ms: u64,
    pub polling_interval_ms: u64,
    pub running: bool,
}

#[derive(Debug, Clone)]
pub struct NetworkEventBatch {
    pub generated_at_unix_ms: u64,
    pub events: Vec<ProcessNetworkEvent>,
}

#[derive(Debug, Clone)]
pub struct ProcessNetworkEvent {
    pub pid: i32,
    pub process_start_time_unix_ms: u64,
    pub bytes_in_per_second: u64,
    pub bytes_out_per_second: u64,
    pub connection_count: u32,
}
