/// System information read from a (mostly Linux) server over SSH.
library;

import '../../l10n/l10n.dart';

/// One read-only POSIX sh script; each section is introduced by `@@name`.
/// Wrapped in `sh -c` so it works whatever the user's login shell is.
const serverStatsCommand =
    "sh -c '"
    'echo @@hostname; hostname 2>/dev/null || uname -n; '
    'echo @@os; if [ -r /etc/os-release ]; then . /etc/os-release; '
    'echo "\$PRETTY_NAME"; else uname -s; fi; '
    'echo @@kernel; uname -r; '
    'echo @@uptime; cat /proc/uptime 2>/dev/null; '
    'echo @@load; cat /proc/loadavg 2>/dev/null; '
    'echo @@nproc; nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null; '
    'echo @@stat; head -n 1 /proc/stat 2>/dev/null; '
    'echo @@mem; grep -E "^(MemTotal|MemAvailable):" /proc/meminfo 2>/dev/null; '
    'echo @@disk; df -kP / 2>/dev/null | tail -n 1; '
    "echo @@end'";

/// Cumulative CPU time from the first line of /proc/stat.
class CpuTimes {
  const CpuTimes({required this.total, required this.idle});

  final int total;
  final int idle;

  /// Busy fraction (0–1) between [earlier] and this sample.
  double? usageSince(CpuTimes earlier) {
    final dTotal = total - earlier.total;
    if (dTotal <= 0) return null;
    final busy = 1 - (idle - earlier.idle) / dTotal;
    return busy.clamp(0.0, 1.0);
  }
}

class ServerStats {
  const ServerStats({
    this.hostname,
    this.os,
    this.kernel,
    this.uptime,
    this.load,
    this.cpuCount,
    this.cpuTimes,
    this.cpuPercent,
    this.memTotal,
    this.memAvailable,
    this.diskTotal,
    this.diskUsed,
  });

  final String? hostname;
  final String? os;
  final String? kernel;
  final Duration? uptime;

  /// 1, 5 and 15 minute load averages.
  final List<double>? load;
  final int? cpuCount;
  final CpuTimes? cpuTimes;

  /// CPU use right now (0-100), when the system reports it directly
  /// (macOS, Windows) instead of as /proc/stat counters.
  final double? cpuPercent;

  /// Bytes.
  final int? memTotal;
  final int? memAvailable;
  final int? diskTotal;
  final int? diskUsed;

  int? get memUsed => (memTotal != null && memAvailable != null)
      ? memTotal! - memAvailable!
      : null;

  /// True when the resource numbers (Linux /proc) were available.
  bool get hasResources =>
      memTotal != null || cpuTimes != null || cpuPercent != null;

  static ServerStats parse(String output) {
    final sections = <String, List<String>>{};
    List<String>? current;
    for (final raw in output.split('\n')) {
      final line = raw.trimRight();
      if (line.startsWith('@@')) {
        current = sections.putIfAbsent(line.substring(2), () => []);
      } else if (current != null && line.trim().isNotEmpty) {
        current.add(line.trim());
      }
    }
    String? first(String name) {
      final lines = sections[name];
      return (lines == null || lines.isEmpty) ? null : lines.first;
    }

    final fields = RegExp(r'\s+');

    Duration? uptime;
    final up = double.tryParse(first('uptime')?.split(fields).first ?? '');
    if (up != null) uptime = Duration(seconds: up.round());

    List<double>? load;
    final loadParts = first('load')?.split(fields);
    if (loadParts != null && loadParts.length >= 3) {
      final values = loadParts.take(3).map(double.tryParse).toList();
      if (!values.contains(null)) load = values.cast<double>();
    }

    CpuTimes? cpuTimes;
    final stat = first('stat')?.split(fields);
    if (stat != null && stat.length > 5 && stat.first == 'cpu') {
      final nums = stat.skip(1).map(int.tryParse).whereType<int>().toList();
      // user nice system idle iowait irq softirq steal (guest is in user)
      final counted = nums.take(8).toList();
      if (counted.length >= 4) {
        cpuTimes = CpuTimes(
          total: counted.fold(0, (a, b) => a + b),
          idle: counted[3] + (counted.length > 4 ? counted[4] : 0),
        );
      }
    }

    int? memTotal, memAvailable;
    for (final line in sections['mem'] ?? <String>[]) {
      final m = RegExp(r'^(\w+):\s+(\d+)\s*kB').firstMatch(line);
      if (m == null) continue;
      final bytes = int.parse(m.group(2)!) * 1024;
      if (m.group(1) == 'MemTotal') memTotal = bytes;
      if (m.group(1) == 'MemAvailable') memAvailable = bytes;
    }

    int? diskTotal, diskUsed;
    final df = first('disk')?.split(fields);
    if (df != null && df.length >= 4) {
      final total = int.tryParse(df[1]), used = int.tryParse(df[2]);
      if (total != null && used != null) {
        diskTotal = total * 1024;
        diskUsed = used * 1024;
      }
    }

    return ServerStats(
      hostname: first('hostname'),
      os: first('os'),
      kernel: first('kernel'),
      uptime: uptime,
      load: load,
      cpuCount: int.tryParse(first('nproc') ?? ''),
      cpuTimes: cpuTimes,
      cpuPercent: double.tryParse(first('cpupct') ?? ''),
      memTotal: memTotal,
      memAvailable: memAvailable,
      diskTotal: diskTotal,
      diskUsed: diskUsed,
    );
  }
}

/// 1024-based, e.g. "3.2 GB".
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = (unit == 0 || value >= 100) ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// "3 天 4 小时", "5 小时 12 分钟", "8 分钟", "不到 1 分钟".
String formatDuration(Duration d) {
  final days = d.inDays, hours = d.inHours % 24, minutes = d.inMinutes % 60;
  final l = currentL10n;
  if (days > 0) {
    return hours > 0 ? l.durationDaysHours(days, hours) : l.durationDays(days);
  }
  if (d.inHours > 0) {
    return minutes > 0
        ? l.durationHoursMinutes(d.inHours, minutes)
        : l.durationHours(d.inHours);
  }
  if (d.inMinutes > 0) return l.durationMinutes(d.inMinutes);
  return currentL10n.durationUnderMinute;
}
