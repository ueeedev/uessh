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
