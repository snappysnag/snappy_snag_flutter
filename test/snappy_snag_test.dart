import 'package:flutter/material.dart';
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

  test('SnappySnag trigger button default visibility based on mode', () {
    final snappy = SnappySnag();

    // Default for user mode is false
    snappy.initialize(
      apiKey: 'test_key',
      packageName: 'com.example.test',
      mode: SnappySnagMode.user,
    );
    expect(snappy.isTriggerButtonVisible.value, isFalse);

    // Default for dev mode is true
    snappy.initialize(
      apiKey: 'test_key',
      packageName: 'com.example.test',
      mode: SnappySnagMode.dev,
    );
    expect(snappy.isTriggerButtonVisible.value, isTrue);

    // Explicit override works for both
    snappy.initialize(
      apiKey: 'test_key',
      packageName: 'com.example.test',
      mode: SnappySnagMode.user,
      showTriggerButton: true,
    );
    expect(snappy.isTriggerButtonVisible.value, isTrue);

    snappy.initialize(
      apiKey: 'test_key',
      packageName: 'com.example.test',
      mode: SnappySnagMode.dev,
      showTriggerButton: false,
    );
    expect(snappy.isTriggerButtonVisible.value, isFalse);
  });

  test('SnappySnag trigger button visibility controls', () {
    final snappy = SnappySnag();
    snappy.initialize(
      apiKey: 'test_key',
      packageName: 'com.example.test',
      showTriggerButton: false,
    );

    expect(snappy.isTriggerButtonVisible.value, isFalse);
    expect(snappy.isTriggerButtonAlwaysVisible, isFalse);

    snappy.showTriggerButton();
    expect(snappy.isTriggerButtonVisible.value, isTrue);
    expect(snappy.isTriggerButtonAlwaysVisible, isTrue);

    snappy.hideTriggerButton();
    expect(snappy.isTriggerButtonVisible.value, isFalse);
    expect(snappy.isTriggerButtonAlwaysVisible, isFalse);

    snappy.setTriggerButtonVisibility(true);
    expect(snappy.isTriggerButtonVisible.value, isTrue);
  });

  testWidgets('SnappySnagHideButton hides and restores trigger button', (tester) async {
    final snappy = SnappySnag();
    snappy.initialize(
      apiKey: 'test_key',
      packageName: 'com.example.test',
      showTriggerButton: true,
    );
    expect(snappy.isTriggerButtonVisible.value, isTrue);

    // Mount SnappySnagHideButton
    await tester.pumpWidget(
      const SnappySnagHideButton(
        child: SizedBox(),
      ),
    );
    await tester.pump(); // allow postFrameCallback to fire

    expect(snappy.isTriggerButtonVisible.value, isFalse);

    // Unmount
    await tester.pumpWidget(const SizedBox());
    expect(snappy.isTriggerButtonVisible.value, isTrue);
  });
}
