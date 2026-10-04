use super::*;
use crate::attachment_store::AttachmentStore;
use crate::moss_ffi::{MossFfiRuntime, MossReceivedMessage};
use crate::org_envelope::{self, OrgContext};
use crate::org_signing;
use crate::persistence::Persistence;
use crate::private_dm_runtime::transport::memory::MemoryNet;
use crate::private_dm_runtime::transport::DmTransport;
use crate::private_dm_runtime::{PeerTransport, PrivateDmRuntime};
use crate::private_group_runtime::PrivateGroupRuntime;
use crate::shared_node::SharedMossNode;
use crate::test_temp_directory::TempDirectory;
use ed25519_dalek::SigningKey;
use std::sync::Arc;

pub(crate) struct Fixture {
    pub org: OrgRuntime,
    pub dm: PrivateDmRuntime,
    pub groups: PrivateGroupRuntime,
    pub store: Arc<Persistence>,
    pub net: Arc<MemoryNet>,
    pub org_key: String,
    pub member: SigningKey,
    own_peer: String,
    _directory: TempDirectory,
}

impl Fixture {
    pub fn new() -> Self {
        crate::moss_ffi::drain_received_messages();
        let directory = TempDirectory::new("mosh-org-workflow");
        let store = Arc::new(
            Persistence::open_with_dek(&directory.path().join("history.redb"), [89; 32]).unwrap(),
        );
        let own_peer = seed_node_identity(&store);
        let member = SigningKey::from_bytes(&[91; 32]);
        let root_key = SigningKey::from_bytes(&[92; 32]);
        let org_key = org_signing::peer_id_hex(&root_key);
        let attachments = Arc::new(AttachmentStore::new(directory.path()).unwrap());
        let shared = SharedMossNode::new(Arc::new(MossFfiRuntime::load_default().unwrap()));
        let mut org = OrgRuntime::from_shared_node(shared.clone(), Some(store.clone()));
        org.join_org(JoinOrgRequest {
            bundle_uri: format!("mosh://org?mesh=workflow-mesh&name=work#org={org_key}"),
            display_name: "Alice".into(),
            listen_port: 0,
            static_peer: None,
        })
        .unwrap();
        let net = MemoryNet::new();
        let member_peer = org_signing::peer_id_hex(&member);
        net.endpoint(&member_peer);
        net.link(&own_peer, &member_peer, PeerTransport::Direct);
        let dm = PrivateDmRuntime::with_transport(
            net.endpoint(&own_peer),
            attachments.clone(),
            Some(store.clone()),
        );
        let groups =
            PrivateGroupRuntime::from_shared_node(shared.clone(), attachments, Some(store.clone()));
        let mut fixture = Self {
            org,
            dm,
            groups,
            store,
            net,
            org_key,
            member,
            own_peer,
            _directory: directory,
        };
        fixture.roster(&root_key);
        fixture
    }

    fn roster(&mut self, key: &SigningKey) {
        let mut roster = serde_json::json!({
            "org_pubkey": self.org_key, "org_name": "work", "version": 1,
            "members": [
                {"moss_peer_id": self.own_peer, "name": "Alice", "role": "admin"},
                {"moss_peer_id": org_signing::peer_id_hex(&self.member), "name": "Bob", "role": "member"},
                {"moss_peer_id": self.other_peer(), "name": "Cleo", "role": "member"},
            ],
        });
        let bytes = crate::org_roster::sign_roster(&mut roster, key).unwrap();
        let wire = serde_json::json!({"type": "Roster", "roster_b64": crate::conversation::encode(&bytes)});
        self.ingest(&serde_json::to_vec(&wire).unwrap());
    }

    fn ingest(&mut self, payload: &[u8]) {
        crate::inbox::deliver(MossReceivedMessage {
            channel: "org-control/workflow-mesh".into(),
            payload: payload.to_vec(),
        });
        self.org.poll(&self.org_key).unwrap();
    }

    pub fn deliver_dm_offer(&mut self, uri: &str) {
        self.deliver_offer(serde_json::json!({
            "kind": "DmOffer", "offer_id": "retryable-offer", "target_peer_id": self.own_peer,
            "from_name": "Bob", "invite_uri": uri,
        }));
    }

    pub fn deliver_group_offer(&mut self, uri: &str) {
        self.deliver_offer(serde_json::json!({
            "kind": "GroupOffer", "offer_id": "retryable-offer", "target_peer_id": self.own_peer,
            "from_name": "Bob", "group_label": null, "group_invite_uri": uri,
        }));
    }

    fn deliver_offer(&mut self, message: serde_json::Value) {
        let payload = serde_json::to_vec(&message).unwrap();
        let context = OrgContext {
            org_pubkey: &self.org_key,
            mesh_id: "workflow-mesh",
            channel_kind: "org-control",
        };
        let envelope = org_envelope::sign(&self.member, &context, &payload);
        let wire = serde_json::json!({
            "type": "Signed", "payload_b64": crate::conversation::encode(&envelope.payload),
            "peer_id": envelope.peer_id, "sig_b64": crate::conversation::encode(&envelope.sig),
        });
        self.ingest(&serde_json::to_vec(&wire).unwrap());
    }

    pub fn dm_request(uri: &str) -> AcceptInviteRequest {
        AcceptInviteRequest {
            invite_uri: uri.into(),
            display_name: "Alice".into(),
            listen_port: 0,
            static_peer: None,
        }
    }

    pub fn group_request(&self) -> CreateGroupRequest {
        CreateGroupRequest {
            label: Some("Work".into()),
            display_name: "Alice".into(),
            listen_port: 0,
            static_peer: None,
            org_pubkey: Some(self.org_key.clone()),
        }
    }

    pub fn own_peer(&self) -> &str {
        &self.own_peer
    }

    pub fn other_peer(&self) -> String {
        org_signing::peer_id_hex(&SigningKey::from_bytes(&[93; 32]))
    }

    pub fn published_dm_frames(&self) -> usize {
        self.net
            .endpoint(&org_signing::peer_id_hex(&self.member))
            .drain()
            .len()
    }

    pub fn group_join_request(&self, uri: &str) -> JoinGroupRequest {
        JoinGroupRequest {
            invite_uri: uri.into(),
            display_name: "Alice".into(),
            listen_port: 0,
            static_peer: None,
            org_pubkey: Some(self.org_key.clone()),
        }
    }

    pub fn restart(&mut self) {
        let attachments = Arc::new(AttachmentStore::new(self._directory.path()).unwrap());
        let shared = SharedMossNode::new(Arc::new(MossFfiRuntime::load_default().unwrap()));
        self.dm = PrivateDmRuntime::with_transport(
            self.net.endpoint(&self.own_peer),
            attachments.clone(),
            Some(self.store.clone()),
        );
        self.groups = PrivateGroupRuntime::from_shared_node(
            shared.clone(),
            attachments,
            Some(self.store.clone()),
        );
        self.org = OrgRuntime::from_shared_node(shared, Some(self.store.clone()));
        self.org.rehydrate();
        self.dm.rehydrate();
        self.groups.rehydrate();
    }
}

fn seed_node_identity(store: &Persistence) -> String {
    let node_key = SigningKey::from_bytes(&[90; 32]);
    let mut identity = vec![1];
    identity.extend_from_slice(&[90; 32]);
    identity.extend_from_slice(&node_key.verifying_key().to_bytes());
    identity.extend_from_slice(&[0; 64]);
    store.put_moss_identity(&identity).unwrap();
    org_signing::peer_id_hex(&node_key)
}
