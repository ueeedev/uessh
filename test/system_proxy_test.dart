import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/core/system_proxy.dart';

void main() {
  group('macOS scutil --proxy parser', () {
    test('parses HTTP/HTTPS proxy and ExceptionsList', () {
      const sample = '''
<dictionary> {
  ExceptionsList : <array> {
    0 : *zhihu.com
    1 : localhost
    2 : *.local
    3 : 127.*
    4 : 192.168.0.0/16
  }
  FTPPassive : 1
  HTTPEnable : 1
  HTTPPort : 7890
  HTTPProxy : 127.0.0.1
  HTTPSEnable : 1
  HTTPSPort : 7890
  HTTPSProxy : 127.0.0.1
  SOCKSEnable : 1
  SOCKSPort : 7890
  SOCKSProxy : 127.0.0.1
}
''';
      final cfg = parseMacOsScutilProxy(sample);
      expect(cfg.httpProxy, '127.0.0.1:7890');
      expect(cfg.httpsProxy, '127.0.0.1:7890');
      expect(
        cfg.resolveFor(Uri.parse('https://api.deepseek.com/chat/completions')),
        'PROXY 127.0.0.1:7890; DIRECT',
      );
      expect(
        cfg.resolveFor(Uri.parse('https://api.openai.com/v1/models')),
        'PROXY 127.0.0.1:7890; DIRECT',
      );
      expect(
        cfg.resolveFor(Uri.parse('http://example.com')),
        'PROXY 127.0.0.1:7890; DIRECT',
      );
      // ExceptionsList & loopback bypass the proxy.
      expect(cfg.resolveFor(Uri.parse('https://www.zhihu.com')), 'DIRECT');
      expect(cfg.resolveFor(Uri.parse('http://nas.local:8080')), 'DIRECT');
      expect(cfg.resolveFor(Uri.parse('http://192.168.1.50:8000')), 'DIRECT');
      expect(cfg.resolveFor(Uri.parse('http://127.0.0.1:11434')), 'DIRECT');
      expect(cfg.resolveFor(Uri.parse('http://localhost:11434')), 'DIRECT');
    });

    test('returns direct when HTTP/HTTPS proxies are disabled', () {
      const disabled = '''
<dictionary> {
  HTTPEnable : 0
  HTTPPort : 7890
  HTTPProxy : 127.0.0.1
  HTTPSEnable : 0
  HTTPSPort : 7890
  HTTPSProxy : 127.0.0.1
}
''';
      final cfg = parseMacOsScutilProxy(disabled);
      expect(cfg.hasProxy, isFalse);
      expect(cfg.resolveFor(Uri.parse('https://api.deepseek.com')), 'DIRECT');
    });
  });

  group('Windows reg query parser', () {
    test('parses single ProxyServer and ProxyOverride including <local>', () {
      const sample = r'''
HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings
    ProxyEnable    REG_DWORD    0x1
    ProxyServer    REG_SZ    127.0.0.1:7890
    ProxyOverride    REG_SZ    localhost;127.*;10.*;192.168.*;*.corp.internal;<local>
''';
      final cfg = parseWindowsRegProxy(sample);
      expect(cfg.httpProxy, '127.0.0.1:7890');
      expect(cfg.httpsProxy, '127.0.0.1:7890');
      expect(
        cfg.resolveFor(Uri.parse('https://api.anthropic.com/v1/messages')),
        'PROXY 127.0.0.1:7890; DIRECT',
      );
      expect(cfg.resolveFor(Uri.parse('https://git.corp.internal')), 'DIRECT');
      expect(cfg.resolveFor(Uri.parse('http://intranet:8080')), 'DIRECT');
      expect(cfg.resolveFor(Uri.parse('http://10.0.0.5:8080')), 'DIRECT');
    });

    test(
      'parses per-protocol ProxyServer and ignores disabled ProxyEnable',
      () {
        const perProto = r'''
HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings
    ProxyEnable    REG_DWORD    0x1
    ProxyServer    REG_SZ    http=127.0.0.1:8080;https=http://127.0.0.1:8443;socks=127.0.0.1:1080
''';
        final cfg = parseWindowsRegProxy(perProto);
        expect(cfg.httpProxy, '127.0.0.1:8080');
        expect(cfg.httpsProxy, '127.0.0.1:8443');
        expect(
          cfg.resolveFor(Uri.parse('http://example.com')),
          'PROXY 127.0.0.1:8080; DIRECT',
        );
        expect(
          cfg.resolveFor(Uri.parse('https://example.com')),
          'PROXY 127.0.0.1:8443; DIRECT',
        );

        const off = r'''
HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings
    ProxyEnable    REG_DWORD    0x0
    ProxyServer    REG_SZ    127.0.0.1:7890
''';
        expect(parseWindowsRegProxy(off).hasProxy, isFalse);
      },
    );
  });

  group('SystemProxyResolver', () {
    test(
      'prefers explicit env proxy, falls back to OS proxy, caches by TTL',
      () {
        var loads = 0;
        var now = DateTime(2026, 11, 25, 10, 0, 0);
        var env = <String, String>{};
        var osProxy = const SystemProxyConfig(
          httpProxy: '127.0.0.1:7890',
          httpsProxy: '127.0.0.1:7890',
        );

        final resolver = SystemProxyResolver(
          ttl: const Duration(seconds: 5),
          loadSystemProxy: () {
            loads++;
            return osProxy;
          },
          readEnvironment: () => env,
          now: () => now,
        );

        // No env proxy (Finder/GUI launch): uses OS system proxy.
        expect(
          resolver.findProxy(Uri.parse('https://api.deepseek.com')),
          'PROXY 127.0.0.1:7890; DIRECT',
        );
        expect(loads, 1);

        // Cached within TTL.
        now = now.add(const Duration(seconds: 3));
        expect(
          resolver.findProxy(Uri.parse('https://api.openai.com')),
          'PROXY 127.0.0.1:7890; DIRECT',
        );
        expect(loads, 1);

        // After TTL, reloads live OS proxy (e.g. user turned proxy off).
        now = now.add(const Duration(seconds: 3));
        osProxy = SystemProxyConfig.direct;
        expect(
          resolver.findProxy(Uri.parse('https://api.openai.com')),
          'DIRECT',
        );
        expect(loads, 2);

        // Explicit env proxy overrides OS proxy.
        env = {'HTTPS_PROXY': 'http://127.0.0.1:9999'};
        expect(
          resolver.findProxy(Uri.parse('https://api.deepseek.com')),
          'PROXY 127.0.0.1:9999',
        );

        // Loopback is always DIRECT even with env proxy set.
        expect(
          resolver.findProxy(Uri.parse('http://127.0.0.1:11434/v1/models')),
          'DIRECT',
        );
      },
    );

    test(
      'SystemProxyHttpOverrides applies findProxy to created HttpClients',
      () {
        final overrides = SystemProxyHttpOverrides(
          resolver: SystemProxyResolver(
            loadSystemProxy: () =>
                const SystemProxyConfig(httpsProxy: '127.0.0.1:7890'),
            readEnvironment: () => const {},
          ),
        );
        final client = overrides.createHttpClient(null);
        addTearDown(() => client.close(force: true));
        expect(
          overrides.resolver.findProxy(Uri.parse('https://api.deepseek.com')),
          'PROXY 127.0.0.1:7890; DIRECT',
        );
      },
    );
  });
}
