import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaitalk/main.dart';
import 'package:thaitalk/models/learning_item.dart';
import 'package:thaitalk/models/speaker_gender.dart';
import 'package:thaitalk/screens/practice_screen.dart';
import 'package:thaitalk/services/app_settings.dart';
import 'package:thaitalk/services/cloud_sync.dart';
import 'package:thaitalk/services/learning_store.dart';

void main() {
  testWidgets(
    'saved settings update examples, copied Thai and spoken Thai across the app',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings.instance;
      await settings.load();
      final store = await LearningStore.load();
      final cloud = await CloudSync.initialize(store);
      final items = (await tester.runAsync(() async {
        await (FontLoader(
          'NotoSansTC',
        )..addFont(rootBundle.load('assets/fonts/NotoSansTC.subset.ttf'))).load();
        await (FontLoader(
          'NotoSerifThai',
        )..addFont(rootBundle.load('assets/fonts/NotoSerifThai.ttf'))).load();
        return loadCurriculum();
      }))!;
      final word = items.singleWhere((item) => item.id == 9);
      final femaleWord = word.forGender(SpeakerGender.female);
      final sentence = items.singleWhere((item) => item.id == 1003);
      final femaleSentence = sentence.forGender(SpeakerGender.female);
      expect(femaleWord.exampleThai, isNot(word.exampleThai));
      expect(femaleSentence.speechText, isNot(sentence.speechText));
      String? copied;
      final spoken = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      const ttsChannel = MethodChannel('flutter_tts');
      const voice = {
        'name': 'thai-local',
        'locale': 'th-TH',
        'network_required': '0',
        'features': '',
      };
      messenger.setMockMethodCallHandler(ttsChannel, (call) async {
        if (call.method == 'getVoices') return [voice];
        if (call.method == 'getDefaultVoice') return voice;
        if (call.method == 'speak') {
          final text = call.arguments is Map
              ? call.arguments['text']
              : call.arguments;
          spoken.add(text as String);
        }
        return 1;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        messenger.setMockMethodCallHandler(ttsChannel, null);
      });
      await tester.pumpWidget(
        ThaiTalkApp(items: items, store: store, cloud: cloud),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-gender-female')));
      await tester.pumpAndSettle();
      final restored = AppSettings();
      await restored.load();
      expect(restored.gender, SpeakerGender.female);
      restored.dispose();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('สวัสดี ค่ะ  你好！'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('library-search')),
        word.speechText,
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library-flashcards')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PracticeScreen>(find.byType(PracticeScreen)).items,
        hasLength(1),
      );
      await tester.tap(find.byTooltip('查看例句'));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('example-sheet'));
      expect(
        find.descendant(
          of: sheet,
          matching: find.text(femaleWord.exampleThai!),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('example-sheet')),
          matching: find.byTooltip('Local TTS 播放'),
        ),
      );
      await tester.pumpAndSettle();
      expect(spoken.last, femaleWord.exampleNativeThai);
      await tester.tap(
        find.descendant(of: sheet, matching: find.byTooltip('複製泰文')),
      );
      await tester.pumpAndSettle();
      expect(copied, femaleWord.exampleThai);
      Navigator.of(tester.element(sheet)).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('結束練習'));
      await tester.pumpAndSettle();
      ScaffoldMessenger.of(
        tester.element(find.byType(NavigationBar)),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('library-search')),
        femaleSentence.speechText,
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library-flashcards')));
      await tester.pumpAndSettle();
      expect(find.text(femaleSentence.thai), findsOneWidget);
      await tester.tap(find.byTooltip('Local TTS 播放'));
      await tester.pumpAndSettle();
      expect(spoken.last, femaleSentence.speechText);
      await tester.tap(find.byTooltip('複製泰文'));
      await tester.pumpAndSettle();
      expect(copied, femaleSentence.thai);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settings.flush();
      await store.flush();
      cloud.dispose();
      store.dispose();
    },
  );
}
