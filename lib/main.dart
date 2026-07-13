import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data' show BytesBuilder, ByteData;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart' show AudioPlayer, DeviceFileSource;
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Глобальный уведомитель для смены темы приложения
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
// Глобальный уведомитель для динамической смены цветовой палитры активной игровой темы
final ValueNotifier<String> activeThemeIdNotifier = ValueNotifier('microworld');
// Уведомитель дневного страйка — чтобы главное меню обновляло значение
// (в т.ч. при возврате приложения из фона на следующий день).
final ValueNotifier<int> streakNotifier = ValueNotifier(1);

// =========================================================================
// СОВМЕСТИМОСТЬ ЭМОДЗИ
// Современные эмодзи (🪰🪲🪨🪙 — Emoji 13.0) есть на iOS и Android 11+ (API 30).
// На старом Android (≤10) их нет — показываем запасные (🦟🐞🗿🟡).
// Флаг выставляется один раз в main(); по умолчанию true (iOS/десктоп/новые).
// =========================================================================
bool gModernEmoji = true;

// Запасной эмодзи -> современный (применяется, когда система их поддерживает).
const Map<String, String> _emojiUpgrade = {
  '🦟': '🪰', // Муха
  '🐞': '🪲', // Жук
  '🗿': '🪨', // Камень
  '🟡': '🪙', // Монета
};

// Возвращает строку с «красивыми» эмодзи на новых системах и запасными на старых.
String em(String s) {
  if (!gModernEmoji) return s;
  _emojiUpgrade.forEach((legacy, modern) => s = s.replaceAll(legacy, modern));
  return s;
}

// Эмодзи монеты с учётом совместимости.
String get coin => gModernEmoji ? '🪙' : '🟡';

Future<void> _detectEmojiSupport() async {
  try {
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      gModernEmoji = info.version.sdkInt >= 30; // Android 11 = API 30
    } else {
      gModernEmoji = true; // iOS и прочие платформы
    }
  } catch (_) {
    gModernEmoji = true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      ),
    );
    await session.setActive(true);
  } catch (e) {
    debugPrint("Ошибка конфигурации AudioSession: $e");
  }

  await _detectEmojiSupport();
  await StorageService.loadData();
  runApp(const SpatialMemoryGame());
}

// =========================================================================
// ДИНАМИЧЕСКИЕ ИГРОВЫЕ ТЕМЫ С ПОЛНОЙ ПАЛИТРОЙ ЦВЕТОВ
// =========================================================================
class GameTheme {
  final String id;
  final String name;
  final String obj1;
  final String obj2;
  final String obstacle;
  final Color primaryColor;
  final Color accentColor;
  final int price;

  const GameTheme({
    required this.id,
    required this.name,
    required this.obj1,
    required this.obj2,
    required this.obstacle,
    required this.primaryColor,
    required this.accentColor,
    required this.price,
  });
}

final List<GameTheme> gameThemes = [
  const GameTheme(
    id: 'microworld',
    // Эмодзи выбраны из набора <= Emoji 11.0, чтобы отображались и на
    // Android 10 (🪰🪲🪨 — это Emoji 13.0, появились только в Android 11).
    // Имена («Муха», «Жук») менять нельзя — к ним привязана озвучка.
    name: 'Микромир',
    obj1: '🦟 Муха',
    obj2: '🐞 Жук',
    obstacle: '🗿 Камень',
    primaryColor: Colors.teal,
    accentColor: Colors.tealAccent,
    price: 0,
  ),
  const GameTheme(
    id: 'cyberpunk',
    name: 'Киберпанк',
    obj1: '👾 Дрон',
    obj2: '🤖 Робот',
    obstacle: '💾 Глюк',
    primaryColor: Color(0xFFE91E63),
    accentColor: Color(0xFF00FFCC),
    price: 2500,
  ),
  const GameTheme(
    id: 'ocean',
    name: 'Океан',
    obj1: '🐠 Рыбка',
    obj2: '🐙 Осьминог',
    obstacle: '⚓ Якорь',
    primaryColor: Colors.blue,
    accentColor: Colors.cyanAccent,
    price: 7000,
  ),
  const GameTheme(
    id: 'space',
    name: 'Космическая',
    obj1: '🌟 Звезда',
    obj2: '🚀 Ракета',
    obstacle: '☄️ Комета',
    primaryColor: Colors.deepPurple,
    accentColor: Colors.amberAccent,
    price: 16000,
  ),
  const GameTheme(
    id: 'egypt',
    name: 'Древний Египет',
    obj1: '🐈 Кошка',
    obj2: '🦅 Сокол',
    obstacle: '🔺 Пирамида',
    primaryColor: Colors.brown,
    accentColor: Colors.orangeAccent,
    price: 25000,
  ),
  const GameTheme(
    id: 'magic',
    name: 'Мифы и Магия',
    obj1: '🐉 Дракон',
    obj2: '🦄 Единорог',
    obstacle: '💎 Кристалл',
    primaryColor: Colors.purple,
    accentColor: Colors.pinkAccent,
    price: 30000,
  ),
];

GameTheme getActiveTheme() {
  return gameThemes.firstWhere(
    (theme) => theme.id == activeThemeIdNotifier.value,
    orElse: () => gameThemes[0],
  );
}

// Акцентные цвета тем нарочно яркие (tealAccent, amberAccent, cyanAccent) —
// на белом фоне такие линии почти не видны. В светлой теме затемняем акцент до
// читаемой светлоты, в тёмной оставляем как есть.
Color readableAccent(Color accent, Brightness brightness) {
  if (brightness == Brightness.dark) return accent;
  final hsl = HSLColor.fromColor(accent);
  return hsl.withLightness((hsl.lightness * 0.55).clamp(0.0, 1.0)).toColor();
}

