## 0.0.1

* Initial release of SnappySnag Flutter SDK.
* Supported Shake gesture and floating overlay trigger button to capture screenshots.
* Integrated Widget Tree layout dumper (up to a depth of 10 levels) for debugging.
* Supported package name locking for authorized API requests.
* Added option to completely disable the SDK in App Store / Google Play production builds.
* Added `enableLogging` parameter to `SnappySnag.initialize()`. Console logging is now muted by default (`enableLogging: false`) to avoid polluting the host application's console. Critical configuration errors and security alerts continue to be printed unconditionally.
