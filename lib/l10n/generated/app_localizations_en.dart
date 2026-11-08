// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get ok => 'OK';

  @override
  String get close => 'Close';

  @override
  String get show => 'Show';

  @override
  String get hide => 'Hide';

  @override
  String get edit => 'Edit';

  @override
  String get importAction => 'Import';

  @override
  String get importFromFile => 'Import from file';

  @override
  String get back => 'Back';

  @override
  String get copy => 'Copy';

  @override
  String get paste => 'Paste';

  @override
  String get loading => 'Loading';

  @override
  String get navHosts => 'Hosts';

  @override
  String get navTerminal => 'Terminal';

  @override
  String get navKeys => 'Keys';

  @override
  String get navSnippets => 'Snippets';

  @override
  String get navForwarding => 'Forwarding';

  @override
  String get navSettings => 'Settings';

  @override
  String get discardChangesTitle => 'Discard unsaved changes?';

  @override
  String get discardChangesBody => 'Anything you entered here will be lost.';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get discardChanges => 'Discard';

  @override
  String get searchHosts => 'Search hosts';

  @override
  String get newHost => 'New host';

  @override
  String get loadHostsFailed => 'Couldn\'t load hosts';

  @override
  String get noHostsTitle => 'No hosts yet';

  @override
  String get noHostsMessage =>
      'Add a server, then connect to it from here in one click';

  @override
  String get noMatchesTitle => 'No matching hosts';

  @override
  String get noMatchesMessage => 'Try a different search';

  @override
  String get renameGroup => 'Rename group';

  @override
  String get deleteGroup => 'Delete group';

  @override
  String deleteGroupTitle(String name) {
    return 'Delete group \"$name\"?';
  }

  @override
  String get deleteGroupEmpty => 'This group has no hosts.';

  @override
  String deleteGroupBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts move to \"Ungrouped\"',
      one: '1 host moves to \"Ungrouped\"',
    );
    return '$_temp0; the hosts themselves are kept.';
  }

  @override
  String get ungrouped => 'Ungrouped';

  @override
  String get groupActions => 'Group actions';

  @override
  String get emptyGroupHint =>
      'No hosts in this group yet. Choose it when editing a host.';

  @override
  String get groupNameRequired => 'Enter a group name';

  @override
  String get groupNameTaken => 'A group with this name already exists';

  @override
  String get groupName => 'Group name';

  @override
  String get groupNameEmptyError => 'Group name can\'t be empty';

  @override
  String groupNameExistsError(String name) {
    return 'A group named \"$name\" already exists';
  }

  @override
  String get reachUp => 'Reachable';

  @override
  String reachUpLatency(int ms) {
    return 'Reachable · $ms ms';
  }

  @override
  String get reachDown => 'Unreachable';

  @override
  String get reachChecking => 'Checking…';

  @override
  String get editHost => 'Edit host';

  @override
  String get fieldName => 'Name';

  @override
  String get hostNameHint => 'e.g. Production server (optional)';

  @override
  String get fieldAddress => 'Address';

  @override
  String get addressHint => 'IP address or domain name';

  @override
  String get addressRequired => 'Enter an address';

  @override
  String get fieldPort => 'Port';

  @override
  String get fieldUsername => 'Username';

  @override
  String get usernameRequired => 'Enter a username';

  @override
  String get authMethod => 'Authentication';

  @override
  String get authPassword => 'Password';

  @override
  String get authKey => 'Private key';

  @override
  String get passwordHelper =>
      'Stored encrypted in uessh. Leave empty to be asked when connecting.';

  @override
  String get fieldPassphrase => 'Key passphrase';

  @override
  String get passphraseHelper =>
      'Leave empty if the key isn\'t encrypted. If it is, you\'ll be asked when connecting.';

  @override
  String saveFailed(String error) {
    return 'Couldn\'t save: $error';
  }

  @override
  String deleteHostTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get deleteHostBody =>
      'The host and its saved password and key will be deleted. This can\'t be undone.';

  @override
  String get keyRequired => 'Paste or import a private key';

  @override
  String get keyWrongPassphrase => 'Wrong key passphrase';

  @override
  String get keyUnrecognized =>
      'Unrecognized key format (supported: OpenSSH, and PEM RSA / ECDSA / Ed25519)';

  @override
  String get keyEmpty => 'No key found in this text';

  @override
  String get newGroupName => 'New group name';

  @override
  String get newGroupHint => 'e.g. Production';

  @override
  String get group => 'Group';

  @override
  String newGroupPending(String name) {
    return '$name (new)';
  }

  @override
  String get addGroup => 'Add group';

  @override
  String get cancelNewGroup => 'Cancel';

  @override
  String get newGroup => 'New group';

  @override
  String get savedKeysHint =>
      'Tip: keys saved on the Keys page can be picked here';

  @override
  String get keyToUse => 'Key';

  @override
  String get pasteKeyOption => 'Paste a key (this host only)';

  @override
  String get addKey => 'Add key';

  @override
  String get editKey => 'Edit key';

  @override
  String get loadKeysFailed => 'Couldn\'t load keys';

  @override
  String get noKeysTitle => 'No keys yet';

  @override
  String get noKeysMessage =>
      'Add an SSH private key to pick it when creating hosts';

  @override
  String get keyEncrypted => 'Encrypted';

  @override
  String deleteKeyTitle(String name) {
    return 'Delete key \"$name\"?';
  }

  @override
  String get deleteKeyBody =>
      'The key and its passphrase will be removed from uessh. This can\'t be undone.';

  @override
  String deleteKeyInUse(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hosts use this key and will need another one',
      one: '1 host uses this key and will need another one',
    );
    return '$_temp0. The key can\'t be recovered.';
  }

  @override
  String get publicKeyCopied =>
      'Public key copied. Paste it into ~/.ssh/authorized_keys on the server.';

  @override
  String get keyNameHint => 'e.g. Work laptop';

  @override
  String get nameRequired => 'Enter a name';

  @override
  String get keyType => 'Type';

  @override
  String get fingerprint => 'Fingerprint';

  @override
  String get copyPublicKey => 'Copy public key';

  @override
  String get enterMasterPassword => 'Enter your master password';

  @override
  String get wrongMasterPassword => 'Wrong master password';

  @override
  String get lockedTitle => 'uessh is locked';

  @override
  String get lockedSubtitle =>
      'Enter your master password to unlock saved passwords and keys';

  @override
  String get masterPassword => 'Master password';

  @override
  String get unlock => 'Unlock';

  @override
  String get forgotMasterPassword => 'Forgot master password?';

  @override
  String get resetVaultTitle => 'Reset the vault?';

  @override
  String get resetVaultBody =>
      'The master password can\'t be recovered. Resetting deletes every saved password, key and passphrase. Hosts and groups are kept; you\'ll need to enter login details again.';

  @override
  String get resetVaultConfirm => 'Delete saved credentials and reset';

  @override
  String get vaultLocked => 'The vault is locked';

  @override
  String minChars(int count) {
    return 'At least $count characters';
  }

  @override
  String get setMasterPassword => 'Set master password';

  @override
  String get setMasterPasswordIntro =>
      'uessh will ask for it each time it starts, before saved passwords and keys can be used. It can\'t be recovered, so don\'t forget it.';

  @override
  String get turnOn => 'Turn on';

  @override
  String get changeMasterPassword => 'Change master password';

  @override
  String get change => 'Change';

  @override
  String get turnOffMasterPassword => 'Turn off master password';

  @override
  String get turnOffIntro =>
      'uessh will stop asking for it at startup. Credentials stay encrypted with a key kept on this computer.';

  @override
  String get currentMasterPassword => 'Current master password';

  @override
  String get enterCurrentMasterPassword => 'Enter your current master password';

  @override
  String get newMasterPassword => 'New master password';

  @override
  String get confirmPassword => 'Enter it again';

  @override
  String get passwordsDontMatch => 'The passwords don\'t match';

  @override
  String get logCopied => 'Log copied to the clipboard';

  @override
  String get log => 'Log';

  @override
  String get warningsOnly => 'Warnings and errors only';

  @override
  String logCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return '$_temp0';
  }

  @override
  String get noLogs => 'No log entries';

  @override
  String logFile(String path) {
    return 'Log file: $path';
  }

  @override
  String get clear => 'Clear';

  @override
  String get copyAll => 'Copy all';

  @override
  String get checkOff => 'Off';

  @override
  String seconds(int n) {
    return '$n s';
  }

  @override
  String minutes(int n) {
    return '$n min';
  }

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get systemAccent => 'Use system accent color';

  @override
  String get systemAccentSubtitle => 'When off, uessh uses its own colors';

  @override
  String get reachability => 'Host reachability';

  @override
  String get checkInterval => 'Check interval';

  @override
  String get checkIntervalOn =>
      'Checked at launch, then again at this interval';

  @override
  String get checkIntervalOff =>
      'Hosts aren\'t checked and no status dots are shown';

  @override
  String get checkMethod => 'Method';

  @override
  String get checkMethodPing =>
      'Sends a ping. Some cloud security groups block ping; such hosts show as unreachable.';

  @override
  String get checkMethodSsh =>
      'Connects to the host\'s SSH port, which shows whether you can log in';

  @override
  String get sshPort => 'SSH port';

  @override
  String get security => 'Security';

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String get logSubtitle =>
      'Connection history and errors, for troubleshooting';

  @override
  String get viewLog => 'View log';

  @override
  String get never => 'Never';

  @override
  String get masterPasswordOn => 'On: uessh asks for it at startup';

  @override
  String get masterPasswordOff =>
      'Off: credentials are encrypted with a key on this computer; no password needed';

  @override
  String get autoLock => 'Auto-lock';

  @override
  String get autoLockSubtitle => 'Lock after a period of inactivity';

  @override
  String get lockNow => 'Lock now';

  @override
  String get language => 'Language';

  @override
  String get languageSubtitle => 'The language uessh is shown in';

  @override
  String get forwardingTitle => 'Port forwarding';

  @override
  String get noForwardsTitle => 'No forwarding rules yet';

  @override
  String get noForwardsMessage =>
      'Local, remote and dynamic (SOCKS) forwarding';

  @override
  String get snippetsTitle => 'Snippets';

  @override
  String get noSnippetsTitle => 'No snippets yet';

  @override
  String get noSnippetsMessage =>
      'Save commands you use often and send them to the terminal in one click';

  @override
  String get info => 'Info';

  @override
  String get closeInfoPanel => 'Close info panel';

  @override
  String get infoAfterConnect => 'Server details appear once connected';

  @override
  String get infoUnavailable => 'Couldn\'t read system information';

  @override
  String get sectionSystem => 'System';

  @override
  String get hostname => 'Hostname';

  @override
  String get os => 'OS';

  @override
  String get kernel => 'Kernel';

  @override
  String get uptime => 'Uptime';

  @override
  String cpuCores(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n cores',
      one: '1 core',
    );
    return '$_temp0';
  }

  @override
  String get load => 'Load';

  @override
  String get resources => 'Resources';

  @override
  String get calculating => 'Calculating…';

  @override
  String get memory => 'Memory';

  @override
  String get diskRoot => 'Disk /';

  @override
  String get statusConnecting => 'Connecting';

  @override
  String get statusConnected => 'Connected';

  @override
  String get statusFailed => 'Connection failed';

  @override
  String get statusClosed => 'Disconnected';

  @override
  String get sectionConnection => 'Connection';

  @override
  String get auth => 'Auth';

  @override
  String get status => 'Status';

  @override
  String get connectedFor => 'Connected for';

  @override
  String get latency => 'Latency';

  @override
  String get fetchingInfo => 'Reading system information…';

  @override
  String durationDaysHours(int days, int hours) {
    return '$days d $hours h';
  }

  @override
  String durationDays(int days) {
    return '$days d';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String durationHours(int hours) {
    return '$hours h';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get durationUnderMinute => 'Less than a minute';

  @override
  String get hostKeyChangedTitle => 'Host key changed';

  @override
  String get hostKeyNewTitle => 'First connection to this host';

  @override
  String hostKeyChangedBody(String hostPort) {
    return 'The host key of $hostPort is different from last time. The server may have been reinstalled, or someone may be intercepting the connection. Only continue if you\'re sure.';
  }

  @override
  String hostKeyNewBody(String hostPort) {
    return 'uessh can\'t confirm the identity of $hostPort. Check the fingerprint below and only continue if it\'s your server.';
  }

  @override
  String previousFingerprint(String type) {
    return 'Previous fingerprint ($type)';
  }

  @override
  String currentFingerprint(String type) {
    return 'New fingerprint ($type)';
  }

  @override
  String get trustAnyway => 'Trust anyway';

  @override
  String get trustAndConnect => 'Trust and connect';

  @override
  String get noSessionsTitle => 'No open sessions';

  @override
  String get noSessionsMessage => 'Click a server under Hosts to connect';

  @override
  String get hideInfoPanel => 'Hide info panel';

  @override
  String get showInfoPanel => 'Show info panel';

  @override
  String get closeTabTitle => 'Close this tab?';

  @override
  String closeTabBody(String name) {
    return 'The SSH connection to $name will be closed and the terminal contents discarded.';
  }

  @override
  String get connectionClosed => 'Connection closed';

  @override
  String get reconnect => 'Reconnect';

  @override
  String connectingTo(String target) {
    return 'Connecting to $target…';
  }

  @override
  String get keyDeletedError =>
      'The key this host uses was deleted. Edit the host and choose another key.';

  @override
  String get noKeyError =>
      'This host has no private key. Edit the host and import one first.';

  @override
  String get enterKeyPassphrase => 'Enter key passphrase';

  @override
  String keyIsEncrypted(String name) {
    return 'The private key for $name is encrypted';
  }

  @override
  String get loginCancelled => 'Login cancelled';

  @override
  String get enterPassword => 'Enter password';

  @override
  String loginTo(String target) {
    return 'Log in to $target';
  }

  @override
  String get serverVerification => 'Server verification';

  @override
  String get connectionClosedMarker => '[connection closed]';

  @override
  String cannotConnect(String address, String reason) {
    return 'Couldn\'t connect to $address ($reason)';
  }

  @override
  String connectTimeout(String address) {
    return 'Connection to $address timed out';
  }

  @override
  String get authFailed =>
      'Authentication failed: wrong username, password or key';

  @override
  String get hostKeyRejected => 'Host key not trusted; disconnected';

  @override
  String get keyFormatShort => 'Unrecognized key format';

  @override
  String sshError(String error) {
    return 'SSH error: $error';
  }

  @override
  String connectFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String get appLanguageZh => '简体中文';

  @override
  String get appLanguageEn => 'English';

  @override
  String get newSession => 'New session';

  @override
  String get pickHostTitle => 'Choose a host to connect to';

  @override
  String get goAddHost => 'Add a host';

  @override
  String get pickHostHint => '↑↓ to choose, Enter to open';

  @override
  String get overviewTotal => 'Total hosts';

  @override
  String overviewGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count groups',
      one: '1 group',
    );
    return '$_temp0';
  }

  @override
  String get overviewOnline => 'Online';

  @override
  String get overviewLost => 'Unreachable';

  @override
  String get overviewChecksOff => 'Checks off';

  @override
  String get overviewLastConnected => 'Last connected';

  @override
  String get overviewNoRecent => 'No connections yet';

  @override
  String get connect => 'Connect';

  @override
  String get timeJustNow => 'just now';

  @override
  String timeMinutesAgo(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String timeDaysAgo(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get showHostOverview => 'Show host overview';

  @override
  String get showHostOverviewSubtitle =>
      'Host counts, status and your last connection at the top of the Hosts page';

  @override
  String get hostIcon => 'Icon';

  @override
  String get iconLetter => 'Letter';

  @override
  String get iconSymbol => 'Symbol';

  @override
  String get iconFlag => 'Flag';

  @override
  String get iconColorAuto => 'Theme color';

  @override
  String get iconFlagHint =>
      'Shows the flag of the country the host\'s IP is in (the IP is sent to ipwho.is). Falls back to the first letter when unknown, e.g. for LAN addresses.';

  @override
  String get moreSettings => 'More settings';

  @override
  String get lessSettings => 'Fewer settings';

  @override
  String get trayShow => 'Show uessh';

  @override
  String get trayQuickConnect => 'Quick connect';

  @override
  String get trayQuit => 'Quit uessh';

  @override
  String get runInBackground => 'Keep running in background';

  @override
  String get runInBackgroundSubtitle =>
      'Shows an icon in the menu bar or system tray; closing the window keeps uessh and its SSH sessions running';

  @override
  String get general => 'General';

  @override
  String get aiAssistant => 'AI assistant';

  @override
  String get aiShowPanel => 'AI assistant';

  @override
  String get aiHidePanel => 'Hide AI assistant';

  @override
  String get aiClosePanel => 'Close AI assistant';

  @override
  String get aiNewChat => 'New chat';

  @override
  String get aiSetupTitle => 'No AI provider set up yet';

  @override
  String get aiSetupBody =>
      'Add an API key in Settings to start. Claude, ChatGPT, DeepSeek, Gemini, Grok and custom endpoints are supported.';

  @override
  String get aiOpenSettings => 'Open Settings';

  @override
  String get aiInputHint =>
      'Ask something. Enter to send, Shift+Enter for a new line';

  @override
  String get aiPickModel => 'Choose a model';

  @override
  String get aiLoadingModels => 'Loading models…';

  @override
  String get aiModelsFailed => 'Couldn\'t load models';

  @override
  String get aiNoModels => 'No models available';

  @override
  String get aiRetry => 'Retry';

  @override
  String get aiManageProviders => 'Manage AI providers…';

  @override
  String get aiAttachOn => 'Attach terminal output: on (last 80 lines)';

  @override
  String get aiAttachOff => 'Attach terminal output: off';

  @override
  String get aiSend => 'Send';

  @override
  String get aiStop => 'Stop';

  @override
  String get aiCopied => 'Copied';

  @override
  String get aiPasteToTerminal => 'Paste into terminal (doesn\'t run it)';

  @override
  String get aiReasoning => 'Reasoning';

  @override
  String get aiRefused => 'The model declined to answer this.';

  @override
  String get aiTruncated => 'The answer was too long and got cut off.';

  @override
  String get aiNoKey => 'This provider has no API key';

  @override
  String get aiWithTerminal => 'Terminal output attached';

  @override
  String get aiStopped => 'Stopped';

  @override
  String get aiSection => 'AI assistant';

  @override
  String get aiProviderConfigured => 'Set up';

  @override
  String get aiProviderNotConfigured => 'Not set up';

  @override
  String get aiAddCustom => 'Add custom provider';

  @override
  String get aiCustomProvider => 'Custom provider';

  @override
  String get aiApiKey => 'API key';

  @override
  String get aiApiKeyKeep => 'Saved; leave empty to keep it';

  @override
  String get aiGetKey => 'Get an API key';

  @override
  String get aiBaseUrl => 'Base URL';

  @override
  String get aiBaseUrlRequired => 'Enter the base URL';

  @override
  String get aiBaseUrlInvalid =>
      'Enter an address starting with http:// or https://';

  @override
  String get aiProviderName => 'Name';

  @override
  String get aiNameRequired => 'Enter a name';

  @override
  String get aiProtocol => 'API format';

  @override
  String get aiProtocolOpenai => 'OpenAI-compatible';

  @override
  String get aiProtocolAnthropic => 'Anthropic';

  @override
  String get aiExtraModels => 'Extra models';

  @override
  String get aiExtraModelsHelper =>
      'If the endpoint doesn\'t list its models, enter model ids here, separated by commas';

  @override
  String get aiTest => 'Test connection';

  @override
  String get aiTesting => 'Testing…';

  @override
  String get aiKeyStored =>
      'API keys are encrypted in this computer\'s vault, never written to config files.';

  @override
  String get aiRemoveProvider => 'Remove';

  @override
  String get aiRemoveTitle => 'Remove this provider?';

  @override
  String get aiRemoveBody => 'Its API key and settings will be deleted.';

  @override
  String get aiKeyRequired => 'Enter the API key';

  @override
  String aiBaseUrlDefault(String url) {
    return 'Leave empty for the default: $url';
  }

  @override
  String aiTestOk(int count) {
    return 'Connected: $count models available';
  }

  @override
  String aiTestFailed(String error) {
    return 'Couldn\'t connect: $error';
  }

  @override
  String get aiToolRun => 'Run command';

  @override
  String get aiToolReadTerminal => 'Read terminal';

  @override
  String get aiToolWaiting => 'Waiting for you';

  @override
  String get aiToolRunning => 'Running';

  @override
  String get aiToolDone => 'Done';

  @override
  String get aiToolDenied => 'Declined';

  @override
  String get aiToolFailed => 'Failed';

  @override
  String get aiToolMayChange =>
      'This command may change the server. It runs only if you allow it.';

  @override
  String get aiToolAskAll =>
      'With your current setting, every command needs your approval.';

  @override
  String get aiAllow => 'Allow';

  @override
  String get aiDeny => 'Decline';

  @override
  String get aiShowOutput => 'Show output';

  @override
  String get aiHideOutput => 'Hide output';

  @override
  String get aiNoOutput => '(no output)';

  @override
  String get aiStepLimit =>
      'Reached the step limit for one message; reply \"continue\" to carry on.';

  @override
  String get aiToolMode => 'Command execution';

  @override
  String get aiToolModeSubtitle =>
      'Let the AI run commands on the connected host to investigate and fix things';

  @override
  String get aiToolModeOff => 'Off';

  @override
  String get aiToolModeAsk => 'Ask for every command';

  @override
  String get aiToolModeAuto => 'Run read-only commands automatically';

  @override
  String aiToolExit(int code) {
    return 'exit $code';
  }

  @override
  String get aiToolModeAll => 'Allow all (never ask)';

  @override
  String get aiAllowAllTitle => 'Let the AI run every command?';

  @override
  String get aiAllowAllBody =>
      'The AI will run any command without asking you, including deleting files, changing configuration and restarting services. It can do anything the SSH user can, and a mistake may lose data or take services down. Best used only on test machines.';

  @override
  String get aiAllowAllConfirm => 'Turn it on';

  @override
  String get splitRight => 'Split right';

  @override
  String get splitDown => 'Split down';

  @override
  String get zoomPane => 'Maximize pane';

  @override
  String get restorePane => 'Restore pane';

  @override
  String get moveToNewTab => 'Move to new tab';

  @override
  String get closePane => 'Close pane';

  @override
  String get broadcastOn => 'Broadcast input to all panes';

  @override
  String get broadcastOff => 'Stop broadcasting input';

  @override
  String get broadcasting => 'Broadcasting';

  @override
  String get workspaceFull => 'A workspace holds at most 9 panes';

  @override
  String get closeWorkspaceTitle => 'Close this workspace?';

  @override
  String get dropHere => 'Drop here';

  @override
  String closeWorkspaceBody(int count) {
    return 'Its $count connections will be closed.';
  }

  @override
  String workspaceName(int n) {
    return 'Workspace $n';
  }

  @override
  String get renameWorkspaceHint => 'Click to rename';

  @override
  String get aiHistory => 'History';

  @override
  String get aiHistoryEmpty => 'No conversations yet';

  @override
  String get aiHistoryThisHost => 'This host';

  @override
  String get aiHistoryOtherHosts => 'Other hosts';

  @override
  String get aiHistoryDelete => 'Delete this conversation';

  @override
  String get aiBackToChat => 'Back to chat';

  @override
  String get aiClearHistory => 'Clear AI conversations';

  @override
  String get aiClearHistorySubtitle =>
      'Conversations are encrypted on this computer; up to 200 are kept';

  @override
  String get aiClearHistoryTitle => 'Clear all AI conversations?';

  @override
  String get aiClearHistoryBody =>
      'Conversations for every host will be deleted. This can\'t be undone.';

  @override
  String get aiClear => 'Clear';

  @override
  String get filesShow => 'Files';

  @override
  String get filesHide => 'Close files';

  @override
  String get filesBack => 'Back';

  @override
  String get filesForward => 'Forward';

  @override
  String get filesUp => 'Enclosing folder';

  @override
  String get filesRefresh => 'Refresh';

  @override
  String get filesFollow => 'Follow the terminal\'s folder';

  @override
  String get filesShowHidden => 'Show hidden files';

  @override
  String get filesHideHidden => 'Hide hidden files';

  @override
  String get viewIcons => 'Icons';

  @override
  String get viewList => 'List';

  @override
  String get viewColumns => 'Columns';

  @override
  String get viewGallery => 'Gallery';

  @override
  String get colName => 'Name';

  @override
  String get colModified => 'Date Modified';

  @override
  String get colSize => 'Size';

  @override
  String get colKind => 'Kind';

  @override
  String get filesEmpty => 'Empty folder';

  @override
  String get filesNotConnected => 'Connect to browse files';

  @override
  String get filesLocating => 'Finding the terminal\'s folder…';

  @override
  String get filesOpen => 'Open';

  @override
  String get filesCdHere => 'Go here in terminal';

  @override
  String get filesCopyPath => 'Copy path';

  @override
  String get filesDownload => 'Download…';

  @override
  String get filesNoPreview => 'No preview';

  @override
  String get filesPermissions => 'Permissions';

  @override
  String get kindFolder => 'Folder';

  @override
  String get kindImage => 'Image';

  @override
  String get kindText => 'Text';

  @override
  String get kindCode => 'Code';

  @override
  String get kindArchive => 'Archive';

  @override
  String get kindVideo => 'Video';

  @override
  String get kindAudio => 'Audio';

  @override
  String get kindPdf => 'PDF document';

  @override
  String get kindDocument => 'Document';

  @override
  String get kindExecutable => 'Executable';

  @override
  String get kindFile => 'File';

  @override
  String get kindLink => 'Alias';

  @override
  String filesItems(int n) {
    return '$n items';
  }

  @override
  String filesError(String error) {
    return 'Can\'t open: $error';
  }

  @override
  String filesDownloaded(String path) {
    return 'Downloaded to $path';
  }

  @override
  String filesDownloading(String name) {
    return 'Downloading $name…';
  }

  @override
  String get aiAddProvider => 'Add AI provider';

  @override
  String get aiNoProviders => 'No AI provider added yet';

  @override
  String get aiNoProvidersHint =>
      'Add a provider with its API key to use the AI assistant on the terminal page';

  @override
  String get aiAlreadyAdded => 'Added';

  @override
  String get filesUpload => 'Upload files…';

  @override
  String get filesUploadHere => 'Upload files here…';

  @override
  String get dropResolving => 'Finding the current folder…';

  @override
  String get uploadNotConnected => 'Not connected; can\'t upload';

  @override
  String get overwriteTitle => 'Replace existing items?';

  @override
  String get overwriteReplace => 'Replace';

  @override
  String get overwriteSkip => 'Skip';

  @override
  String dropToUpload(String path) {
    return 'Release to upload to $path';
  }

  @override
  String uploadProgress(String path) {
    return 'Uploading to $path';
  }

  @override
  String uploadDone(int count, String path) {
    return 'Uploaded $count files to $path';
  }

  @override
  String uploadFailed(String error) {
    return 'Upload failed: $error';
  }

  @override
  String overwriteBody(String path, String names) {
    return '$path already has: $names';
  }

  @override
  String uploadCount(int done, int total) {
    return '$done/$total files';
  }

  @override
  String get aiToolHiddenChars =>
      'The command contains hidden or reversed characters (shown as <U+…>); it may not be what it looks like.';

  @override
  String aiToolOnHost(String host) {
    return 'Runs on $host';
  }

  @override
  String get aiPasteRunsTitle => 'Pasting will run it';

  @override
  String get aiPasteAnyway => 'Paste anyway';

  @override
  String aiPasteRunsBody(int n) {
    return 'This server\'s shell doesn\'t use safe (bracketed) paste: the first $n lines will run right away, as if Enter were pressed.';
  }

  @override
  String get aiBaseUrlHttps =>
      'Use https://, or the API key travels unencrypted (http is only allowed for localhost)';

  @override
  String get aiAllowAllActive =>
      'Allow all is on: the AI runs any command without asking. Tap to change in Settings';

  @override
  String get workbench => 'Workbench';

  @override
  String reconnectingIn(int seconds, int attempt, int total) {
    return 'Reconnecting in ${seconds}s (attempt $attempt/$total)';
  }

  @override
  String reconnectGaveUp(int count) {
    return 'Still not connected after $count attempts; stopped reconnecting';
  }

  @override
  String reconnectBanner(int seconds, int attempt, int total) {
    return 'Disconnected. Reconnecting in ${seconds}s ($attempt/$total)';
  }

  @override
  String reconnectingNow(int attempt, int total) {
    return 'Reconnecting ($attempt/$total)…';
  }

  @override
  String get reconnectNow => 'Reconnect now';

  @override
  String get settingsReconnect => 'Auto-reconnect';

  @override
  String get settingsReconnectSubtitle =>
      'Reconnect when an SSH connection drops unexpectedly; typing exit doesn\'t reconnect';

  @override
  String get settingsReconnectAttempts => 'Reconnect attempts';

  @override
  String get settingsReconnectDelay => 'Time between attempts';

  @override
  String reconnectAttemptsValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count times',
      one: '1 time',
    );
    return '$_temp0';
  }

  @override
  String reconnectDelayValue(int seconds) {
    return '${seconds}s';
  }

  @override
  String get sshSection => 'SSH connections';

  @override
  String get settingsHighlight => 'Command syntax highlighting';

  @override
  String get settingsHighlightSubtitle =>
      'Colors the command you\'re typing in the terminal; local only, nothing changes on the server';

  @override
  String get highlightCommand => 'Command';

  @override
  String get highlightDangerous => 'Dangerous command';

  @override
  String get highlightOption => 'Option';

  @override
  String get highlightString => 'String';

  @override
  String get highlightVariable => 'Variable';

  @override
  String get highlightOperator => 'Pipe / redirect';

  @override
  String get highlightComment => 'Comment';

  @override
  String get highlightResetAll => 'Reset all';

  @override
  String get highlightDefault => 'Default color';
}
