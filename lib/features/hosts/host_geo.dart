import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_log.dart';
import '../../core/app_providers.dart';
import '../../core/json_file.dart';
import 'host.dart';
import 'hosts_providers.dart';

/// Where a host's server is, from ipwho.is.
class HostGeo {
  const HostGeo({
    required this.countryCode,
    required this.country,
    this.region,
    this.city,
    this.flagSvg,
  });

  final String countryCode;
  final String country;
  final String? region;
  final String? city;

  /// The country flag (ipwho.is `flag.img`), when downloaded.
  final String? flagSvg;

  /// "City, Region, Country" without blanks or repeats.
  String get place {
    final parts = <String>[];
    for (final p in [city, region, country]) {
      if (p != null && p.isNotEmpty && !parts.contains(p)) parts.add(p);
    }
    return parts.join(', ');
  }
}

/// Network side of the lookup, replaceable in tests.
abstract class GeoApi {
  /// The IP an address (name or IP) points to, or null if it can't be found.
  Future<InternetAddress?> resolve(String address);

  /// ipwho.is answer for [ip]. Throws on network errors.
  Future<Map<String, Object?>> lookup(String ip);

  /// Downloads a flag image. Throws on network errors.
  Future<String> download(Uri url);
}

class IpWhoIsApi implements GeoApi {
  static const _timeout = Duration(seconds: 8);
  static const _maxFlagBytes = 256 * 1024;

  @override
  Future<InternetAddress?> resolve(String address) async {
    final ip = InternetAddress.tryParse(address);
    if (ip != null) return ip;
    try {
      final found = await InternetAddress.lookup(address).timeout(_timeout);
      if (found.isEmpty) return null;
      return found.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => found.first,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, Object?>> lookup(String ip) async {
    final text = await _get(Uri.https('ipwho.is', '/$ip'), 64 * 1024);
    return (jsonDecode(text) as Map).cast<String, Object?>();
  }

  @override
  Future<String> download(Uri url) => _get(url, _maxFlagBytes);

  Future<String> _get(Uri url, int maxBytes) async {
    final client = HttpClient()
      ..connectionTimeout = _timeout
      ..userAgent = 'uessh';
    try {
      final req = await client.getUrl(url).timeout(_timeout);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}', uri: url);
      }
      final bytes = <int>[];
      await for (final chunk in res.timeout(_timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          throw HttpException('Response too large', uri: url);
        }
      }
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      client.close(force: true);
    }
  }
}

final geoApiProvider = Provider<GeoApi>((ref) => IpWhoIsApi());

/// True for addresses ipwho.is can't place: private, loopback, link-local.
bool isPrivateAddress(InternetAddress ip) {
  if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) return true;
  final b = ip.rawAddress;
  if (ip.type == InternetAddressType.IPv4) {
    return b[0] == 10 ||
        b[0] == 0 ||
        (b[0] == 172 && b[1] >= 16 && b[1] < 32) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 100 && b[1] >= 64 && b[1] < 128); // carrier-grade NAT
  }
  return (b[0] & 0xfe) == 0xfc; // IPv6 unique local fc00::/7
}

/// Key for [hostGeoProvider]'s map.
String hostGeoKey(String address) => address.trim().toLowerCase();

/// Looks up where each host is and keeps the answers (and flag images) on
/// disk, so each address is asked about once a month at most. Only hosts
/// whose icon is a flag are looked up. State maps host address -> where it is;
/// addresses that can't be placed are left out.
class HostGeoNotifier extends Notifier<Map<String, HostGeo>> {
  static const _okFor = Duration(days: 30);
  static const _noneFor = Duration(days: 1);

  late final Directory _dir;
  Map<String, Map<String, Object?>> _cache = {};
  Future<void>? _loaded;
  final _queue = <String>[];
  final _seen = <String>{};
  bool _running = false;

  @override
  Map<String, HostGeo> build() {
    _dir = Directory('${ref.watch(dataDirProvider).path}/geo');
    ref.listen(hostsProvider, (_, next) {
      final hosts = next.value?.hosts;
      if (hosts != null) _onHosts(hosts);
    }, fireImmediately: true);
    return const {};
  }

  JsonFile get _cacheFile => JsonFile(File('${_dir.path}/cache.json'));
  File _flagFile(String code) => File('${_dir.path}/flags/$code.svg');

