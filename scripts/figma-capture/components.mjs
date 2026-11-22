// Design components of the redesign (MOSH-119) and the captured widgets each
// one covers. inventory.mjs fails until every widget that paints in more than
// one scene is listed here once. Lib widgets go by class name, private ones
// as "<file stem>._Name", Material controls by their Flutter class.
export const GROUPS = [
  { id: 'controls', title: 'Base controls', ticket: 'MOSH-123' },
  { id: 'rows', title: 'Chat rows and messages', ticket: 'MOSH-124' },
  { id: 'surfaces', title: 'Surfaces and feedback', ticket: 'MOSH-125' },
  { id: 'call', title: 'Call', ticket: 'MOSH-126' },
];

/** Where SCREEN_PARTS go: laid out per screen, not redrawn as components. */
export const SCREEN_GROUP = { id: 'screen', title: 'Screen parts', ticket: 'MOSH-127' };

const component = (group, name, widgets) => ({ group, name, widgets });

export const COMPONENTS = [
  component('controls', 'Button', ['FilledButton', 'OutlinedButton', 'TextButton', 'FieldLogButton']),
  component('controls', 'Icon button', ['IconButton', 'attachment_actions._ActionIcon', 'media_viewer._MediaCloseButton']),
  component('controls', 'Text field', ['TextField', 'InlineError', 'invite_result._LinkField']),
  component('controls', 'Select', ['MoshSelect', 'AudioDevicePicker']),
  component('controls', 'Switch', ['Switch', 'AsyncSwitchTile']),
  component('controls', 'Chip and segment', ['ChoiceChip', 'ActionChip', 'conversation_search_box._FilterSegment']),
  component('controls', 'Avatar', ['Avatar', 'ConversationKindAvatar', 'UserPlusBadge']),
  component('controls', 'Badge and status pill', ['UnreadBadge', 'StatePill', 'summary_card._StatusBadge']),
  component('controls', 'Progress', ['CircularProgressIndicator', 'LinearProgressIndicator', 'MoshProgressBar']),
  component('controls', 'Slider', ['Slider']),
  component('controls', 'Divider', ['Divider']),

  component('rows', 'Chat row', ['RailItem', 'rail_item._RailText', 'ChatRowMenu', 'CompactRailItem']),
  component('rows', 'Chat list controls', ['SessionsListControls', 'RailNewButton', 'RailSettingsButton', 'CompactRailButton', 'RailDivider']),
  component('rows', 'Org section', ['OrgSection', 'org_section._Header', 'org_section._MemberRow', 'org_section._OfferRow', 'org_section._NewGroupForm']),
  component('rows', 'Message bubble', ['ConversationMessageRow', 'ConversationMessageText', 'ConversationMessageFooter', 'DeliveryTicks', 'FailedMessageRetry']),
  component('rows', 'Sender meta', ['conversation_sender_meta._PeerNickname', 'DeviceFingerprintChip']),
  component('rows', 'Feed divider', ['ConversationDateDivider', 'ConversationUnreadDivider']),
  component('rows', 'Call log entry', ['CallLogEntry']),
  component('rows', 'Attachment card', ['attachment_card._FileCardShell', 'AttachmentThumb', 'ConversationSharedFile']),
  component('rows', 'Voice message', ['VoiceMessageCard', 'VoiceWaveform', 'VoiceCardTimeLabel']),
  component('rows', 'Composer', ['ConversationComposer', 'AttachmentPicker', 'VoiceComposer', 'VoiceRecordingDot', 'TypingHint']),
  component('rows', 'Search bar', ['ConversationSearchBox', 'ConversationFilterToggle', 'MobileConversationSearch', 'MobileConversationFilterNotice', 'ConversationSearchEmpty']),
  component('rows', 'Selection bar', ['MessageSelectionBar', 'MessageSelectionActions', 'MessageSelectionComposer', 'Checkbox']),

  component('surfaces', 'Window title bar', ['MoshTitleBar', 'mosh_title_bar._ChatListToggle', 'DesktopCaptionButtons']),
  component('surfaces', 'Top app bar', ['AppBar', 'ConversationAppBar', 'ConversationHeaderTitle', 'ChatHeaderMenu', 'MobileSearchToggle', 'FingerprintLock']),
  component('surfaces', 'Dialog', ['Dialog', 'VpnConsentModal']),
  component('surfaces', 'Menu', ['MoshMenuItem', 'MenuItemButton', 'message_context_menu._MessageMenuPanel']),
  component('surfaces', 'Banner', ['CryptoNoticeBanner', 'ChatErrorBanner', 'OrgAddMissingBanner', 'GroupRejoinNeededError', 'PersistenceWarningBanner', 'persistence_warning_banner._IconPlate', 'AboutUpdateNotice']),
  component('surfaces', 'Inline note', ['SetupPrivacyNote', 'channel_join_step._OpenWarning', 'invite_result._ReadyNote']),
  component('surfaces', 'Toast', ['ToastCard']),
  component('surfaces', 'Settings card', ['SettingsSurface', 'SettingsCardHeader', 'SettingsIcon', 'ListTile', 'Card']),
  component('surfaces', 'Navigation row', ['SettingsNav', 'settings_nav._SectionRow', 'StartRow', 'start_list._Section']),
  component('surfaces', 'Device row', ['LinkedDeviceList', 'device_list._DeviceRow', 'device_list._Id', 'device_list._RevocationRow']),
  component('surfaces', 'Details panel', ['ConversationDetailsPanel', 'conversation_details_panel._Section', 'ExpansionTile', 'PeerStatusDrawer', 'peer_status_drawer._DrawerHeader']),
  component('surfaces', 'Diagnostics rows', ['DiagnosticsGroup', 'diagnostics_sections._GroupLabel', 'DiagnosticsRow', 'DiagnosticsEmptyState', 'SummaryCard', 'summary_card._Heading', 'summary_card._FactCell', 'Metric', 'event_log._EventRow', 'RuntimeError']),
  component('surfaces', 'Wizard step', ['SetupFrame', 'SetupHeading', 'SetupProgress', 'StartStep', 'device_link_steps._Step']),
  component('surfaces', 'Empty and error state', ['sessions_rail_list._EmptyState', 'sessions_screen._ErrorState', 'conversation_screen_body._ConversationEmpty']),
  component('surfaces', 'Media viewer', ['MediaViewer', 'media_viewer._MediaCaption', 'media_viewer._ImageStage', 'media_viewer_stages._AudioCard', 'media_viewer_stages._PlaybackPlaceholderCard', 'media_viewer_controls._PlaybackControls', 'MediaTimeLabel']),

  component('call', 'Call window', ['MainWindowCallFrame']),
  component('call', 'Call card', ['CallModalCard']),
  component('call', 'Call video stage', ['CallVideoStage']),
  component('call', 'Call button', ['CallButton']),
  component('call', 'Floating call', ['FloatingCallView']),
];

