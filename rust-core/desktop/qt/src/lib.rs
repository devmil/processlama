//! Qt Bridges adapters.
use qtbridge::qobject;

#[derive(Default)]
pub struct Probe {
    value: i32,
}

#[qobject(ConvertToCamelCase)]
impl Probe {
    qproperty!("value", Member = value, Notify = value_changed);

    #[qsignal]
    fn value_changed(&mut self);
}
