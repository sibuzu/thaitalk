import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/app_settings.dart';
import 'models/study_language.dart';
import 'models/learning_item.dart';

const ink = Color(0xFF263F36);
const muted = Color(0xFF858C84);
const canvas = Color(0xFFF8F9F5);
const orange = Color(0xFFD66C4D);
const peach = Color(0xFFF8E8DD);
const sage = Color(0xFFE8EEE3);
const line = Color(0xFFE9ECE5);

ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'NotoSansTC',
  fontFamilyFallback: const ['NotoSerifThai', 'NotoSansKR'],
  scaffoldBackgroundColor: canvas,
  colorScheme: ColorScheme.fromSeed(
    seedColor: orange,
    primary: orange,
    secondary: ink,
    surface: Colors.white,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      color: ink,
      height: 1.4,
    ),
    headlineMedium: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontSize: 19,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.6),
    bodySmall: TextStyle(fontSize: 12, color: muted, height: 1.6),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 23, vertical: 19),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      textStyle: const TextStyle(
        fontFamily: 'NotoSansTC',
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: ink,
      side: const BorderSide(color: line),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.all(18),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: orange),
    ),
  ),
  dividerColor: line,
);

Text thai(
  String text, {
  double size = 32,
  Color color = ink,
  FontWeight weight = FontWeight.w500,
  TextAlign? align,
  StudyLanguage? language,
}) => Text(
  text,
  textAlign: align,
  style: TextStyle(
    fontFamily: (language ?? AppSettings.instance.language).fontFamily,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.6,
  ),
);

/// Reading appears above Japanese kanji; katakana needs no repeated reading.
Widget learningText(LearningItem item, {double size = 30, TextAlign? align}) =>
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        if (item.showsFurigana)
          Text(
            item.romanization,
            textAlign: align,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
        thai(item.thai, size: size, align: align, language: item.language),
        if (item.language == StudyLanguage.thai)
          Text(
            item.romanization,
            textAlign: align,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
      ],
    );

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: line),
    ),
    child: child,
  );
}

class Tag extends StatelessWidget {
  const Tag(
    this.text, {
    super.key,
    this.color = ink,
    this.background = sage,
    this.icon,
  });
  final String text;
  final Color color, background;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.title, {
    super.key,
    this.subtitle,
    this.action,
    this.onAction,
  });
  final String title;
  final String? subtitle, action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Row(
              children: [
                Text(
                  action!,
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.arrow_forward_rounded, size: 15, color: muted),
              ],
            ),
          ),
      ],
    ),
  );
}

IconData categoryIcon(String c) => switch (c) {
  'greeting' => Icons.waving_hand_outlined,
  'numbers' => Icons.numbers_rounded,
  'time' => Icons.schedule_rounded,
  'food' || 'restaurant' => Icons.restaurant_rounded,
  'transport' || 'taxi' => Icons.local_taxi_outlined,
  'travel' || 'airport' => Icons.flight_takeoff_rounded,
  'shopping' => Icons.shopping_bag_outlined,
  'hotel' => Icons.hotel_outlined,
  'dating' => Icons.favorite_border_rounded,
  'emergency' => Icons.health_and_safety_outlined,
  _ => Icons.auto_awesome_outlined,
};

String categoryName(String c) => switch (c) {
  'greeting' => '打招呼與交流',
  'numbers' => '數字與金錢',
  'time' => '時間與日期',
  'food' => '美食與飲品',
  'transport' => '交通與方向',
  'travel' => '旅行與探索',
  'shopping' => '購物與生活',
  'verbs' => '常用動作',
  'restaurant' => '餐廳點餐',
  'hotel' => '飯店住宿',
  'taxi' => '搭車出行',
  'airport' => '機場旅行',
  'dating' => '交朋友',
  'emergency' => '緊急求助',
  _ => c,
};

void showNotice(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
      ),
    );

class CopyThaiButton extends StatelessWidget {
  const CopyThaiButton(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '複製${AppSettings.instance.language.textLabel}',
    icon: const Icon(Icons.content_copy_rounded, size: 18, color: muted),
    onPressed: () async {
      try {
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) {
          showNotice(context, '已複製${AppSettings.instance.language.textLabel}');
        }
      } catch (_) {
        if (context.mounted) showNotice(context, '無法存取剪貼簿，請再試一次。');
      }
    },
  );
}
