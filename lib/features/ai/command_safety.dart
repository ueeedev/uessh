/// Decides whether a shell command proposed by the AI may run without the
/// user's approval ("read-only"), or must be shown for approval first.
///
/// This is a security boundary: text the model reads (logs, files, web
/// pages) can try to steer it into running something harmful. So the check
/// is an allowlist, never a denylist:
///
/// * the command is parsed the way a POSIX shell does (quotes, backslash
///   escapes, comments); anything it can't be sure about - command or
///   process substitution, `${...}` beyond a plain name, arithmetic,
///   subshells, here-documents - needs approval;
/// * redirections may only read files or go to /dev/null;
/// * every program must be on the list, and for many, only the options
///   known to be harmless are accepted (no writing files, no running
///   other programs, no config that could do either);
/// * environment assignments (`LD_PRELOAD=...`, `LESSOPEN=...`) need
///   approval, except a few harmless ones (locale, time zone);
/// * anything that reaches the network (curl, dig, ping, ...) needs
///   approval: it could send data out;
/// * anything that touches secrets (keys, `.env`, shadow, tokens, ...)
///   needs approval: it would be sent to the AI provider;
/// * invisible, control or bidirectional characters need approval: what
///   the user sees must be what runs.
bool isReadOnlyCommand(String command) {
  final cmd = command.trim();
  if (cmd.isEmpty || cmd.length > 4000) return false;
  if (hasHiddenCharacters(cmd)) return false;
  final segments = _lex(cmd);
  if (segments == null) return false;
  var any = false;
  for (final words in segments) {
    if (words.isEmpty) continue;
    any = true;
    if (!_segmentReadOnly(words)) return false;
  }
  return any;
}

// ---------------------------------------------------------------------------
// Characters

bool _hidden(int c) =>
    (c < 0x20 && c != 0x09 && c != 0x0a) ||
    c == 0x7f ||
    (c >= 0x80 && c <= 0x9f) ||
    (c >= 0x200b && c <= 0x200f) || // zero-width, LRM / RLM
    (c >= 0x202a && c <= 0x202e) || // bidi embedding / override
    (c >= 0x2066 && c <= 0x2069) || // bidi isolates
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x061c ||
    c == 0xfeff;

/// Control, zero-width or bidirectional characters: they can make a
/// command look different from what runs.
bool hasHiddenCharacters(String s) => s.runes.any(_hidden);

