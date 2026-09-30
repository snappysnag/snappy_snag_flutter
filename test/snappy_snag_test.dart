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
    'SnappySnag initializes without throwing error when packageName is omitted or empty',
    () {
      final snappy = SnappySnag();
      expect(
        () => snappy.initialize(
          apiKey: 'test_api_key_123456789',
        ),
        returnsNormally,
      );
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

  test('SnappySnag trigger button default visibility is false for all modes', () {
    final snappy = SnappySnag();

    // Default for user mode is false
    snappy.initialize(
      apiKey: 'test_key',
      packageName: 'com.example.test',
      mode: SnappySnagMode.user,
    );
    expect(snappy.isTriggerButtonVisible.value, isFalse);

    // Default for dev mode is now also false (secure by default)
    snappy.initialize(
      apiKey: 'test_key',
      packageName: 'com.example.test',
      mode: SnappySnagMode.dev,
    );
    expect(snappy.isTriggerButtonVisible.value, isFalse);

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
      showTriggerButton: true,
    );
    expect(snappy.isTriggerButtonVisible.value, isTrue);
  });

  test('SnappySnag enableWidgetTree default is true and can be disabled', () {
    final snappy = SnappySnag();

    snappy.initialize(
      apiKey: 'test_key',
    );
    expect(snappy.enableWidgetTree, isTrue);

    snappy.initialize(
      apiKey: 'test_key',
      enableWidgetTree: false,
    );
    expect(snappy.enableWidgetTree, isFalse);
  });

  test('SnappySnag enableShakeTrigger default is true and can be configured', () {
    final snappy = SnappySnag();

    snappy.initialize(
      apiKey: 'test_key',
    );
    expect(snappy.enableShakeTrigger, isTrue);

    snappy.initialize(
      apiKey: 'test_key',
      enableShakeTrigger: false,
    );
    expect(snappy.enableShakeTrigger, isFalse);
  });

  test('SnappySnag enableLogging default is false and can be configured', () {
    final snappy = SnappySnag();

    snappy.initialize(
      apiKey: 'test_key',
    );
    expect(snappy.enableLogging, isFalse);

    snappy.initialize(
      apiKey: 'test_key',
      enableLogging: true,
    );
    expect(snappy.enableLogging, isTrue);

    snappy.initialize(
      apiKey: 'test_key',
      enableLogging: false,
    );
    expect(snappy.enableLogging, isFalse);
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

  test('DrawingPoint JSON serialization and deserialization test', () {
    final point = DrawingPoint(
      offsets: [const Offset(10, 20), const Offset(30, 40)],
      color: const Color(0xFFEF4444),
      strokeWidth: 4.0,
      recordedSize: const Size(375, 812),
      tool: SnappyDrawingTool.redPen,
      rect: const Rect.fromLTWH(5, 5, 50, 50),
    );

    final json = point.toJson();
    expect(json['tool'], 'redPen');
    expect(json['color'], const Color(0xFFEF4444).toARGB32());
    expect(json['rect'], {
      'left': 5.0,
      'top': 5.0,
      'right': 55.0,
      'bottom': 55.0,
    });

    final restored = DrawingPoint.fromJson(json);
    expect(restored.tool, SnappyDrawingTool.redPen);
    expect(restored.strokeWidth, 4.0);
    expect(restored.recordedSize.width, 375);
    expect(restored.recordedSize.height, 812);
    expect(restored.rect, const Rect.fromLTWH(5, 5, 50, 50));
    expect(restored.offsets.length, 2);
    expect(restored.offsets[0], const Offset(10, 20));
  });

  test('SnappyPin JSON serialization and deserialization test', () {
    final pin = SnappyPin(
      id: 'pin_123',
      number: 1,
      xRatio: 0.45,
      yRatio: 0.85,
      comment: 'Button is misaligned',
    );

    final json = pin.toJson();
    expect(json['id'], 'pin_123');
    expect(json['number'], 1);
    expect(json['x'], 0.45);
    expect(json['y'], 0.85);
    expect(json['comment'], 'Button is misaligned');

    final restored = SnappyPin.fromJson(json);
    expect(restored.id, 'pin_123');
    expect(restored.number, 1);
    expect(restored.xRatio, 0.45);
    expect(restored.yRatio, 0.85);
    expect(restored.comment, 'Button is misaligned');
  });

  testWidgets('WidgetTreeDumper findTargetAtPosition and resolveTargetPosition test', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('my_test_button'),
              onPressed: () {},
              child: const Text('はじめる'),
            ),
          ),
        ),
      ),
    );

    final context = tester.element(find.byType(ElevatedButton));
    final btnRenderBox = context.findRenderObject() as RenderBox;
    final btnCenter = btnRenderBox.localToGlobal(btnRenderBox.size.center(Offset.zero));

    final target = WidgetTreeDumper.findTargetAtPosition(context, btnCenter);
    expect(target, isNotNull);
    expect(target?.widgetType.contains('Button'), isTrue);

    final resolved = WidgetTreeDumper.resolveTargetPosition(context, target!);
    expect(resolved, isNotNull);
    expect(resolved, equals(btnCenter));
  });

  testWidgets('WidgetTreeDumper disambiguates multiple common buttons by text and position', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ElevatedButton(
                onPressed: () {},
                child: const Row(
                  children: [
                    Icon(Icons.arrow_forward),
                    Text('キャンセル'),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () {},
                child: const Row(
                  children: [
                    Icon(Icons.arrow_forward),
                    Text('保存'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // 1つ目のボタンの矢印アイコンをタップしたと想定
    final icon1Context = tester.element(find.byType(Icon).first);
    final icon1Box = icon1Context.findRenderObject() as RenderBox;
    final icon1Center = icon1Box.localToGlobal(icon1Box.size.center(Offset.zero));

    final target1 = WidgetTreeDumper.findTargetAtPosition(icon1Context, icon1Center);
    expect(target1, isNotNull);
    // アイコン部分をタップしても、親ボタンの子孫テキスト「キャンセル」が自動抽出されていること
    expect(target1?.widgetText, 'キャンセル');

    // 2つ目のボタンの矢印アイコンをタップしたと想定
    final icon2Context = tester.element(find.byType(Icon).last);
    final icon2Box = icon2Context.findRenderObject() as RenderBox;
    final icon2Center = icon2Box.localToGlobal(icon2Box.size.center(Offset.zero));

    final target2 = WidgetTreeDumper.findTargetAtPosition(icon2Context, icon2Center);
    expect(target2, isNotNull);
    // アイコン部分をタップしても、親ボタンの子孫テキスト「保存」が自動抽出されていること
    expect(target2?.widgetText, '保存');
  });
}