// Базовые Colors.orange / Colors.green на белом дают контраст около 2:1 —
// текст читается тускло. Берём тёмные оттенки в светлой теме и светлые
// в тёмной.
Color okGreen(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? Colors.greenAccent.shade400
    : Colors.green.shade800;

Color hotOrange(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? Colors.orange.shade300
    : Colors.orange.shade900;

// =========================================================================
// КЛАСС СЕССИИ ИСТОРИИ ИГР
// =========================================================================
class GameSession {
  final String id;
  final String date;
  final int score;
  final String themeName;
  final int difficultyLevel;
  final bool isPerfectSession;

  GameSession({
    required this.id,
    required this.date,
    required this.score,
    required this.themeName,
    required this.difficultyLevel,
    required this.isPerfectSession,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'score': score,
    'themeName': themeName,
    'difficultyLevel': difficultyLevel,
    'isPerfectSession': isPerfectSession,
  };

  factory GameSession.fromJson(Map<String, dynamic> json) => GameSession(
    id: json['id'] ?? '',
    date: json['date'] ?? '',
    score: json['score'] ?? 0,
    themeName: json['themeName'] ?? '',
    difficultyLevel: json['difficultyLevel'] ?? 1,
    isPerfectSession: json['isPerfectSession'] ?? false,
  );
}

// =========================================================================
// ПОСТОЯННАЯ ПАМЯТЬ НА УСТРОЙСТВЕ (ХРАНИЛИЩЕ)
// =========================================================================
class StorageService {
  static List<GameSession> gameHistory = [];
  static int userTotalBank = 0;
  static int currentStreak = 1;

  // Расширено под 10 уровней
  static Map<int, int> difficultyWins = {
    1: 0,
    2: 0,
    3: 0,
    4: 0,
    5: 0,
    6: 0,
    7: 0,
    8: 0,
    9: 0,
    10: 0,
  };
  static List<int> unlockedDifficulties = [1];
  static List<String> unlockedThemes = ['microworld'];

  static int itemShieldCount = 0;
  static int itemXrayCount = 0;

  static bool controlsOnLeft = true;
  static bool devModeActive = false;
  // Слепой режим: во время раундов поле скрыто, остаются только кнопки
  // «Дальше»/«Стоп» (в ландшафте — зоны нажатия). Включён по умолчанию, награда ×2.
  static bool isBlindModeGlobal = true;
  static bool showSpeechText = false;

  // Голос диктора: false — мужской (assets/voice/), true — женский
  // (assets/voice/female/). По умолчанию мужской.
  static bool voiceFemale = false;

  static int activeDifficulty = 1;

  // Пользовательская настройка количества объектов/преград на уровень.
  // Ключ — номер уровня. Если значения нет — используется дефолт конфига.
  static Map<int, int> customObjects = {};
  static Map<int, int> customObstacles = {};

  // Фактическое количество объектов в матче: выбранное игроком, но не больше
  // максимума уровня и не меньше 1.
  static int effectiveObjects(DifficultyConfig c) {
    final v = customObjects[c.level] ?? c.objectsCount;
    return v.clamp(1, c.objectsCount);
  }

  // Фактическое количество преград: минимум 1 (если уровень их вообще имеет),
  // максимум — сколько предлагает уровень.
  static int effectiveObstacles(DifficultyConfig c) {
    if (c.obstaclesCount == 0) return 0;
    final v = customObstacles[c.level] ?? c.obstaclesCount;
    return v.clamp(1, c.obstaclesCount);
  }

  // Уровень, с которым реально стартует сессия. Активный уровень может
  // оказаться закрытым: его выбрали в режиме тестировщика (там открыто всё),
  // а потом режим выключили — играть за него нельзя, откатываемся на
  // максимальный разблокированный.
  static int effectiveDifficulty() {
    if (devModeActive || unlockedDifficulties.contains(activeDifficulty)) {
      return activeDifficulty;
    }
    return unlockedDifficulties.isEmpty
        ? 1
        : unlockedDifficulties.reduce((a, b) => a > b ? a : b);
  }

  static DifficultyConfig activeConfig() {
    final int level = effectiveDifficulty();
    return difficulties.firstWhere(
      (d) => d.level == level,
      orElse: () => difficulties.first,
    );
  }

  static Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    userTotalBank = prefs.getInt('userTotalBank') ?? 0;
    itemShieldCount = prefs.getInt('itemShieldCount') ?? 0;
    itemXrayCount = prefs.getInt('itemXrayCount') ?? 0;
    controlsOnLeft = prefs.getBool('controlsOnLeft') ?? true;
    isBlindModeGlobal = prefs.getBool('isBlindModeGlobal') ?? true;
    devModeActive = prefs.getBool('devModeActive') ?? false;
    showSpeechText = prefs.getBool('showSpeechText') ?? false;
    voiceFemale = prefs.getBool('voiceFemale') ?? false;
    TTSEngine.volume = prefs.getDouble('ttsVolume') ?? 0.9;

    unlockedDifficulties =
        (prefs.getStringList('unlockedDifficulties') ?? ['1'])
            .map((e) => int.parse(e))
            .toList();
    activeDifficulty = prefs.getInt('activeDifficulty') ?? 1;
    // Сохранённый активный уровень может оказаться закрытым (его выбрали в
    // режиме тестировщика или сбросили прогресс) — приводим к доступному.
    activeDifficulty = effectiveDifficulty();

    // Сначала сбрасываем к значениям по умолчанию. Ключа в хранилище может не
    // быть (первый запуск или «Сбросить весь прогресс») — тогда в памяти не
    // должны оставаться прежние значения, иначе они снова уедут на диск.
    difficultyWins = {for (final d in difficulties) d.level: 0};
    customObjects = {};
    customObstacles = {};

    String? winsJson = prefs.getString('difficultyWins');
    if (winsJson != null) {
      Map<String, dynamic> decoded = jsonDecode(winsJson);
      difficultyWins = decoded.map(
        (key, value) => MapEntry(int.parse(key), value as int),
      );
    }

    String? customObjJson = prefs.getString('customObjects');
    if (customObjJson != null) {
      Map<String, dynamic> decoded = jsonDecode(customObjJson);
      customObjects = decoded.map(
        (key, value) => MapEntry(int.parse(key), value as int),
      );
    }

    String? customObsJson = prefs.getString('customObstacles');
    if (customObsJson != null) {
      Map<String, dynamic> decoded = jsonDecode(customObsJson);
      customObstacles = decoded.map(
        (key, value) => MapEntry(int.parse(key), value as int),
      );
    }

    unlockedThemes = prefs.getStringList('unlockedThemes') ?? ['microworld'];
    activeThemeIdNotifier.value =
        prefs.getString('activeThemeId') ?? 'microworld';

    List<String> historyRaw = prefs.getStringList('gameHistoryJson') ?? [];
    gameHistory = historyRaw
        .map((e) => GameSession.fromJson(jsonDecode(e)))
        .toList();

    await _checkDailyStreak(prefs);

    bool isDark = prefs.getBool('isDarkMode') ?? false;
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  static Future<void> _checkDailyStreak(SharedPreferences prefs) async {
    String? lastLoginStr = prefs.getString('lastLoginDate');
    DateTime now = DateTime.now();
    DateTime todayZero = DateTime(now.year, now.month, now.day);

    currentStreak = prefs.getInt('currentStreak') ?? 1;

    if (lastLoginStr != null) {
      DateTime lastLogin = DateTime.parse(lastLoginStr);
      DateTime lastLoginZero = DateTime(
        lastLogin.year,
        lastLogin.month,
        lastLogin.day,
      );

      int diffInDays = todayZero.difference(lastLoginZero).inDays;

      if (diffInDays == 1) {
        currentStreak++;
      } else if (diffInDays > 1) {
        currentStreak = 1;
      }
    } else {
      currentStreak = 1;
    }

    await prefs.setString('lastLoginDate', todayZero.toIso8601String());
    await prefs.setInt('currentStreak', currentStreak);
    streakNotifier.value = currentStreak;
  }

  // Пересчитать страйк «на лету» — вызывается при возврате приложения из фона,
  // чтобы значение обновлялось, даже если приложение не перезапускалось
  // (Android часто держит его в памяти между днями).
  static Future<void> refreshDailyStreak() async {
    final prefs = await SharedPreferences.getInstance();
    await _checkDailyStreak(prefs);
  }

  static Future<void> syncWithDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('userTotalBank', userTotalBank);
    await prefs.setInt('itemShieldCount', itemShieldCount);
    await prefs.setInt('itemXrayCount', itemXrayCount);
    await prefs.setBool('controlsOnLeft', controlsOnLeft);
    await prefs.setBool('isBlindModeGlobal', isBlindModeGlobal);
    await prefs.setBool('devModeActive', devModeActive);
    await prefs.setBool('showSpeechText', showSpeechText);
    await prefs.setBool('voiceFemale', voiceFemale);
    await prefs.setDouble('ttsVolume', TTSEngine.volume);

    await prefs.setStringList(
      'unlockedDifficulties',
      unlockedDifficulties.map((e) => e.toString()).toList(),
    );
    await prefs.setInt('activeDifficulty', activeDifficulty);

    await prefs.setString(
      'difficultyWins',
      jsonEncode(difficultyWins.map((k, v) => MapEntry(k.toString(), v))),
    );
    await prefs.setString(
      'customObjects',
      jsonEncode(customObjects.map((k, v) => MapEntry(k.toString(), v))),
    );
    await prefs.setString(
      'customObstacles',
      jsonEncode(customObstacles.map((k, v) => MapEntry(k.toString(), v))),
    );

    await prefs.setStringList('unlockedThemes', unlockedThemes);
    await prefs.setString('activeThemeId', activeThemeIdNotifier.value);

    List<String> historyRaw = gameHistory
        .map((e) => jsonEncode(e.toJson()))
        .toList();
    await prefs.setStringList('gameHistoryJson', historyRaw);

    await prefs.setBool('isDarkMode', themeNotifier.value == ThemeMode.dark);
  }

  // level — уровень, который реально играли (widget.config.level). Брать
  // activeDifficulty нельзя: он может отличаться от запущенного конфига, и
  // тогда победа засчиталась бы не тому уровню.
  static void addSessionToHistory(int score, bool isPerfect, int level) {
    if (isPerfect) {
      difficultyWins[level] = (difficultyWins[level] ?? 0) + 1;
    }

    userTotalBank += score;

    final newSession = GameSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: _getFormattedDate(DateTime.now()),
      score: score,
      themeName: getActiveTheme().name,
      difficultyLevel: level,
      isPerfectSession: isPerfect,
    );

    gameHistory.insert(0, newSession);
    if (gameHistory.length > 20) {
      gameHistory = gameHistory.sublist(0, 20);
    }

    syncWithDisk();
  }

  static String _getFormattedDate(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }
}

// =========================================================================
// НАСТРОЙКИ СЛОЖНОСТЕЙ ДО УРОВНЯ 10 (СЕТКА 10х10)
// =========================================================================
class DifficultyConfig {
  final int level;
  final int gridSize;
  final int objectsCount;
  final int obstaclesCount;
  // Суммарное число «шагов» (клеток) за ход: от minSteps до maxSteps.
  // Шаг = одна клетка. Ход — 1 или 2 сегмента (прямые, Г-образные,
  // двойные «и ещё на», обратные), сложность = сумма пройденных клеток.
  final int minSteps;
  final int maxSteps;
  // Число ходов в раунде: выборка из пула вариаций без повторов
  // (маленький пул уровней 2-3 проходится несколько раз).
  final int movesPerRound;
  final int unlockCost;
  final int winsRequiredFromPrevious;

  const DifficultyConfig({
    required this.level,
    required this.gridSize,
    required this.objectsCount,
    required this.obstaclesCount,
    required this.minSteps,
    required this.maxSteps,
    required this.movesPerRound,
    required this.unlockCost,
    required this.winsRequiredFromPrevious,
  });

  // Награда считается от фактического количества объектов/преград в матче —
  // если игрок уменьшил сложность через настройку, награда падает пропорционально.
  int pointsFor(int objects, int obstacles) {
    // Уровень 1 — фиксированная награда из таблицы экономики ТЗ: 10 🪙 за ход.
    if (level == 1) return 10;
    int points = 10;
    if (gridSize >= 4) points += 5;
    if (gridSize >= 6) points += 10;
    if (gridSize >= 8) points += 15;
    if (gridSize >= 10) points += 20;
    if (objects > 1) points += 5;
    if (obstacles > 0) points += 5 * obstacles;
    if (maxSteps > 1) points += 5 * (maxSteps - 1);
    return points;
  }
}

final List<DifficultyConfig> difficulties = [
  const DifficultyConfig(
    level: 1,
    gridSize: 3,
    objectsCount: 1,
    obstaclesCount: 0,
    minSteps: 1, // 3x3: допустимы одиночные шаги (своё ТЗ уровня 1)
    maxSteps: 2,
    movesPerRound: 16,
    unlockCost: 0,
    winsRequiredFromPrevious: 0,
  ),
  const DifficultyConfig(
    level: 2,
    gridSize: 4,
    objectsCount: 2,
    obstaclesCount: 0,
    minSteps: 2,
    maxSteps: 2,
    movesPerRound: 16, // пул из 4 прямых ходов проходится 4 раза
    unlockCost: 1000,
    winsRequiredFromPrevious: 4,
  ),
  const DifficultyConfig(
    level: 3,
    gridSize: 4,
    objectsCount: 1,
    obstaclesCount: 1,
    minSteps: 2,
    maxSteps: 2,
    movesPerRound: 16, // пул из 4 прямых ходов проходится 4 раза
    unlockCost: 2500,
    winsRequiredFromPrevious: 4,
  ),
  const DifficultyConfig(
    level: 4,
    gridSize: 5,
    objectsCount: 2,
    obstaclesCount: 1,
    minSteps: 2,
    maxSteps: 3,
    movesPerRound: 24,
    unlockCost: 5000,
    winsRequiredFromPrevious: 5,
  ),
  const DifficultyConfig(
    level: 5,
    gridSize: 6,
    objectsCount: 2,
    obstaclesCount: 2,
    minSteps: 2,
    maxSteps: 3,
    movesPerRound: 20,
    unlockCost: 9000,
    winsRequiredFromPrevious: 5,
  ),
  const DifficultyConfig(
    level: 6,
    gridSize: 7,
    objectsCount: 1,
    obstaclesCount: 3,
    minSteps: 2,
    maxSteps: 3,
    movesPerRound: 20,
    unlockCost: 14000,
    winsRequiredFromPrevious: 6,
  ),
  const DifficultyConfig(
    level: 7,
    gridSize: 8,
    objectsCount: 2,
    obstaclesCount: 3,
    minSteps: 2,
    maxSteps: 4,
    movesPerRound: 48,
    unlockCost: 20000,
    winsRequiredFromPrevious: 6,
  ),
  const DifficultyConfig(
    level: 8,
    gridSize: 9,
    objectsCount: 1,
    obstaclesCount: 4,
    minSteps: 2,
    maxSteps: 4,
    movesPerRound: 28,
    unlockCost: 28000,
    winsRequiredFromPrevious: 7,
  ),
  const DifficultyConfig(
    level: 9,
    gridSize: 9,
    objectsCount: 2,
    obstaclesCount: 5,
    minSteps: 2,
    maxSteps: 4,
    movesPerRound: 28,
    unlockCost: 38000,
    winsRequiredFromPrevious: 7,
  ),
  const DifficultyConfig(
    level: 10,
    gridSize: 10,
    objectsCount: 2,
    obstaclesCount: 6,
    minSteps: 2,
    maxSteps: 4,
    movesPerRound: 28,
    unlockCost: 50000,
    winsRequiredFromPrevious: 8,
  ),
];

// =========================================================================
// ПУЛЫ ВАРИАЦИЙ И ПЛАНЫ РАУНДОВ (ПО СТРАНИЦАМ УРОВНЕЙ 1-10, docs/levels)
// Вариация хода — строка из букв направлений: В — вверх, Н — вниз,
// Л — влево, П — вправо. Каждая буква = 1 шаг (1 клетка); одинаковые буквы
// подряд — один сегмент («ВВП» = «на две клетки вверх и на одну вправо»);
// знак «+» разделяет два сегмента одного направления («ЛЛ+ЛЛ» = «на две
// клетки влево и ещё на две влево»).
// Ход — 1-2 сегмента, сумма клеток в бюджете уровня [minSteps, maxSteps].
// Типы: прямые, Г-образные (перпендикулярные), двойные (одно направление
// дважды) и обратные (противоположные направления). Нулевых обратных
// (возврат в ту же клетку, например «ВВ+НН») нет; со 2-го уровня нет ходов
// из двух одиночных сегментов (1+1). Уровень 1 — своё ТЗ: только одиночные,
// прямые на 2 и перпендикулярные Г-ходы 1+1.
// Раунд = случайная выборка movesPerRound разных вариаций из пула (малый
// пул уровней 2-3 проходится 4 раза) с балансом ровно 50/50 ДАЛЬШЕ/СТОП.
// Проверяется только клетка приземления: край / преграда / объект = СТОП.
// =========================================================================

const List<String> _dirLetters = ['Л', 'П', 'В', 'Н'];

const Map<String, String> _letterToDir = {
  'В': 'вверх',
  'Н': 'вниз',
  'Л': 'влево',
  'П': 'вправо',
};

bool _isHorizontal(String letter) => letter == 'Л' || letter == 'П';

// Пул вариаций хода уровня, выводится из бюджета шагов [minSteps, maxSteps].
// Размеры пулов по уровням: 16 / 4 / 4 / 40 / 40 / 40 / 88 / 88 / 88 / 88.
List<String> buildMovePool(DifficultyConfig config) {
  final bool isL1 = config.level == 1;
  final List<String> pool = [];
  for (int total = config.minSteps; total <= config.maxSteps; total++) {
    if (total == 1) {
      pool.addAll(_dirLetters); // одиночные шаги (только уровень 1)
      continue;
    }
    if (total <= 4) {
      for (final d in _dirLetters) {
        pool.add(d * total); // прямой ход на total клеток
      }
    }
    for (int a = 1; a < total; a++) {
      final int b = total - a;
      if (a > 4 || b > 4) continue; // лимит озвучки — 4 клетки на сегмент
      if (!isL1 && a < 2 && b < 2) continue; // нет ходов 1+1 со 2-го уровня
      for (final d1 in _dirLetters) {
        for (final d2 in _dirLetters) {
          if (isL1) {
            // Уровень 1 (по его ТЗ): только перпендикулярные Г-ходы.
            if (_isHorizontal(d1) == _isHorizontal(d2)) continue;
            pool.add(d1 * a + d2 * b);
          } else if (d1 == d2) {
            // Двойной ход: то же направление вторым сегментом («и ещё на»).
            pool.add('${d1 * a}+${d2 * b}');
          } else if (_isHorizontal(d1) == _isHorizontal(d2)) {
            // Обратный ход: противоположные направления. Нулевые (a == b —
            // возврат в ту же клетку) исключены.
            if (a == b) continue;
            pool.add(d1 * a + d2 * b);
          } else {
            pool.add(d1 * a + d2 * b); // Г-образный ход
          }
        }
      }
    }
  }
  return pool;
}

// Количество ходов в раунде уровня (из конфига).
int roundLength(DifficultyConfig config) => config.movesPerRound;

// Вариация -> сегменты для движка и озвучки: одинаковые буквы подряд —
// один сегмент, «+» — граница сегментов одного направления.
List<MoveSegment> moveSegmentsFor(String move) {
  final List<MoveSegment> segments = [];
  for (final part in move.split('+')) {
    int i = 0;
    while (i < part.length) {
      int j = i;
      while (j < part.length && part[j] == part[i]) {
        j++;
      }
      segments.add(MoveSegment(_letterToDir[part[i]]!, j - i));
      i = j;
    }
  }
  return segments;
}

// Суммарное смещение вариации (x растёт вправо, y — вниз).
Point<int> moveOffset(String move) {
  int dx = 0, dy = 0;
  for (final ch in move.split('')) {
    switch (ch) {
      case 'Л':
        dx--;
      case 'П':
        dx++;
      case 'В':
        dy--;
      case 'Н':
        dy++;
    }
  }
  return Point(dx, dy);
}

// Один запланированный ход раунда: какому объекту адресован и вариация.
class PlannedMove {
  final int objectId; // id объекта (1 или 2)
  final String move;
  const PlannedMove(this.objectId, this.move);
}

// Правильные ответы плана при безошибочной игре: объекты стартуют в своих
// клетках и передвигаются на каждом валидном ходе, преграды статичны.
// true = ДАЛЬШЕ (клетка приземления в поле, не преграда и не другой объект).
List<bool> roundPlanAnswers({
  required List<PlannedMove> plan,
  required List<Point<int>> objectStarts,
  required List<Point<int>> obstacles,
  required int gridSize,
}) {
  final pos = [for (final p in objectStarts) Point(p.x, p.y)];
  final List<bool> answers = [];
  for (final planned in plan) {
    final int idx = (planned.objectId - 1).clamp(0, pos.length - 1);
    final o = moveOffset(planned.move);
    final target = Point(pos[idx].x + o.x, pos[idx].y + o.y);
    bool safe = target.x >= 0 &&
        target.x < gridSize &&
        target.y >= 0 &&
        target.y < gridSize &&
        !obstacles.contains(target);
    if (safe) {
      for (int j = 0; j < pos.length; j++) {
        if (j != idx && pos[j] == target) safe = false;
      }
    }
    answers.add(safe);
    if (safe) pos[idx] = target;
  }
  return answers;
}

int roundPlanSafeCount({
  required List<PlannedMove> plan,
  required List<Point<int>> objectStarts,
  required List<Point<int>> obstacles,
  required int gridSize,
}) => roundPlanAnswers(
      plan: plan,
      objectStarts: objectStarts,
      obstacles: obstacles,
      gridSize: gridSize,
    ).where((a) => a).length;

// План раунда: случайная выборка movesPerRound разных вариаций из пула
// (малый пул уровней 2-3 тиражируется до 16 ходов); на двухобъектных
// уровнях ходы поделены между объектами поровну. Перемешиваем, пока баланс
// не станет ровно 50/50 (обычно хватает единиц попыток); страховочный
// лимит возвращает лучший найденный вариант.
List<PlannedMove> generateRoundPlan({
  required DifficultyConfig config,
  required List<Point<int>> objectStarts,
  required List<Point<int>> obstacles,
  required Random rand,
}) {
  final pool = buildMovePool(config);
  final int target = config.movesPerRound;
  final bool sampled = pool.length >= target;
  final int reps = sampled ? 1 : target ~/ pool.length;
  final int half = target ~/ 2;

  // Адресаты ходов: ровно половина каждому объекту (одному — все).
  final List<int> ids = [
    for (int i = 0; i < target; i++)
      objectStarts.length == 2 && i >= half ? 2 : 1,
  ];

  List<PlannedMove> build() {
    pool.shuffle(rand);
    final List<String> moves = sampled
        ? pool.sublist(0, target)
        : ([for (int r = 0; r < reps; r++) ...pool]..shuffle(rand));
    ids.shuffle(rand);
    return [
      for (int i = 0; i < target; i++) PlannedMove(ids[i], moves[i]),
    ];
  }

  int diffOf(List<PlannedMove> plan) => (roundPlanSafeCount(
        plan: plan,
        objectStarts: objectStarts,
        obstacles: obstacles,
        gridSize: config.gridSize,
      ) - half).abs();

  List<PlannedMove> best = build();
  int bestDiff = diffOf(best);
  for (int attempt = 0; attempt < 2000 && bestDiff != 0; attempt++) {
    final plan = build();
    final int diff = diffOf(plan);
    if (diff < bestDiff) {
      best = plan;
      bestDiff = diff;
    }
  }
  return best;
}

// =========================================================================
// КЛАССЫ СОСТОЯНИЙ И ИГРОВОЙ ДВИЖОК
// =========================================================================
class ObjectState {
  final int id;
  int x;
  int y;
  final String emoji;

  ObjectState({
    required this.id,
    required this.x,
    required this.y,
    required this.emoji,
  });

  ObjectState clone() => ObjectState(id: id, x: x, y: y, emoji: emoji);
}

// Один сегмент хода: направление + количество клеток. Ход состоит из 1-2
// сегментов (перпендикулярных «влево и вверх» или сдвоенных «вверх и ещё вверх»).
class MoveSegment {
  final String dir;
  final int step;
  const MoveSegment(this.dir, this.step);
}

class PendingMove {
  final int objectId;
  final String objectEmoji;
  final String directionText;
  final int step;
  final int nextX;
  final int nextY;
  final bool isSafe;
  final String speechText;
  final List<String> speechClips;

  PendingMove({
    required this.objectId,
    required this.objectEmoji,
    required this.directionText,
    required this.step,
    required this.nextX,
    required this.nextY,
    required this.isSafe,
    required this.speechText,
    required this.speechClips,
  });
}

// Результат генерации озвучки хода: и текст (для UI/fallback), и список
// аудиоклипов, которые проигрываются подряд нейро-голосом.
class MoveSpeech {
  final String text;
  final List<String> clips;
  const MoveSpeech(this.text, this.clips);
}

// =========================================================================
// СИНТЕЗАТОР РЕЧИ
// =========================================================================
class TTSEngine {
  static final FlutterTts _flutterTts = FlutterTts();
  static double volume = 0.9;

  static const Map<String, List<String>> _actions = {
    "Рыбка": ["поплыть", "уплыть"],
    "Осьминог": ["поплыть", "уплыть"],
    "Сокол": ["полететь", "улететь"],
    "Муха": ["полететь", "улететь"],
    "Дракон": ["полететь", "улететь"],
    "Дрон": ["полететь", "улететь"],
    "Ракета": ["полететь", "улететь"],
    "Кошка": ["пойти", "пробежать"],
    "Единорог": ["пойти", "ускакать"],
    "Робот": ["двинуться", "переместиться"],
    "Жук": ["проползти", "пойти"],
    "Звезда": ["полететь", "улететь"],
  };

  // Модальные глаголы вступления: [текст, ключ-файла]. Должны совпадать
  // с tool/generate_voice_lines.dart.
  static const List<List<String>> _modals = [
    ["хочет", "hochet"],
    ["планирует", "planiruet"],
    ["собирается", "sobiraetsya"],
    ["пробует", "probuet"],
  ];

  // Транслитерация для имён аудиофайлов (см. tool/generate_voice_lines.dart).
  static const Map<String, String> _nameKeys = {
    "Муха": "mukha",
    "Жук": "zhuk",
    "Дрон": "dron",
    "Робот": "robot",
    "Рыбка": "rybka",
    "Осьминог": "osminog",
    "Звезда": "zvezda",
    "Ракета": "raketa",
    "Кошка": "koshka",
    "Сокол": "sokol",
    "Дракон": "drakon",
    "Единорог": "edinorog",
  };
  static const Map<String, String> _actionKeys = {
    "полететь": "poletet",
    "улететь": "uletet",
    "проползти": "propolzti",
    "пойти": "poyti",
    "двинуться": "dvinutsya",
    "переместиться": "peremestitsya",
    "поплыть": "poplyt",
    "уплыть": "uplyt",
    "пробежать": "probezhat",
    "ускакать": "uskakat",
  };
  static const Map<String, String> _dirKeys = {
    "влево": "vlevo",
    "вправо": "vpravo",
    "вверх": "vverh",
    "вниз": "vniz",
  };

  static Future<void> init() async {
    await _flutterTts.setLanguage("ru-RU");
    await _flutterTts.setSpeechRate(0.45);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(volume);
    await _flutterTts.setSharedInstance(true);

    try {
      await _flutterTts
          .setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            IosTextToSpeechAudioCategoryOptions.duckOthers,
          ]);
    } catch (e) {
      debugPrint("Ошибка настройки TTS iOS Audio: $e");
    }
  }

  static Future<void> speak(String text) async {
    await _flutterTts.stop();
    await _flutterTts.setVolume(volume);
    // Системный откат тоже учитывает выбранный пол голоса: женский — выше тоном.
    await _flutterTts.setPitch(StorageService.voiceFemale ? 1.5 : 1.0);
    await _flutterTts.speak(text);
  }

  static Future<void> stop() async {
    await _flutterTts.stop();
  }

  static String _stepWord(int s) => s == 1
      ? "одну клетку"
      : (s == 2 ? "две клетки" : (s == 3 ? "три клетки" : "четыре клетки"));

  // Собирает озвучку хода: текст (для UI/fallback) и список аудиоклипов,
  // которые проигрываются подряд: вступление + движение [+ связка + движение].
  // Связка между сегментами: «и ещё на» — если направление повторяется
  // (сдвоенный ход), иначе «и на» (перпендикулярный ход).
  static MoveSpeech generateMove({
    required String rawName,
    required List<MoveSegment> segments,
  }) {
    final rand = Random();

    List<String> parts = rawName.split(' ');
    String cleanName = parts.length > 1 ? parts[1].trim() : rawName.trim();

    List<String> availableActions =
        _actions[cleanName] ?? ["переместиться", "двинуться"];
    String action = availableActions[rand.nextInt(availableActions.length)];
    List<String> modal = _modals[rand.nextInt(_modals.length)];

    String nameKey = _nameKeys[cleanName] ?? "koshka";
    String actionKey = _actionKeys[action] ?? "poyti";

    List<String> clips = ["intro_${nameKey}_${modal[1]}_$actionKey"];

    final buf = StringBuffer("$cleanName ${modal[0]} $action на");
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (i > 0) {
        final bool sameDir = segments[i - 1].dir == seg.dir;
        clips.add(sameDir ? "connector_i_eshe_na" : "connector_i_na");
        buf.write(sameDir ? " и ещё на" : " и на");
      }
      clips.add("motion_${seg.step}_${_dirKeys[seg.dir]}");
      buf.write(" ${_stepWord(seg.step)} ${seg.dir}");
    }

    return MoveSpeech(buf.toString(), clips);
  }
}

