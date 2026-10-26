//! Android OS job callbacks own execution, independently of Dart scheduling hints.
use std::collections::HashMap;
#[cfg(target_os = "android")]
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Mutex, OnceLock,
};

#[derive(Default)]
struct Grants {
    incarnation: Option<String>,
    entries: HashMap<String, u64>,
    highwater: u64,
}

impl Grants {
    fn apply(&mut self, incarnation: &str, id: &str, generation: u64, allowed: bool) -> i32 {
        if !hex_id(incarnation, 32)
            || !id
                .strip_prefix("transfer-")
                .is_some_and(|id| hex_id(id, 32))
            || generation == 0
        {
            return -4;
        }
        if self
            .incarnation
            .as_deref()
            .is_some_and(|current| current != incarnation)
        {
            return -3;
        }
        if generation < self.highwater {
            return if allowed { -3 } else { 0 };
        }
        if generation == self.highwater {
            if allowed {
                return if self.entries.get(id) == Some(&generation) {
                    0
                } else {
                    -3
                };
            }
            if self.entries.get(id) == Some(&generation) {
                self.entries.remove(id);
            }
            return 0;
        }
        if allowed && !self.entries.contains_key(id) && self.entries.len() >= 256 {
            return -4;
        }
        self.incarnation
            .get_or_insert_with(|| incarnation.to_owned());
        self.highwater = generation;
        if allowed {
            self.entries.insert(id.into(), generation);
        } else {
            self.entries.remove(id);
        }
        0
    }

    fn allows(&self, id: &str) -> bool {
        self.entries.contains_key(id)
    }
}

fn hex_id(value: &str, length: usize) -> bool {
    value.len() == length
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

#[cfg(target_os = "android")]
static INTERACTIVE: AtomicBool = AtomicBool::new(false);

#[cfg(target_os = "android")]
static OS_GRANTS: OnceLock<Mutex<Grants>> = OnceLock::new();

#[cfg(target_os = "android")]
pub(crate) fn set(incarnation: &str, id: &str, generation: i64, allowed: bool) -> i32 {
    let Ok(generation) = u64::try_from(generation) else {
        return -4;
    };
    let result = OS_GRANTS
        .get_or_init(|| Mutex::new(Grants::default()))
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .apply(incarnation, id, generation, allowed);
    if result == 0 {
        super::changes::changed();
    }
    result
}

#[cfg(target_os = "android")]
pub(crate) fn allowed(id: &str) -> bool {
    OS_GRANTS
        .get_or_init(|| Mutex::new(Grants::default()))
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .allows(id)
}

#[cfg(target_os = "android")]
pub(crate) fn set_interactive(interactive: bool) -> i32 {
    if INTERACTIVE.swap(interactive, Ordering::AcqRel) != interactive {
        super::changes::changed();
    }
    0
}

#[cfg(target_os = "android")]
pub(crate) fn interactive() -> bool {
    INTERACTIVE.load(Ordering::Acquire)
}

#[cfg(test)]
mod tests {
    use super::*;
    const FIRST: &str = "0123456789abcdef0123456789abcdef";
    const NEXT: &str = "1123456789abcdef0123456789abcdef";
    const ID: &str = "transfer-0123456789abcdef0123456789abcdef";

    #[test]
    fn retired_operations_do_not_exhaust_the_process_and_cannot_be_regranted() {
        let mut grants = Grants::default();
        for number in 1..=600 {
            let id = format!("transfer-{number:032x}");
            assert_eq!(grants.apply(FIRST, &id, number * 2, true), 0);
            assert_eq!(grants.apply(FIRST, &id, number * 2 + 1, false), 0);
        }
        assert!(!grants.allows(ID));
        assert_eq!(
            grants.apply(FIRST, "transfer-00000000000000000000000000000001", 2, true),
            -3
        );
    }

    #[test]
    fn exact_os_stop_fences_late_start_and_old_generation_cannot_stop_new_work() {
        let mut grants = Grants::default();
        assert!(!grants.allows(ID));
        assert_eq!(grants.apply(FIRST, ID, 1, true), 0);
        assert!(grants.allows(ID));
        assert_eq!(grants.apply(FIRST, ID, 1, false), 0);
        assert!(!grants.allows(ID));
        assert_eq!(grants.apply(FIRST, ID, 1, true), -3);
        assert!(!grants.allows(ID));
        assert_eq!(grants.apply(FIRST, ID, 2, true), 0);
        assert_eq!(grants.apply(FIRST, ID, 1, false), 0);
        assert!(grants.allows(ID));
        assert_eq!(grants.apply(NEXT, ID, 3, true), -3);
        assert_eq!(grants.apply(FIRST, ID, 0, true), -4);
        assert_eq!(grants.apply(FIRST, "../chat", 3, true), -4);
    }
}
