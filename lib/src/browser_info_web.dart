// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;


String getBrowserInfo() {
  try {
    final userAgent = js.context['navigator']['userAgent'] as String? ?? '';
    final ua = userAgent.toLowerCase();

    if (ua.contains('edg')) {
      final match = RegExp(r'edg/([0-9\.]+)').firstMatch(ua);
      return 'Edge ${match?.group(1) ?? ""}';
    } else if (ua.contains('chrome')) {
      final match = RegExp(r'chrome/([0-9\.]+)').firstMatch(ua);
      return 'Chrome ${match?.group(1) ?? ""}';
    } else if (ua.contains('safari') && !ua.contains('chrome') && !ua.contains('android')) {
      final match = RegExp(r'version/([0-9\.]+)').firstMatch(ua);
      return 'Safari ${match?.group(1) ?? ""}';
    } else if (ua.contains('firefox')) {
      final match = RegExp(r'firefox/([0-9\.]+)').firstMatch(ua);
      return 'Firefox ${match?.group(1) ?? ""}';
    }
    return userAgent.length > 30 ? '${userAgent.substring(0, 30)}...' : userAgent;
  } catch (e) {
    return 'Browser';
  }
}
