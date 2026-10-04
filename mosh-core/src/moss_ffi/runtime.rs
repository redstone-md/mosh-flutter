//! Runtime loading and node construction.
use super::*;

impl MossFfiRuntime {
    pub fn load_default() -> Result<Self, MossFfiError> {
        // Android resolves packaged libraries through its linker namespace.
        #[cfg(target_os = "android")]
        if let Ok(runtime) =
            Self::load_from_path(std::path::Path::new(crate::moss_runtime::MOSS_LIBRARY_NAME))
        {
            return Ok(runtime);
        }
        let path = MossDynamicRuntime::from_default_candidates()
            .first_available_path()
            .ok_or_else(|| {
                MossFfiError::Runtime(MossRuntimeError::Load("library not found".into()))
            })?;

        Self::load_from_path(&path)
    }

    pub fn load_from_path(path: &std::path::Path) -> Result<Self, MossFfiError> {
        let library = unsafe { Library::new(path) }
            .map_err(|error| MossFfiError::Runtime(MossRuntimeError::Load(error.to_string())))?;

        Ok(Self {
            init: load_symbol(&library, b"Moss_Init\0")?,
            start: load_symbol(&library, b"Moss_Start\0")?,
            stop: load_symbol(&library, b"Moss_Stop\0")?,
            subscribe: load_symbol(&library, b"Moss_Subscribe\0")?,
            unsubscribe: load_symbol(&library, b"Moss_Unsubscribe\0")?,
            join_room: load_symbol(&library, b"Moss_JoinRoom\0")?,
            leave_room: load_symbol(&library, b"Moss_LeaveRoom\0")?,
            subscribe_room: load_symbol(&library, b"Moss_SubscribeRoom\0")?,
            unsubscribe_room: load_symbol(&library, b"Moss_UnsubscribeRoom\0")?,
            publish_room: load_symbol(&library, b"Moss_PublishRoom\0")?,
            connect: load_symbol(&library, b"Moss_Connect\0")?,
            connect_to_peer: load_symbol(&library, b"Moss_ConnectToPeer\0")?,
            publish: load_symbol(&library, b"Moss_Publish\0")?,
            set_callback: load_symbol(&library, b"Moss_SetCallback\0")?,
            set_event_callback: load_symbol(&library, b"Moss_SetEventCallback\0")?,
            get_mesh_info: load_symbol(&library, b"Moss_GetMeshInfo\0")?,
            get_nat_type: load_symbol(&library, b"Moss_GetNATType\0")?,
            get_public_key: load_symbol(&library, b"Moss_GetPublicKey\0")?,
            free: load_symbol(&library, b"Moss_Free\0")?,
            set_key_store: load_symbol(&library, b"Moss_SetKeyStore\0")?,
            version: try_load_symbol(&library, b"Moss_Version\0"),
            last_error: try_load_symbol(&library, b"Moss_LastError\0"),
            peer_rtt: try_load_symbol(&library, b"Moss_PeerRTT\0"),
            open_stream: try_load_symbol(&library, b"Moss_OpenStream\0"),
            send_stream: try_load_symbol(&library, b"Moss_SendStream\0"),
            on_stream: try_load_symbol(&library, b"Moss_OnStream\0"),
            _library: ManuallyDrop::new(library),
        })
    }

    /// Install the process-global identity callbacks before starting nodes.
    pub fn install_keystore(&self) -> Result<(), MossFfiError> {
        check_code("set_key_store", unsafe {
            (self.set_key_store)(Some(keystore_load), Some(keystore_save))
        })
    }

    #[cfg(test)]
    pub fn uninstall_keystore(&self) -> Result<(), MossFfiError> {
        check_code("set_key_store", unsafe { (self.set_key_store)(None, None) })
    }

    pub fn init_node(
        self: &Arc<Self>,
        mesh_id: &str,
        config_json: &str,
    ) -> Result<MossNode, MossFfiError> {
        let mesh_id = c_string(mesh_id)?;
        let config = c_string(config_json)?;
        // Moss Init calls these context-free callbacks synchronously. Serializing
        // Init gives each node only the key Moss actually selected for it.
        let _init = identity::INIT_LOCK
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        self.install_keystore()?;
        drop(identity::take_identity());
        let handle = unsafe { (self.init)(mesh_id.as_ptr(), std::ptr::null(), config.as_ptr()) };
        let identity_signer = identity::take_identity();

        if handle <= 0 {
            return Err(MossFfiError::Operation {
                name: "init",
                code: handle as i32,
            });
        }

        let node = MossNode {
            runtime: Arc::clone(self),
            handle,
            identity_signer,
        };
        if !node.identity_signer.as_ref().is_some_and(|key| {
            node.identity_public_key_hex().as_deref()
                == Some(&hex::encode(key.verifying_key().to_bytes()))
        }) {
            return Err(MossFfiError::IdentityUnavailable);
        }
        Ok(node)
    }

    pub fn init_default_node(
        self: &Arc<Self>,
        mesh_id: &str,
        config: &MossNodeConfig,
    ) -> Result<MossNode, MossFfiError> {
        self.init_node(mesh_id, &node_config_json(config))
    }
}
