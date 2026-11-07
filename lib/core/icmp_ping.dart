/// ICMP echo ("ping") implemented inside the app, without launching the
/// system `ping` command.
///
/// - macOS / Linux: an unprivileged ICMP datagram socket
///   (`socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)`), the same mechanism the
///   system ping uses, called through dart:ffi.
/// - Windows: `IcmpSendEcho` from iphlpapi.dll (no admin rights, no
///   console window). IPv4 only.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Sends one echo request to [address] (an IP literal or host name) and
/// returns the round-trip time, or null if no reply came within
/// [timeout]. Throws [IcmpUnavailable] if the OS refused to open an ICMP
/// socket at all. Runs on a background isolate (the socket calls block).
Future<Duration?> icmpPing(
  String address, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final InternetAddress target;
  try {
    target = await _resolve(address);
  } on SocketException {
    return null; // name doesn't resolve: unreachable
  }
  final raw = target.rawAddress;
  final v6 = target.type == InternetAddressType.IPv6;
  final ms = timeout.inMilliseconds;
  final micros = await Isolate.run(
    () => Platform.isWindows
        ? _pingWindows(raw, v6, ms)
        : _pingPosix(raw, v6, ms),
  );
  return micros == null ? null : Duration(microseconds: micros);
}

class IcmpUnavailable implements Exception {
  IcmpUnavailable(this.message);
  final String message;
  @override
  String toString() => 'ICMP unavailable: $message';
}

Future<InternetAddress> _resolve(String address) async {
  final literal = InternetAddress.tryParse(address);
  if (literal != null) return literal;
  final all = await InternetAddress.lookup(address);
  return all.firstWhere(
    (a) => a.type == InternetAddressType.IPv4,
    orElse: () => all.first,
  );
}

// --- packet helpers (pure, unit-tested) ----------------------------------

/// Internet checksum (RFC 1071).
int icmpChecksum(Uint8List data) {
  var sum = 0;
  for (var i = 0; i + 1 < data.length; i += 2) {
    sum += (data[i] << 8) | data[i + 1];
  }
  if (data.length.isOdd) sum += data.last << 8;
  while (sum >> 16 != 0) {
    sum = (sum & 0xffff) + (sum >> 16);
  }
  return ~sum & 0xffff;
}

/// Echo request with a random [token] in the payload so the reply can be
/// recognised even where the kernel rewrites the identifier (Linux).
Uint8List buildEchoRequest({
  required bool v6,
  required int id,
  required int seq,
  required Uint8List token,
}) {
  final p = Uint8List(8 + token.length);
  p[0] = v6 ? 128 : 8; // echo request
  p[4] = id >> 8;
  p[5] = id & 0xff;
  p[6] = seq >> 8;
  p[7] = seq & 0xff;
  p.setRange(8, p.length, token);
  if (!v6) {
    // The kernel fills in the ICMPv6 checksum itself.
    final c = icmpChecksum(p);
    p[2] = c >> 8;
    p[3] = c & 0xff;
  }
  return p;
}

/// True if [packet] (as received, possibly with an IPv4 header in front,
/// as macOS delivers it) is the echo reply to our [token].
bool isEchoReplyFor(
  Uint8List packet, {
  required bool v6,
  required Uint8List token,
}) {
  var offset = 0;
  if (!v6 && packet.isNotEmpty && packet[0] >> 4 == 4) {
    offset = (packet[0] & 0x0f) * 4; // skip the IPv4 header
  }
  if (packet.length < offset + 8 + token.length) return false;
  if (packet[offset] != (v6 ? 129 : 0)) return false; // echo reply
  for (var i = 0; i < token.length; i++) {
    if (packet[offset + 8 + i] != token[i]) return false;
  }
  return true;
}

Uint8List _randomToken() {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(16, (_) => r.nextInt(256)));
}

// --- macOS / Linux ---------------------------------------------------------

typedef _SocketC = Int32 Function(Int32, Int32, Int32);
typedef _SocketD = int Function(int, int, int);
typedef _SetsockoptC = Int32 Function(
  Int32,
  Int32,
  Int32,
  Pointer<Void>,
  Uint32,
);
typedef _SetsockoptD = int Function(int, int, int, Pointer<Void>, int);
typedef _SendtoC = IntPtr Function(
  Int32,
  Pointer<Uint8>,
  IntPtr,
  Int32,
  Pointer<Uint8>,
  Uint32,
);
typedef _SendtoD = int Function(
  int,
  Pointer<Uint8>,
  int,
  int,
  Pointer<Uint8>,
  int,
);
typedef _RecvfromC = IntPtr Function(
  Int32,
  Pointer<Uint8>,
  IntPtr,
  Int32,
  Pointer<Uint8>,
  Pointer<Uint32>,
);
typedef _RecvfromD = int Function(
  int,
  Pointer<Uint8>,
  int,
  int,
  Pointer<Uint8>,
  Pointer<Uint32>,
);
typedef _CloseC = Int32 Function(Int32);
typedef _CloseD = int Function(int);