// =========================================================================
// ОЗВУЧКА: нейро-голос диктора (аудиоклипы) с откатом на системный TTS
// =========================================================================
class VoiceService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _neuralReady = false;

  static double get volume => TTSEngine.volume;
  static set volume(double v) => TTSEngine.volume = v;

  // Тексты статичных фраз — совпадают с tool/generate_voice_lines.dart.
  // Для фраз без записанного клипа (found_single, game_over_safe,
  // miss_wrong_order) целая фраза озвучивается системным TTS, пока диктор
  // не запишет клипы (перегенерация через tool/generate_voice_lines.dart).
  static const Map<String, String> _staticTexts = {
    "memorize": "Запомни расположение объектов на поле.",
    "game_over": "Ой! Вы ошиблись и объект попал в тупик.",
    "game_over_safe": "Ой! Вы ошиблись. Путь был чист — объект мог пройти.",
    "perfect_finish": "Отличная работа! Идеальная сессия. Запуск супер-игры.",
    "supergame_trap":
        "Ловушка! Вы наступили на препятствие. Супер-игра окончена.",
    "found_first": "Правильно! Нашли первый объект.",
    "found_second": "Отлично! Нашли второй объект. Монеты удвоены!",
    "found_single": "Правильно! Объект найден. Монеты удвоены!",
    "miss_empty": "Промах! Это была пустая ячейка.",
    "miss_wrong_order": "Промах! Это второй объект — сначала найдите первый.",
    "xray_on": "Рентген активирован на три секунды.",
  };

  // Подстановка для клипов, которых может не оказаться в assets: вместо
  // отсутствующего играем ближайший по смыслу, чтобы фраза целиком звучала
  // голосом диктора. Клип «и ещё на» уже записан — подмена осталась как
  // страховка на случай его пропажи из пакета.
  static const Map<String, String> _clipFallback = {
    "connector_i_eshe_na": "connector_i_na",
  };

  static Future<ByteData> _loadClip(String id) async {
    final String dir = StorageService.voiceFemale ? 'female/' : '';
    final String? fb = _clipFallback[id];
    // Порядок поиска: выбранный голос -> подмена клипа в выбранном голосе ->
    // мужской (если женский ещё не записан) -> подмена в мужском.
    final candidates = <String>[
      'assets/voice/$dir$id.mp3',
      if (fb != null) 'assets/voice/$dir$fb.mp3',
      if (dir.isNotEmpty) 'assets/voice/$id.mp3',
      if (dir.isNotEmpty && fb != null) 'assets/voice/$fb.mp3',
    ];
    for (final path in candidates) {
      try {
        return await rootBundle.load(path);
      } catch (_) {}
    }
    // Ничего не нашли — бросаем, чтобы сработал откат на системный голос.
    return await rootBundle.load(candidates.first);
  }

  static Future<void> init() async {
    await TTSEngine.init();
    // Проверяем, добавлен ли пакет нейро-озвучки. Если файлов ещё нет —
    // работаем на системном голосе, приложение не ломается.
    try {
      await rootBundle.load('assets/voice/found_first.mp3');
      _neuralReady = true;
    } catch (_) {
      _neuralReady = false;
    }
  }

  static Future<void> stop() async {
    _playToken++; // прерываем любую «в полёте» озвучку, чтобы она не заиграла
    try {
      await _player.stop();
    } catch (_) {}
    await TTSEngine.stop();
  }

  static Future<void> speakStatic(String id) async {
    await _speak([id], _staticTexts[id] ?? "");
  }

  static Future<void> speakMove(MoveSpeech move) async {
    await _speak(move.clips, move.text);
  }

  // Монотонный токен последней озвучки. Каждый новый вызов _speak его
  // увеличивает; более старые вызовы, увидев, что токен сменился, прерываются —
  // так две фразы не накладываются друг на друга.
  static int _playToken = 0;
  // Кэш временной папки и последней громкости — чтобы не дёргать плагины
  // на каждой фразе (меньше задержка перед стартом озвучки).
  static Directory? _tmpDir;
  static double _lastVol = -1;

  static Future<void> _speak(List<String> clipIds, String fallbackText) async {
    final int myToken = ++_playToken;
    if (!_neuralReady) {
      await TTSEngine.speak(fallbackText);
      return;
    }
    await TTSEngine.stop();
    try {
      // Глушим предыдущую фразу через stop() — без release(): release пересоздаёт
      // нативный плеер и даёт заметную паузу между фразами. От наложения
      // защищают снятый ReleaseMode.stop и токен _playToken ниже.
      try {
        await _player.stop();
      } catch (_) {}
      if (myToken != _playToken) return; // нас уже сменил новый вызов

      // Склеиваем нужные клипы в один временный файл и проигрываем одним
      // воспроизведением — между «...пойти на», «одну клетку вверх», «и на»,
      // «три клетки влево» нет паузы плеера на подготовку каждого файла.
      final builder = BytesBuilder();
      for (final id in clipIds) {
        final data = await _loadClip(id);
        if (myToken != _playToken) return; // прервали во время загрузки
        builder.add(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
      _tmpDir ??= await getTemporaryDirectory();
      // ротация имени, чтобы не упереться в блокировку предыдущего файла
      final path = '${_tmpDir!.path}/mf_phrase_${myToken % 4}.mp3';
      await File(path).writeAsBytes(builder.toBytes(), flush: true);
      if (myToken != _playToken) return; // прервали во время записи

      if (_lastVol != TTSEngine.volume) {
        await _player.setVolume(TTSEngine.volume);
        _lastVol = TTSEngine.volume;
      }
      // Последняя проверка перед стартом: между записью файла и play() успевает
      // пройти setVolume, и если в это окно игрок вышел с экрана, фраза иначе
      // заиграла бы уже после stop().
      if (myToken != _playToken) return;
      await _player.play(DeviceFileSource(path));
      // Плеер стартует асинхронно: если нас остановили, пока он раскручивался,
      // глушим звук сами — иначе диктор договорит на пустом экране.
      if (myToken != _playToken) {
        try {
          await _player.stop();
        } catch (_) {}
      }
    } catch (e) {
      if (myToken != _playToken) return;
      debugPrint("VoiceService: ошибка склейки/воспроизведения ($e), откат на TTS");
      await TTSEngine.speak(fallbackText);
    }
  }
}

// =========================================================================
// ГЛАВНЫЙ КЛАСС ПРИЛОЖЕНИЯ
// =========================================================================
class SpatialMemoryGame extends StatefulWidget {
  const SpatialMemoryGame({super.key});

  @override
  State<SpatialMemoryGame> createState() => _SpatialMemoryGameState();
}

class _SpatialMemoryGameState extends State<SpatialMemoryGame>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // Глушим озвучку, когда приложение уходит в фон / экран блокируется,
      // иначе диктор продолжает говорить после выхода из игры.
      VoiceService.stop();
    } else {
      // При возвращении в приложение пересчитываем дневной страйк — чтобы он
      // обновлялся и без полного перезапуска (Android держит приложение живым).
      StorageService.refreshDailyStreak();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return ValueListenableBuilder<String>(
          valueListenable: activeThemeIdNotifier,
          builder: (context, activeTheme, _) {
            final activeThemeData = getActiveTheme();
            return MaterialApp(
              title: 'MemoryFly',
              debugShowCheckedModeBanner: false,
              themeMode: currentMode,
              theme: ThemeData(
                colorScheme:
                    ColorScheme.fromSeed(
                      seedColor: activeThemeData.primaryColor,
                      brightness: Brightness.light,
                    ).copyWith(
                      // Акцент темы теперь живой: он приходит в схему цветов и
                      // рисует разметку игрового поля. На светлом фоне яркие
                      // акценты (tealAccent, amberAccent) не видны — затемняем.
                      secondary: readableAccent(
                        activeThemeData.accentColor,
                        Brightness.light,
                      ),
                    ),
                scaffoldBackgroundColor: const Color(0xFFF9FBFA),
                cardColor: Colors.white,
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme:
                    ColorScheme.fromSeed(
                      seedColor: activeThemeData.primaryColor,
                      brightness: Brightness.dark,
                    ).copyWith(
                      secondary: readableAccent(
                        activeThemeData.accentColor,
                        Brightness.dark,
                      ),
                    ),
                scaffoldBackgroundColor: const Color(0xFF131722),
                cardColor: const Color(0xFF1E222D),
                useMaterial3: true,
              ),
              home: const MainMenuScreen(),
            );
          },
        );
      },
    );
  }
}

