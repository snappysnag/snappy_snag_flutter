import 'package:flutter_test/flutter_test.dart';
import 'package:snappy_snag/snappy_snag.dart';

void main() {
  test('SnappySnag singleton initialization test', () {
    final snappy = SnappySnag();
    snappy.initialize(
      apiKey: 'test_api_key_123456789',
      packageName: 'com.example.test',
    );
    expect(snappy, isNotNull);
  });

  test(
    'SnappySnag initializes without throwing error when packageName is empty',
    () {
      final snappy = SnappySnag();
      expect(
        () => snappy.initialize(
          apiKey: 'test_api_key_123456789',
          packageName: '   ',
        ),
        returnsNormally,
      );
    },
  );
}