// Widgets that lay out one screen or flow; MOSH-127 rebuilds them from the
// components above instead of redrawing them as components.
export const SCREEN_PARTS = [
  'MoshApp', 'mosh_shell._MobileShell', 'RailPane', 'rail_pane._ResizeHandle', 'SessionsScreen', 'SessionsRailList', 'ChatPaneWelcome',
  'ConversationScreen', 'ConversationScreenBody', 'chat_drop_zone._DropOverlay',
  'SettingsScreen', 'SettingsContent', 'ProfileSettingsSection', 'DevicesSettingsSection', 'VoiceSettingsSection', 'DisplayNameForm',
  'BindInterfaceControls', 'DeviceLinkImportForm', 'DeviceLinkQr', 'DeviceLinkApprovalForm', 'DeviceQrScanner',
  'PlusMainnetSettings', 'PlusCurrencyCheckout', 'PlusPaymentDetails', 'PlusPaymentTerms', 'PlusNewPayment', 'PlusPendingPayment',
  'plus_checkout._PaymentLinkActions', 'PlusRecoveryPanel', 'PlusMembershipStatus',
  'FirstRunGate', 'FirstRunWizard', 'FirstRunDeviceStep', 'FirstRunNetworkForm', 'FirstRunNetworkStep', 'StartHero',
  'OnboardJoinStep', 'JoinPreview', 'ChatCreateStep', 'GroupCreateStep', 'ChannelJoinStep', 'channel_join_step._Examples', 'InviteResult',
  'InvitePasteScreen', 'MoshLockScreen', 'mosh_lock_screen._LockBody',
];

// Lib widgets that add behaviour (focus, press, motion, hit targets) around
// content they do not draw: their paint counts toward the widget around them.
// The app-level hosts are wrappers too: routes, dialogs, sheets and the call
// window open in overlays below them, so whatever those paint without a lib
// widget of their own would otherwise land on the host. It lands on MoshApp.
export const WRAPPERS = [
  'ToastHost', 'VpnConsentOverlay', 'PlusHost', 'voice_call_host._CallHostOverlay',
  'FocusRing', 'PressScale', 'ResumedInk', 'OpticalIcon', 'ContextualIconSwitcher', 'ModalFocusTrap', 'MoshDialogTransition',
  'StartReveal', 'toast_card._Bump', 'SetupArtworkMotion', 'SetupStepTransition', 'first_run_transition._SetupPanel',
  'CopyableMessage', 'SelectableMessageRow', 'MessageContextMenu', 'MessageSelectionHost', 'ChatDropZone', 'AttachmentOpenTarget',
  'CallVideoSurfaceScope', 'CallVideoSurfaceReport', 'mosh_shell._SemanticsPane',
];