  /// Only hosts set to show a flag are looked up.
  void _onHosts(List<Host> hosts) {
    for (final h in hosts) {
      if (h.icon.kind == HostIconKind.flag) _enqueue(h.address);
    }
  }

  /// Looks up [address] now (the host editor's preview, before saving).
  void request(String address) => _enqueue(address);

  void _enqueue(String raw) {
    final address = hostGeoKey(raw);
    if (address.isEmpty || !_seen.add(address)) return;
    _queue.add(address);
    unawaited(_drain());
  }

  /// One lookup at a time, to stay well inside ipwho.is limits.
  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      await (_loaded ??= _loadCache());
      while (_queue.isNotEmpty && ref.mounted) {
        final address = _queue.removeAt(0);
        try {
          await _place(address);
        } catch (e) {
          // Offline or the service is down: try again next launch or
          // when the host list changes.
          _seen.remove(address);
          log.warn('geo', 'Lookup for $address failed: $e');
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _loadCache() async {
    try {
      final data = await _cacheFile.read();
      if (data is Map) {
        _cache = {
          for (final e in data.entries)
            if (e.value is Map)
              e.key as String: (e.value as Map).cast<String, Object?>(),
        };
      }
    } catch (e) {
      log.warn('geo', 'Could not read the location cache: $e');
    }
  }

  Future<void> _place(String address) async {
    var entry = _cache[address];
    if (entry == null || _expired(entry)) {
      entry = await _fetch(address);
      _cache[address] = entry;
      await _cacheFile.write(_cache);
    }
    final geo = await _toGeo(entry);
    if (!ref.mounted) return;
    if (geo == null) {
      if (state.containsKey(address)) state = {...state}..remove(address);
    } else {
      state = {...state, address: geo};
    }
  }

  bool _expired(Map<String, Object?> entry) {
    final at = DateTime.tryParse(entry['at'] as String? ?? '');
    if (at == null) return true;
    final ok = entry['countryCode'] != null;
    return DateTime.now().difference(at) > (ok ? _okFor : _noneFor);
  }

  Future<Map<String, Object?>> _fetch(String address) async {
    final api = ref.read(geoApiProvider);
    final now = DateTime.now().toIso8601String();
    final ip = await api.resolve(address);
    if (ip == null || isPrivateAddress(ip)) return {'at': now};

    final json = await api.lookup(ip.address);
    if (json['success'] != true) {
      log.info('geo', 'No location for $address: ${json['message']}');
      return {'at': now, 'ip': ip.address};
    }
    final code = (json['country_code'] as String? ?? '').toLowerCase();
    if (!RegExp(r'^[a-z]{2}$').hasMatch(code)) {
      return {'at': now, 'ip': ip.address};
    }
    final flag = json['flag'];
    final flagUrl = flag is Map ? flag['img'] as String? : null;
    final entry = <String, Object?>{
      'at': now,
      'ip': ip.address,
      'countryCode': code,
      'country': json['country'] as String? ?? code.toUpperCase(),
      'region': json['region'] as String?,
      'city': json['city'] as String?,
      'flagUrl': flagUrl,
    };
    await _ensureFlag(code, flagUrl);
    return entry;
  }

  /// Downloads the flag once per country; it never changes.
  Future<void> _ensureFlag(String code, String? flagUrl) async {
    final file = _flagFile(code);
    if (await file.exists()) return;
    final url = Uri.tryParse(flagUrl ?? '');
    if (url == null || url.scheme != 'https') return;
    try {
      final svg = await ref.read(geoApiProvider).download(url);
      if (!svg.contains('<svg')) return;
      await file.parent.create(recursive: true);
      await file.writeAsString(svg);
    } catch (e) {
      log.warn('geo', 'Flag download for $code failed: $e');
    }
  }

  Future<HostGeo?> _toGeo(Map<String, Object?> entry) async {
    final code = entry['countryCode'] as String?;
    if (code == null) return null;
    final file = _flagFile(code);
    if (!await file.exists()) {
      await _ensureFlag(code, entry['flagUrl'] as String?);
    }
    return HostGeo(
      countryCode: code,
      country: entry['country'] as String? ?? code.toUpperCase(),
      region: entry['region'] as String?,
      city: entry['city'] as String?,
      flagSvg: await file.exists() ? await file.readAsString() : null,
    );
  }
}

final hostGeoProvider = NotifierProvider<HostGeoNotifier, Map<String, HostGeo>>(
  HostGeoNotifier.new,
);
