import 'browser_info_stub.dart'
    if (dart.library.js) 'browser_info_web.dart';

String getBrowserInfoHelper() {
  return getBrowserInfo();
}
