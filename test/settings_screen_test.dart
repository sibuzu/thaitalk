import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaitalk/models/speaker_gender.dart';
import 'package:thaitalk/screens/settings_screen.dart';
import 'package:thaitalk/services/app_settings.dart';
import 'package:thaitalk/theme.dart';

class RejectingPreferences implements SharedPreferences {
  @override
  String? getString(String key) => null;

  @override
  Future<bool> setString(String key, String value) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('phone settings persist gender and omit TTS provider selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    // Keep the serial preference queue in the widget test's async zone.
    final settings = AppSettings();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: SettingsScreen(settings: settings),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('สวัสดี ครับ'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('settings-gender-female')));
    await tester.pumpAndSettle();
    expect(settings.gender, SpeakerGender.female);
    expect(find.text('สวัสดี ค่ะ'), findsOneWidget);
    expect(find.text('Local TTS'), findsNothing);
    expect(find.text('Azure TTS'), findsNothing);
    expect(find.text('已儲存設定。'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await settings.flush();
    final restarted = AppSettings();
    await restarted.load();
    expect(restarted.gender, SpeakerGender.female);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
    restarted.dispose();
  });

  testWidgets('failed save stays visible and preserves the selected option', (
    tester,
  ) async {
    final settings = AppSettings(preferences: RejectingPreferences());
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: SettingsScreen(settings: settings),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-gender-female')));
    await tester.pumpAndSettle();
    expect(settings.gender, SpeakerGender.male);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('settings-gender-male')),
          )
          .selected,
      isTrue,
    );
    expect(find.textContaining('設定尚未儲存'), findsOneWidget);
    expect(find.text('已儲存設定。'), findsNothing);
    await settings.flush();
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
}
