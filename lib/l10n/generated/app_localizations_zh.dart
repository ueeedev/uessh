// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get save => '保存';

  @override
  String get ok => '确定';

  @override
  String get close => '关闭';

  @override
  String get show => '显示';

  @override
  String get hide => '隐藏';

  @override
  String get edit => '编辑';

  @override
  String get importAction => '导入';

  @override
  String get importFromFile => '从文件导入';

  @override
  String get back => '返回';

  @override
  String get copy => '复制';

  @override
  String get paste => '粘贴';

  @override
  String get loading => '加载中';

  @override
  String get navHosts => '主机';

  @override
  String get navTerminal => '终端';

  @override
  String get navKeys => '密钥';

  @override
  String get navSnippets => '片段';

  @override
  String get navForwarding => '转发';

  @override
  String get navSettings => '设置';

  @override
  String get discardChangesTitle => '放弃未保存的修改？';

  @override
  String get discardChangesBody => '关闭后，刚才填写的内容不会保存。';

  @override
  String get keepEditing => '继续编辑';

  @override
  String get discardChanges => '放弃修改';

  @override
  String get searchHosts => '搜索主机';

  @override
  String get newHost => '新建主机';

  @override
  String get loadHostsFailed => '读取主机列表失败';

  @override
  String get noHostsTitle => '还没有主机';

  @override
  String get noHostsMessage => '添加一台服务器后，就可以从这里一键连接';

  @override
  String get noMatchesTitle => '没有匹配的主机';

  @override
  String get noMatchesMessage => '换个关键词试试';

  @override
  String get renameGroup => '重命名分组';

  @override
  String get deleteGroup => '删除分组';

  @override
  String deleteGroupTitle(String name) {
    return '删除分组“$name”？';
  }

  @override
  String get deleteGroupEmpty => '这个分组里没有主机。';

  @override
  String deleteGroupBody(int count) {
    return '组内 $count 台主机会移到“未分组”，主机本身不会被删除。';
  }

  @override
  String get ungrouped => '未分组';

  @override
  String get groupActions => '分组操作';

  @override
  String get emptyGroupHint => '这个分组还没有主机，编辑主机时可以把它放进来';

  @override
  String get groupNameRequired => '请输入分组名称';

  @override
  String get groupNameTaken => '已经有同名的分组';

  @override
  String get groupName => '分组名称';

  @override
  String get groupNameEmptyError => '分组名称不能为空';

  @override
  String groupNameExistsError(String name) {
    return '已经有名为“$name”的分组';
  }

  @override
  String get reachUp => '连通';

  @override
  String reachUpLatency(int ms) {
    return '连通 · $ms ms';
  }

  @override
  String get reachDown => '不通';

  @override
  String get reachChecking => '正在检测…';

  @override
  String get editHost => '编辑主机';

  @override
  String get fieldName => '名称';

  @override
  String get hostNameHint => '例如：生产服务器（可选）';

  @override
  String get fieldAddress => '地址';

  @override
  String get addressHint => 'IP 或域名';

  @override
  String get addressRequired => '请输入地址';

  @override
  String get fieldPort => '端口';

  @override
  String get fieldUsername => '用户名';

  @override
  String get usernameRequired => '请输入用户名';

  @override
  String get authMethod => '认证方式';

  @override
  String get authPassword => '密码';

  @override
  String get authKey => '私钥';

  @override
  String get passwordHelper => '加密保存在 uessh 中；留空则每次连接时询问';

  @override
  String get fieldPassphrase => '私钥口令';

  @override
  String get passphraseHelper => '私钥没有加密就留空；加密了但留空则每次连接时询问';

  @override
  String saveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String deleteHostTitle(String name) {
    return '删除 $name？';
  }

  @override
  String get deleteHostBody => '主机信息和保存的密码、私钥会一起删除，无法恢复。';

  @override
  String get keyRequired => '请粘贴或导入私钥';

  @override
  String get keyWrongPassphrase => '私钥口令不正确';

  @override
  String get keyUnrecognized =>
      '无法识别私钥格式（支持 OpenSSH、PEM 格式的 RSA / ECDSA / Ed25519）';

  @override
  String get keyEmpty => '私钥里没有找到密钥';

  @override
  String get newGroupName => '新分组名称';

  @override
  String get newGroupHint => '例如：生产环境';

  @override
  String get group => '分组';

  @override
  String newGroupPending(String name) {
    return '$name（新）';
  }

  @override
  String get addGroup => '添加分组';

  @override
  String get cancelNewGroup => '取消新建';

  @override
  String get newGroup => '新建分组';

  @override
  String get savedKeysHint => '提示：在“密钥”页保存常用私钥后，这里可以直接选用';

  @override
  String get keyToUse => '使用的密钥';

  @override
  String get pasteKeyOption => '直接粘贴私钥（仅用于这台主机）';

  @override
  String get addKey => '添加密钥';

  @override
  String get editKey => '编辑密钥';

  @override
  String get loadKeysFailed => '读取密钥失败';

  @override
  String get noKeysTitle => '还没有密钥';

  @override
  String get noKeysMessage => '添加 SSH 私钥后，新建主机时可以直接选用';

  @override
  String get keyEncrypted => '已加密';

  @override
  String deleteKeyTitle(String name) {
    return '删除密钥“$name”？';
  }

  @override
  String get deleteKeyBody => '私钥和口令会从 uessh 中删除，无法恢复。';

  @override
  String deleteKeyInUse(int count) {
    return '有 $count 台主机正在使用这个密钥，删除后需要为它们重新选择密钥。私钥和口令无法恢复。';
  }

  @override
  String get publicKeyCopied => '公钥已复制，可以粘贴到服务器的 ~/.ssh/authorized_keys';

  @override
  String get keyNameHint => '例如：工作笔记本';

  @override
  String get nameRequired => '请输入名称';

  @override
  String get keyType => '类型';

  @override
  String get fingerprint => '指纹';

  @override
  String get copyPublicKey => '复制公钥';

  @override
  String get enterMasterPassword => '请输入主密码';

  @override
  String get wrongMasterPassword => '主密码不正确';

  @override
  String get lockedTitle => 'uessh 已锁定';

  @override
  String get lockedSubtitle => '输入主密码解锁已保存的密码和私钥';

  @override
  String get masterPassword => '主密码';

  @override
  String get unlock => '解锁';

  @override
  String get forgotMasterPassword => '忘记主密码？';

  @override
  String get resetVaultTitle => '重置保险库？';

  @override
  String get resetVaultBody =>
      '主密码无法找回。重置会删除所有已保存的密码、私钥和口令，主机列表和分组会保留，之后需要重新填写登录信息。';

  @override
  String get resetVaultConfirm => '删除已保存的凭据并重置';

  @override
  String get vaultLocked => '保险库已锁定';

  @override
  String minChars(int count) {
    return '至少 $count 个字符';
  }

  @override
  String get setMasterPassword => '设置主密码';

  @override
  String get setMasterPasswordIntro =>
      '开启后，每次打开 uessh 需要输入一次主密码，才能使用已保存的密码和私钥。主密码无法找回，请务必记住。';

  @override
  String get turnOn => '开启';

  @override
  String get changeMasterPassword => '修改主密码';

  @override
  String get change => '修改';

  @override
  String get turnOffMasterPassword => '关闭主密码';

  @override
  String get turnOffIntro => '关闭后，打开 uessh 不再需要输入主密码，凭据改用本机密钥加密保存。';

  @override
  String get currentMasterPassword => '当前主密码';

  @override
  String get enterCurrentMasterPassword => '请输入当前主密码';

  @override
  String get newMasterPassword => '新主密码';

  @override
  String get confirmPassword => '再输入一次';

  @override
  String get passwordsDontMatch => '两次输入不一致';

  @override
  String get logCopied => '日志已复制到剪贴板';

  @override
  String get log => '日志';

  @override
  String get warningsOnly => '只看警告和错误';

  @override
  String logCount(int count) {
    return '$count 条';
  }

  @override
  String get noLogs => '暂无日志';

  @override
  String logFile(String path) {
    return '日志文件：$path';
  }

  @override
  String get clear => '清空';

  @override
  String get copyAll => '复制全部';

  @override
  String get checkOff => '不启用';

  @override
  String seconds(int n) {
    return '$n 秒';
  }

  @override
  String minutes(int n) {
    return '$n 分钟';
  }

  @override
  String get appearance => '外观';

  @override
  String get theme => '主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get systemAccent => '使用系统强调色';

  @override
  String get systemAccentSubtitle => '关闭后使用 uessh 默认配色';

  @override
  String get reachability => '主机连通检测';

  @override
  String get checkInterval => '检测间隔';

  @override
  String get checkIntervalOn => '打开软件时检测一次，之后按这个间隔重复检测';

  @override
  String get checkIntervalOff => '不检测主机连通状态，主机页也不显示状态点';

  @override
  String get checkMethod => '检测方式';

  @override
  String get checkMethodPing => '发送 ping。部分云服务器的安全组会屏蔽 ping，这时会显示为不通';

  @override
  String get checkMethodSsh => '尝试连接主机的 SSH 端口，能反映是否可以 SSH 登录';

  @override
  String get sshPort => 'SSH 端口';

  @override
  String get security => '安全';

  @override
  String get diagnostics => '诊断';

  @override
  String get logSubtitle => '连接记录和错误信息，排查问题时使用';

  @override
  String get viewLog => '查看日志';

  @override
  String get never => '从不';

  @override
  String get masterPasswordOn => '已开启：打开 uessh 时需要输入主密码';

  @override
  String get masterPasswordOff => '未开启：凭据用本机密钥加密保存，使用时无需输入密码';

  @override
  String get autoLock => '自动锁定';

  @override
  String get autoLockSubtitle => '一段时间没有操作后自动锁定';

  @override
  String get lockNow => '立即锁定';

  @override
  String get language => '语言';

  @override
  String get languageSubtitle => '界面显示的语言';

  @override
  String get forwardingTitle => '端口转发';

  @override
  String get noForwardsTitle => '还没有转发规则';

  @override
  String get noForwardsMessage => '支持本地、远程和动态（SOCKS）转发';

  @override
  String get snippetsTitle => '代码片段';

  @override
  String get noSnippetsTitle => '还没有代码片段';

  @override
  String get noSnippetsMessage => '保存常用命令，在终端里一键发送';

  @override
  String get info => '信息';

  @override
  String get closeInfoPanel => '关闭信息栏';

  @override
  String get infoAfterConnect => '连接后显示服务器的系统信息';

  @override
  String get infoUnavailable => '无法获取系统信息';

  @override
  String get sectionSystem => '系统';

  @override
  String get hostname => '主机名';

  @override
  String get os => '系统';

  @override
  String get kernel => '内核';

  @override
  String get uptime => '运行时间';

  @override
  String cpuCores(int n) {
    return '$n 核';
  }

  @override
  String get load => '负载';

  @override
  String get resources => '资源';

  @override
  String get calculating => '计算中…';

  @override
  String get memory => '内存';

  @override
  String get diskRoot => '磁盘 /';

  @override
  String get statusConnecting => '正在连接';

  @override
  String get statusConnected => '已连接';

  @override
  String get statusFailed => '连接失败';

  @override
  String get statusClosed => '已断开';

  @override
  String get sectionConnection => '连接';

  @override
  String get auth => '认证';

  @override
  String get status => '状态';

  @override
  String get connectedFor => '已连接';

  @override
  String get latency => '延迟';

  @override
  String get fetchingInfo => '正在获取系统信息…';

  @override
  String durationDaysHours(int days, int hours) {
    return '$days 天 $hours 小时';
  }

  @override
  String durationDays(int days) {
    return '$days 天';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours 小时 $minutes 分钟';
  }

  @override
  String durationHours(int hours) {
    return '$hours 小时';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get durationUnderMinute => '不到 1 分钟';

  @override
  String get hostKeyChangedTitle => '主机密钥已变化';

  @override
  String get hostKeyNewTitle => '首次连接这台主机';

  @override
  String hostKeyChangedBody(String hostPort) {
    return '$hostPort 的主机密钥和上次不同。可能是服务器重装了系统，也可能有人在拦截连接。确认无误后再继续。';
  }

  @override
  String hostKeyNewBody(String hostPort) {
    return '无法确认 $hostPort 的身份。请核对下面的指纹，确认是你的服务器后再继续。';
  }

  @override
  String previousFingerprint(String type) {
    return '之前的指纹（$type）';
  }

  @override
  String currentFingerprint(String type) {
    return '现在的指纹（$type）';
  }

  @override
  String get trustAnyway => '仍然信任';

  @override
  String get trustAndConnect => '信任并连接';

  @override
  String get noSessionsTitle => '没有打开的会话';

  @override
  String get noSessionsMessage => '在“主机”里点一台服务器即可连接';

  @override
  String get hideInfoPanel => '隐藏信息栏';

  @override
  String get showInfoPanel => '显示信息栏';

  @override
  String get closeTabTitle => '关闭标签页？';

  @override
  String closeTabBody(String name) {
    return '与 $name 的 SSH 连接会断开，终端里的内容不会保留。';
  }

  @override
  String get connectionClosed => '连接已关闭';

  @override
  String get reconnect => '重新连接';

  @override
  String connectingTo(String target) {
    return '正在连接 $target …';
  }

  @override
  String get keyDeletedError => '这台主机使用的密钥已被删除，请编辑主机重新选择密钥';

  @override
  String get noKeyError => '这台主机没有保存私钥，请先编辑主机并导入私钥';

  @override
  String get enterKeyPassphrase => '输入私钥口令';

  @override
  String keyIsEncrypted(String name) {
    return '$name 的私钥已加密';
  }

  @override
  String get loginCancelled => '已取消登录';

  @override
  String get enterPassword => '输入密码';

  @override
  String loginTo(String target) {
    return '登录 $target';
  }

  @override
  String get serverVerification => '服务器验证';

  @override
  String get connectionClosedMarker => '[连接已关闭]';

  @override
  String cannotConnect(String address, String reason) {
    return '无法连接到 $address（$reason）';
  }

  @override
  String connectTimeout(String address) {
    return '连接 $address 超时';
  }

  @override
  String get authFailed => '认证失败：用户名、密码或密钥不正确';

  @override
  String get hostKeyRejected => '主机密钥未被信任，已断开连接';

  @override
  String get keyFormatShort => '无法识别私钥格式';

  @override
  String sshError(String error) {
    return 'SSH 错误：$error';
  }

  @override
  String connectFailed(String error) {
    return '连接失败：$error';
  }

  @override
  String get appLanguageZh => '简体中文';

  @override
  String get appLanguageEn => 'English';

  @override
  String get newSession => '新建窗口';

  @override
  String get pickHostTitle => '选择要连接的主机';

  @override
  String get goAddHost => '去添加主机';

  @override
  String get pickHostHint => '↑↓ 选择，回车打开';

  @override
  String get overviewTotal => '主机总数';

  @override
  String overviewGroups(int count) {
    return '$count 个分组';
  }

  @override
  String get overviewOnline => '在线';

  @override
  String get overviewLost => '失联';

  @override
  String get overviewChecksOff => '检测已关闭';

  @override
  String get overviewLastConnected => '上次连接';

  @override
  String get overviewNoRecent => '还没有连接过主机';

  @override
  String get connect => '连接';

  @override
  String get timeJustNow => '刚刚';

  @override
  String timeMinutesAgo(int n) {
    return '$n 分钟前';
  }

  @override
  String timeHoursAgo(int n) {
    return '$n 小时前';
  }

  @override
  String timeDaysAgo(int n) {
    return '$n 天前';
  }

  @override
  String get showHostOverview => '显示主机概览';

  @override
  String get showHostOverviewSubtitle => '在主机页顶部显示主机数量、在线情况和上次连接';

  @override
  String get trayShow => '显示 uessh';

  @override
  String get trayQuickConnect => '快速连接';

  @override
  String get trayQuit => '退出 uessh';

  @override
  String get runInBackground => '后台常驻';

  @override
  String get runInBackgroundSubtitle => '在菜单栏或任务栏显示图标；关闭窗口后继续在后台运行，SSH 连接不会断开';

  @override
  String get general => '通用';
}
