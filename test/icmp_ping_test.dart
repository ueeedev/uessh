import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/core/icmp_ping.dart';

void main() {
  test('checksum matches the RFC 1071 example', () {
    // RFC 1071 section 3: 00 01 f2 03 f4 f5 f6 f7 -> sum ddf2, checksum 220d
    final data = Uint8List.fromList([
      0x00,
      0x01,
      0xf2,
      0x03,
      0xf4,
      0xf5,
      0xf6,
      0xf7,
    ]);
    expect(icmpChecksum(data), 0x220d);
  });

  test('a built echo request verifies to zero checksum', () {
    final token = Uint8List.fromList(List.generate(16, (i) => i * 7));
    final p = buildEchoRequest(v6: false, id: 0x1234, seq: 1, token: token);
    expect(p[0], 8);
    expect(icmpChecksum(p), 0, reason: 'checksum over a valid packet is 0');
  });

  test('recognises our reply with and without an IPv4 header', () {
    final token = Uint8List.fromList(List.generate(16, (i) => 255 - i));
    final reply = buildEchoRequest(v6: false, id: 1, seq: 1, token: token)
      ..[0] = 0; // echo reply
    expect(isEchoReplyFor(reply, v6: false, token: token), isTrue);

    final ipHeader = Uint8List(20)..[0] = 0x45; // IPv4, 5 words
    final withHeader = Uint8List.fromList([...ipHeader, ...reply]);
    expect(isEchoReplyFor(withHeader, v6: false, token: token), isTrue);

    final otherToken = Uint8List(16);
    expect(isEchoReplyFor(reply, v6: false, token: otherToken), isFalse);
    final request = buildEchoRequest(v6: false, id: 1, seq: 1, token: token);
    expect(
      isEchoReplyFor(request, v6: false, token: token),
      isFalse,
      reason: 'a request is not a reply',
    );
  });

  test('pings localhost over IPv4 and IPv6 without the ping command', () async {
    final v4 = await icmpPing('127.0.0.1');
    expect(v4, isNotNull);
    expect(v4!.inMilliseconds, lessThan(500));
    expect(await icmpPing('::1'), isNotNull);
    expect(await icmpPing('localhost'), isNotNull);
  });

  test('an address that never answers times out as null', () async {
    final watch = Stopwatch()..start();
    final r = await icmpPing(
      '192.0.2.1',
      timeout: const Duration(milliseconds: 800),
    );
    expect(r, isNull);
    expect(watch.elapsedMilliseconds, lessThan(3000));
  });
}
