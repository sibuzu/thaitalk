import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'models/learning_item.dart';
import 'services/learning_store.dart';
import 'services/cloud_sync.dart';
import 'services/speech_settings.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SpeechSettings.instance.load();
    final items = await loadCurriculum();
    final store = await LearningStore.load();
    final cloud = await CloudSync.initialize(store);
    runApp(ThaiTalkApp(items: items, store: store, cloud: cloud));
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
    required this.store,
    required this.cloud,
  });
  final List<LearningItem> items;
  final LearningStore store;
  final CloudSync cloud;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ThaiTalk · 每天一點泰語',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    locale: const Locale('zh', 'TW'),
    supportedLocales: const [Locale('zh', 'TW'), Locale('en'), Locale('th')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: HomeScreen(items: items, store: store, cloud: cloud),
  );
}
