import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @ok.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get ok;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @show.
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get show;

  /// No description provided for @hide.
  ///
  /// In zh, this message translates to:
  /// **'隐藏'**
  String get hide;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @importAction.
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get importAction;

  /// No description provided for @importFromFile.
  ///
  /// In zh, this message translates to:
  /// **'从文件导入'**
  String get importFromFile;

  /// No description provided for @back.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get back;

  /// No description provided for @copy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get copy;

  /// No description provided for @paste.
  ///
  /// In zh, this message translates to:
  /// **'粘贴'**
  String get paste;

  /// No description provided for @loading.
  ///
  /// In zh, this message translates to:
  /// **'加载中'**
  String get loading;

  /// No description provided for @navHosts.
  ///
  /// In zh, this message translates to:
  /// **'主机'**
  String get navHosts;

  /// No description provided for @navTerminal.
  ///
  /// In zh, this message translates to:
  /// **'终端'**
  String get navTerminal;

  /// No description provided for @navKeys.
  ///
  /// In zh, this message translates to:
  /// **'密钥'**
  String get navKeys;

  /// No description provided for @navSnippets.
  ///
  /// In zh, this message translates to:
  /// **'片段'**
  String get navSnippets;

  /// No description provided for @navForwarding.
  ///
  /// In zh, this message translates to:
  /// **'转发'**
  String get navForwarding;

  /// No description provided for @navSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get navSettings;

  /// No description provided for @discardChangesTitle.
  ///
  /// In zh, this message translates to:
  /// **'放弃未保存的修改？'**
  String get discardChangesTitle;

  /// No description provided for @discardChangesBody.
  ///
  /// In zh, this message translates to:
  /// **'关闭后，刚才填写的内容不会保存。'**
  String get discardChangesBody;

  /// No description provided for @keepEditing.
  ///
  /// In zh, this message translates to:
  /// **'继续编辑'**
  String get keepEditing;

  /// No description provided for @discardChanges.
  ///
  /// In zh, this message translates to:
  /// **'放弃修改'**
  String get discardChanges;

  /// No description provided for @searchHosts.
  ///
  /// In zh, this message translates to:
  /// **'搜索主机'**
  String get searchHosts;

  /// No description provided for @newHost.
  ///
  /// In zh, this message translates to:
  /// **'新建主机'**
  String get newHost;

  /// No description provided for @loadHostsFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取主机列表失败'**
  String get loadHostsFailed;

  /// No description provided for @noHostsTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有主机'**
  String get noHostsTitle;

  /// No description provided for @noHostsMessage.
  ///
  /// In zh, this message translates to:
  /// **'添加一台服务器后，就可以从这里一键连接'**
  String get noHostsMessage;

  /// No description provided for @noMatchesTitle.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的主机'**
  String get noMatchesTitle;

  /// No description provided for @noMatchesMessage.
  ///
  /// In zh, this message translates to:
  /// **'换个关键词试试'**
  String get noMatchesMessage;

  /// No description provided for @renameGroup.
  ///
  /// In zh, this message translates to:
  /// **'重命名分组'**
  String get renameGroup;

  /// No description provided for @deleteGroup.
  ///
  /// In zh, this message translates to:
  /// **'删除分组'**
  String get deleteGroup;

  /// No description provided for @deleteGroupTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除分组“{name}”？'**
  String deleteGroupTitle(String name);

  /// No description provided for @deleteGroupEmpty.
  ///
  /// In zh, this message translates to:
  /// **'这个分组里没有主机。'**
  String get deleteGroupEmpty;

  /// No description provided for @deleteGroupBody.
  ///
  /// In zh, this message translates to:
  /// **'组内 {count} 台主机会移到“未分组”，主机本身不会被删除。'**
  String deleteGroupBody(int count);

  /// No description provided for @ungrouped.
  ///
  /// In zh, this message translates to:
  /// **'未分组'**
  String get ungrouped;

  /// No description provided for @groupActions.
  ///
  /// In zh, this message translates to:
  /// **'分组操作'**
  String get groupActions;

  /// No description provided for @emptyGroupHint.
  ///
  /// In zh, this message translates to:
  /// **'这个分组还没有主机，编辑主机时可以把它放进来'**
  String get emptyGroupHint;

  /// No description provided for @groupNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入分组名称'**
  String get groupNameRequired;

  /// No description provided for @groupNameTaken.
  ///
  /// In zh, this message translates to:
  /// **'已经有同名的分组'**
  String get groupNameTaken;

  /// No description provided for @groupName.
  ///
  /// In zh, this message translates to:
  /// **'分组名称'**
  String get groupName;

  /// No description provided for @groupNameEmptyError.
  ///
  /// In zh, this message translates to:
  /// **'分组名称不能为空'**
  String get groupNameEmptyError;

  /// No description provided for @groupNameExistsError.
  ///
  /// In zh, this message translates to:
  /// **'已经有名为“{name}”的分组'**
  String groupNameExistsError(String name);

  /// No description provided for @reachUp.
  ///
  /// In zh, this message translates to:
  /// **'连通'**
  String get reachUp;

  /// No description provided for @reachUpLatency.
  ///
  /// In zh, this message translates to:
  /// **'连通 · {ms} ms'**
  String reachUpLatency(int ms);

  /// No description provided for @reachDown.
  ///
  /// In zh, this message translates to:
  /// **'不通'**
  String get reachDown;

  /// No description provided for @reachChecking.
  ///
  /// In zh, this message translates to:
  /// **'正在检测…'**
  String get reachChecking;

  /// No description provided for @editHost.
  ///
  /// In zh, this message translates to:
  /// **'编辑主机'**
  String get editHost;

  /// No description provided for @fieldName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get fieldName;

  /// No description provided for @hostNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：生产服务器（可选）'**
  String get hostNameHint;

  /// No description provided for @fieldAddress.
  ///
  /// In zh, this message translates to:
  /// **'地址'**
  String get fieldAddress;

  /// No description provided for @addressHint.
  ///
  /// In zh, this message translates to:
  /// **'IP 或域名'**
  String get addressHint;

  /// No description provided for @addressRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入地址'**
  String get addressRequired;

  /// No description provided for @fieldPort.
  ///
  /// In zh, this message translates to:
  /// **'端口'**
  String get fieldPort;

  /// No description provided for @fieldUsername.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get fieldUsername;

  /// No description provided for @usernameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入用户名'**
  String get usernameRequired;

  /// No description provided for @authMethod.
  ///
  /// In zh, this message translates to:
  /// **'认证方式'**
  String get authMethod;

  /// No description provided for @authPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get authPassword;

  /// No description provided for @authKey.
  ///
  /// In zh, this message translates to:
  /// **'私钥'**
  String get authKey;

  /// No description provided for @passwordHelper.
  ///
  /// In zh, this message translates to:
  /// **'加密保存在 uessh 中；留空则每次连接时询问'**
  String get passwordHelper;

  /// No description provided for @fieldPassphrase.
  ///
  /// In zh, this message translates to:
  /// **'私钥口令'**
  String get fieldPassphrase;

  /// No description provided for @passphraseHelper.
  ///
  /// In zh, this message translates to:
  /// **'私钥没有加密就留空；加密了但留空则每次连接时询问'**
  String get passphraseHelper;

  /// No description provided for @saveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{error}'**
  String saveFailed(String error);

  /// No description provided for @deleteHostTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除 {name}？'**
  String deleteHostTitle(String name);

  /// No description provided for @deleteHostBody.
  ///
  /// In zh, this message translates to:
  /// **'主机信息和保存的密码、私钥会一起删除，无法恢复。'**
  String get deleteHostBody;

  /// No description provided for @keyRequired.
  ///
  /// In zh, this message translates to:
  /// **'请粘贴或导入私钥'**
  String get keyRequired;

  /// No description provided for @keyWrongPassphrase.
  ///
  /// In zh, this message translates to:
  /// **'私钥口令不正确'**
  String get keyWrongPassphrase;

  /// No description provided for @keyUnrecognized.
  ///
  /// In zh, this message translates to:
  /// **'无法识别私钥格式（支持 OpenSSH、PEM 格式的 RSA / ECDSA / Ed25519）'**
  String get keyUnrecognized;

  /// No description provided for @keyEmpty.
  ///
  /// In zh, this message translates to:
  /// **'私钥里没有找到密钥'**
  String get keyEmpty;

  /// No description provided for @newGroupName.
  ///
  /// In zh, this message translates to:
  /// **'新分组名称'**
  String get newGroupName;

  /// No description provided for @newGroupHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：生产环境'**
  String get newGroupHint;

  /// No description provided for @group.
  ///
  /// In zh, this message translates to:
  /// **'分组'**
  String get group;

  /// No description provided for @newGroupPending.
  ///
  /// In zh, this message translates to:
  /// **'{name}（新）'**
  String newGroupPending(String name);

  /// No description provided for @addGroup.
  ///
  /// In zh, this message translates to:
  /// **'添加分组'**
  String get addGroup;

  /// No description provided for @cancelNewGroup.
  ///
  /// In zh, this message translates to:
  /// **'取消新建'**
  String get cancelNewGroup;

  /// No description provided for @newGroup.
  ///
  /// In zh, this message translates to:
  /// **'新建分组'**
  String get newGroup;

  /// No description provided for @savedKeysHint.
  ///
  /// In zh, this message translates to:
  /// **'提示：在“密钥”页保存常用私钥后，这里可以直接选用'**
  String get savedKeysHint;

  /// No description provided for @keyToUse.
  ///
  /// In zh, this message translates to:
  /// **'使用的密钥'**
  String get keyToUse;

  /// No description provided for @pasteKeyOption.
  ///
  /// In zh, this message translates to:
  /// **'直接粘贴私钥（仅用于这台主机）'**
  String get pasteKeyOption;

  /// No description provided for @addKey.
  ///
  /// In zh, this message translates to:
  /// **'添加密钥'**
  String get addKey;

  /// No description provided for @editKey.
  ///
  /// In zh, this message translates to:
  /// **'编辑密钥'**
  String get editKey;

  /// No description provided for @loadKeysFailed.
  ///
  /// In zh, this message translates to:
  /// **'读取密钥失败'**
  String get loadKeysFailed;

  /// No description provided for @noKeysTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有密钥'**
  String get noKeysTitle;

  /// No description provided for @noKeysMessage.
  ///
  /// In zh, this message translates to:
  /// **'添加 SSH 私钥后，新建主机时可以直接选用'**
  String get noKeysMessage;

  /// No description provided for @keyEncrypted.
  ///
  /// In zh, this message translates to:
  /// **'已加密'**
  String get keyEncrypted;

  /// No description provided for @deleteKeyTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除密钥“{name}”？'**
  String deleteKeyTitle(String name);

  /// No description provided for @deleteKeyBody.
  ///
  /// In zh, this message translates to:
  /// **'私钥和口令会从 uessh 中删除，无法恢复。'**
  String get deleteKeyBody;

  /// No description provided for @deleteKeyInUse.
  ///
  /// In zh, this message translates to:
  /// **'有 {count} 台主机正在使用这个密钥，删除后需要为它们重新选择密钥。私钥和口令无法恢复。'**
  String deleteKeyInUse(int count);

  /// No description provided for @publicKeyCopied.
  ///
  /// In zh, this message translates to:
  /// **'公钥已复制，可以粘贴到服务器的 ~/.ssh/authorized_keys'**
  String get publicKeyCopied;

  /// No description provided for @keyNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：工作笔记本'**
  String get keyNameHint;

  /// No description provided for @nameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入名称'**
  String get nameRequired;

  /// No description provided for @keyType.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get keyType;

  /// No description provided for @fingerprint.
  ///
  /// In zh, this message translates to:
  /// **'指纹'**
  String get fingerprint;

  /// No description provided for @copyPublicKey.
  ///
  /// In zh, this message translates to:
  /// **'复制公钥'**
  String get copyPublicKey;

  /// No description provided for @enterMasterPassword.
  ///
  /// In zh, this message translates to:
  /// **'请输入主密码'**
  String get enterMasterPassword;

  /// No description provided for @wrongMasterPassword.
  ///
  /// In zh, this message translates to:
  /// **'主密码不正确'**
  String get wrongMasterPassword;

  /// No description provided for @lockedTitle.
  ///
  /// In zh, this message translates to:
  /// **'uessh 已锁定'**
  String get lockedTitle;

  /// No description provided for @lockedSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'输入主密码解锁已保存的密码和私钥'**
  String get lockedSubtitle;

  /// No description provided for @masterPassword.
  ///
  /// In zh, this message translates to:
  /// **'主密码'**
  String get masterPassword;

  /// No description provided for @unlock.
  ///
  /// In zh, this message translates to:
  /// **'解锁'**
  String get unlock;

  /// No description provided for @forgotMasterPassword.
  ///
  /// In zh, this message translates to:
  /// **'忘记主密码？'**
  String get forgotMasterPassword;

  /// No description provided for @resetVaultTitle.
  ///
  /// In zh, this message translates to:
  /// **'重置保险库？'**
  String get resetVaultTitle;

  /// No description provided for @resetVaultBody.
  ///
  /// In zh, this message translates to:
  /// **'主密码无法找回。重置会删除所有已保存的密码、私钥和口令，主机列表和分组会保留，之后需要重新填写登录信息。'**
  String get resetVaultBody;

  /// No description provided for @resetVaultConfirm.
  ///
  /// In zh, this message translates to:
  /// **'删除已保存的凭据并重置'**
  String get resetVaultConfirm;

  /// No description provided for @vaultLocked.
  ///
  /// In zh, this message translates to:
  /// **'保险库已锁定'**
  String get vaultLocked;

  /// No description provided for @minChars.
  ///
  /// In zh, this message translates to:
  /// **'至少 {count} 个字符'**
  String minChars(int count);

  /// No description provided for @setMasterPassword.
  ///
  /// In zh, this message translates to:
  /// **'设置主密码'**
  String get setMasterPassword;

  /// No description provided for @setMasterPasswordIntro.
  ///
  /// In zh, this message translates to:
  /// **'开启后，每次打开 uessh 需要输入一次主密码，才能使用已保存的密码和私钥。主密码无法找回，请务必记住。'**
  String get setMasterPasswordIntro;

  /// No description provided for @turnOn.
  ///
  /// In zh, this message translates to:
  /// **'开启'**
  String get turnOn;

  /// No description provided for @changeMasterPassword.
  ///
  /// In zh, this message translates to:
  /// **'修改主密码'**
  String get changeMasterPassword;

  /// No description provided for @change.
  ///
  /// In zh, this message translates to:
  /// **'修改'**
  String get change;

  /// No description provided for @turnOffMasterPassword.
  ///
  /// In zh, this message translates to:
  /// **'关闭主密码'**
  String get turnOffMasterPassword;

  /// No description provided for @turnOffIntro.
  ///
  /// In zh, this message translates to:
  /// **'关闭后，打开 uessh 不再需要输入主密码，凭据改用本机密钥加密保存。'**
  String get turnOffIntro;

  /// No description provided for @currentMasterPassword.
  ///
  /// In zh, this message translates to:
  /// **'当前主密码'**
  String get currentMasterPassword;

  /// No description provided for @enterCurrentMasterPassword.
  ///
  /// In zh, this message translates to:
  /// **'请输入当前主密码'**
  String get enterCurrentMasterPassword;

  /// No description provided for @newMasterPassword.
  ///
  /// In zh, this message translates to:
  /// **'新主密码'**
  String get newMasterPassword;

  /// No description provided for @confirmPassword.
  ///
  /// In zh, this message translates to:
  /// **'再输入一次'**
  String get confirmPassword;

  /// No description provided for @passwordsDontMatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入不一致'**
  String get passwordsDontMatch;

  /// No description provided for @logCopied.
  ///
  /// In zh, this message translates to:
  /// **'日志已复制到剪贴板'**
  String get logCopied;

  /// No description provided for @log.
  ///
  /// In zh, this message translates to:
  /// **'日志'**
  String get log;

  /// No description provided for @warningsOnly.
  ///
  /// In zh, this message translates to:
  /// **'只看警告和错误'**
  String get warningsOnly;

  /// No description provided for @logCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条'**
  String logCount(int count);

  /// No description provided for @noLogs.
  ///
  /// In zh, this message translates to:
  /// **'暂无日志'**
  String get noLogs;

  /// No description provided for @logFile.
  ///
  /// In zh, this message translates to:
  /// **'日志文件：{path}'**
  String logFile(String path);

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get clear;

  /// No description provided for @copyAll.
  ///
  /// In zh, this message translates to:
  /// **'复制全部'**
  String get copyAll;

  /// No description provided for @checkOff.
  ///
  /// In zh, this message translates to:
  /// **'不启用'**
  String get checkOff;

  /// No description provided for @seconds.
  ///
  /// In zh, this message translates to:
  /// **'{n} 秒'**
  String seconds(int n);

  /// No description provided for @minutes.
  ///
  /// In zh, this message translates to:
  /// **'{n} 分钟'**
  String minutes(int n);

  /// No description provided for @appearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get appearance;

  /// No description provided for @theme.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @systemAccent.
  ///
  /// In zh, this message translates to:
  /// **'使用系统强调色'**
  String get systemAccent;

  /// No description provided for @systemAccentSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'关闭后使用 uessh 默认配色'**
  String get systemAccentSubtitle;

  /// No description provided for @reachability.
  ///
  /// In zh, this message translates to:
  /// **'主机连通检测'**
  String get reachability;

  /// No description provided for @checkInterval.
  ///
  /// In zh, this message translates to:
  /// **'检测间隔'**
  String get checkInterval;

  /// No description provided for @checkIntervalOn.
  ///
  /// In zh, this message translates to:
  /// **'打开软件时检测一次，之后按这个间隔重复检测'**
  String get checkIntervalOn;

  /// No description provided for @checkIntervalOff.
  ///
  /// In zh, this message translates to:
  /// **'不检测主机连通状态，主机页也不显示状态点'**
  String get checkIntervalOff;

  /// No description provided for @checkMethod.
  ///
  /// In zh, this message translates to:
  /// **'检测方式'**
  String get checkMethod;

  /// No description provided for @checkMethodPing.
  ///
  /// In zh, this message translates to:
  /// **'发送 ping。部分云服务器的安全组会屏蔽 ping，这时会显示为不通'**
  String get checkMethodPing;

  /// No description provided for @checkMethodSsh.
  ///
  /// In zh, this message translates to:
  /// **'尝试连接主机的 SSH 端口，能反映是否可以 SSH 登录'**
  String get checkMethodSsh;

  /// No description provided for @sshPort.
  ///
  /// In zh, this message translates to:
  /// **'SSH 端口'**
  String get sshPort;

  /// No description provided for @security.
  ///
  /// In zh, this message translates to:
  /// **'安全'**
  String get security;

  /// No description provided for @diagnostics.
  ///
  /// In zh, this message translates to:
  /// **'诊断'**
  String get diagnostics;

  /// No description provided for @logSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'连接记录和错误信息，排查问题时使用'**
  String get logSubtitle;

  /// No description provided for @viewLog.
  ///
  /// In zh, this message translates to:
  /// **'查看日志'**
  String get viewLog;

  /// No description provided for @never.
  ///
  /// In zh, this message translates to:
  /// **'从不'**
  String get never;

  /// No description provided for @masterPasswordOn.
  ///
  /// In zh, this message translates to:
  /// **'已开启：打开 uessh 时需要输入主密码'**
  String get masterPasswordOn;

  /// No description provided for @masterPasswordOff.
  ///
  /// In zh, this message translates to:
  /// **'未开启：凭据用本机密钥加密保存，使用时无需输入密码'**
  String get masterPasswordOff;

  /// No description provided for @autoLock.
  ///
  /// In zh, this message translates to:
  /// **'自动锁定'**
  String get autoLock;

  /// No description provided for @autoLockSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'一段时间没有操作后自动锁定'**
  String get autoLockSubtitle;

  /// No description provided for @lockNow.
  ///
  /// In zh, this message translates to:
  /// **'立即锁定'**
  String get lockNow;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @languageSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'界面显示的语言'**
  String get languageSubtitle;

  /// No description provided for @forwardingTitle.
  ///
  /// In zh, this message translates to:
  /// **'端口转发'**
  String get forwardingTitle;

  /// No description provided for @noForwardsTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有转发规则'**
  String get noForwardsTitle;

  /// No description provided for @noForwardsMessage.
  ///
  /// In zh, this message translates to:
  /// **'支持本地、远程和动态（SOCKS）转发'**
  String get noForwardsMessage;

  /// No description provided for @snippetsTitle.
  ///
  /// In zh, this message translates to:
  /// **'代码片段'**
  String get snippetsTitle;

  /// No description provided for @noSnippetsTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有代码片段'**
  String get noSnippetsTitle;

  /// No description provided for @noSnippetsMessage.
  ///
  /// In zh, this message translates to:
  /// **'保存常用命令，在终端里一键发送'**
  String get noSnippetsMessage;

  /// No description provided for @info.
  ///
  /// In zh, this message translates to:
  /// **'信息'**
  String get info;

  /// No description provided for @closeInfoPanel.
  ///
  /// In zh, this message translates to:
  /// **'关闭信息栏'**
  String get closeInfoPanel;

  /// No description provided for @infoAfterConnect.
  ///
  /// In zh, this message translates to:
  /// **'连接后显示服务器的系统信息'**
  String get infoAfterConnect;

  /// No description provided for @infoUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'无法获取系统信息'**
  String get infoUnavailable;

  /// No description provided for @sectionSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get sectionSystem;

  /// No description provided for @hostname.
  ///
  /// In zh, this message translates to:
  /// **'主机名'**
  String get hostname;

  /// No description provided for @os.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get os;

  /// No description provided for @kernel.
  ///
  /// In zh, this message translates to:
  /// **'内核'**
  String get kernel;

  /// No description provided for @uptime.
  ///
  /// In zh, this message translates to:
  /// **'运行时间'**
  String get uptime;

  /// No description provided for @cpuCores.
  ///
  /// In zh, this message translates to:
  /// **'{n} 核'**
  String cpuCores(int n);

  /// No description provided for @load.
  ///
  /// In zh, this message translates to:
  /// **'负载'**
  String get load;

  /// No description provided for @resources.
  ///
  /// In zh, this message translates to:
  /// **'资源'**
  String get resources;

  /// No description provided for @calculating.
  ///
  /// In zh, this message translates to:
  /// **'计算中…'**
  String get calculating;

  /// No description provided for @memory.
  ///
  /// In zh, this message translates to:
  /// **'内存'**
  String get memory;

  /// No description provided for @diskRoot.
  ///
  /// In zh, this message translates to:
  /// **'磁盘 /'**
  String get diskRoot;

  /// No description provided for @statusConnecting.
  ///
  /// In zh, this message translates to:
  /// **'正在连接'**
  String get statusConnecting;

  /// No description provided for @statusConnected.
  ///
  /// In zh, this message translates to:
  /// **'已连接'**
  String get statusConnected;

  /// No description provided for @statusFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败'**
  String get statusFailed;

  /// No description provided for @statusClosed.
  ///
  /// In zh, this message translates to:
  /// **'已断开'**
  String get statusClosed;

  /// No description provided for @sectionConnection.
  ///
  /// In zh, this message translates to:
  /// **'连接'**
  String get sectionConnection;

  /// No description provided for @auth.
  ///
  /// In zh, this message translates to:
  /// **'认证'**
  String get auth;

  /// No description provided for @status.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get status;

  /// No description provided for @connectedFor.
  ///
  /// In zh, this message translates to:
  /// **'已连接'**
  String get connectedFor;

  /// No description provided for @latency.
  ///
  /// In zh, this message translates to:
  /// **'延迟'**
  String get latency;

  /// No description provided for @fetchingInfo.
  ///
  /// In zh, this message translates to:
  /// **'正在获取系统信息…'**
  String get fetchingInfo;

  /// No description provided for @durationDaysHours.
  ///
  /// In zh, this message translates to:
  /// **'{days} 天 {hours} 小时'**
  String durationDaysHours(int days, int hours);

  /// No description provided for @durationDays.
  ///
  /// In zh, this message translates to:
  /// **'{days} 天'**
  String durationDays(int days);

  /// No description provided for @durationHoursMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{hours} 小时 {minutes} 分钟'**
  String durationHoursMinutes(int hours, int minutes);

  /// No description provided for @durationHours.
  ///
  /// In zh, this message translates to:
  /// **'{hours} 小时'**
  String durationHours(int hours);

  /// No description provided for @durationMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分钟'**
  String durationMinutes(int minutes);

  /// No description provided for @durationUnderMinute.
  ///
  /// In zh, this message translates to:
  /// **'不到 1 分钟'**
  String get durationUnderMinute;

  /// No description provided for @hostKeyChangedTitle.
  ///
  /// In zh, this message translates to:
  /// **'主机密钥已变化'**
  String get hostKeyChangedTitle;

  /// No description provided for @hostKeyNewTitle.
  ///
  /// In zh, this message translates to:
  /// **'首次连接这台主机'**
  String get hostKeyNewTitle;

  /// No description provided for @hostKeyChangedBody.
  ///
  /// In zh, this message translates to:
  /// **'{hostPort} 的主机密钥和上次不同。可能是服务器重装了系统，也可能有人在拦截连接。确认无误后再继续。'**
  String hostKeyChangedBody(String hostPort);

  /// No description provided for @hostKeyNewBody.
  ///
  /// In zh, this message translates to:
  /// **'无法确认 {hostPort} 的身份。请核对下面的指纹，确认是你的服务器后再继续。'**
  String hostKeyNewBody(String hostPort);

  /// No description provided for @previousFingerprint.
  ///
  /// In zh, this message translates to:
  /// **'之前的指纹（{type}）'**
  String previousFingerprint(String type);

  /// No description provided for @currentFingerprint.
  ///
  /// In zh, this message translates to:
  /// **'现在的指纹（{type}）'**
  String currentFingerprint(String type);

  /// No description provided for @trustAnyway.
  ///
  /// In zh, this message translates to:
  /// **'仍然信任'**
  String get trustAnyway;

  /// No description provided for @trustAndConnect.
  ///
  /// In zh, this message translates to:
  /// **'信任并连接'**
  String get trustAndConnect;

  /// No description provided for @noSessionsTitle.
  ///
  /// In zh, this message translates to:
  /// **'没有打开的会话'**
  String get noSessionsTitle;

  /// No description provided for @noSessionsMessage.
  ///
  /// In zh, this message translates to:
  /// **'在“主机”里点一台服务器即可连接'**
  String get noSessionsMessage;

  /// No description provided for @hideInfoPanel.
  ///
  /// In zh, this message translates to:
  /// **'隐藏信息栏'**
  String get hideInfoPanel;

  /// No description provided for @showInfoPanel.
  ///
  /// In zh, this message translates to:
  /// **'显示信息栏'**
  String get showInfoPanel;

  /// No description provided for @closeTabTitle.
  ///
  /// In zh, this message translates to:
  /// **'关闭标签页？'**
  String get closeTabTitle;

  /// No description provided for @closeTabBody.
  ///
  /// In zh, this message translates to:
  /// **'与 {name} 的 SSH 连接会断开，终端里的内容不会保留。'**
  String closeTabBody(String name);

  /// No description provided for @connectionClosed.
  ///
  /// In zh, this message translates to:
  /// **'连接已关闭'**
  String get connectionClosed;

  /// No description provided for @reconnect.
  ///
  /// In zh, this message translates to:
  /// **'重新连接'**
  String get reconnect;

  /// No description provided for @connectingTo.
  ///
  /// In zh, this message translates to:
  /// **'正在连接 {target} …'**
  String connectingTo(String target);

  /// No description provided for @keyDeletedError.
  ///
  /// In zh, this message translates to:
  /// **'这台主机使用的密钥已被删除，请编辑主机重新选择密钥'**
  String get keyDeletedError;

  /// No description provided for @noKeyError.
  ///
  /// In zh, this message translates to:
  /// **'这台主机没有保存私钥，请先编辑主机并导入私钥'**
  String get noKeyError;

  /// No description provided for @enterKeyPassphrase.
  ///
  /// In zh, this message translates to:
  /// **'输入私钥口令'**
  String get enterKeyPassphrase;

  /// No description provided for @keyIsEncrypted.
  ///
  /// In zh, this message translates to:
  /// **'{name} 的私钥已加密'**
  String keyIsEncrypted(String name);

  /// No description provided for @loginCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消登录'**
  String get loginCancelled;

  /// No description provided for @enterPassword.
  ///
  /// In zh, this message translates to:
  /// **'输入密码'**
  String get enterPassword;

  /// No description provided for @loginTo.
  ///
  /// In zh, this message translates to:
  /// **'登录 {target}'**
  String loginTo(String target);

  /// No description provided for @serverVerification.
  ///
  /// In zh, this message translates to:
  /// **'服务器验证'**
  String get serverVerification;

  /// No description provided for @connectionClosedMarker.
  ///
  /// In zh, this message translates to:
  /// **'[连接已关闭]'**
  String get connectionClosedMarker;

  /// No description provided for @cannotConnect.
  ///
  /// In zh, this message translates to:
  /// **'无法连接到 {address}（{reason}）'**
  String cannotConnect(String address, String reason);

  /// No description provided for @connectTimeout.
  ///
  /// In zh, this message translates to:
  /// **'连接 {address} 超时'**
  String connectTimeout(String address);

  /// No description provided for @authFailed.
  ///
  /// In zh, this message translates to:
  /// **'认证失败：用户名、密码或密钥不正确'**
  String get authFailed;

  /// No description provided for @hostKeyRejected.
  ///
  /// In zh, this message translates to:
  /// **'主机密钥未被信任，已断开连接'**
  String get hostKeyRejected;

  /// No description provided for @keyFormatShort.
  ///
  /// In zh, this message translates to:
  /// **'无法识别私钥格式'**
  String get keyFormatShort;

  /// No description provided for @sshError.
  ///
  /// In zh, this message translates to:
  /// **'SSH 错误：{error}'**
  String sshError(String error);

  /// No description provided for @connectFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败：{error}'**
  String connectFailed(String error);

  /// No description provided for @appLanguageZh.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get appLanguageZh;

  /// No description provided for @appLanguageEn.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get appLanguageEn;

  /// No description provided for @newSession.
  ///
  /// In zh, this message translates to:
  /// **'新建窗口'**
  String get newSession;

  /// No description provided for @pickHostTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择要连接的主机'**
  String get pickHostTitle;

  /// No description provided for @goAddHost.
  ///
  /// In zh, this message translates to:
  /// **'去添加主机'**
  String get goAddHost;

  /// No description provided for @pickHostHint.
  ///
  /// In zh, this message translates to:
  /// **'↑↓ 选择，回车打开'**
  String get pickHostHint;

  /// No description provided for @overviewTotal.
  ///
  /// In zh, this message translates to:
  /// **'主机总数'**
  String get overviewTotal;

  /// No description provided for @overviewGroups.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个分组'**
  String overviewGroups(int count);

  /// No description provided for @overviewOnline.
  ///
  /// In zh, this message translates to:
  /// **'在线'**
  String get overviewOnline;

  /// No description provided for @overviewLost.
  ///
  /// In zh, this message translates to:
  /// **'失联'**
  String get overviewLost;

  /// No description provided for @overviewChecksOff.
  ///
  /// In zh, this message translates to:
  /// **'检测已关闭'**
  String get overviewChecksOff;

  /// No description provided for @overviewLastConnected.
  ///
  /// In zh, this message translates to:
  /// **'上次连接'**
  String get overviewLastConnected;

  /// No description provided for @overviewNoRecent.
  ///
  /// In zh, this message translates to:
  /// **'还没有连接过主机'**
  String get overviewNoRecent;

  /// No description provided for @connect.
  ///
  /// In zh, this message translates to:
  /// **'连接'**
  String get connect;

  /// No description provided for @timeJustNow.
  ///
  /// In zh, this message translates to:
  /// **'刚刚'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In zh, this message translates to:
  /// **'{n} 分钟前'**
  String timeMinutesAgo(int n);

  /// No description provided for @timeHoursAgo.
  ///
  /// In zh, this message translates to:
  /// **'{n} 小时前'**
  String timeHoursAgo(int n);

  /// No description provided for @timeDaysAgo.
  ///
  /// In zh, this message translates to:
  /// **'{n} 天前'**
  String timeDaysAgo(int n);

  /// No description provided for @showHostOverview.
  ///
  /// In zh, this message translates to:
  /// **'显示主机概览'**
  String get showHostOverview;

  /// No description provided for @showHostOverviewSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'在主机页顶部显示主机数量、在线情况和上次连接'**
  String get showHostOverviewSubtitle;

  /// No description provided for @hostIcon.
  ///
  /// In zh, this message translates to:
  /// **'图标'**
  String get hostIcon;

  /// No description provided for @iconLetter.
  ///
  /// In zh, this message translates to:
  /// **'字母'**
  String get iconLetter;

  /// No description provided for @iconSymbol.
  ///
  /// In zh, this message translates to:
  /// **'图标'**
  String get iconSymbol;

  /// No description provided for @iconFlag.
  ///
  /// In zh, this message translates to:
  /// **'国旗'**
  String get iconFlag;

  /// No description provided for @iconColorAuto.
  ///
  /// In zh, this message translates to:
  /// **'跟随主题色'**
  String get iconColorAuto;

  /// No description provided for @iconFlagHint.
  ///
  /// In zh, this message translates to:
  /// **'按主机 IP 查询所在国家/地区并显示国旗（IP 会发送给 ipwho.is）。查不到时（如内网地址）显示首字母。'**
  String get iconFlagHint;

  /// No description provided for @moreSettings.
  ///
  /// In zh, this message translates to:
  /// **'更多设置'**
  String get moreSettings;

  /// No description provided for @lessSettings.
  ///
  /// In zh, this message translates to:
  /// **'收起'**
  String get lessSettings;

  /// No description provided for @trayShow.
  ///
  /// In zh, this message translates to:
  /// **'显示 uessh'**
  String get trayShow;

  /// No description provided for @trayQuickConnect.
  ///
  /// In zh, this message translates to:
  /// **'快速连接'**
  String get trayQuickConnect;

  /// No description provided for @trayQuit.
  ///
  /// In zh, this message translates to:
  /// **'退出 uessh'**
  String get trayQuit;

  /// No description provided for @runInBackground.
  ///
  /// In zh, this message translates to:
  /// **'后台常驻'**
  String get runInBackground;

  /// No description provided for @runInBackgroundSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'在菜单栏或任务栏显示图标；关闭窗口后继续在后台运行，SSH 连接不会断开'**
  String get runInBackgroundSubtitle;

  /// No description provided for @general.
  ///
  /// In zh, this message translates to:
  /// **'通用'**
  String get general;

  /// No description provided for @aiAssistant.
  ///
  /// In zh, this message translates to:
  /// **'AI 助手'**
  String get aiAssistant;

  /// No description provided for @aiShowPanel.
  ///
  /// In zh, this message translates to:
  /// **'AI 助手'**
  String get aiShowPanel;

  /// No description provided for @aiHidePanel.
  ///
  /// In zh, this message translates to:
  /// **'隐藏 AI 助手'**
  String get aiHidePanel;

  /// No description provided for @aiClosePanel.
  ///
  /// In zh, this message translates to:
  /// **'关闭 AI 助手'**
  String get aiClosePanel;

  /// No description provided for @aiNewChat.
  ///
  /// In zh, this message translates to:
  /// **'新对话'**
  String get aiNewChat;

  /// No description provided for @aiSetupTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有配置 AI 供应商'**
  String get aiSetupTitle;

  /// No description provided for @aiSetupBody.
  ///
  /// In zh, this message translates to:
  /// **'在设置里填入 API Key 后即可使用。支持 Claude、ChatGPT、DeepSeek、Gemini、Grok 和自定义接口。'**
  String get aiSetupBody;

  /// No description provided for @aiOpenSettings.
  ///
  /// In zh, this message translates to:
  /// **'前往设置'**
  String get aiOpenSettings;

  /// No description provided for @aiInputHint.
  ///
  /// In zh, this message translates to:
  /// **'输入问题，Enter 发送，Shift+Enter 换行'**
  String get aiInputHint;

  /// No description provided for @aiPickModel.
  ///
  /// In zh, this message translates to:
  /// **'选择模型'**
  String get aiPickModel;

  /// No description provided for @aiLoadingModels.
  ///
  /// In zh, this message translates to:
  /// **'正在加载模型…'**
  String get aiLoadingModels;

  /// No description provided for @aiModelsFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法获取模型列表'**
  String get aiModelsFailed;

  /// No description provided for @aiNoModels.
  ///
  /// In zh, this message translates to:
  /// **'没有可用模型'**
  String get aiNoModels;

  /// No description provided for @aiRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get aiRetry;

  /// No description provided for @aiManageProviders.
  ///
  /// In zh, this message translates to:
  /// **'管理 AI 供应商…'**
  String get aiManageProviders;

  /// No description provided for @aiAttachOn.
  ///
  /// In zh, this message translates to:
  /// **'附带终端输出：开（最近 80 行）'**
  String get aiAttachOn;

  /// No description provided for @aiAttachOff.
  ///
  /// In zh, this message translates to:
  /// **'附带终端输出：关'**
  String get aiAttachOff;

  /// No description provided for @aiSend.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get aiSend;

  /// No description provided for @aiStop.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get aiStop;

  /// No description provided for @aiCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get aiCopied;

  /// No description provided for @aiPasteToTerminal.
  ///
  /// In zh, this message translates to:
  /// **'粘贴到终端（不会执行）'**
  String get aiPasteToTerminal;

  /// No description provided for @aiReasoning.
  ///
  /// In zh, this message translates to:
  /// **'思考过程'**
  String get aiReasoning;

  /// No description provided for @aiRefused.
  ///
  /// In zh, this message translates to:
  /// **'模型拒绝回答这个问题。'**
  String get aiRefused;

  /// No description provided for @aiTruncated.
  ///
  /// In zh, this message translates to:
  /// **'回答过长，已被截断。'**
  String get aiTruncated;

  /// No description provided for @aiNoKey.
  ///
  /// In zh, this message translates to:
  /// **'这个供应商还没有 API Key'**
  String get aiNoKey;

  /// No description provided for @aiWithTerminal.
  ///
  /// In zh, this message translates to:
  /// **'已附带终端输出'**
  String get aiWithTerminal;

  /// No description provided for @aiStopped.
  ///
  /// In zh, this message translates to:
  /// **'已停止'**
  String get aiStopped;

  /// No description provided for @aiSection.
  ///
  /// In zh, this message translates to:
  /// **'AI 助手'**
  String get aiSection;

  /// No description provided for @aiProviderConfigured.
  ///
  /// In zh, this message translates to:
  /// **'已配置'**
  String get aiProviderConfigured;

  /// No description provided for @aiProviderNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置'**
  String get aiProviderNotConfigured;

  /// No description provided for @aiAddCustom.
  ///
  /// In zh, this message translates to:
  /// **'添加自定义供应商'**
  String get aiAddCustom;

  /// No description provided for @aiCustomProvider.
  ///
  /// In zh, this message translates to:
  /// **'自定义供应商'**
  String get aiCustomProvider;

  /// No description provided for @aiApiKey.
  ///
  /// In zh, this message translates to:
  /// **'API Key'**
  String get aiApiKey;

  /// No description provided for @aiApiKeyKeep.
  ///
  /// In zh, this message translates to:
  /// **'已保存；留空则保持不变'**
  String get aiApiKeyKeep;

  /// No description provided for @aiGetKey.
  ///
  /// In zh, this message translates to:
  /// **'获取 API Key'**
  String get aiGetKey;

  /// No description provided for @aiBaseUrl.
  ///
  /// In zh, this message translates to:
  /// **'接口地址'**
  String get aiBaseUrl;

  /// No description provided for @aiBaseUrlRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入接口地址'**
  String get aiBaseUrlRequired;

  /// No description provided for @aiBaseUrlInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入以 http:// 或 https:// 开头的地址'**
  String get aiBaseUrlInvalid;

  /// No description provided for @aiProviderName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get aiProviderName;

  /// No description provided for @aiNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入名称'**
  String get aiNameRequired;

  /// No description provided for @aiProtocol.
  ///
  /// In zh, this message translates to:
  /// **'接口格式'**
  String get aiProtocol;

  /// No description provided for @aiProtocolOpenai.
  ///
  /// In zh, this message translates to:
  /// **'OpenAI 兼容'**
  String get aiProtocolOpenai;

  /// No description provided for @aiProtocolAnthropic.
  ///
  /// In zh, this message translates to:
  /// **'Anthropic'**
  String get aiProtocolAnthropic;

  /// No description provided for @aiExtraModels.
  ///
  /// In zh, this message translates to:
  /// **'额外模型'**
  String get aiExtraModels;

  /// No description provided for @aiExtraModelsHelper.
  ///
  /// In zh, this message translates to:
  /// **'接口不提供模型列表时，在这里填写模型 ID，用逗号分隔'**
  String get aiExtraModelsHelper;

  /// No description provided for @aiTest.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get aiTest;

  /// No description provided for @aiTesting.
  ///
  /// In zh, this message translates to:
  /// **'正在测试…'**
  String get aiTesting;

  /// No description provided for @aiKeyStored.
  ///
  /// In zh, this message translates to:
  /// **'API Key 加密保存在本机保险库里，不会写入配置文件。'**
  String get aiKeyStored;

  /// No description provided for @aiRemoveProvider.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get aiRemoveProvider;

  /// No description provided for @aiRemoveTitle.
  ///
  /// In zh, this message translates to:
  /// **'移除这个供应商？'**
  String get aiRemoveTitle;

  /// No description provided for @aiRemoveBody.
  ///
  /// In zh, this message translates to:
  /// **'会删除它的 API Key 和设置。'**
  String get aiRemoveBody;

  /// No description provided for @aiKeyRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入 API Key'**
  String get aiKeyRequired;

  /// No description provided for @aiBaseUrlDefault.
  ///
  /// In zh, this message translates to:
  /// **'留空使用默认地址：{url}'**
  String aiBaseUrlDefault(String url);

  /// No description provided for @aiTestOk.
  ///
  /// In zh, this message translates to:
  /// **'连接成功，可用模型 {count} 个'**
  String aiTestOk(int count);

  /// No description provided for @aiTestFailed.
  ///
  /// In zh, this message translates to:
  /// **'连接失败：{error}'**
  String aiTestFailed(String error);

  /// No description provided for @aiToolRun.
  ///
  /// In zh, this message translates to:
  /// **'执行命令'**
  String get aiToolRun;

  /// No description provided for @aiToolReadTerminal.
  ///
  /// In zh, this message translates to:
  /// **'读取终端'**
  String get aiToolReadTerminal;

  /// No description provided for @aiToolWaiting.
  ///
  /// In zh, this message translates to:
  /// **'等待你允许'**
  String get aiToolWaiting;

  /// No description provided for @aiToolRunning.
  ///
  /// In zh, this message translates to:
  /// **'运行中'**
  String get aiToolRunning;

  /// No description provided for @aiToolDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get aiToolDone;

  /// No description provided for @aiToolDenied.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝'**
  String get aiToolDenied;

  /// No description provided for @aiToolFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get aiToolFailed;

  /// No description provided for @aiToolMayChange.
  ///
  /// In zh, this message translates to:
  /// **'这条命令可能会修改服务器，你允许后才会执行。'**
  String get aiToolMayChange;

  /// No description provided for @aiToolAskAll.
  ///
  /// In zh, this message translates to:
  /// **'按当前设置，每条命令都需要你允许。'**
  String get aiToolAskAll;

  /// No description provided for @aiAllow.
  ///
  /// In zh, this message translates to:
  /// **'允许执行'**
  String get aiAllow;

  /// No description provided for @aiDeny.
  ///
  /// In zh, this message translates to:
  /// **'拒绝'**
  String get aiDeny;

  /// No description provided for @aiShowOutput.
  ///
  /// In zh, this message translates to:
  /// **'显示输出'**
  String get aiShowOutput;

  /// No description provided for @aiHideOutput.
  ///
  /// In zh, this message translates to:
  /// **'收起输出'**
  String get aiHideOutput;

  /// No description provided for @aiNoOutput.
  ///
  /// In zh, this message translates to:
  /// **'（没有输出）'**
  String get aiNoOutput;

  /// No description provided for @aiStepLimit.
  ///
  /// In zh, this message translates to:
  /// **'已达到单条消息的步骤上限；回复「继续」可以接着做。'**
  String get aiStepLimit;

  /// No description provided for @aiToolMode.
  ///
  /// In zh, this message translates to:
  /// **'命令执行'**
  String get aiToolMode;

  /// No description provided for @aiToolModeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'允许 AI 在当前连接的主机上执行命令来排查和处理问题'**
  String get aiToolModeSubtitle;

  /// No description provided for @aiToolModeOff.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get aiToolModeOff;

  /// No description provided for @aiToolModeAsk.
  ///
  /// In zh, this message translates to:
  /// **'每条命令都询问'**
  String get aiToolModeAsk;

  /// No description provided for @aiToolModeAuto.
  ///
  /// In zh, this message translates to:
  /// **'只读命令自动执行'**
  String get aiToolModeAuto;

  /// No description provided for @aiToolExit.
  ///
  /// In zh, this message translates to:
  /// **'退出码 {code}'**
  String aiToolExit(int code);

  /// No description provided for @aiToolModeAll.
  ///
  /// In zh, this message translates to:
  /// **'全量允许（不再询问）'**
  String get aiToolModeAll;

  /// No description provided for @aiAllowAllTitle.
  ///
  /// In zh, this message translates to:
  /// **'允许 AI 执行所有命令？'**
  String get aiAllowAllTitle;

  /// No description provided for @aiAllowAllBody.
  ///
  /// In zh, this message translates to:
  /// **'开启后，AI 执行任何命令都不再询问你，包括删除文件、修改配置、重启服务等。它能做当前 SSH 用户能做的一切，误操作可能造成数据丢失或服务中断。建议只在测试机上使用。'**
  String get aiAllowAllBody;

  /// No description provided for @aiAllowAllConfirm.
  ///
  /// In zh, this message translates to:
  /// **'仍要开启'**
  String get aiAllowAllConfirm;

  /// No description provided for @splitRight.
  ///
  /// In zh, this message translates to:
  /// **'向右拆分'**
  String get splitRight;

  /// No description provided for @splitDown.
  ///
  /// In zh, this message translates to:
  /// **'向下拆分'**
  String get splitDown;

  /// No description provided for @zoomPane.
  ///
  /// In zh, this message translates to:
  /// **'最大化窗格'**
  String get zoomPane;

  /// No description provided for @restorePane.
  ///
  /// In zh, this message translates to:
  /// **'还原窗格'**
  String get restorePane;

  /// No description provided for @moveToNewTab.
  ///
  /// In zh, this message translates to:
  /// **'拆分到新标签'**
  String get moveToNewTab;

  /// No description provided for @closePane.
  ///
  /// In zh, this message translates to:
  /// **'关闭窗格'**
  String get closePane;

  /// No description provided for @broadcastOn.
  ///
  /// In zh, this message translates to:
  /// **'广播输入到所有窗格'**
  String get broadcastOn;

  /// No description provided for @broadcastOff.
  ///
  /// In zh, this message translates to:
  /// **'停止广播输入'**
  String get broadcastOff;

  /// No description provided for @broadcasting.
  ///
  /// In zh, this message translates to:
  /// **'广播中'**
  String get broadcasting;

  /// No description provided for @workspaceFull.
  ///
  /// In zh, this message translates to:
  /// **'一个工作区最多放 9 个窗格'**
  String get workspaceFull;

  /// No description provided for @closeWorkspaceTitle.
  ///
  /// In zh, this message translates to:
  /// **'关闭这个工作区？'**
  String get closeWorkspaceTitle;

  /// No description provided for @dropHere.
  ///
  /// In zh, this message translates to:
  /// **'放到这里'**
  String get dropHere;

  /// No description provided for @closeWorkspaceBody.
  ///
  /// In zh, this message translates to:
  /// **'会关闭其中的 {count} 个连接。'**
  String closeWorkspaceBody(int count);

  /// No description provided for @workspaceName.
  ///
  /// In zh, this message translates to:
  /// **'工作区 {n}'**
  String workspaceName(int n);

  /// No description provided for @renameWorkspaceHint.
  ///
  /// In zh, this message translates to:
  /// **'点击重命名'**
  String get renameWorkspaceHint;

  /// No description provided for @aiHistory.
  ///
  /// In zh, this message translates to:
  /// **'历史对话'**
  String get aiHistory;

  /// No description provided for @aiHistoryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有历史对话'**
  String get aiHistoryEmpty;

  /// No description provided for @aiHistoryThisHost.
  ///
  /// In zh, this message translates to:
  /// **'这台主机'**
  String get aiHistoryThisHost;

  /// No description provided for @aiHistoryOtherHosts.
  ///
  /// In zh, this message translates to:
  /// **'其他主机'**
  String get aiHistoryOtherHosts;

  /// No description provided for @aiHistoryDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除这条对话'**
  String get aiHistoryDelete;

  /// No description provided for @aiBackToChat.
  ///
  /// In zh, this message translates to:
  /// **'返回对话'**
  String get aiBackToChat;

  /// No description provided for @aiClearHistory.
  ///
  /// In zh, this message translates to:
  /// **'清除 AI 对话记录'**
  String get aiClearHistory;

  /// No description provided for @aiClearHistorySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'对话记录加密保存在本机，最多保留 200 条'**
  String get aiClearHistorySubtitle;

  /// No description provided for @aiClearHistoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'清除所有 AI 对话记录？'**
  String get aiClearHistoryTitle;

  /// No description provided for @aiClearHistoryBody.
  ///
  /// In zh, this message translates to:
  /// **'所有主机的 AI 对话都会被删除，无法恢复。'**
  String get aiClearHistoryBody;

  /// No description provided for @aiClear.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get aiClear;

  /// No description provided for @filesShow.
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get filesShow;

  /// No description provided for @filesHide.
  ///
  /// In zh, this message translates to:
  /// **'关闭文件'**
  String get filesHide;

  /// No description provided for @filesBack.
  ///
  /// In zh, this message translates to:
  /// **'后退'**
  String get filesBack;

  /// No description provided for @filesForward.
  ///
  /// In zh, this message translates to:
  /// **'前进'**
  String get filesForward;

  /// No description provided for @filesUp.
  ///
  /// In zh, this message translates to:
  /// **'上一级'**
  String get filesUp;

  /// No description provided for @filesRefresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get filesRefresh;

  /// No description provided for @filesFollow.
  ///
  /// In zh, this message translates to:
  /// **'跟随终端当前目录'**
  String get filesFollow;

  /// No description provided for @filesShowHidden.
  ///
  /// In zh, this message translates to:
  /// **'显示隐藏文件'**
  String get filesShowHidden;

  /// No description provided for @filesHideHidden.
  ///
  /// In zh, this message translates to:
  /// **'不显示隐藏文件'**
  String get filesHideHidden;

  /// No description provided for @viewIcons.
  ///
  /// In zh, this message translates to:
  /// **'图标'**
  String get viewIcons;

  /// No description provided for @viewList.
  ///
  /// In zh, this message translates to:
  /// **'列表'**
  String get viewList;

  /// No description provided for @viewColumns.
  ///
  /// In zh, this message translates to:
  /// **'分栏'**
  String get viewColumns;

  /// No description provided for @viewGallery.
  ///
  /// In zh, this message translates to:
  /// **'画廊'**
  String get viewGallery;

  /// No description provided for @colName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get colName;

  /// No description provided for @colModified.
  ///
  /// In zh, this message translates to:
  /// **'修改日期'**
  String get colModified;

  /// No description provided for @colSize.
  ///
  /// In zh, this message translates to:
  /// **'大小'**
  String get colSize;

  /// No description provided for @colKind.
  ///
  /// In zh, this message translates to:
  /// **'种类'**
  String get colKind;

  /// No description provided for @filesEmpty.
  ///
  /// In zh, this message translates to:
  /// **'空文件夹'**
  String get filesEmpty;

  /// No description provided for @filesNotConnected.
  ///
  /// In zh, this message translates to:
  /// **'连接后才能浏览文件'**
  String get filesNotConnected;

  /// No description provided for @filesLocating.
  ///
  /// In zh, this message translates to:
  /// **'正在定位终端目录…'**
  String get filesLocating;

  /// No description provided for @filesOpen.
  ///
  /// In zh, this message translates to:
  /// **'打开'**
  String get filesOpen;

  /// No description provided for @filesCdHere.
  ///
  /// In zh, this message translates to:
  /// **'在终端中进入'**
  String get filesCdHere;

  /// No description provided for @filesCopyPath.
  ///
  /// In zh, this message translates to:
  /// **'复制路径'**
  String get filesCopyPath;

  /// No description provided for @filesDownload.
  ///
  /// In zh, this message translates to:
  /// **'下载…'**
  String get filesDownload;

  /// No description provided for @filesNoPreview.
  ///
  /// In zh, this message translates to:
  /// **'没有预览'**
  String get filesNoPreview;

  /// No description provided for @filesPermissions.
  ///
  /// In zh, this message translates to:
  /// **'权限'**
  String get filesPermissions;

  /// No description provided for @kindFolder.
  ///
  /// In zh, this message translates to:
  /// **'文件夹'**
  String get kindFolder;

  /// No description provided for @kindImage.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get kindImage;

  /// No description provided for @kindText.
  ///
  /// In zh, this message translates to:
  /// **'文本'**
  String get kindText;

  /// No description provided for @kindCode.
  ///
  /// In zh, this message translates to:
  /// **'代码'**
  String get kindCode;

  /// No description provided for @kindArchive.
  ///
  /// In zh, this message translates to:
  /// **'压缩包'**
  String get kindArchive;

  /// No description provided for @kindVideo.
  ///
  /// In zh, this message translates to:
  /// **'视频'**
  String get kindVideo;

  /// No description provided for @kindAudio.
  ///
  /// In zh, this message translates to:
  /// **'音频'**
  String get kindAudio;

  /// No description provided for @kindPdf.
  ///
  /// In zh, this message translates to:
  /// **'PDF 文稿'**
  String get kindPdf;

  /// No description provided for @kindDocument.
  ///
  /// In zh, this message translates to:
  /// **'文档'**
  String get kindDocument;

  /// No description provided for @kindExecutable.
  ///
  /// In zh, this message translates to:
  /// **'可执行文件'**
  String get kindExecutable;

  /// No description provided for @kindFile.
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get kindFile;

  /// No description provided for @kindLink.
  ///
  /// In zh, this message translates to:
  /// **'替身'**
  String get kindLink;

  /// No description provided for @filesItems.
  ///
  /// In zh, this message translates to:
  /// **'{n} 项'**
  String filesItems(int n);

  /// No description provided for @filesError.
  ///
  /// In zh, this message translates to:
  /// **'无法打开：{error}'**
  String filesError(String error);

  /// No description provided for @filesDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'已下载到 {path}'**
  String filesDownloaded(String path);

  /// No description provided for @filesDownloading.
  ///
  /// In zh, this message translates to:
  /// **'正在下载 {name}…'**
  String filesDownloading(String name);

  /// No description provided for @aiAddProvider.
  ///
  /// In zh, this message translates to:
  /// **'添加 AI 供应商'**
  String get aiAddProvider;

  /// No description provided for @aiNoProviders.
  ///
  /// In zh, this message translates to:
  /// **'还没有添加 AI 供应商'**
  String get aiNoProviders;

  /// No description provided for @aiNoProvidersHint.
  ///
  /// In zh, this message translates to:
  /// **'添加一个供应商并填入 API Key，就可以在终端页使用 AI 助手'**
  String get aiNoProvidersHint;

  /// No description provided for @aiAlreadyAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加'**
  String get aiAlreadyAdded;

  /// No description provided for @filesUpload.
  ///
  /// In zh, this message translates to:
  /// **'上传文件…'**
  String get filesUpload;

  /// No description provided for @filesUploadHere.
  ///
  /// In zh, this message translates to:
  /// **'上传文件到这里…'**
  String get filesUploadHere;

  /// No description provided for @dropResolving.
  ///
  /// In zh, this message translates to:
  /// **'正在获取当前目录…'**
  String get dropResolving;

  /// No description provided for @uploadNotConnected.
  ///
  /// In zh, this message translates to:
  /// **'未连接，无法上传'**
  String get uploadNotConnected;

  /// No description provided for @overwriteTitle.
  ///
  /// In zh, this message translates to:
  /// **'替换已有的项目？'**
  String get overwriteTitle;

  /// No description provided for @overwriteReplace.
  ///
  /// In zh, this message translates to:
  /// **'替换'**
  String get overwriteReplace;

  /// No description provided for @overwriteSkip.
  ///
  /// In zh, this message translates to:
  /// **'跳过'**
  String get overwriteSkip;

  /// No description provided for @dropToUpload.
  ///
  /// In zh, this message translates to:
  /// **'松开上传到 {path}'**
  String dropToUpload(String path);

  /// No description provided for @uploadProgress.
  ///
  /// In zh, this message translates to:
  /// **'正在上传到 {path}'**
  String uploadProgress(String path);

  /// No description provided for @uploadDone.
  ///
  /// In zh, this message translates to:
  /// **'已上传 {count} 个文件到 {path}'**
  String uploadDone(int count, String path);

  /// No description provided for @uploadFailed.
  ///
  /// In zh, this message translates to:
  /// **'上传失败：{error}'**
  String uploadFailed(String error);

  /// No description provided for @overwriteBody.
  ///
  /// In zh, this message translates to:
  /// **'{path} 里已有同名项目：{names}'**
  String overwriteBody(String path, String names);

  /// No description provided for @uploadCount.
  ///
  /// In zh, this message translates to:
  /// **'{done}/{total} 个文件'**
  String uploadCount(int done, int total);

  /// No description provided for @aiToolHiddenChars.
  ///
  /// In zh, this message translates to:
  /// **'命令里有不可见或反向的字符（已标成 <U+…>），可能和看上去的不一样，请仔细确认。'**
  String get aiToolHiddenChars;

  /// No description provided for @aiToolOnHost.
  ///
  /// In zh, this message translates to:
  /// **'在 {host} 上执行'**
  String aiToolOnHost(String host);

  /// No description provided for @aiPasteRunsTitle.
  ///
  /// In zh, this message translates to:
  /// **'粘贴后会直接执行'**
  String get aiPasteRunsTitle;

  /// No description provided for @aiPasteAnyway.
  ///
  /// In zh, this message translates to:
  /// **'仍要粘贴'**
  String get aiPasteAnyway;

  /// No description provided for @aiPasteRunsBody.
  ///
  /// In zh, this message translates to:
  /// **'这台服务器的 Shell 没有开启安全粘贴，多行内容粘贴后，前 {n} 行会像按了回车一样立即执行。'**
  String aiPasteRunsBody(int n);

  /// No description provided for @aiBaseUrlHttps.
  ///
  /// In zh, this message translates to:
  /// **'需要使用 https://，否则 API Key 会明文传输（本机 http://localhost 除外）'**
  String get aiBaseUrlHttps;

  /// No description provided for @aiAllowAllActive.
  ///
  /// In zh, this message translates to:
  /// **'全量允许已开启：AI 执行任何命令都不会询问你。点此去设置更改'**
  String get aiAllowAllActive;

  /// No description provided for @workbench.
  ///
  /// In zh, this message translates to:
  /// **'工作台'**
  String get workbench;

  /// No description provided for @reconnectingIn.
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒后自动重连（第 {attempt}/{total} 次）'**
  String reconnectingIn(int seconds, int attempt, int total);

  /// No description provided for @reconnectGaveUp.
  ///
  /// In zh, this message translates to:
  /// **'已重连 {count} 次仍未成功，停止自动重连'**
  String reconnectGaveUp(int count);

  /// No description provided for @reconnectBanner.
  ///
  /// In zh, this message translates to:
  /// **'连接已断开，{seconds} 秒后重连（{attempt}/{total}）'**
  String reconnectBanner(int seconds, int attempt, int total);

  /// No description provided for @reconnectingNow.
  ///
  /// In zh, this message translates to:
  /// **'正在重连（{attempt}/{total}）…'**
  String reconnectingNow(int attempt, int total);

  /// No description provided for @reconnectNow.
  ///
  /// In zh, this message translates to:
  /// **'立即重连'**
  String get reconnectNow;

  /// No description provided for @settingsReconnect.
  ///
  /// In zh, this message translates to:
  /// **'自动重连'**
  String get settingsReconnect;

  /// No description provided for @settingsReconnectSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'SSH 连接意外断开后自动重新连接；输入 exit 退出不会重连'**
  String get settingsReconnectSubtitle;

  /// No description provided for @settingsReconnectAttempts.
  ///
  /// In zh, this message translates to:
  /// **'重连次数'**
  String get settingsReconnectAttempts;

  /// No description provided for @settingsReconnectDelay.
  ///
  /// In zh, this message translates to:
  /// **'重连间隔'**
  String get settingsReconnectDelay;

  /// No description provided for @reconnectAttemptsValue.
  ///
  /// In zh, this message translates to:
  /// **'{count} 次'**
  String reconnectAttemptsValue(int count);

  /// No description provided for @reconnectDelayValue.
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒'**
  String reconnectDelayValue(int seconds);

  /// No description provided for @sshSection.
  ///
  /// In zh, this message translates to:
  /// **'SSH 连接'**
  String get sshSection;

  /// No description provided for @settingsHighlight.
  ///
  /// In zh, this message translates to:
  /// **'命令语法高亮'**
  String get settingsHighlight;

  /// No description provided for @settingsHighlightSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'在终端里为正在输入的命令着色，只在本机显示，不修改服务器'**
  String get settingsHighlightSubtitle;

  /// No description provided for @highlightCommand.
  ///
  /// In zh, this message translates to:
  /// **'命令'**
  String get highlightCommand;

  /// No description provided for @highlightDangerous.
  ///
  /// In zh, this message translates to:
  /// **'危险命令'**
  String get highlightDangerous;

  /// No description provided for @highlightOption.
  ///
  /// In zh, this message translates to:
  /// **'选项'**
  String get highlightOption;

  /// No description provided for @highlightString.
  ///
  /// In zh, this message translates to:
  /// **'字符串'**
  String get highlightString;

  /// No description provided for @highlightVariable.
  ///
  /// In zh, this message translates to:
  /// **'变量'**
  String get highlightVariable;

  /// No description provided for @highlightOperator.
  ///
  /// In zh, this message translates to:
  /// **'管道/重定向'**
  String get highlightOperator;

  /// No description provided for @highlightComment.
  ///
  /// In zh, this message translates to:
  /// **'注释'**
  String get highlightComment;

  /// No description provided for @highlightResetAll.
  ///
  /// In zh, this message translates to:
  /// **'全部恢复默认'**
  String get highlightResetAll;

  /// No description provided for @highlightDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认颜色'**
  String get highlightDefault;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