/// Returns the RTT in microseconds, or null on timeout.
int? _pingPosix(Uint8List addr, bool v6, int timeoutMs) {
  final mac = Platform.isMacOS;
  final libc = DynamicLibrary.process();
  final socket = libc.lookupFunction<_SocketC, _SocketD>('socket');
  final setsockopt = libc.lookupFunction<_SetsockoptC, _SetsockoptD>(
    'setsockopt',
  );
  final sendto = libc.lookupFunction<_SendtoC, _SendtoD>('sendto');
  final recvfrom = libc.lookupFunction<_RecvfromC, _RecvfromD>('recvfrom');
  final close = libc.lookupFunction<_CloseC, _CloseD>('close');

  const sockDgram = 2;
  final af = v6 ? (mac ? 30 : 10) : 2; // AF_INET6 is 30 on macOS, 10 on Linux
  final proto = v6 ? 58 : 1; // IPPROTO_ICMPV6 / IPPROTO_ICMP
  final solSocket = mac ? 0xffff : 1;
  final soRcvTimeo = mac ? 0x1006 : 20;

  final fd = socket(af, sockDgram, proto);
  if (fd < 0) throw IcmpUnavailable('socket() failed');

  // sockaddr_in (16 bytes) / sockaddr_in6 (28 bytes). macOS has a leading
  // length byte and a 1-byte family; Linux a 2-byte family.
  final saLen = v6 ? 28 : 16;
  final sa = calloc<Uint8>(saLen);
  final tv = calloc<Uint8>(16); // struct timeval: 8-byte seconds + usec
  final buf = calloc<Uint8>(1500);
  final from = calloc<Uint8>(128);
  final fromLen = calloc<Uint32>();
  try {
    if (mac) {
      sa[0] = saLen;
      sa[1] = af;
    } else {
      sa[0] = af & 0xff;
      sa[1] = af >> 8;
    }
    sa
        .asTypedList(saLen)
        .setRange(v6 ? 8 : 4, (v6 ? 8 : 4) + addr.length, addr);

    // struct timeval: 8-byte seconds, then microseconds (int32 on macOS,
    // int64 on Linux; little-endian, so the low 4 bytes match either way).
    final t = ByteData(16)
      ..setInt64(0, timeoutMs ~/ 1000, Endian.little)
      ..setInt32(8, (timeoutMs % 1000) * 1000, Endian.little);
    tv.asTypedList(16).setAll(0, t.buffer.asUint8List());
    setsockopt(fd, solSocket, soRcvTimeo, tv.cast(), 16);

    final token = _randomToken();
    final id = Random().nextInt(0xffff);
    final packet = buildEchoRequest(v6: v6, id: id, seq: 1, token: token);
    buf.asTypedList(packet.length).setAll(0, packet);

    final watch = Stopwatch()..start();
    if (sendto(fd, buf, packet.length, 0, sa, saLen) < 0) return null;

    // Read until our reply arrives or the time is up (other ICMP traffic
    // can show up on the same socket).
    while (watch.elapsedMilliseconds < timeoutMs) {
      fromLen.value = 128;
      final n = recvfrom(fd, buf, 1500, 0, from, fromLen);
      if (n < 0) return null; // timed out (or error)
      if (isEchoReplyFor(
        Uint8List.fromList(buf.asTypedList(n)),
        v6: v6,
        token: token,
      )) {
        return watch.elapsedMicroseconds;
      }
    }
    return null;
  } finally {
    close(fd);
    calloc.free(sa);
    calloc.free(tv);
    calloc.free(buf);
    calloc.free(from);
    calloc.free(fromLen);
  }
}

// --- Windows ----------------------------------------------------------------

typedef _IcmpCreateC = IntPtr Function();
typedef _IcmpCreateD = int Function();
typedef _IcmpCloseC = Int32 Function(IntPtr);
typedef _IcmpCloseD = int Function(int);
typedef _IcmpSendEchoC = Uint32 Function(
  IntPtr,
  Uint32,
  Pointer<Uint8>,
  Uint16,
  Pointer<Void>,
  Pointer<Uint8>,
  Uint32,
  Uint32,
);
typedef _IcmpSendEchoD = int Function(
  int,
  int,
  Pointer<Uint8>,
  int,
  Pointer<Void>,
  Pointer<Uint8>,
  int,
  int,
);

/// Returns the RTT in microseconds, or null on timeout. Untested on real
/// Windows yet.
int? _pingWindows(Uint8List addr, bool v6, int timeoutMs) {
  if (v6) return null; // IcmpSendEcho is IPv4-only
  final lib = DynamicLibrary.open('iphlpapi.dll');
  final create = lib.lookupFunction<_IcmpCreateC, _IcmpCreateD>(
    'IcmpCreateFile',
  );
  final closeHandle = lib.lookupFunction<_IcmpCloseC, _IcmpCloseD>(
    'IcmpCloseHandle',
  );
  final send = lib.lookupFunction<_IcmpSendEchoC, _IcmpSendEchoD>(
    'IcmpSendEcho',
  );

  final handle = create();
  if (handle == -1 || handle == 0) {
    throw IcmpUnavailable('IcmpCreateFile failed');
  }
  final token = _randomToken();
  final data = calloc<Uint8>(token.length);
  // ICMP_ECHO_REPLY (32 bytes on 64-bit) + payload + 8 bytes of slack.
  final replySize = 64 + token.length + 8;
  final reply = calloc<Uint8>(replySize);
  try {
    data.asTypedList(token.length).setAll(0, token);
    // IPAddr is the address in network byte order, read as a native
    // (little-endian) uint32.
    final ip = ByteData.sublistView(addr).getUint32(0, Endian.little);
    final watch = Stopwatch()..start();
    final count = send(
      handle,
      ip,
      data,
      token.length,
      nullptr,
      reply,
      replySize,
      timeoutMs,
    );
    watch.stop();
    if (count == 0) return null;
    final status = ByteData.sublistView(reply.asTypedList(8))
        .getUint32(4, Endian.little);
    if (status != 0) return null; // IP_SUCCESS
    return watch.elapsedMicroseconds;
  } finally {
    closeHandle(handle);
    calloc.free(data);
    calloc.free(reply);
  }
}
