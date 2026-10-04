use super::*;
use std::path::Path;

fn temp_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("mosh-log-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    dir
}

fn read_lines(dir: &Path, name: &str) -> Vec<String> {
    fs::read_to_string(dir.join(name))
        .map(|text| text.lines().map(str::to_string).collect())
        .unwrap_or_default()
}

#[test]
fn writes_one_structured_line_per_event() {
    let dir = temp_dir("structured");
    let mut sink = LogSink::new(dir.clone(), 10_000);
    sink.write_line(LogLevel::Error, kinds::HANDSHAKE, "s1", "handshake failed");
    sink.write_line(LogLevel::Info, kinds::TEST, "", "plain message");
    let lines = read_lines(&dir, FILE_NAME);
    assert_eq!(lines.len(), 2, "one line per event");
    let first = &lines[0];
    assert_eq!(&first[4..5], "-");
    assert_eq!(&first[10..11], "T");
    assert_eq!(&first[19..20], "Z", "ISO8601 UTC: {first}");
    assert!(
        first.contains(" error handshake s1 handshake failed"),
        "{first}"
    );
    assert!(
        lines[1].contains(" info test plain message"),
        "{}",
        lines[1]
    );
    assert!(!lines[1].contains("  "), "an empty context leaves no gap");
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn renders_known_instants_as_utc() {
    assert_eq!(iso8601_utc(0), "1970-01-01T00:00:00Z");
    assert_eq!(iso8601_utc(1_700_000_000), "2023-11-14T22:13:20Z");
    assert_eq!(iso8601_utc(951_782_400), "2000-02-29T00:00:00Z");
}

#[test]
fn rotates_and_keeps_every_line_across_three_files() {
    let dir = temp_dir("rotate");
    let mut sink = LogSink::new(dir.clone(), 200);
    for event in 1..=12 {
        sink.write_line(
            LogLevel::Info,
            kinds::TEST,
            "c1",
            &format!("event-{event:02}"),
        );
    }
    let live = read_lines(&dir, FILE_NAME);
    let first = read_lines(&dir, ROTATED_NAMES[0]);
    let second = read_lines(&dir, ROTATED_NAMES[1]);
    assert_eq!(
        live.len() + first.len() + second.len(),
        12,
        "nothing dropped yet"
    );
    assert!(
        second[0].contains("event-01"),
        "oldest land in .2: {second:?}"
    );
    assert!(
        first[0].contains("event-05"),
        "middle land in .1: {first:?}"
    );
    assert!(live.last().is_some_and(|l| l.contains("event-12")));
    for name in [FILE_NAME, ROTATED_NAMES[0], ROTATED_NAMES[1]] {
        if let Ok(metadata) = fs::metadata(dir.join(name)) {
            assert!(metadata.len() <= 200 + 100, "{name} grew past the cap");
        }
    }
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn reopens_and_appends_across_instances() {
    let dir = temp_dir("reopen");
    let mut first = LogSink::new(dir.clone(), 10_000);
    first.write_line(LogLevel::Warn, kinds::TEST, "c1", "before restart");
    drop(first);
    let mut second = LogSink::new(dir.clone(), 10_000);
    second.write_line(LogLevel::Warn, kinds::TEST, "c1", "after restart");
    let lines = read_lines(&dir, FILE_NAME);
    assert_eq!(lines.len(), 2, "append keeps the previous content");
    assert!(lines[0].contains("before restart"));
    assert!(lines[1].contains("after restart"));
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn a_full_file_rotates_on_reopen() {
    let dir = temp_dir("reopen-rotate");
    let mut first = LogSink::new(dir.clone(), 60);
    first.write_line(LogLevel::Info, kinds::TEST, "c1", "one");
    drop(first);
    let mut second = LogSink::new(dir.clone(), 60);
    second.write_line(LogLevel::Info, kinds::TEST, "c1", "two");
    assert!(
        read_lines(&dir, ROTATED_NAMES[0])[0].contains("one"),
        "old moved to .1"
    );
    assert!(read_lines(&dir, FILE_NAME)[0].contains("two"));
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn never_panics_when_the_log_file_cannot_be_created() {
    let dir = temp_dir("blocked");
    fs::create_dir_all(dir.join(FILE_NAME)).expect("occupy the file path");
    let mut sink = LogSink::new(dir.clone(), 10_000);
    sink.write_line(LogLevel::Error, kinds::TEST, "c1", "must be dropped");
    assert_eq!(sink.ready_path(), None, "no usable file, no path to report");
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn the_global_sink_reports_the_resolved_path() {
    // Reset the sink after changing the process data directory.
    let _ = crate::api::shared_runtime::set_app_data_dir(
        temp_dir("global-sink").to_string_lossy().into_owned(),
    );
    reset_sink_for_tests();
    write(LogLevel::Info, kinds::TEST, "t", "global sink smoke");
    let path = current_log_path().expect("a write opened the global sink");
    assert_eq!(path, resolved_data_dir().join(LOGS_DIR).join(FILE_NAME));
    assert!(path.is_file());
    let _ = fs::remove_dir_all(temp_dir("global-sink"));
}

#[test]
fn a_panic_lands_in_the_field_log() {
    let _ = crate::api::shared_runtime::set_app_data_dir(
        temp_dir("panic-hook").to_string_lossy().into_owned(),
    );
    reset_sink_for_tests();
    install_panic_hook();
    // The hook mirrors the panic into the log and then runs the default
    // hook, so the panic still unwinds exactly as the caller expects.
    let outcome = std::panic::catch_unwind(|| panic!("hook smoke test"));
    assert!(outcome.is_err(), "the panic must still unwind");

    let dir = resolved_data_dir().join(LOGS_DIR);
    let lines: Vec<String> = read_lines(&dir, FILE_NAME)
        .into_iter()
        .filter(|line| line.contains("hook smoke test"))
        .collect();
    assert_eq!(lines.len(), 1, "one line per panic");
    assert!(lines[0].contains("error panic"), "logged as an error");
    assert!(
        lines[0].contains("panic at "),
        "the line carries the panic location"
    );
    reset_sink_for_tests();
    let _ = fs::remove_dir_all(temp_dir("panic-hook"));
}
