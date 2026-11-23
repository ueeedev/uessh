/// System information read from a (mostly Linux) server over SSH.
library;

import '../../l10n/l10n.dart';

/// One read-only POSIX sh script; each section is introduced by `@@name`.
/// Wrapped in `sh -c` so it works whatever the user's login shell is.
const serverStatsCommand =
    "sh -c '"
    'LC_ALL=C; export LC_ALL; '
    'echo @@hostname; hostname 2>/dev/null || uname -n; '
    'echo @@os; if [ -r /etc/os-release ]; then . /etc/os-release; '
    'echo "\$PRETTY_NAME"; else uname -s; fi; '
    'echo @@kernel; uname -r; '
    'echo @@platform; uname -s; '
    'echo @@uptime; cat /proc/uptime 2>/dev/null; '
    'echo @@load; cat /proc/loadavg 2>/dev/null; '
    'echo @@nproc; nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null; '
    'echo @@stat; head -n 1 /proc/stat 2>/dev/null; '
    'echo @@mem; grep -E "^(MemTotal|MemAvailable):" /proc/meminfo 2>/dev/null; '
    'echo @@disk; df -kP / 2>/dev/null | tail -n 1; '
    'echo @@disks; df -kP -l 2>/dev/null | head -n 65 | tail -n +2; '
    'echo @@processes; '
    'ps -A -o pid= -o user= -o pcpu= -o rss= -o comm= 2>/dev/null '
    '| sort -k3,3nr | head -n 50; '
    "echo @@end'";

/// Capacity of one mounted filesystem, in bytes.
class DiskStats {
  const DiskStats({
    required this.device,
    required this.mountPoint,
    required this.total,
    required this.used,
    required this.available,
  });

  final String device;
  final String mountPoint;
  final int total;
  final int used;
  final int available;

  /// Accepts POSIX df rows and the equivalent rows emitted by PowerShell.
  static DiskStats? parse(String line) {
    final match = RegExp(r'^(.+?)\s+(\d+)\s+(\d+)\s+(\d+)(?:\s+\d+%\s+(.+))?$')
        .firstMatch(line.trim());
    if (match == null) return null;
    final total = int.tryParse(match[2]!);
    final used = int.tryParse(match[3]!);
    final available = int.tryParse(match[4]!);
    if (total == null || total <= 0 || used == null || available == null) {
      return null;
    }
    return DiskStats(
      device: match[1]!,
      mountPoint: match[5] ?? match[1]!,
      total: total * 1024,
      used: used * 1024,
      available: available * 1024,
    );
  }
}

/// A process snapshot. Only the executable name is collected, since full
/// command arguments can contain passwords or tokens.
class ProcessStats {
  const ProcessStats({
    required this.pid,
    required this.name,
    required this.cpuPercent,
    required this.memoryBytes,
    this.user,
  });

  final int pid;
  final String name;
  final String? user;
  final double cpuPercent;
  final int memoryBytes;

  static ProcessStats? parse(String line) {
    final match = RegExp(r'^\s*(\d+)\s+(\S+)\s+([\d.]+)\s+(\d+)\s+(.+)$')
        .firstMatch(line);
    if (match == null) return null;
    final pid = int.tryParse(match[1]!);
    final cpu = double.tryParse(match[3]!);
    final memory = int.tryParse(match[4]!);
    if (pid == null ||
        pid <= 0 ||
        cpu == null ||
        !cpu.isFinite ||
        memory == null) {
      return null;
    }
    return ProcessStats(
      pid: pid,
      name: match[5]!.trim(),
      user: match[2] == '-' ? null : match[2],
      cpuPercent: cpu,
      memoryBytes: memory * 1024,
    );
  }
}

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

enum ServerPlatform {
  windows,
  macos,
  linux;

  /// The kernel name is authoritative. Display names also support older
  /// collectors and snapshots that predate the platform section.
  static ServerPlatform? fromName(String? name) {
    final value = name?.toLowerCase() ?? '';
    if (value.contains('windows')) return windows;
    if (RegExp(r'\b(macos|mac os|os x|darwin)\b').hasMatch(value)) return macos;
    if (RegExp(
      r'\b(linux|ubuntu|debian|fedora|centos|alpine|arch|rhel|rocky|alma|opensuse|suse)\b',
    ).hasMatch(value)) {
      return linux;
    }
    return null;
  }
}

class ServerStats {
  const ServerStats({
    this.hostname,
    this.os,
    this.kernel,
    this.platform,
    this.uptime,
    this.load,
    this.cpuCount,
    this.cpuTimes,
    this.cpuPercent,
    this.memTotal,
    this.memAvailable,
    this.diskTotal,
    this.diskUsed,
    this.disks = const [],
    this.processes = const [],
  });

  final String? hostname;
  final String? os;
  final String? kernel;
  final ServerPlatform? platform;
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
  final List<DiskStats> disks;
  final List<ProcessStats> processes;

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

    final disks = [
      for (final line in sections['disks'] ?? <String>[])
        ?DiskStats.parse(line),
    ];
    // Older collectors only reported the root/system volume.
    if (disks.isEmpty) {
      if (first('disk') case final line?) {
        if (DiskStats.parse(line) case final disk?) disks.add(disk);
      }
    }
    final processes = [
      for (final line in sections['processes'] ?? <String>[])
        ?ProcessStats.parse(line),
    ]..sort((a, b) => b.cpuPercent.compareTo(a.cpuPercent));

    return ServerStats(
      hostname: first('hostname'),
      os: first('os'),
      kernel: first('kernel'),
      platform:
          ServerPlatform.fromName(first('platform') ?? first('os')) ??
          (first('platform') == null && cpuTimes != null
              ? ServerPlatform.linux
              : null),
      uptime: uptime,
      load: load,
      cpuCount: int.tryParse(first('nproc') ?? ''),
      cpuTimes: cpuTimes,
      cpuPercent: double.tryParse(first('cpupct') ?? ''),
      memTotal: memTotal,
      memAvailable: memAvailable,
      diskTotal: diskTotal,
      diskUsed: diskUsed,
      disks: disks,
      processes: processes,
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
