import 'dart:io';

/// Opens [url] in the default browser.
Future<void> openInBrowser(String url) async {
  if (Platform.isMacOS) {
    await Process.run('open', [url]);
  } else if (Platform.isWindows) {
    await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
  } else {
    await Process.run('xdg-open', [url]);
  }
}