/// [s] with hidden characters shown as `<U+202E>` (tabs and newlines
/// kept), for showing a command to the user or in the terminal.
String visibleCommand(String s) {
  final out = StringBuffer();
  for (final r in s.runes) {
    if (_hidden(r)) {
      out.write('<U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}>');
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString();
}

// ---------------------------------------------------------------------------
// Lexer

/// Splits [s] into simple commands (lists of words, quotes and escapes
/// resolved), the way sh would. Returns null for anything that isn't
/// plainly safe to reason about.
List<List<String>>? _lex(String s) {
  final segments = <List<String>>[[]];
  final word = StringBuffer();
  var inWord = false;
  var i = 0;

  void endWord() {
    if (inWord) segments.last.add(word.toString());
    word.clear();
    inWord = false;
  }

  void newSegment() {
    endWord();
    segments.add([]);
  }

  /// `$` at [i]: plain `$NAME`, `$1`, `$?` and `${NAME}` are fine (they
  /// only expand); `$(`, `$((`, `$[`, other `${...}` are not.
  bool dollarOk() {
    if (i + 1 >= s.length) return true;
    final n = s[i + 1];
    if (n == '(' || n == '[') return false;
    if (n == '{') {
      final end = s.indexOf('}', i + 2);
      if (end < 0) return false;
      final name = s.substring(i + 2, end);
      return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name);
    }
    return true;
  }

  /// Reads the target word of a redirection (quotes resolved).
  String? redirectTarget() {
    while (i < s.length && (s[i] == ' ' || s[i] == '\t')) {
      i++;
    }
    final t = StringBuffer();
    while (i < s.length) {
      final c = s[i];
      if (' \t\n;&|<>()'.contains(c)) break;
      if (c == "'") {
        final end = s.indexOf("'", i + 1);
        if (end < 0) return null;
        t.write(s.substring(i + 1, end));
        i = end + 1;
      } else if (c == '"') {
        final end = s.indexOf('"', i + 1);
        if (end < 0) return null;
        final inner = s.substring(i + 1, end);
        if (inner.contains(r'$') || inner.contains('`')) return null;
        t.write(inner);
        i = end + 1;
      } else if (c == r'$' || c == '`' || c == r'\') {
        return null;
      } else {
        t.write(c);
        i++;
      }
    }
    return t.isEmpty ? null : t.toString();
  }

  while (i < s.length) {
    final c = s[i];
    switch (c) {
      case ' ' || '\t':
        endWord();
        i++;
      case '\n' || ';':
        newSegment();
        i++;
      case '&':
        if (i + 1 < s.length && s[i + 1] == '>') {
          // &> file / &>> file: both streams to a file.
          i += s.startsWith('&>>', i) ? 3 : 2;
          endWord();
          if (redirectTarget() != '/dev/null') return null;
        } else {
          newSegment();
          i += (i + 1 < s.length && s[i + 1] == '&') ? 2 : 1;
        }
      case '|':
        newSegment();
        i += (i + 1 < s.length && (s[i + 1] == '|' || s[i + 1] == '&')) ? 2 : 1;
      case '(' || ')' || '`':
        return null; // subshells, functions, command substitution
      case '<' || '>':
        // A file descriptor number just before (2>...) isn't a word.
        if (inWord && RegExp(r'^\d+$').hasMatch(word.toString())) {
          word.clear();
          inWord = false;
        } else {
          endWord();
        }
        final op = RegExp(r'^(<<<|<<|<>|<&|<\(|>>|>\||>&|>\(|<|>)')
            .firstMatch(s.substring(i))!
            .group(0)!;
        i += op.length;
        switch (op) {
          case '<<' || '<>' || '<(' || '>(':
            return null;
          case '<<<':
            break; // here-string: input only; the word follows normally
          case '<':
            final t = redirectTarget();
            if (t == null) return null;
            segments.last.add(t); // checked like an argument (secrets)
          case '>&' || '<&':
            final t = redirectTarget();
            if (t == null || !RegExp(r'^(\d+|-)$').hasMatch(t)) return null;
          default: // > >> >|
            if (redirectTarget() != '/dev/null') return null;
        }
      case '#' when !inWord:
        // Comment: the rest of the line doesn't run.
        while (i < s.length && s[i] != '\n') {
          i++;
        }
      case r'\':
        if (i + 1 >= s.length) return null;
        if (s[i + 1] != '\n') {
          word.write(s[i + 1]);
          inWord = true;
        }
        i += 2; // backslash-newline continues the line
      case "'":
        final end = s.indexOf("'", i + 1);
        if (end < 0) return null;
        word.write(s.substring(i + 1, end));
        inWord = true;
        i = end + 1;
      case '"':
        i++;
        inWord = true;
        var closed = false;
        while (i < s.length) {
          final d = s[i];
          if (d == '"') {
            closed = true;
            i++;
            break;
          }
          if (d == '`') return null;
          if (d == r'$' && !dollarOk()) return null;
          if (d == r'\' && i + 1 < s.length && r'$`"\'.contains(s[i + 1])) {
            word.write(s[i + 1]);
            i += 2;
            continue;
          }
          word.write(d);
          i++;
        }
        if (!closed) return null;
      case r'$':
        if (i + 1 < s.length && s[i + 1] == "'") {
          // $'...' (ANSI-C quoting): literal text with escapes.
          final end = s.indexOf("'", i + 2);
          if (end < 0) return null;
          word.write(s.substring(i + 2, end));
          inWord = true;
          i = end + 1;
        } else {
          if (!dollarOk()) return null;
          word.write(c);
          inWord = true;
          i++;
        }
      default:
        word.write(c);
        inWord = true;
        i++;
    }
  }
  endWord();
  return segments;
}

// ---------------------------------------------------------------------------
// Programs

/// Environment assignments that can't change what a program does in a
/// harmful way.
bool _harmlessAssignment(String w) {
  final name = w.substring(0, w.indexOf('='));
  return name.startsWith('LC_') ||
      const {
        'LANG', 'LANGUAGE', 'TZ', 'COLUMNS', 'LINES', 'NO_COLOR', 'TERM', //
      }.contains(name);
}

/// Words that point at secrets; reading them would send them to the AI
/// provider.
final _sensitive = RegExp(
  r'\.ssh\b|id_(rsa|dsa|ecdsa|ed25519)|shadow|sudoers|(^|/|\b)\.env\b|'
  r'\.pem\b|\.key\b|\.p12\b|\.pfx\b|\.jks\b|keystore|\.kube|kubeconfig|'
  r'\.aws\b|\.azure\b|gcloud|\.gnupg|\.netrc|\.pgpass|\.my\.cnf|'
  r'htpasswd|credential|secret|token|password|passphrase|private|'
  r'api[_-]?key|environ\b|\.docker/config|wallet|vault|\.git-credentials',
  caseSensitive: false,
);

/// Programs that only read, with any arguments.
const _plainReaders = {
  'ls', 'cat', 'head', 'tail', 'grep', 'egrep', 'fgrep', 'wc', 'cut', 'tr',
  'column', 'nl', 'stat', 'du', 'df', 'free', 'uptime', 'w', 'who', 'whoami',
  'id', 'groups', 'last', 'lastlog', 'uname', 'pwd', 'echo', 'printf', 'cal',
  'which', 'whereis', 'type', 'ps', 'pgrep', 'pidof', 'vmstat', 'iostat',
  'mpstat', 'lscpu', 'lsblk', 'lsusb', 'lspci', 'lsmod', 'lsof', 'netstat',
  'md5sum', 'sha1sum', 'sha256sum', 'sha512sum', 'readlink', 'realpath',
  'basename', 'dirname', 'locale', 'getenforce', 'sestatus', 'test', '[',
  'true', 'false', 'diff', 'cmp', 'zcat', 'zgrep', 'jq', 'nproc', 'arch',
  'findmnt', //
};

/// Programs allowed with only these options (and non-option arguments
/// where [_flagsOnly] allows them).
bool _onlyFlags(List<String> args, Set<String> allowed, {bool values = true}) {
  for (final a in args) {
    if (a.startsWith('-')) {
      if (!allowed.contains(a)) return false;
    } else if (!values) {
      return false;
    }
  }
  return true;
}

bool _segmentReadOnly(List<String> words) {
  // Environment assignments in front.
  var start = 0;
  while (start < words.length &&
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(words[start])) {
    if (!_harmlessAssignment(words[start])) return false;
    start++;
  }
  if (start == words.length) return true; // only harmless assignments
  final cmd = words.sublist(start);

  // Secrets anywhere in the command.
  if (cmd.any(_sensitive.hasMatch)) return false;

  // The program: a bare name, or one in the system's own folders (not
  // e.g. /tmp/x/ls).
  var prog = cmd.first;
  if (prog.contains('/')) {
    if (prog.contains('..') ||
        !RegExp(r'^/(usr/)?s?bin/[^/]+$').hasMatch(prog)) {
      return false;
    }
    prog = prog.split('/').last;
  }
  final args = cmd.sublist(1);
  bool has(Iterable<String> flags) =>
      args.any((a) => flags.any((f) => a == f || a.startsWith('$f=')));
  bool hasPrefix(Iterable<String> prefixes) =>
      args.any((a) => prefixes.any(a.startsWith));
  final operands = [
    for (final a in args)
      if (!a.startsWith('-')) a,
  ];
  final sub = operands.firstOrNull;

  if (_plainReaders.contains(prog)) return true;

  switch (prog) {
    case 'sort':
      return !hasPrefix(['-o', '--output', '--compress-program']);
    case 'uniq':
      return operands.length <= 1; // a second name is an output file
    case 'tree':
      return !hasPrefix(['-o', '--fromfile']);
    case 'yq':
      return !hasPrefix(['-i', '--inplace']);
    case 'file':
      return !hasPrefix(['-C', '--compile', '-m', '--magic-file']);
    case 'rg':
      return !hasPrefix(['--pre', '--search-zip', '-z']);
    case 'top':
      return args.contains('-b') || hasPrefix(['-bn', '-b ']);
    case 'dmesg':
      return !hasPrefix([
        '-c', '-C', '-D', '-E', '-n', '--clear', '--console', '--read-clear',
        '-w', '--follow', //
      ]);
    case 'sed':
      return _sedReadOnly(args);
    case 'awk' || 'gawk' || 'mawk':
      return _awkReadOnly(args);
    case 'printenv':
      // Named variables only (all of them could include secrets).
      return args.isNotEmpty && args.every((a) => !a.startsWith('-'));
    case 'find':
      return !has([
        '-delete', '-exec', '-execdir', '-ok', '-okdir', '-fprint',
        '-fprint0', '-fprintf', '-fls', //
      ]);
    case 'hostname':
      return _onlyFlags(args, {
        '-f', '--fqdn', '-s', '--short', '-i', '--ip-address', '-I',
        '--all-ip-addresses', '-d', '--domain', '-A', '--all-fqdns', //
      }, values: false);
    case 'date':
      return !hasPrefix(['-s', '--set']);
    case 'mount':
      return _onlyFlags(args, {'-l'}, values: false);
    case 'swapon':
      return _onlyFlags(args, {'--show', '-s', '--summary'}, values: false);
    case 'blkid':
      return !hasPrefix(['-g', '--garbage-collect', '-c']);
    case 'ip':
      if (hasPrefix(['-b', '-force', '-n', '-netns'])) return false;
      return !operands.any(
        (a) => const {
          'add', 'del', 'delete', 'set', 'flush', 'change', 'replace',
          'append', 'prepend', 'exec', 'monitor', 'save', 'restore', 'up',
          'down', 'attach', 'detach', 'load', 'unload', //
        }.contains(a),
      );
    case 'ifconfig':
      return args.isEmpty || (args.length == 1 && !args.first.contains('='));
    case 'route':
      return _onlyFlags(args, {'-n', '-e', '-ee', '-v'}, values: false);
    case 'arp':
      return _onlyFlags(args, {'-a', '-n', '-e', '-v'});
    case 'ss':
      for (final a in args) {
        if (a == '--kill' || a.startsWith('--diag')) return false;
        if (a.startsWith('-') &&
            !a.startsWith('--') &&
            (a.contains('K') || a.contains('D'))) {
          return false;
        }
      }
      return true;
    case 'getent':
      return const {'passwd', 'group', 'services', 'protocols'}.contains(sub);
    case 'systemctl':
      return sub == null ||
          const {
            'status', 'show', 'list-units', 'list-unit-files', 'list-timers',
            'list-sockets', 'list-dependencies', 'is-active', 'is-enabled',
            'is-failed', 'cat', 'get-default', //
          }.contains(sub);
    case 'service':
      return (args.length == 2 && args[1] == 'status') ||
          (args.length == 1 && args.first == '--status-all');
    case 'journalctl':
      return !hasPrefix([
        '--vacuum', '--rotate', '--flush', '--sync', '--relinquish',
        '--setup-keys', '--update-catalog', '-f', '--follow', //
      ]);
    case 'docker' || 'podman':
      return _dockerReadOnly(args);
    case 'kubectl':
      if (hasPrefix(['--kubeconfig', '-s', '--server', '--token'])) {
        return false;
      }
      return const {
        'get', 'describe', 'logs', 'top', 'version', 'cluster-info',
        'explain', 'api-resources', //
      }.contains(sub);
    case 'git':
      return _gitReadOnly(args);
    case 'nginx':
      return args.isNotEmpty &&
          _onlyFlags(args, {'-t', '-T', '-v', '-V'}, values: false);
    case 'crontab':
      return args.length == 1 && args.first == '-l';
    case 'timedatectl' || 'hostnamectl' || 'localectl':
      return _onlyFlags(args, {'--no-pager'}) &&
          (sub == null || sub == 'status' || sub.startsWith('list-'));
    case 'sysctl':
      for (final a in args) {
        if (a.startsWith('-')) {
          if (!const {
            '-a', '--all', '-n', '--values', '-e', '--ignore', '-N',
            '--names', '-q', '--quiet', '-r', //
          }.contains(a)) {
            return false;
          }
        } else if (a.contains('=')) {
          return false;
        }
      }
      return true;
    case 'iptables' || 'ip6tables':
      if (!args.any((a) => a == '-L' || a == '-S' || a.startsWith('--list'))) {
        return false;
      }
      return _onlyFlags(args, {
        '-L', '--list', '-S', '--list-rules', '-n', '--numeric', '-v',
        '--verbose', '-x', '--exact', '--line-numbers', '-t', '--table', //
      });
    case 'nft':
      return _onlyFlags(args, {'-a', '--handle', '-n', '--numeric'}) &&
          sub == 'list';
    case 'ufw':
      return sub == 'status';
    case 'firewall-cmd':
      return args.isNotEmpty &&
          args.every(
            (a) =>
                a.startsWith('--list') ||
                a == '--state' ||
                a.startsWith('--get') ||
                a.startsWith('--zone=') ||
                a == '--permanent',
          );
    case 'apt':
      return const {'list', 'show', 'policy'}.contains(sub);
    case 'apt-cache':
      return const {
        'show', 'showpkg', 'policy', 'search', 'depends', 'rdepends',
        'madison', 'stats', 'pkgnames', //
      }.contains(sub);
    case 'dpkg':
      return args.isNotEmpty &&
          _onlyFlags(args, {
            '-l', '--list', '-L', '--listfiles', '-s', '--status', '-S',
            '--search', '-p', '--print-avail', '--get-selections',
            '--print-architecture', '--version', //
          });
    case 'rpm':
      return args.isNotEmpty &&
          args.first.startsWith('-q') &&
          args.every(
            (a) =>
                !a.startsWith('-') ||
                RegExp(r'^-q[a-zA-Z]*$').hasMatch(a) ||
                const {
                  '--all',
                  '--info',
                  '--list',
                  '--whatprovides',
                  '--requires',
                  '--changelog',
                }.contains(a),
          );
    case 'yum' || 'dnf':
      return const {'list', 'info', 'repolist'}.contains(sub);
    case 'snap':
      return const {'list', 'info', 'services'}.contains(sub);
    case 'pip' || 'pip3':
      return const {'list', 'show', 'freeze'}.contains(sub);
    case 'npm':
      return const {'ls', 'list'}.contains(sub) ||
          (args.length == 1 && const {'-v', '--version'}.contains(args.first));
    case 'node' ||
        'python' ||
        'python3' ||
        'java' ||
        'go' ||
        'php' ||
        'ruby' ||
        'perl':
      return args.length == 1 &&
          const {
            '-v',
            '--version',
            '-version',
            'version',
            '-V',
          }.contains(args.first);
    case 'openssl':
      if (sub == 'version') return args.length <= 2;
      return sub == 'x509' &&
          args.contains('-noout') &&
          _onlyFlags(args, {
            '-noout', '-in', '-text', '-subject', '-issuer', '-dates',
            '-fingerprint', '-serial', '-enddate', '-startdate', '-ext', //
          });
  }
  return false;
}

/// sed: only printing / substituting scripts (no `e`, `w`, `r`, `-i`...).
bool _sedReadOnly(List<String> args) {
  final scripts = <String>[];
  var sawScript = false;
  for (var k = 0; k < args.length; k++) {
    final a = args[k];
    if (a == '-n' ||
        a == '-E' ||
        a == '-r' ||
        a == '--quiet' ||
        a == '--regexp-extended' ||
        a == '-s') {
      continue;
    }
    if (a == '-e') {
      if (k + 1 >= args.length) return false;
      scripts.add(args[++k]);
      sawScript = true;
      continue;
    }
    if (a.startsWith('-')) return false; // -i, -f, -z ... ask
    if (!sawScript) {
      scripts.add(a);
      sawScript = true;
    }
  }
  if (scripts.isEmpty) return false;
  final address = r'(\d+|\$|/([^/\\]|\\.)*/)';
  final ok = RegExp(
    '^($address(,$address)?)?\\s*(p|d|=|q|'
    r's/([^/\\]|\\.)*/([^/\\]|\\.)*/[gIip0-9]*'
    ')\$',
  );
  for (final script in scripts) {
    for (final part in script.split(RegExp(r'[;\n]'))) {
      if (part.trim().isEmpty) continue;
      if (!ok.hasMatch(part.trim())) return false;
    }
  }
  return true;
}

/// awk: programs that can't write files, run commands or read input from
/// commands.
bool _awkReadOnly(List<String> args) {
  for (var k = 0; k < args.length; k++) {
    final a = args[k];
    if (a == '-F' || a == '-v') {
      k++; // separator / variable value
      if (a == '-v' && k < args.length && _sensitive.hasMatch(args[k])) {
        return false;
      }
      continue;
    }
    if (a.startsWith('-F')) continue;
    if (a.startsWith('-')) return false; // -f progfile, -i include, ...
    final bad = RegExp(
      r'[>|]|system\s*\(|getline|@|ENVIRON|PROCINFO|close\s*\(|fflush',
    );
    if (bad.hasMatch(a)) return false;
    break; // the program; the rest are input files
  }
  return true;
}

bool _dockerReadOnly(List<String> args) {
  // No global options (-H/--host, --config, --context ...).
  if (args.isEmpty || args.first.startsWith('-')) return false;
  final sub = args.first;
  final rest = args.sublist(1);
  final restOps = [
    for (final a in rest)
      if (!a.startsWith('-')) a,
  ];
  switch (sub) {
    case 'compose':
      return rest.isNotEmpty &&
          !rest.first.startsWith('-') &&
          const {'ps', 'logs', 'ls', 'images', 'top'}.contains(rest.first);
    case 'network' || 'volume' || 'container' || 'image':
      return restOps.firstOrNull == 'ls';
    case 'ps' ||
        'images' ||
        'logs' ||
        'version' ||
        'info' ||
        'top' ||
        'port' ||
        'history' ||
        'df':
      return true;
    case 'stats':
      return rest.contains('--no-stream');
    case 'system':
      return restOps.firstOrNull == 'df';
  }
  return false; // inspect included: it shows environment variables
}

bool _gitReadOnly(List<String> args) {
  // Global options: only -C <dir> and --no-pager.
  var k = 0;
  while (k < args.length && args[k].startsWith('-')) {
    if (args[k] == '-C' && k + 1 < args.length) {
      k += 2;
    } else if (args[k] == '--no-pager') {
      k++;
    } else {
      return false; // -c, --git-dir, --exec-path, --config-env ...
    }
  }
  if (k >= args.length) return false;
  final sub = args[k];
  final rest = args.sublist(k + 1);
  if (rest.any(
    (a) =>
        a.startsWith('--output') ||
        a.startsWith('--ext-diff') ||
        a.startsWith('--exec') ||
        a.startsWith('--textconv') ||
        a.startsWith('--open-files-in-pager') ||
        a == '-O',
  )) {
    return false;
  }
  switch (sub) {
    case 'status' ||
        'log' ||
        'diff' ||
        'show' ||
        'rev-parse' ||
        'ls-files' ||
        'blame' ||
        'describe' ||
        'shortlog':
      return true;
    case 'reflog':
      return rest.isEmpty || rest.first == 'show' || rest.first.startsWith('-');
    case 'branch':
      return _onlyFlags(rest, {
        '-a', '--all', '-r', '--remotes', '-v', '-vv', '--verbose', '-l',
        '--list', '--show-current', '--merged', '--no-merged', '--contains',
        '--no-color', //
      });
    case 'remote':
      return rest.isEmpty || (rest.length == 1 && rest.first == '-v');
  }
  return false;
}