// =========================================================================
// ЭКРАН 1: ГЛАВНОЕ МЕНЮ ПРИЛОЖЕНИЯ
// =========================================================================
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  @override
  void initState() {
    super.initState();
    VoiceService.init();
  }

  void _showHowToPlay() {
    showDialog(
      context: context,
      builder: (context) {
        final activeTheme = getActiveTheme();
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.menu_book, color: activeTheme.primaryColor),
              const SizedBox(width: 10),
              const Text(
                'Инструкция к игре',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🎯 Цель',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Держите в уме, где на поле находятся скрытые объекты. Сами они по экрану не двигаются — каждый ход вслух объявляет диктор. Ваша задача — мысленно понимать, куда объект попадёт.',
                ),
                const Divider(height: 20),
                const Text(
                  '⏱️ Запоминание',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'В начале сессии объекты и преграды на несколько секунд показываются на поле. Запомните их расположение — дальше поле станет пустым.',
                ),
                const Divider(height: 20),
                const Text(
                  '🎧 Ход и решение',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Диктор произносит очередной ход, например: «Кошка хочет пойти на две клетки вверх и на одну клетку вправо» или «...на две клетки влево и ещё на две влево». Сразу принимайте решение:',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '«Дальше» — если после хода объект остаётся на поле и не встаёт на преграду или на другой объект.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.dangerous, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '«Стоп» — если ход выводит объект за край поля, ставит его на преграду или на другой объект.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Учитывается финальная клетка после хода. Верный «Стоп» тоже засчитывается как пройденный ход — объект остаётся на месте, а монет за него начисляется половина.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const Text(
                  '💡 В горизонтальном режиме можно нажимать в любом месте своей половины экрана: слева — «Дальше», справа — «Стоп».',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Divider(height: 20),
                Text(
                  '🧩 Элементы темы «${activeTheme.name}»',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(em('• Объект 1: ${activeTheme.obj1}')),
                Text(em('• Объект 2 (если есть): ${activeTheme.obj2}')),
                Text(em('• Преграда: ${activeTheme.obstacle}')),
                const Divider(height: 20),
                const Text(
                  '🏆 Супер-игра',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Пройдите всю сессию без ошибок — начнётся «Супер-Тап»: по памяти ткните в клетки, где спрятаны объекты, на пустом поле. Не попадите в клетки бывших преград — там ловушки. Успех удваивает монеты!',
                ),
                const Divider(height: 20),
                const Text(
                  '💰 Монеты и голос',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'За верные решения начисляются монеты (в «слепом режиме» — ×2). На них в магазине открываются новые уровни и темы. Голос диктора (мужской/женский) и громкость меняются в «Настройках».',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Все ясно!'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      body: SafeArea(
        // LayoutBuilder + полноширинный скролл: тянуть/скролить можно в любом
        // месте экрана, а не только по колонке с кнопками (важно для ландшафта).
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: landscape ? 12.0 : 20.0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - (landscape ? 24.0 : 40.0),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  Hero(
                    tag: 'game_logo',
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Color(0xFF14B8A6), Color(0xFF6366F1)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds),
                            child: Text(
                              'MemoryFly',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: landscape ? 32 : 44,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                                height: 1.0,
                                color: Colors
                                    .white, // перекрывается градиентом ShaderMask
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'ТРЕНАЖЁР ПРОСТРАНСТВЕННОЙ ПАМЯТИ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.0,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white54
                                  : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_fire_department,
                            color: hotOrange(context),
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          ValueListenableBuilder<int>(
                            valueListenable: streakNotifier,
                            builder: (context, streak, _) => Text(
                              'Страйк: $streak дн.',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: hotOrange(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (StorageService.devModeActive) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          "⚙️ ТЕСТИРОВЩИК АКТИВЕН",
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: landscape ? 16 : 30),
                  _buildMenuButton(
                    context,
                    icon: Icons.play_arrow_rounded,
                    label: 'Старт сессии',
                    color: const Color(0xFF14B8A6),
                    onTap: () {
                      // Только разблокированный уровень (в режиме
                      // тестировщика — любой): см. activeConfig().
                      final config = StorageService.activeConfig();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GameScreen(config: config),
                        ),
                      ).then((_) => setState(() {}));
                    },
                  ),
                  _buildMenuButton(
                    context,
                    icon: Icons.lock_open_rounded,
                    label: 'Сложность и Прогресс',
                    color: const Color(0xFF6366F1),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const UpgradesScreen(),
                        ),
                      ).then((_) => setState(() {}));
                    },
                  ),
                  _buildMenuButton(
                    context,
                    icon: Icons.shopping_bag_rounded,
                    label: 'Магазин',
                    color: const Color(0xFFF59E0B),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ShopScreen(),
                        ),
                      ).then((_) => setState(() {}));
                    },
                  ),
                  _buildMenuButton(
                    context,
                    icon: Icons.help_outline_rounded,
                    label: 'Инструкция к игре',
                    color: const Color(0xFF10B981),
                    onTap: _showHowToPlay,
                  ),
                  _buildMenuButton(
                    context,
                    icon: Icons.history_rounded,
                    label: 'Журнал игр',
                    color: Colors.blueAccent,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const GameHistoryScreen(),
                        ),
                      );
                    },
                  ),
                  _buildMenuButton(
                    context,
                    icon: Icons.settings_rounded,
                    label: 'Настройки',
                    color: const Color(0xFF64748B),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      ).then((_) => setState(() {}));
                    },
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      'Баланс кошелька: ${StorageService.userTotalBank} $coin',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    // В ландшафте делаем кнопки компактнее, чтобы все пункты помещались
    // и шапка не «съедала» половину невысокого экрана.
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: landscape ? 4.0 : 6.0),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          elevation: 2,
          padding: EdgeInsets.symmetric(vertical: landscape ? 9 : 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        label: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: landscape ? 15 : 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// ЭКРАН ЖУРНАЛА ИГР (ИСТОРИЯ СЕССИЙ)
// =========================================================================
class GameHistoryScreen extends StatelessWidget {
  const GameHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final activeTheme = getActiveTheme();
    return Scaffold(
      appBar: AppBar(title: const Text('Журнал игр'), centerTitle: true),
      body: StorageService.gameHistory.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 64,
                    color: Colors.grey.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Журнал пуст.\nСыграйте хотя бы один матч!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: StorageService.gameHistory.length,
              itemBuilder: (context, index) {
                final session = StorageService.gameHistory[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: activeTheme.primaryColor.withValues(
                        alpha: 0.15,
                      ),
                      child: Text(
                        "${session.difficultyLevel}⭐",
                        style: TextStyle(
                          color: activeTheme.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(
                          'Уровень ${session.difficultyLevel}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        if (session.isPerfectSession)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.teal,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'ИДЕАЛЬНО',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('Тема: ${session.themeName}'),
                        const SizedBox(height: 2),
                        Text(
                          session.date,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '+${session.score}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: okGreen(context),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(coin, style: const TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// =========================================================================
// ЭКРАН УСЛОЖНЕНИЙ И ГИБРИДНОЙ РАЗБЛОКИРОВКИ + СЛЕПОЙ РЕЖИМ (BLIND MODE)
// =========================================================================
class UpgradesScreen extends StatefulWidget {
  const UpgradesScreen({super.key});

  @override
  State<UpgradesScreen> createState() => _UpgradesScreenState();
}

class _UpgradesScreenState extends State<UpgradesScreen> {
  void _tryUnlock(DifficultyConfig config) {
    int previousWins = StorageService.difficultyWins[config.level - 1] ?? 0;

    if (previousWins < config.winsRequiredFromPrevious) {
      _showErrorDialog(
        "Вам нужно набрать как минимум ${config.winsRequiredFromPrevious} идеальных побед на Уровне ${config.level - 1}!\nВаш текущий результат: $previousWins побед.",
      );
      return;
    }

    if (StorageService.userTotalBank < config.unlockCost) {
      _showErrorDialog(
        "Недостаточно монет! Стоимость разблокировки: ${config.unlockCost} $coin.\nВаш баланс: ${StorageService.userTotalBank} $coin.",
      );
      return;
    }

    setState(() {
      StorageService.userTotalBank -= config.unlockCost;
      StorageService.unlockedDifficulties.add(config.level);
      StorageService.activeDifficulty = config.level;
      StorageService.syncWithDisk();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Уровень сложности ${config.level} успешно разблокирован!',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Внимание!'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ок'),
          ),
        ],
      ),
    );
  }

  // Компактный чип-характеристика уровня (сетка/объекты/преграды/шаги/награда).
  Widget _statChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  // Степпер «− значение +» для настройки количества объектов/преград.
  // Кнопки блокируются на границах [min, max] — нельзя превысить максимум уровня.
  Widget _buildCounterRow({
    required String label,
    required int value,
    required int min,
    required int max,
    required Color color,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          color: color,
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 24,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          color: color,
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
        Text(
          '/ $max',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeTheme = getActiveTheme();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сложность и Прогресс'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            // decoration (а не color:) — чтобы SwitchListTile ниже не оказался
            // внутри ColoredBox (иначе Flutter ругается на невидимые ink-эффекты).
            decoration: BoxDecoration(
              color: activeTheme.primaryColor.withValues(alpha: 0.1),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Ваш баланс: ${StorageService.userTotalBank} $coin',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Сложность: ${StorageService.activeDifficulty}★',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                // Собственный Material под ListTile — иначе он рисует ink на
                // цветном контейнере выше, и Flutter выдаёт предупреждение.
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Слепой режим',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Во время раунда поле скрыто — только кнопки (награда ×2 $coin)',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    activeThumbColor: activeTheme.primaryColor,
                    value: StorageService.isBlindModeGlobal,
                    onChanged: (val) {
                      setState(() {
                        StorageService.isBlindModeGlobal = val;
                        StorageService.syncWithDisk();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: difficulties.length,
              itemBuilder: (context, index) {
                final config = difficulties[index];
                final isUnlocked =
                    StorageService.unlockedDifficulties.contains(
                      config.level,
                    ) ||
                    StorageService.devModeActive;
                final isActive =
                    StorageService.activeDifficulty == config.level;

                final effObjects = StorageService.effectiveObjects(config);
                final effObstacles = StorageService.effectiveObstacles(config);
                final reward = config.pointsFor(effObjects, effObstacles);
                // Есть ли что настраивать на этом уровне.
                final bool canCustomize =
                    config.objectsCount > 1 || config.obstaclesCount > 1;

                final wins = StorageService.difficultyWins[config.level] ?? 0;
                final prevWins =
                    StorageService.difficultyWins[config.level - 1] ?? 0;

                Widget trailingWidget;
                if (isActive) {
                  trailingWidget = const Chip(
                    label: Text(
                      'Активен',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: Colors.green,
                  );
                } else if (isUnlocked) {
                  trailingWidget = ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      setState(() {
                        StorageService.activeDifficulty = config.level;
                        StorageService.syncWithDisk();
                      });
                    },
                    child: const Text('Выбрать'),
                  );
                } else {
                  trailingWidget = ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _tryUnlock(config),
                    icon: const Icon(
                      Icons.lock_open,
                      size: 14,
                      color: Colors.white,
                    ),
                    label: Text(
                      '${config.unlockCost} $coin',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  );
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isActive
                          ? activeTheme.primaryColor
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Уровень ${config.level}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            trailingWidget,
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Характеристики уровня компактными чипами (эргономичнее,
                        // чем 5 отдельных строк — карточка стала ниже).
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _statChip('${config.gridSize}×${config.gridSize}'),
                            _statChip(
                              'объектов $effObjects/${config.objectsCount}',
                            ),
                            _statChip(
                              'преград $effObstacles/${config.obstaclesCount}',
                            ),
                            _statChip(
                              config.minSteps == config.maxSteps
                                  ? 'шагов ${config.maxSteps}'
                                  : 'шагов ${config.minSteps}–${config.maxSteps}',
                            ),
                            _statChip('ходов ${config.movesPerRound}'),
                            // Награда за ход — сразу с бонусом слепого режима,
                            // иначе чип врёт (режим включён по умолчанию).
                            _statChip(
                              StorageService.isBlindModeGlobal
                                  ? '+${reward * 2} $coin (×2)'
                                  : '+$reward $coin',
                            ),
                          ],
                        ),
                        if (isUnlocked && canCustomize) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: activeTheme.primaryColor.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '⚙️ Настройка матча',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                if (config.objectsCount > 1)
                                  _buildCounterRow(
                                    label: 'Объекты',
                                    value: effObjects,
                                    min: 1,
                                    max: config.objectsCount,
                                    color: activeTheme.primaryColor,
                                    onChanged: (v) {
                                      setState(() {
                                        StorageService.customObjects[config
                                                .level] =
                                            v;
                                        StorageService.syncWithDisk();
                                      });
                                    },
                                  ),
                                if (config.obstaclesCount > 1)
                                  _buildCounterRow(
                                    label: 'Преграды',
                                    value: effObstacles,
                                    min: 1,
                                    max: config.obstaclesCount,
                                    color: activeTheme.primaryColor,
                                    onChanged: (v) {
                                      setState(() {
                                        StorageService.customObstacles[config
                                                .level] =
                                            v;
                                        StorageService.syncWithDisk();
                                      });
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const Divider(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                'Идеальных побед на уровне: $wins',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (!isUnlocked && config.level > 1) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Требуется побед на\nуровне ${config.level - 1}: $prevWins / ${config.winsRequiredFromPrevious}',
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    color:
                                        prevWins >=
                                            config.winsRequiredFromPrevious
                                        ? Colors.green
                                        : Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// ЭКРАН МАГАЗИНА ТЕМ
// =========================================================================
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  void _buyTheme(GameTheme theme) {
    if (StorageService.userTotalBank < theme.price) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Недостаточно монет!'),
          content: Text(
            'Для покупки темы "${theme.name}" требуется ${theme.price} $coin.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Понятно'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      StorageService.userTotalBank -= theme.price;
      StorageService.unlockedThemes.add(theme.id);
      StorageService.syncWithDisk();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Вы успешно приобрели тему "${theme.name}"!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _buyConsumable(String type, int price) {
    if (StorageService.userTotalBank < price) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Недостаточно монет!'),
          content: Text('Вам не хватает монет для покупки товара.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Ок'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      StorageService.userTotalBank -= price;
      if (type == 'shield') {
        StorageService.itemShieldCount++;
      } else {
        StorageService.itemXrayCount++;
      }
      StorageService.syncWithDisk();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Покупка успешно совершена!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeTheme = getActiveTheme();
    return Scaffold(
      appBar: AppBar(title: const Text('Магазин'), centerTitle: true),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: activeTheme.primaryColor.withValues(alpha: 0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Баланс: ${StorageService.userTotalBank} $coin',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Row(
                  children: [
                    Text('🛡️ x${StorageService.itemShieldCount}'),
                    const SizedBox(width: 14),
                    Text('👁️ x${StorageService.itemXrayCount}'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Расходники работают в любом режиме: щит отменяет ошибку,
                  // рентген возвращает поле на 3 секунды (в слепом режиме это
                  // как раз его главный смысл).
                  const Text(
                    'Вспомогательные расходники:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildItemCard(
                          icon: '🛡️',
                          title: 'Щит Спасения',
                          desc: 'Защищает от 1 промаха',
                          price: 1000,
                          onBuy: () => _buyConsumable('shield', 1000),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildItemCard(
                          icon: '👁️',
                          title: 'Рентген-визор',
                          desc: 'Показывает объекты на 3 сек',
                          price: 1500,
                          onBuy: () => _buyConsumable('xray', 1500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Комплексные Игровые Темы:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: gameThemes.length,
                    itemBuilder: (context, index) {
                      final theme = gameThemes[index];
                      final isUnlocked =
                          StorageService.unlockedThemes.contains(theme.id) ||
                          StorageService.devModeActive;
                      final isActive = activeThemeIdNotifier.value == theme.id;

                      Widget actionButton;
                      if (isActive) {
                        actionButton = const Chip(
                          label: Text(
                            'Активна',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          backgroundColor: Colors.green,
                        );
                      } else if (isUnlocked) {
                        actionButton = ElevatedButton(
                          onPressed: () {
                            setState(() {
                              activeThemeIdNotifier.value = theme.id;
                              StorageService.syncWithDisk();
                            });
                          },
                          child: const Text('Применить'),
                        );
                      } else {
                        actionButton = ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                          ),
                          onPressed: () => _buyTheme(theme),
                          icon: const Icon(
                            Icons.shopping_cart,
                            size: 16,
                            color: Colors.white,
                          ),
                          label: Text(
                            '${theme.price} $coin',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isActive
                                ? theme.primaryColor
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: theme.primaryColor.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Text(
                                    '🎨',
                                    style: TextStyle(fontSize: 24),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      theme.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      em('${theme.obj1}  /  ${theme.obj2}\nПреграда: ${theme.obstacle}'),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              actionButton,
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard({
    required String icon,
    required String title,
    required String desc,
    required int price,
    required VoidCallback onBuy,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              desc,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: onBuy,
              child: Text(
                '$price $coin',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// НАСТРОЙКИ СЕТКИ И ФОНА
// =========================================================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final activeTheme = getActiveTheme();
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                SwitchListenable(
                  title: 'Тёмная тема',
                  subtitle: 'Комфортный режим для глаз',
                  value: themeNotifier.value == ThemeMode.dark,
                  onChanged: (val) {
                    setState(() {
                      themeNotifier.value = val
                          ? ThemeMode.dark
                          : ThemeMode.light;
                      StorageService.syncWithDisk();
                    });
                  },
                ),
                const Divider(height: 1),
                SwitchListenable(
                  title: 'Слепой режим',
                  subtitle: 'Во время раунда поле скрыто — только кнопки (награда ×2 $coin)',
                  value: StorageService.isBlindModeGlobal,
                  onChanged: (val) {
                    setState(() {
                      StorageService.isBlindModeGlobal = val;
                      StorageService.syncWithDisk();
                    });
                  },
                ),
                // «Панель управления слева» влияет только на обычный режим с
                // видимым полем в ландшафте — в слепом режиме прячем, чтобы не путать.
                if (!StorageService.isBlindModeGlobal) ...[
                  const Divider(height: 1),
                  SwitchListenable(
                    title: 'Панель управления слева',
                    subtitle: 'Адаптация интерфейса в ландшафте',
                    value: StorageService.controlsOnLeft,
                    onChanged: (val) {
                      setState(() {
                        StorageService.controlsOnLeft = val;
                        StorageService.syncWithDisk();
                      });
                    },
                  ),
                ],
                const Divider(height: 1),
                SwitchListenable(
                  title: 'Отображение текста хода',
                  subtitle: 'Показывать текстовое описание шагов в матче',
                  value: StorageService.showSpeechText,
                  onChanged: (val) {
                    setState(() {
                      StorageService.showSpeechText = val;
                      StorageService.syncWithDisk();
                    });
                  },
                ),
                const Divider(height: 1),
                SwitchListenable(
                  title: 'Женский голос диктора',
                  subtitle: 'Переключить озвучку: выкл — мужской, вкл — женский',
                  value: StorageService.voiceFemale,
                  onChanged: (val) {
                    setState(() {
                      StorageService.voiceFemale = val;
                      StorageService.syncWithDisk();
                      VoiceService.stop();
                    });
                  },
                ),
                const Divider(height: 1),
                SwitchListenable(
                  title: 'Режим тестировщика',
                  subtitle: 'Включить подсказки реальных позиций',
                  value: StorageService.devModeActive,
                  onChanged: (val) {
                    setState(() {
                      StorageService.devModeActive = val;
                      // В режиме тестировщика открыты все уровни. При его
                      // выключении активный уровень может оказаться закрытым —
                      // откатываем на максимальный купленный.
                      StorageService.activeDifficulty =
                          StorageService.effectiveDifficulty();
                      StorageService.syncWithDisk();
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Громкость голоса диктора',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Text(
            'Насколько громко диктор произносит ходы и подсказки',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          Slider(
            value: TTSEngine.volume,
            activeColor: activeTheme.primaryColor,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            label: (TTSEngine.volume * 100).round().toString(),
            onChanged: (val) {
              setState(() {
                TTSEngine.volume = val;
              });
            },
            onChangeEnd: (val) => StorageService.syncWithDisk(),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Сброс прогресса?'),
                  content: const Text(
                    'Это действие безвозвратно удалит монеты, открытые темы и сложности.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear();
                        await StorageService.loadData();

                        if (context.mounted) {
                          Navigator.pop(context);
                          Navigator.pop(context);
                        }
                      },
                      child: const Text(
                        'Сбросить',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
            },
            child: const Text(
              'Сбросить весь прогресс',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SwitchListenable extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SwitchListenable({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}

// =========================================================================
// ЭКРАН 5: ПРОЦЕСС СЕССИИ ИГРЫ
// =========================================================================
class GameScreen extends StatefulWidget {
  final DifficultyConfig config;

  const GameScreen({super.key, required this.config});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  bool isMemorizing = true;
  int memorizationTime = 4;
  int currentRound = 1;
  int maxRounds = 10;
  int coinsEarned = 0;

  // Фактическое количество объектов/преград в этой сессии — с учётом настройки
  // игрока на экране «Сложность» (но не больше максимума уровня).
  late final int effObjects = StorageService.effectiveObjects(widget.config);
  late final int effObstacles = StorageService.effectiveObstacles(widget.config);

  bool xrayActive = false;
  List<Point<int>> obstacleCoordinates = [];
  List<ObjectState> objects = [];
  PendingMove? currentMove;

  final Random _random = Random();
  bool isGameOver = false;

  // Сессия записывается в журнал ровно один раз — из какой бы точки она ни
  // завершилась (поражение, промах в супер-игре, «Забрать монеты», выход
  // кнопкой «назад»).
  bool _sessionRecorded = false;

  // Короткая блокировка кнопок сразу после появления нового хода. В ландшафте
  // зоны нажатия занимают половину экрана, и случайный второй тап иначе
  // отвечал бы на ещё не прозвучавший ход — почти гарантированный проигрыш.
  bool _inputLocked = false;

  // План раунда: все вариации пула уровня (баланс 50/50), генерируется при
  // спавне расстановки; ходы идут строго по плану.
  List<PlannedMove> _roundPlan = [];

  List<String> devLogs = [];

  bool superGameMode = false;
  int superGameStep = 1;
  bool superGameFailed = false;
  bool superGameSuccess = false;
  List<int> tappedIndices = [];

  @override
  void initState() {
    super.initState();
    // Раунд = все вариации пула уровня (по страницам уровней):
    // 16 / 16 / 16 / 24 / 20 / 20 / 48 / 28 / 28 / 28 ходов.
    maxRounds = roundLength(widget.config);
    _setupInitialGrid();
    _startMemorizationCountdown();
  }

  void _setupInitialGrid() {
    obstacleCoordinates.clear();
    while (obstacleCoordinates.length < effObstacles) {
      final p = Point(
        _random.nextInt(widget.config.gridSize),
        _random.nextInt(widget.config.gridSize),
      );
      if (!obstacleCoordinates.contains(p)) {
        obstacleCoordinates.add(p);
      }
    }

    objects.clear();
    final theme = getActiveTheme();

    Point<int>? p1;
    while (p1 == null) {
      final p = Point(
        _random.nextInt(widget.config.gridSize),
        _random.nextInt(widget.config.gridSize),
      );
      if (!obstacleCoordinates.contains(p)) {
        p1 = p;
      }
    }
    objects.add(
      ObjectState(id: 1, x: p1.x, y: p1.y, emoji: em(theme.obj1).split(' ').first),
    );

    if (effObjects > 1) {
      Point<int>? p2;
      while (p2 == null) {
        final p = Point(
          _random.nextInt(widget.config.gridSize),
          _random.nextInt(widget.config.gridSize),
        );
        if (!obstacleCoordinates.contains(p) && p != p1) {
          p2 = p;
        }
      }
      objects.add(
        ObjectState(
          id: 2,
          x: p2.x,
          y: p2.y,
          emoji: em(theme.obj2).split(' ').first,
        ),
      );
    }

    // Сразу строим план раунда от стартовой расстановки: все вариации пула
    // уровня в случайном порядке с балансом ровно 50/50 ДАЛЬШЕ/СТОП.
    _roundPlan = generateRoundPlan(
      config: widget.config,
      objectStarts: [for (final o in objects) Point(o.x, o.y)],
      obstacles: obstacleCoordinates,
      rand: _random,
    );

    _logDev("--- СПАВН ОБЪЕКТОВ И ПРЕПЯТСТВИЙ ---");
    _logDev(
      "Размер сетки: ${widget.config.gridSize}x${widget.config.gridSize}",
    );
    _logDev("Камни: $obstacleCoordinates");
    for (var obj in objects) {
      _logDev("Объект ${obj.id} [${obj.emoji}] спавн на: (${obj.x}, ${obj.y})");
    }
    _logDev(
      "План раунда (${maxRounds ~/ 2}/${maxRounds ~/ 2}): "
      "${_roundPlan.map((p) => '${p.objectId}:${p.move}').join(' · ')}",
    );
  }

  void _logDev(String message) {
    setState(() {
      devLogs.add("[LOG] $message");
    });
    debugPrint("[GAME DEV LOG] $message");
  }

  void _startMemorizationCountdown() {
    VoiceService.speakStatic("memorize");
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        memorizationTime--;
      });
      return memorizationTime > 0;
    }).then((_) {
      if (mounted) {
        setState(() {
          isMemorizing = false;
        });
        _generateNextStep();
      }
    });
  }

  void _generateNextStep() {
    if (currentRound > maxRounds) {
      _triggerPerfectFinish();
      return;
    }

    // Очередной ход из плана раунда: адресат и вариация зафиксированы планом.
    final PlannedMove planned = _roundPlan[currentRound - 1];
    final activeObj = objects.firstWhere(
      (o) => o.id == planned.objectId,
      orElse: () => objects.first,
    );
    final theme = getActiveTheme();
    String fullObjName = activeObj.id == 1 ? theme.obj1 : theme.obj2;

    final config = widget.config;

    final List<MoveSegment> segments = moveSegmentsFor(planned.move);

    // Суммарный сдвиг по сегментам — проверяем только финальную клетку.
    int nextX = activeObj.x;
    int nextY = activeObj.y;
    for (final seg in segments) {
      switch (seg.dir) {
        case "влево":
          nextX -= seg.step;
          break;
        case "вправо":
          nextX += seg.step;
          break;
        case "вверх":
          nextY -= seg.step;
          break;
        case "вниз":
          nextY += seg.step;
          break;
      }
    }

    bool isInside =
        nextX >= 0 &&
        nextX < config.gridSize &&
        nextY >= 0 &&
        nextY < config.gridSize;
    bool landsOnObstacle = obstacleCoordinates.contains(Point(nextX, nextY));

    bool landsOnOtherObject = false;
    for (var o in objects) {
      if (o.id != activeObj.id && o.x == nextX && o.y == nextY) {
        landsOnOtherObject = true;
      }
    }

    bool isSafe = isInside && !landsOnObstacle && !landsOnOtherObject;

    MoveSpeech speech = TTSEngine.generateMove(
      rawName: fullObjName,
      segments: segments,
    );

    setState(() {
      currentMove = PendingMove(
        objectId: activeObj.id,
        objectEmoji: activeObj.emoji,
        directionText: segments.map((s) => "${s.dir} ${s.step}").join(" + "),
        step: segments.fold(0, (sum, s) => sum + s.step),
        nextX: nextX,
        nextY: nextY,
        isSafe: isSafe,
        speechText: speech.text,
        speechClips: speech.clips,
      );
    });

    _logDev(
      "ХОД $currentRound. ${activeObj.emoji} из (${activeObj.x}, ${activeObj.y}) -> Цель: ($nextX, $nextY). Безопасен: $isSafe.",
    );
    _lockInput();
    VoiceService.speakMove(speech);
  }

  // Ход только что объявлен — на пол-секунды глушим кнопки. Осмысленный ответ
  // всё равно приходит позже (фраза диктора длится секунды), а «залипший»
  // второй тап по предыдущему ходу теперь ничего не ломает.
  void _lockInput() {
    _inputLocked = true;
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _inputLocked = false);
    });
  }

  void _onPlayerDecision(bool playerSaysSafe) {
    if (currentMove == null || _inputLocked) return;

    setState(() {
      xrayActive = false;
    });

    bool isCorrect = (playerSaysSafe == currentMove!.isSafe);

    if (isCorrect) {
      int reward = widget.config.pointsFor(effObjects, effObstacles);
      if (StorageService.isBlindModeGlobal) reward *= 2;

      setState(() {
        if (currentMove!.isSafe) {
          final activeObj = objects.firstWhere(
            (o) => o.id == currentMove!.objectId,
          );
          activeObj.x = currentMove!.nextX;
          activeObj.y = currentMove!.nextY;
          coinsEarned += reward;
          currentRound++;
          _logDev(
            "УСПЕХ: Объект ${activeObj.emoji} перемещен на (${activeObj.x}, ${activeObj.y}). Ход пройден.",
          );
        } else {
          coinsEarned += (reward ~/ 2);
          // Раунд — фиксированный план ходов: предотвращённый тупик тоже
          // расходует ход, счётчик идёт дальше по плану.
          currentRound++;
          _logDev(
            "УСПЕХ: Предотвращен тупик! Объект остался на месте. Следующий ход плана.",
          );
        }
      });

      _generateNextStep();
    } else {
      // Щит спасает от поражения в любом режиме: поле ему не нужно, он просто
      // отменяет ошибку и даёт переотвечать на тот же ход.
      if (StorageService.itemShieldCount > 0) {
        setState(() {
          StorageService.itemShieldCount--;
        });
        StorageService.syncWithDisk();

        _showCustomDialog(
          title: '🛡️ Щит Спас Вас!',
          content:
              'Был израсходован Щит Спасения. Ход прозвучит ещё раз — ответьте заново.',
          buttonText: 'Уф, спасибо!',
        ).then((_) {
          // Повторяем ход голосом: после диалога игрок мог его забыть.
          final move = currentMove;
          if (!mounted || move == null) return;
          _lockInput();
          VoiceService.speakMove(
            MoveSpeech(move.speechText, move.speechClips),
          );
        });
        _logDev("ОШИБКА: Использован автоматический Щит. Сессия спасена.");
        return;
      }

      _triggerGameOver();
    }
  }

  // Единственная точка записи сессии в журнал: повторные вызовы игнорируются,
  // поэтому монеты не пропадут и не начислятся дважды, каким бы путём игрок ни
  // вышел из матча.
  void _recordSession(bool perfect) {
    if (_sessionRecorded) return;
    _sessionRecorded = true;
    StorageService.addSessionToHistory(
      coinsEarned,
      perfect,
      widget.config.level,
    );
  }

  void _triggerGameOver() {
    // Две разные ошибки — две разные фразы: нажал «Дальше» на тупике
    // (объект «попал в тупик») или нажал «Стоп» на чистом пути.
    VoiceService.speakStatic(
      currentMove?.isSafe == true ? "game_over_safe" : "game_over",
    );
    setState(() {
      isGameOver = true;
    });
    _recordSession(false);
  }

  void _triggerPerfectFinish() {
    VoiceService.speakStatic("perfect_finish");
    setState(() {
      superGameMode = true;
      tappedIndices.clear();
    });
  }

  void _onSuperGameCellTap(int index) {
    if (superGameFailed || superGameSuccess) return;
    // Повторный тап по уже открытой ячейке (найденному объекту) — не промах,
    // просто игнорируем, чтобы случайный двойной тап не завершал супер-игру.
    if (tappedIndices.contains(index)) return;

    int col = index % widget.config.gridSize;
    int row = index ~/ widget.config.gridSize;

    bool clickedObstacle = obstacleCoordinates.contains(Point(col, row));
    if (clickedObstacle) {
      setState(() {
        superGameFailed = true;
        tappedIndices.add(index);
      });
      VoiceService.speakStatic("supergame_trap");
      _recordSession(true);
      return;
    }

    if (superGameStep == 1) {
      final obj1 = objects[0];
      if (obj1.x == col && obj1.y == row) {
        // Один объект в матче — «первого/второго» нет, сразу удвоение.
        VoiceService.speakStatic(
          objects.length == 1 ? "found_single" : "found_first",
        );
        setState(() {
          tappedIndices.add(index);
          if (objects.length == 1) {
            superGameSuccess = true;
            coinsEarned *= 2;
          } else {
            superGameStep = 2;
          }
        });
      } else {
        _handleSuperGameMiss(index);
      }
    } else if (superGameStep == 2) {
      final obj2 = objects[1];
      if (obj2.x == col && obj2.y == row) {
        VoiceService.speakStatic("found_second");
        setState(() {
          tappedIndices.add(index);
          superGameSuccess = true;
          coinsEarned *= 2;
        });
      } else {
        _handleSuperGameMiss(index);
      }
    }
  }

  void _handleSuperGameMiss(int index) {
    int col = index % widget.config.gridSize;
    int row = index ~/ widget.config.gridSize;
    // Тап по клетке второго объекта раньше первого — это ошибка порядка,
    // а не «пустая ячейка»: фраза диктора должна соответствовать.
    final bool hitOtherObject = objects.any((o) => o.x == col && o.y == row);
    setState(() {
      superGameFailed = true;
      tappedIndices.add(index);
    });
    VoiceService.speakStatic(hitOtherObject ? "miss_wrong_order" : "miss_empty");
    _recordSession(true);
  }

  void _completePerfectWithBonus() {
    _recordSession(true);
    Navigator.pop(context);
  }

  void _activateXray() {
    if (StorageService.itemXrayCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'У вас нет Рентген-визоров в инвентаре! Купите в магазине.',
          ),
        ),
      );
      return;
    }

    setState(() {
      StorageService.itemXrayCount--;
      xrayActive = true;
    });

    StorageService.syncWithDisk();
    VoiceService.speakStatic("xray_on");

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          xrayActive = false;
        });
      }
    });
  }

  Future<void> _showCustomDialog({
    required String title,
    required String content,
    required String buttonText,
  }) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeTheme = getActiveTheme();

    // В слепом режиме во время раундов показываем только кнопки (без поля).
    // Исключения, когда поле нужно вернуть: рентген (он ровно для того и
    // покупается — на 3 секунды показать реальные позиции) и режим
    // тестировщика (иначе полупрозрачные подсказки и лог координат негде
    // рисовать, и режим бесполезен при настройках по умолчанию).
    final bool blindRoundsView =
        StorageService.isBlindModeGlobal &&
        !isMemorizing &&
        !isGameOver &&
        !superGameMode &&
        !xrayActive &&
        !StorageService.devModeActive;

    final Widget scaffold = blindRoundsView
        ? Scaffold(body: _buildEmptyRoundsBody())
        : Scaffold(
            appBar: AppBar(
              // В супер-игре ходов уже нет, а счётчик стоит на maxRounds + 1 —
              // показывать «Ход 17 / 16» нельзя.
              title: Text(
                superGameMode
                    ? 'Супер-игра'
                    : 'Ход ${min(currentRound, maxRounds)} / $maxRounds',
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  VoiceService.stop();
                  Navigator.pop(context);
                },
              ),
              actions: [
                if (!isMemorizing && !isGameOver && !superGameMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: activeTheme.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _activateXray,
                      icon: const Icon(Icons.remove_red_eye_outlined),
                      label: Text('Рентген (${StorageService.itemXrayCount})'),
                    ),
                  ),
              ],
            ),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  bool isLandscape =
                      constraints.maxWidth > constraints.maxHeight;

                  if (isLandscape) {
                    return Row(
                      children: [
                        if (StorageService.controlsOnLeft) ...[
                          Expanded(child: _buildControlsPanel(activeTheme)),
                          const VerticalDivider(width: 1),
                          Expanded(child: _buildGridArea(activeTheme)),
                        ] else ...[
                          Expanded(child: _buildGridArea(activeTheme)),
                          const VerticalDivider(width: 1),
                          Expanded(child: _buildControlsPanel(activeTheme)),
                        ],
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        Expanded(child: _buildGridArea(activeTheme)),
                        const Divider(height: 1),
                        _buildControlsPanel(activeTheme),
                      ],
                    );
                  }
                },
              ),
            ),
          );

    // Останавливаем озвучку, если игрок выходит системной кнопкой «назад»
    // (в пустом режиме своей кнопки выхода на полотне нет).
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        VoiceService.stop();
        // Выход из матча любым способом: заработанное сохраняется — ровно так
        // же, как при поражении (там монеты тоже начисляются). Идеальной
        // сессия считается только если основная фаза пройдена целиком, то есть
        // дошли до супер-игры. Повторную запись гасит _recordSession.
        if (superGameMode || coinsEarned > 0) _recordSession(superGameMode);
      },
      child: scaffold,
    );
  }

  // Полноэкранное полотно режима «пустой экран»: тёмная тема — чёрное,
  // светлая — серое.
  //  • Горизонтально (ландшафт): область под верхней полосой делится на 2
  //    кликабельные зоны (левая = «Дальше», правая = «Стоп»), кнопки по центру.
  //  • Вертикально (портрет): как было раньше — кнопки внизу экрана.
  Widget _buildEmptyRoundsBody() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // Более приятный фон вместо тусклого серого/чёрного: мягкий
    // сине-серый в светлой теме и глубокий тёмный (как у приложения) в тёмной.
    final Color canvasColor = isDark
        ? const Color(0xFF161B24)
        : const Color(0xFFE8ECF2);

    Widget backButton() => IconButton(
      icon: Icon(
        Icons.arrow_back,
        color: isDark ? Colors.white54 : Colors.black54,
      ),
      onPressed: () {
        VoiceService.stop();
        Navigator.pop(context);
      },
    );

    // Рентген в слепом режиме: единственная кнопка, возвращающая поле на
    // 3 секунды. В обычном режиме она живёт в AppBar, а здесь AppBar нет.
    Widget xrayButton() => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? Colors.white70 : Colors.black87,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: _activateXray,
        icon: const Icon(Icons.remove_red_eye_outlined, size: 20),
        label: Text('Рентген (${StorageService.itemXrayCount})'),
      ),
    );

    // Ландшафт: половина экрана — одна большая кликабельная зона.
    Widget tapZone({
      required Color color,
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
    }) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque, // ловим тап по всей зоне
          onTap: onPressed,
          child: Container(
            color: color.withValues(alpha: 0.14), // лёгкая подсветка половины
            alignment: Alignment.center,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                minimumSize: const Size(150, 56),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onPressed,
              icon: Icon(icon, color: Colors.white),
              label: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Портрет: прежняя кнопка (растянута по половине ширины, внизу экрана).
    Widget bottomButton({
      required Color color,
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
    }) {
      return Expanded(
        child: SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onPressed,
            icon: Icon(icon, color: Colors.white),
            label: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    // Текст текущего хода — если включена настройка «Отображение текста хода».
    // Показывает то же, что произнёс диктор (позиции не раскрывает).
    Widget speechLabel() {
      if (!StorageService.showSpeechText) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(
          currentMove?.speechText ?? '',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: canvasColor,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isLandscape = constraints.maxWidth > constraints.maxHeight;

            if (isLandscape) {
              // Зоны на весь экран только в горизонтальном режиме.
              return Column(
                children: [
                  // Верхняя полоса с кнопками выхода и рентгена — НЕ входит
                  // в зоны нажатия «Дальше»/«Стоп».
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        backButton(),
                        const Spacer(),
                        xrayButton(),
                      ],
                    ),
                  ),
                  speechLabel(),
                  Expanded(
                    child: Row(
                      children: [
                        tapZone(
                          color: Colors.green,
                          icon: Icons.arrow_forward_rounded,
                          label: 'Дальше',
                          onPressed: () => _onPlayerDecision(true),
                        ),
                        tapZone(
                          color: Colors.red,
                          icon: Icons.front_hand_rounded,
                          label: 'Стоп',
                          onPressed: () => _onPlayerDecision(false),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            // Портрет — как было: стрелка сверху-слева, кнопки внизу.
            return Stack(
              children: [
                Row(
                  children: [
                    backButton(),
                    const Spacer(),
                    xrayButton(),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const SizedBox(height: 44), // отступ под верхнюю полосу
                      speechLabel(),
                      const Spacer(),
                      Row(
                        children: [
                          bottomButton(
                            color: Colors.green,
                            icon: Icons.arrow_forward_rounded,
                            label: 'Дальше',
                            onPressed: () => _onPlayerDecision(true),
                          ),
                          const SizedBox(width: 12),
                          bottomButton(
                            color: Colors.red,
                            icon: Icons.front_hand_rounded,
                            label: 'Стоп',
                            onPressed: () => _onPlayerDecision(false),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildGridArea(GameTheme activeTheme) {
    bool isBlind = StorageService.isBlindModeGlobal;

    // Акцентный цвет темы: рамка поля и клетки. Именно он визуально отличает
    // «Океан» от «Киберпанка» — на светлом фоне уже приведён к читаемому.
    final Color accent = Theme.of(context).colorScheme.secondary;

    return Center(
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accent.withValues(alpha: 0.45),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.config.gridSize * widget.config.gridSize,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: widget.config.gridSize,
              crossAxisSpacing:
                  4, // Уменьшено расстояние для поддержки сеток 10х10
              mainAxisSpacing: 4,
            ),
            itemBuilder: (context, index) {
              int col = index % widget.config.gridSize;
              int row = index ~/ widget.config.gridSize;

              bool isObstacle = obstacleCoordinates.contains(Point(col, row));
              ObjectState? activeObject;
              for (var o in objects) {
                if (o.x == col && o.y == row) {
                  activeObject = o;
                }
              }

              bool showGridBorders =
                  !isBlind ||
                  isMemorizing ||
                  xrayActive ||
                  isGameOver ||
                  superGameMode ||
                  // Тестировщику нужна разметка: иначе полупрозрачные подсказки
                  // висят в пустоте, без клеток.
                  StorageService.devModeActive;
              Color cellBgColor = Colors.transparent;

              if (showGridBorders) {
                cellBgColor = Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.03);
              }

              Widget? cellContent;

              if (superGameMode) {
                bool isTapped = tappedIndices.contains(index);
                if (isTapped) {
                  if (isObstacle) {
                    cellBgColor = Colors.red.withValues(alpha: 0.3);
                    cellContent = const Text(
                      '❌',
                      style: TextStyle(fontSize: 16),
                    );
                  } else if (activeObject != null) {
                    cellBgColor = Colors.green.withValues(alpha: 0.3);
                    cellContent = Text(
                      activeObject.emoji,
                      style: const TextStyle(fontSize: 18),
                    );
                  } else {
                    cellBgColor = Colors.red.withValues(alpha: 0.2);
                    cellContent = const Text(
                      '💨',
                      style: TextStyle(fontSize: 16),
                    );
                  }
                }
              } else {
                if (isMemorizing || xrayActive || isGameOver) {
                  if (activeObject != null) {
                    cellContent = Text(
                      activeObject.emoji,
                      style: const TextStyle(fontSize: 18),
                    );
                  } else if (isObstacle) {
                    cellContent = Text(
                      em(activeTheme.obstacle).split(' ').first,
                      style: const TextStyle(fontSize: 18),
                    );
                  }
                } else if (StorageService.devModeActive) {
                  if (activeObject != null) {
                    cellContent = Opacity(
                      opacity: 0.45,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          activeObject.emoji,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    );
                  } else if (isObstacle) {
                    cellContent = Opacity(
                      opacity: 0.45,
                      child: Text(
                        em(activeTheme.obstacle).split(' ').first,
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  }
                }
              }

              return GestureDetector(
                onTap: () {
                  if (superGameMode) {
                    _onSuperGameCellTap(index);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    color: cellBgColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: showGridBorders
                          ? accent.withValues(alpha: 0.3)
                          : Colors.transparent,
                    ),
                  ),
                  child: Center(child: cellContent),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildControlsPanel(GameTheme activeTheme) {
    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    if (isGameOver) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'ИГРА ОКОНЧЕНА',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Вы заработали: $coinsEarned $coin',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: activeTheme.primaryColor,
              ),
              onPressed: () {
                setState(() {
                  isGameOver = false;
                  currentRound = 1;
                  coinsEarned = 0;
                  memorizationTime = 4;
                  isMemorizing = true;
                  superGameMode = false;
                  // Полный сброс состояния супер-игры и рентгена, чтобы новая
                  // попытка гарантированно стартовала «с чистого листа».
                  superGameStep = 1;
                  superGameFailed = false;
                  superGameSuccess = false;
                  tappedIndices.clear();
                  xrayActive = false;
                  // Новая попытка — новая сессия в журнале, свой лог и
                  // разблокированные кнопки.
                  _sessionRecorded = false;
                  _inputLocked = false;
                  devLogs.clear();
                  _setupInitialGrid();
                  _startMemorizationCountdown();
                });
              },
              child: const Text(
                'Повторить попытку',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    if (superGameMode) {
      return Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '🔥 СУПЕР-ИГРА УДВОЕНИЯ 🔥',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: hotOrange(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              superGameStep == 1
                  ? 'Где сейчас находится ${objects[0].emoji} ?'
                  : 'Где находится второй объект ${objects[1].emoji} ?',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (superGameFailed) ...[
              const Text(
                'Упс! Неверный тап. Удвоение аннулировано.',
                style: TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Завершить сессию'),
              ),
            ] else if (superGameSuccess) ...[
              Text(
                'ПОТРЯСАЮЩЕ! Вы нашли все цели! Награда х2 $coin!',
                style: TextStyle(
                  color: okGreen(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _completePerfectWithBonus,
                child: const Text('Забрать монеты и выйти'),
              ),
            ] else ...[
              // Про ловушки предупреждаем только если на уровне были камни.
              Text(
                obstacleCoordinates.isEmpty
                    ? 'Тапните по ячейке поля на память.'
                    : 'Тапните по ячейке поля на память.\nОпасайтесь скрытых ловушек на месте камней!',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMemorizing) ...[
            Text(
              'Запоминание позиций... $memorizationTime сек.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: hotOrange(context),
              ),
            ),
          ] else ...[
            if (StorageService.showSpeechText)
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      const Text(
                        'Диктор зачитал ход:',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentMove?.speechText ?? "Генерация...",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: activeTheme.primaryColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 14),
            // ИЗМЕНЕНО: Названия кнопок переименованы в "Дальше" и "Стоп"
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => _onPlayerDecision(true),
                      icon: const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Дальше',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => _onPlayerDecision(false),
                      icon: const Icon(
                        Icons.front_hand_rounded,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Стоп',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$coin Заработано: $coinsEarned',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (StorageService.isBlindModeGlobal)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    // Белым по яркому оранжевому — контраст ~2:1. Берём тёмный
                    // оттенок, чтобы подпись читалась.
                    color: Colors.orange.shade800,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Слепой режим х2',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          if (StorageService.devModeActive && devLogs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              height: 70,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                // Раньше был «чёрный 5%» — в тёмной теме панель сливалась с
                // карточкой, а текст blueGrey был почти нечитаем.
                color: isDarkTheme
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: devLogs.length,
                reverse: true,
                itemBuilder: (context, idx) {
                  return Text(
                    devLogs[devLogs.length - 1 - idx],
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 10,
                      color: isDarkTheme
                          ? Colors.lightBlueAccent.shade100
                          : Colors.blueGrey.shade800,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
