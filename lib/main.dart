import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'models/learning_item.dart';
import 'models/study_language.dart';
import 'services/learning_store.dart';
import 'services/cloud_sync.dart';
import 'services/speech_settings.dart';
import 'services/app_settings.dart';
import 'services/curriculum_repository.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SpeechSettings.instance.load();
    await AppSettings.instance.load();
    final curricula = <StudyLanguage, List<LearningItem>>{};
    final stores = <StudyLanguage, LearningStore>{};
    await Future.wait([
      for (final language in StudyLanguage.values)
        CurriculumRepository.forLanguage(
          language,
        ).loadAtStartup().then((items) => curricula[language] = items),
    ]);
    // Initialize the shared device ID before opening the other language stores.
    for (final language in StudyLanguage.values) {
      stores[language] = await LearningStore.load(language: language);
    }
    final cloud = await CloudSync.initialize(stores[StudyLanguage.thai]!);
    runApp(
      ThaiTalkApp(
        items: curricula[StudyLanguage.thai]!,
        curricula: curricula,
        store: stores[StudyLanguage.thai]!,
        stores: stores,
        cloud: cloud,
      ),
    );
  } catch (error, stack) {
    debugPrint('ThaiTalk startup failed: $error\n$stack');
    runApp(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 48, color: orange),
                const SizedBox(height: 20),
                const Text('無法載入學習資料，請重新開啟 App。'),
                const SizedBox(height: 20),
                FilledButton(onPressed: main, child: const Text('重新載入')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ThaiTalkApp extends StatelessWidget {
  const ThaiTalkApp({
    super.key,
    required this.items,
    this.curricula = const {},
    required this.store,
    this.stores = const {},
    required this.cloud,
  });
  final List<LearningItem> items;
  final Map<StudyLanguage, List<LearningItem>> curricula;
  final LearningStore store;
  final Map<StudyLanguage, LearningStore> stores;
  final CloudSync cloud;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppSettings.instance,
    builder: (context, _) {
      final selected = AppSettings.instance.language;
      final language =
          curricula.containsKey(selected) && stores.containsKey(selected)
          ? selected
          : StudyLanguage.thai;
      return MaterialApp(
        title: 'ThaiTalk · 每天一點${language.chineseName}',
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        locale: const Locale('zh', 'TW'),
        supportedLocales: const [
          Locale('zh', 'TW'),
          Locale('en'),
          Locale('th'),
          Locale('ja'),
          Locale('ko'),
          Locale('vi'),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: HomeScreen(
          key: ValueKey(language),
          items: curricula[language] ?? items,
          store: stores[language] ?? store,
          cloud: cloud,
          language: language,
        ),
      );
    },
  );
}
