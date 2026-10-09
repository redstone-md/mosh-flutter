use nokhwa::utils::{ApiBackend, CameraIndex, CameraInfo};
use serde::Serialize;

#[derive(Serialize)]
pub struct Device {
    pub id: String,
    pub name: String,
    pub stable: bool,
    #[serde(skip)]
    pub index: CameraIndex,
}

pub fn list() -> anyhow::Result<Vec<Device>> {
    Ok(nokhwa::query(ApiBackend::Auto)?
        .into_iter()
        .map(device)
        .collect())
}

fn device(info: CameraInfo) -> Device {
    let mut index = info.index().clone();
    let (id, stable) = if cfg!(target_os = "linux") {
        linux_id(&index).map_or_else(|| (format!("index:{index}"), false), |id| (id, true))
    } else if !info.misc().is_empty() {
        index = CameraIndex::String(info.misc());
        (format!("native:{}", info.misc()), true)
    } else {
        (format!("index:{index}"), false)
    };
    Device {
        id,
        name: info.human_name(),
        stable,
        index,
    }
}

fn linux_id(index: &CameraIndex) -> Option<String> {
    let target = std::fs::canonicalize(format!("/dev/video{}", index.as_index().ok()?)).ok()?;
    let mut paths: Vec<_> = std::fs::read_dir("/dev/v4l/by-id")
        .ok()?
        .filter_map(Result::ok)
        .collect();
    paths.sort_by_key(|entry| entry.file_name());
    paths
        .into_iter()
        .find(|entry| std::fs::canonicalize(entry.path()).ok().as_ref() == Some(&target))
        .map(|entry| format!("v4l:{}", entry.file_name().to_string_lossy()))
}
