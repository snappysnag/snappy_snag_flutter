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

  test('SnappySnagUser sets and updates user info correctly', () {
    final snappy = SnappySnag();
    snappy.initialize(
      apiKey: 'test_key',
      packageName: 'com.example.test',
      user: const SnappySnagUser(
        id: 'user_123',
        email: 'test@example.com',
        name: 'Taro Yamada',
        customAttributes: {'plan': 'premium'},
      ),
    );

    expect(snappy.user?.id, 'user_123');
    expect(snappy.user?.email, 'test@example.com');
    expect(snappy.user?.name, 'Taro Yamada');
    expect(snappy.reporterUserId, 'user_123');
    expect(snappy.reporterEmail, 'test@example.com');
    expect(snappy.user?.toJson(), {
      'id': 'user_123',
      'email': 'test@example.com',
      'name': 'Taro Yamada',
      'plan': 'premium',
    });

    snappy.setUser(const SnappySnagUser(id: 'user_456', email: 'new@example.com'));
    expect(snappy.user?.id, 'user_456');
    expect(snappy.user?.email, 'new@example.com');

    snappy.clearUser();
    expect(snappy.user, isNull);
    expect(snappy.reporterUserId, isNull);
    expect(snappy.reporterEmail, isNull);
  });

  test('SnappySnag defaultNavigatorKey is always available', () {
    expect(SnappySnag.defaultNavigatorKey, isNotNull);
    expect(SnappySnag().navigatorKey, equals(SnappySnag.defaultNavigatorKey));
  });
}
