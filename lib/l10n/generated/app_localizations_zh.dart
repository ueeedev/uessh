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
  String get hostIcon => '图标';

  @override
  String get iconLetter => '字母';

  @override
  String get iconSymbol => '图标';

  @override
  String get iconFlag => '国旗';

  @override
  String get iconColorAuto => '跟随主题色';

  @override
  String get iconFlagHint =>
      '按主机 IP 查询所在国家/地区并显示国旗（IP 会发送给 ipwho.is）。查不到时（如内网地址）显示首字母。';

  @override
  String get moreSettings => '更多设置';

  @override
  String get lessSettings => '收起';

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

  @override
  String get aiAssistant => 'AI 助手';

  @override
  String get aiShowPanel => 'AI 助手';

  @override
  String get aiHidePanel => '隐藏 AI 助手';

  @override
  String get aiClosePanel => '关闭 AI 助手';

  @override
  String get aiNewChat => '新对话';

  @override
  String get aiSetupTitle => '还没有配置 AI 供应商';

  @override
  String get aiSetupBody =>
      '在设置里填入 API Key 后即可使用。支持 Claude、ChatGPT、DeepSeek、Gemini、Grok 和自定义接口。';

  @override
  String get aiOpenSettings => '前往设置';

  @override
  String get aiInputHint => '输入问题，Enter 发送，Shift+Enter 换行';

  @override
  String get aiPickModel => '选择模型';

  @override
  String get aiLoadingModels => '正在加载模型…';

  @override
  String get aiModelsFailed => '无法获取模型列表';

  @override
  String get aiNoModels => '没有可用模型';

  @override
  String get aiRetry => '重试';

  @override
  String get aiManageProviders => '管理 AI 供应商…';

  @override
  String get aiAttachOn => '附带终端输出：开（最近 80 行）';

  @override
  String get aiAttachOff => '附带终端输出：关';

  @override
  String get aiSend => '发送';

  @override
  String get aiStop => '停止';

  @override
  String get aiCopied => '已复制';

  @override
  String get aiPasteToTerminal => '粘贴到终端（不会执行）';

  @override
  String get aiReasoning => '思考过程';

  @override
  String get aiRefused => '模型拒绝回答这个问题。';

  @override
  String get aiTruncated => '回答过长，已被截断。';

  @override
  String get aiNoKey => '这个供应商还没有 API Key';

  @override
  String get aiWithTerminal => '已附带终端输出';

  @override
  String get aiStopped => '已停止';

  @override
  String get aiSection => 'AI 助手';

  @override
  String get aiProviderConfigured => '已配置';

  @override
  String get aiProviderNotConfigured => '未配置';

  @override
  String get aiAddCustom => '添加自定义供应商';

  @override
  String get aiCustomProvider => '自定义供应商';

  @override
  String get aiApiKey => 'API Key';

  @override
  String get aiApiKeyKeep => '已保存；留空则保持不变';

  @override
  String get aiGetKey => '获取 API Key';

  @override
  String get aiBaseUrl => '接口地址';

  @override
  String get aiBaseUrlRequired => '请输入接口地址';

  @override
  String get aiBaseUrlInvalid => '请输入以 http:// 或 https:// 开头的地址';

  @override
  String get aiProviderName => '名称';

  @override
  String get aiNameRequired => '请输入名称';

  @override
  String get aiProtocol => '接口格式';

  @override
  String get aiProtocolOpenai => 'OpenAI 兼容';

  @override
  String get aiProtocolAnthropic => 'Anthropic';

  @override
  String get aiExtraModels => '额外模型';

  @override
  String get aiExtraModelsHelper => '接口不提供模型列表时，在这里填写模型 ID，用逗号分隔';

  @override
  String get aiTest => '测试连接';

  @override
  String get aiTesting => '正在测试…';

  @override
  String get aiKeyStored => 'API Key 加密保存在本机保险库里，不会写入配置文件。';

  @override
  String get aiRemoveProvider => '移除';

  @override
  String get aiRemoveTitle => '移除这个供应商？';

  @override
  String get aiRemoveBody => '会删除它的 API Key 和设置。';

  @override
  String get aiKeyRequired => '请输入 API Key';

  @override
  String aiBaseUrlDefault(String url) {
    return '留空使用默认地址：$url';
  }

  @override
  String aiTestOk(int count) {
    return '连接成功，可用模型 $count 个';
  }

  @override
  String aiTestFailed(String error) {
    return '连接失败：$error';
  }

  @override
  String get aiToolRun => '执行命令';

  @override
  String get aiToolReadTerminal => '读取终端';

  @override
  String get aiToolWaiting => '等待你允许';

  @override
  String get aiToolRunning => '运行中';

  @override
  String get aiToolDone => '完成';

  @override
  String get aiToolDenied => '已拒绝';

  @override
  String get aiToolFailed => '失败';

  @override
  String get aiToolMayChange => '这条命令可能会修改服务器，你允许后才会执行。';

  @override
  String get aiToolAskAll => '按当前设置，每条命令都需要你允许。';

  @override
  String get aiAllow => '允许执行';

  @override
  String get aiDeny => '拒绝';

  @override
  String get aiShowOutput => '显示输出';

  @override
  String get aiHideOutput => '收起输出';

  @override
  String get aiNoOutput => '（没有输出）';

  @override
  String get aiStepLimit => '已达到单条消息的步骤上限；回复「继续」可以接着做。';

  @override
  String get aiToolMode => '命令执行';

  @override
  String get aiToolModeSubtitle => '允许 AI 在当前连接的主机上执行命令来排查和处理问题';

  @override
  String get aiToolModeOff => '关闭';

  @override
  String get aiToolModeAsk => '每条命令都询问';

  @override
  String get aiToolModeAuto => '只读命令自动执行';

  @override
  String aiToolExit(int code) {
    return '退出码 $code';
  }

  @override
  String get aiToolModeAll => '全量允许（不再询问）';

  @override
  String get aiAllowAllTitle => '允许 AI 执行所有命令？';

  @override
  String get aiAllowAllBody =>
      '开启后，AI 执行任何命令都不再询问你，包括删除文件、修改配置、重启服务等。它能做当前 SSH 用户能做的一切，误操作可能造成数据丢失或服务中断。建议只在测试机上使用。';

  @override
  String get aiAllowAllConfirm => '仍要开启';

  @override
  String get splitRight => '向右拆分';

  @override
  String get splitDown => '向下拆分';

  @override
  String get zoomPane => '最大化窗格';

  @override
  String get restorePane => '还原窗格';

  @override
  String get moveToNewTab => '拆分到新标签';

  @override
  String get closePane => '关闭窗格';

  @override
  String get broadcastOn => '广播输入到所有窗格';

  @override
  String get broadcastOff => '停止广播输入';

  @override
  String get broadcasting => '广播中';

  @override
  String get workspaceFull => '一个工作区最多放 9 个窗格';

  @override
  String get closeWorkspaceTitle => '关闭这个工作区？';

  @override
  String get dropHere => '放到这里';

  @override
  String closeWorkspaceBody(int count) {
    return '会关闭其中的 $count 个连接。';
  }

  @override
  String workspaceName(int n) {
    return '工作区 $n';
  }

  @override
  String get renameWorkspaceHint => '点击重命名';

  @override
  String get aiHistory => '历史对话';

  @override
  String get aiHistoryEmpty => '还没有历史对话';

  @override
  String get aiHistoryThisHost => '这台主机';

  @override
  String get aiHistoryOtherHosts => '其他主机';

  @override
  String get aiHistoryDelete => '删除这条对话';

  @override
  String get aiBackToChat => '返回对话';

  @override
  String get aiClearHistory => '清除 AI 对话记录';

  @override
  String get aiClearHistorySubtitle => '对话记录加密保存在本机，最多保留 200 条';

  @override
  String get aiClearHistoryTitle => '清除所有 AI 对话记录？';

  @override
  String get aiClearHistoryBody => '所有主机的 AI 对话都会被删除，无法恢复。';

  @override
  String get aiClear => '清除';

  @override
  String get filesShow => '文件';

  @override
  String get filesHide => '关闭文件';

  @override
  String get filesBack => '后退';

  @override
  String get filesForward => '前进';

  @override
  String get filesUp => '上一级';

  @override
  String get filesRefresh => '刷新';

  @override
  String get filesFollow => '跟随终端当前目录';

  @override
  String get filesShowHidden => '显示隐藏文件';

  @override
  String get filesHideHidden => '不显示隐藏文件';

  @override
  String get viewIcons => '图标';

  @override
  String get viewList => '列表';

  @override
  String get viewColumns => '分栏';

  @override
  String get viewGallery => '画廊';

  @override
  String get colName => '名称';

  @override
  String get colModified => '修改日期';

  @override
  String get colSize => '大小';

  @override
  String get colKind => '种类';

  @override
  String get filesEmpty => '空文件夹';

  @override
  String get filesNotConnected => '连接后才能浏览文件';

  @override
  String get filesLocating => '正在定位终端目录…';

  @override
  String get filesOpen => '打开';

  @override
  String get filesCdHere => '在终端中进入';

  @override
  String get filesCopyPath => '复制路径';

  @override
  String get filesDownload => '下载…';

  @override
  String get filesNoPreview => '没有预览';

  @override
  String get filesPermissions => '权限';

  @override
  String get kindFolder => '文件夹';

  @override
  String get kindImage => '图片';

  @override
  String get kindText => '文本';

  @override
  String get kindCode => '代码';

  @override
  String get kindArchive => '压缩包';

  @override
  String get kindVideo => '视频';

  @override
  String get kindAudio => '音频';

  @override
  String get kindPdf => 'PDF 文稿';

  @override
  String get kindDocument => '文档';

  @override
  String get kindExecutable => '可执行文件';

  @override
  String get kindFile => '文件';

  @override
  String get kindLink => '替身';

  @override
  String filesItems(int n) {
    return '$n 项';
  }

  @override
  String filesError(String error) {
    return '无法打开：$error';
  }

  @override
  String filesDownloaded(String path) {
    return '已下载到 $path';
  }

  @override
  String filesDownloading(String name) {
    return '正在下载 $name…';
  }

  @override
  String get aiAddProvider => '添加 AI 供应商';

  @override
  String get aiNoProviders => '还没有添加 AI 供应商';

  @override
  String get aiNoProvidersHint => '添加一个供应商并填入 API Key，就可以在终端页使用 AI 助手';

  @override
  String get aiAlreadyAdded => '已添加';

  @override
  String get filesUpload => '上传文件…';

  @override
  String get filesUploadHere => '上传文件到这里…';

  @override
  String get dropResolving => '正在获取当前目录…';

  @override
  String get uploadNotConnected => '未连接，无法上传';

  @override
  String get overwriteTitle => '替换已有的项目？';

  @override
  String get overwriteReplace => '替换';

  @override
  String get overwriteSkip => '跳过';

  @override
  String dropToUpload(String path) {
    return '松开上传到 $path';
  }

  @override
  String uploadProgress(String path) {
    return '正在上传到 $path';
  }

  @override
  String uploadDone(int count, String path) {
    return '已上传 $count 个文件到 $path';
  }

  @override
  String uploadFailed(String error) {
    return '上传失败：$error';
  }

  @override
  String overwriteBody(String path, String names) {
    return '$path 里已有同名项目：$names';
  }

  @override
  String uploadCount(int done, int total) {
    return '$done/$total 个文件';
  }

  @override
  String get aiToolHiddenChars => '命令里有不可见或反向的字符（已标成 <U+…>），可能和看上去的不一样，请仔细确认。';

  @override
  String aiToolOnHost(String host) {
    return '在 $host 上执行';
  }

  @override
  String get aiPasteRunsTitle => '粘贴后会直接执行';

  @override
  String get aiPasteAnyway => '仍要粘贴';

  @override
  String aiPasteRunsBody(int n) {
    return '这台服务器的 Shell 没有开启安全粘贴，多行内容粘贴后，前 $n 行会像按了回车一样立即执行。';
  }

  @override
  String get aiBaseUrlHttps =>
      '需要使用 https://，否则 API Key 会明文传输（本机 http://localhost 除外）';

  @override
  String get aiAllowAllActive => '全量允许已开启：AI 执行任何命令都不会询问你。点此去设置更改';

  @override
  String get workbench => '工作台';

  @override
  String reconnectingIn(int seconds, int attempt, int total) {
    return '$seconds 秒后自动重连（第 $attempt/$total 次）';
  }

  @override
  String reconnectGaveUp(int count) {
    return '已重连 $count 次仍未成功，停止自动重连';
  }

  @override
  String reconnectBanner(int seconds, int attempt, int total) {
    return '连接已断开，$seconds 秒后重连（$attempt/$total）';
  }

  @override
  String reconnectingNow(int attempt, int total) {
    return '正在重连（$attempt/$total）…';
  }

  @override
  String get reconnectNow => '立即重连';

  @override
  String get settingsReconnect => '自动重连';

  @override
  String get settingsReconnectSubtitle => 'SSH 连接意外断开后自动重新连接；输入 exit 退出不会重连';

  @override
  String get settingsReconnectAttempts => '重连次数';

  @override
  String get settingsReconnectDelay => '重连间隔';

  @override
  String reconnectAttemptsValue(int count) {
    return '$count 次';
  }

  @override
  String reconnectDelayValue(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get sshSection => 'SSH 连接';

  @override
  String get settingsHighlight => '命令语法高亮';

  @override
  String get settingsHighlightSubtitle => '在终端里为正在输入的命令着色，只在本机显示，不修改服务器';

  @override
  String get highlightCommand => '命令';

  @override
  String get highlightDangerous => '危险命令';

  @override
  String get highlightOption => '选项';

  @override
  String get highlightString => '字符串';

  @override
  String get highlightVariable => '变量';

  @override
  String get highlightOperator => '管道/重定向';

  @override
  String get highlightComment => '注释';

  @override
  String get highlightResetAll => '全部恢复默认';

  @override
  String get highlightDefault => '默认颜色';

  @override
  String get aiOpenLinkTitle => '打开这个链接？';

  @override
  String get aiOpenLink => '在浏览器中打开';

  @override
  String get localTerminal => '本地终端';

  @override
  String localTerminalFailed(String reason) {
    return '无法启动本地终端：$reason';
  }

  @override
  String get localTerminalEnded => '[本地终端已退出]';

  @override
  String get diskSystem => '系统盘';

  @override
  String get autoCheckUpdates => '自动检查更新';

  @override
  String get autoCheckUpdatesSubtitle =>
      '启动时检查 GitHub 上是否有新版本，有就提示；关闭后只能在设置页底部手动检查';

  @override
  String get updateCheck => '检查更新';

  @override
  String get updateChecking => '正在检查…';

  @override
  String get updateCheckFailed => '检查更新失败，请稍后再试';

  @override
  String updateUpToDate(String version) {
    return '已是最新版本（$version）';
  }

  @override
  String updateAvailableTitle(String version) {
    return '发现新版本 v$version';
  }

  @override
  String updateAvailableBody(String current) {
    return '当前版本 v$current。点击「立刻前往」到 GitHub 下载最新版。';
  }

  @override
  String get updateLater => '下次再说～';

  @override
  String get updateGo => '立刻前往';

  @override
  String get updateIgnore => '忽略此版本';
}
