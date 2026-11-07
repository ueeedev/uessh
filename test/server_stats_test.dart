import 'package:flutter_test/flutter_test.dart';
import 'package:uessh/features/terminal/server_stats.dart';

const _ubuntu = '''
@@hostname
web-01
@@os
Ubuntu 22.04.5 LTS
@@kernel
5.15.0-181-generic
@@uptime
5299138.52 10403912.31
@@load
0.01 0.05 0.06 1/183 123456
@@nproc
2
@@stat
cpu  1000 50 500 8000 200 0 30 0 0 0
@@mem
MemTotal:        1977940 kB
MemAvailable:     992640 kB
@@disk
/dev/vda2       51485392 25122428  24148640  51% /
@@end
''';

void main() {
  test('parses a typical Linux server', () {
    final s = ServerStats.parse(_ubuntu);
    expect(s.hostname, 'web-01');
    expect(s.os, 'Ubuntu 22.04.5 LTS');
    expect(s.kernel, '5.15.0-181-generic');
    expect(s.uptime, const Duration(seconds: 5299139));
    expect(s.load, [0.01, 0.05, 0.06]);
    expect(s.cpuCount, 2);
    expect(s.cpuTimes!.total, 1000 + 50 + 500 + 8000 + 200 + 0 + 30 + 0);
    expect(s.cpuTimes!.idle, 8000 + 200);
    expect(s.memTotal, 1977940 * 1024);
    expect(s.memUsed, (1977940 - 992640) * 1024);
    expect(s.diskTotal, 51485392 * 1024);
    expect(s.diskUsed, 25122428 * 1024);
    expect(s.hasResources, isTrue);
  });

  test('CPU usage comes from the difference between two samples', () {
    const a = CpuTimes(total: 1000, idle: 800);
    const b = CpuTimes(total: 1100, idle: 870); // 30 of 100 ticks busy
    expect(b.usageSince(a), closeTo(0.3, 1e-9));
    expect(a.usageSince(a), isNull, reason: 'no time passed');
  });

  test('non-Linux servers (no /proc) still give the basics', () {
    final s = ServerStats.parse('''
@@hostname
mac-mini
@@os
Darwin
@@kernel
24.1.0
@@uptime
@@load
@@nproc
8
@@stat
@@mem
@@disk
/dev/disk3s1s1 482797652 10204104 300213456 4% /
@@end
''');
    expect(s.hostname, 'mac-mini');
    expect(s.os, 'Darwin');
    expect(s.uptime, isNull);
    expect(s.load, isNull);
    expect(s.cpuTimes, isNull);
    expect(s.memTotal, isNull);
    expect(s.hasResources, isFalse);
    expect(s.diskTotal, 482797652 * 1024);
  });

  test('garbage input does not throw', () {
    final s = ServerStats.parse('sh: 1: not found\n@@load\nabc def\n');
    expect(s.hostname, isNull);
    expect(s.load, isNull);
  });

  test('the command is wrapped in sh -c with balanced quotes', () {
    expect(serverStatsCommand, startsWith("sh -c '"));
    expect(serverStatsCommand, endsWith("'"));
    expect("'".allMatches(serverStatsCommand).length, 2);
  });

  test('formatBytes and formatDuration', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(2025410560), '1.9 GB');
    expect(formatBytes(52721041408), '49.1 GB');
    expect(formatDuration(const Duration(seconds: 30)), '不到 1 分钟');
    expect(formatDuration(const Duration(minutes: 8)), '8 分钟');
    expect(formatDuration(const Duration(hours: 5, minutes: 12)), '5 小时 12 分钟');
    expect(formatDuration(const Duration(days: 3, hours: 4)), '3 天 4 小时');
    expect(formatDuration(const Duration(days: 61)), '61 天');
  });
}
