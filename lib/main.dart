import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Глобальный уведомитель для смены темы приложения
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
// Глобальный уведомитель для динамической смены цветовой палитры активной игровой темы
final ValueNotifier<String> activeThemeIdNotifier = ValueNotifier('microworld');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
    ));
    await session.setActive(true);
  } catch (e) {
    debugPrint("Ошибка конфигурации AudioSession: $e");
  }

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
    name: 'Микромир',
    obj1: '🪰 Муха',
    obj2: '🪲 Жук',
    obstacle: '🪨 Камень',
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
// ПОСТОЯННАЯ ПАМЯТЬ НА ДИСКЕ (ХРАНИЛИЩЕ)
// =========================================================================
class StorageService {
  static List<GameSession> gameHistory = [];
  static int userTotalBank = 0;
  static int currentStreak = 1;

  // Отслеживание успешных побед для каждой сложности (для гибридной разблокировки)
  static Map<int, int> difficultyWins = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
  // Список разблокированных сложностей (1 всегда открыта)
  static List<int> unlockedDifficulties = [1];
  // Купленные игровые темы
  static List<String> unlockedThemes = ['microworld'];

  static int itemShieldCount = 0;
  static int itemXrayCount = 0;

  static bool controlsOnLeft = true;
  static bool devModeActive = false; // Режим тестировщика
  static bool isBlindModeGlobal = false; // Глобальный тумблер слепой сетки

  static int activeDifficulty = 1;

  static Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    userTotalBank = prefs.getInt('userTotalBank') ?? 0;
    itemShieldCount = prefs.getInt('itemShieldCount') ?? 0;
    itemXrayCount = prefs.getInt('itemXrayCount') ?? 0;
    controlsOnLeft = prefs.getBool('controlsOnLeft') ?? true;
    isBlindModeGlobal = prefs.getBool('isBlindModeGlobal') ?? false;
    devModeActive = prefs.getBool('devModeActive') ?? false;

    // Загрузка сложностей
    unlockedDifficulties = (prefs.getStringList('unlockedDifficulties') ?? ['1'])
        .map((e) => int.parse(e))
        .toList();
    activeDifficulty = prefs.getInt('activeDifficulty') ?? 1;

    // Загрузка побед по уровням
    String? winsJson = prefs.getString('difficultyWins');
    if (winsJson != null) {
      Map<String, dynamic> decoded = jsonDecode(winsJson);
      difficultyWins = decoded.map((key, value) => MapEntry(int.parse(key), value as int));
    }

    // Загрузка тем
    unlockedThemes = prefs.getStringList('unlockedThemes') ?? ['microworld'];
    activeThemeIdNotifier.value = prefs.getString('activeThemeId') ?? 'microworld';

    // Загрузка истории
    List<String> historyRaw = prefs.getStringList('gameHistoryJson') ?? [];
    gameHistory = historyRaw.map((e) => GameSession.fromJson(jsonDecode(e))).toList();

    // Расчет страйка (Исправление логики дней подряд)
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
      DateTime lastLoginZero = DateTime(lastLogin.year, lastLogin.month, lastLogin.day);

      int diffInDays = todayZero.difference(lastLoginZero).inDays;

      if (diffInDays == 1) {
        currentStreak++;
      } else if (diffInDays > 1) {
        currentStreak = 1;
      }
      // Если diffInDays == 0, страйк сохраняется без изменений
    } else {
      currentStreak = 1;
    }

    await prefs.setString('lastLoginDate', todayZero.toIso8601String());
    await prefs.setInt('currentStreak', currentStreak);
  }

  static Future<void> syncWithDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('userTotalBank', userTotalBank);
    await prefs.setInt('itemShieldCount', itemShieldCount);
    await prefs.setInt('itemXrayCount', itemXrayCount);
    await prefs.setBool('controlsOnLeft', controlsOnLeft);
    await prefs.setBool('isBlindModeGlobal', isBlindModeGlobal);
    await prefs.setBool('devModeActive', devModeActive);

    await prefs.setStringList('unlockedDifficulties', unlockedDifficulties.map((e) => e.toString()).toList());
    await prefs.setInt('activeDifficulty', activeDifficulty);

    await prefs.setString('difficultyWins', jsonEncode(difficultyWins.map((k, v) => MapEntry(k.toString(), v))));
    await prefs.setStringList('unlockedThemes', unlockedThemes);
    await prefs.setString('activeThemeId', activeThemeIdNotifier.value);

    List<String> historyRaw = gameHistory.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('gameHistoryJson', historyRaw);

    await prefs.setBool('isDarkMode', themeNotifier.value == ThemeMode.dark);
  }

  static void addSessionToHistory(int score, bool isPerfect) {
    // Сохраняем победу
    if (isPerfect) {
      difficultyWins[activeDifficulty] = (difficultyWins[activeDifficulty] ?? 0) + 1;
    }

    userTotalBank += score;

    final newSession = GameSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: _getFormattedDate(DateTime.now()),
      score: score,
      themeName: getActiveTheme().name,
      difficultyLevel: activeDifficulty,
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
// НАСТРОЙКИ СЛОЖНОСТЕЙ И КОНФИГУРАЦИЯ
// =========================================================================
class DifficultyConfig {
  final int level;
  final int gridSize;
  final int objectsCount;
  final int obstaclesCount;
  final int maxStep;
  final int unlockCost;
  final int winsRequiredFromPrevious;

  const DifficultyConfig({
    required this.level,
    required this.gridSize,
    required this.objectsCount,
    required this.obstaclesCount,
    required this.maxStep,
    required this.unlockCost,
    required this.winsRequiredFromPrevious,
  });

  // Честное начисление игровых монет в зависимости от уровня сложности
  int get basePoints {
    int points = 10;
    if (gridSize >= 4) points += 5;
    if (gridSize >= 5) points += 10;
    if (objectsCount > 1) points += 5;
    if (obstaclesCount > 0) points += 5;
    if (maxStep > 1) points += 5 * (maxStep - 1);
    return points;
  }
}

final List<DifficultyConfig> difficulties = [
  const DifficultyConfig(level: 1, gridSize: 3, objectsCount: 1, obstaclesCount: 0, maxStep: 1, unlockCost: 0, winsRequiredFromPrevious: 0),
  const DifficultyConfig(level: 2, gridSize: 4, objectsCount: 2, obstaclesCount: 0, maxStep: 1, unlockCost: 1000, winsRequiredFromPrevious: 5),
  const DifficultyConfig(level: 3, gridSize: 4, objectsCount: 1, obstaclesCount: 1, maxStep: 1, unlockCost: 3000, winsRequiredFromPrevious: 5),
  const DifficultyConfig(level: 4, gridSize: 5, objectsCount: 2, obstaclesCount: 1, maxStep: 2, unlockCost: 6000, winsRequiredFromPrevious: 7),
  const DifficultyConfig(level: 5, gridSize: 6, objectsCount: 2, obstaclesCount: 2, maxStep: 3, unlockCost: 12000, winsRequiredFromPrevious: 10),
];

// =========================================================================
// КЛАССЫ СОСТОЯНИЙ И ИГРОВОЙ ДВИЖОК
// =========================================================================
class ObjectState {
  final int id; // 1 или 2
  int x; // col
  int y; // row
  final String emoji;

  ObjectState({required this.id, required this.x, required this.y, required this.emoji});

  ObjectState clone() => ObjectState(id: id, x: x, y: y, emoji: emoji);
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

  PendingMove({
    required this.objectId,
    required this.objectEmoji,
    required this.directionText,
    required this.step,
    required this.nextX,
    required this.nextY,
    required this.isSafe,
    required this.speechText,
  });
}

// =========================================================================
// СИНТЕЗАТОР РЕЧИ (УЛУЧШЕННЫЕ ЖИВЫЕ ШАБЛОНЫ)
// =========================================================================
class TTSEngine {
  static final FlutterTts _flutterTts = FlutterTts();
  static double volume = 0.9;

  static Future<void> init() async {
    await _flutterTts.setLanguage("ru-RU");
    await _flutterTts.setSpeechRate(0.45);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(volume);
    await _flutterTts.setSharedInstance(true);

    try {
      // Использование строго типизированных перечислений вместо сырых строк для предотвращения ошибок iOS компиляции
      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
      );
    } catch (e) {
      debugPrint("Ошибка настройки TTS iOS Audio: $e");
    }
  }

  static Future<void> speak(String text) async {
    await _flutterTts.stop();
    await _flutterTts.setVolume(volume);
    await _flutterTts.speak(text);
  }

  static Future<void> stop() async {
    await _flutterTts.stop();
  }

  static String generateLivelySpeech(String name, String direction, int step) {
    final rand = Random();
    String stepWord = step == 1 ? "одну клетку" : (step == 2 ? "две клетки" : "три клетки");

    List<String> templates = [
      "$name аккуратно перемещается на $stepWord $direction",
      "Теперь $name делает уверенный шаг на $stepWord $direction",
      "Внимание, $name сдвигается на $stepWord $direction",
      "А сейчас $name совершает маневр на $stepWord $direction",
      "$name плавно переползает на $stepWord $direction",
    ];

    return templates[rand.nextInt(templates.length)];
  }
}

// =========================================================================
// ГЛАВНЫЙ КЛАСС ПРИЛОЖЕНИЯ
// =========================================================================
class SpatialMemoryGame extends StatelessWidget {
  const SpatialMemoryGame({super.key});

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
              title: 'Ментальные Границы',
              debugShowCheckedModeBanner: false,
              themeMode: currentMode,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: activeThemeData.primaryColor,
                  brightness: Brightness.light,
                ),
                scaffoldBackgroundColor: const Color(0xFFF9FBFA),
                cardColor: Colors.white,
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: activeThemeData.primaryColor,
                  brightness: Brightness.dark,
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
  int logoTaps = 0;

  @override
  void initState() {
    super.initState();
    TTSEngine.init();
  }

  void _onLogoTap() {
    setState(() {
      logoTaps++;
      if (logoTaps >= 5) {
        StorageService.devModeActive = !StorageService.devModeActive;
        StorageService.syncWithDisk();
        logoTaps = 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              StorageService.devModeActive
                  ? "Режим Тестировщика активирован! Открыт весь контент и включен рентген."
                  : "Режим Тестировщика отключен.",
            ),
            backgroundColor: StorageService.devModeActive ? Colors.green : Colors.red,
          ),
        );
      }
    });
  }

  void _showHowToPlay() {
    showDialog(
      context: context,
      builder: (context) {
        final activeTheme = getActiveTheme();
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.menu_book, color: activeTheme.primaryColor),
              const SizedBox(width: 10),
              const Text('Инструкция к игре', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🎯 Главное правило:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Мысленно отслеживайте траектории движения скрытых объектов на поле. Физически они не перемещаются на экране. Движение озвучивает диктор.',
                ),
                const Divider(height: 20),
                const Text(
                  '🎮 Пошаговый контроль:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Программа озвучивает ровно один ход для случайного объекта. Вы должны моментально принять решение:',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '«Путь чист» — если объект после шага остается в пределах сетки и не натыкается на преграды или финал другого объекта.',
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
                        '«Тупик!» — если шаг выводит объект наружу, на камень/преграду или сталкивает его со второй фишкой.',
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Text(
                  '🪐 Элементы Мира Темы (${activeTheme.name}):',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text('• Фишка 1: ${activeTheme.obj1}'),
                Text('• Фишка 2 (при наличии): ${activeTheme.obj2}'),
                Text('• Преграда Темы: ${activeTheme.obstacle}'),
                const SizedBox(height: 12),
                const Text(
                  '🏆 Сверх-игра:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'В конце безошибочной сессии начнется «Супер-Тап»: по памяти найдите скрытые объекты на пустом поле. Избегайте ловушек на месте препятствий!',
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
    final activeTheme = getActiveTheme();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    onTap: _onLogoTap,
                    child: Hero(
                      tag: 'game_logo',
                      child: Text(
                        'МЕНТАЛЬНЫЕ ГРАНИЦЫ',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: activeTheme.primaryColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
                          const SizedBox(width: 6),
                          Text(
                            'Страйк: ${StorageService.currentStreak} дн.',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          "⚙️ ТЕСТИРОВЩИК АКТИВЕН",
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 30),
                  _buildMenuButton(
                    context,
                    icon: Icons.play_arrow_rounded,
                    label: 'Старт сессии',
                    color: const Color(0xFF14B8A6),
                    onTap: () {
                      final config = difficulties.firstWhere(
                        (element) => element.level == StorageService.activeDifficulty,
                        orElse: () => difficulties[0],
                      );
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
                        MaterialPageRoute(builder: (context) => const UpgradesScreen()),
                      ).then((_) => setState(() {}));
                    },
                  ),
                  _buildMenuButton(
                    context,
                    icon: Icons.shopping_bag_rounded,
                    label: 'Магазин тем',
                    color: const Color(0xFFF59E0B),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ShopScreen()),
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
                        MaterialPageRoute(builder: (context) => const GameHistoryScreen()),
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
                        MaterialPageRoute(builder: (context) => const SettingsScreen()),
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
                        )
                      ],
                    ),
                    child: Text(
                      'Баланс кошелька: ${StorageService.userTotalBank} 🪙',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          elevation: 2,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
      appBar: AppBar(
        title: const Text('Журнал игр'),
        centerTitle: true,
      ),
      body: StorageService.gameHistory.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.grey.withValues(alpha: 0.5)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: activeTheme.primaryColor.withValues(alpha: 0.15),
                      child: Text(
                        "${session.difficultyLevel}⭐",
                        style: TextStyle(color: activeTheme.primaryColor, fontWeight: FontWeight.bold),
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
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.teal,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'ИДЕАЛЬНО',
                              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
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
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '+${session.score}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                        const SizedBox(width: 4),
                        const Text('🪙', style: TextStyle(fontSize: 16)),
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
      _showErrorDialog("Вам нужно набрать как минимум ${config.winsRequiredFromPrevious} идеальных побед на Уровне ${config.level - 1}!\nВаш текущий результат: $previousWins побед.");
      return;
    }

    if (StorageService.userTotalBank < config.unlockCost) {
      _showErrorDialog("Недостаточно монет! Стоимость разблокировки: ${config.unlockCost} 🪙.\nВаш баланс: ${StorageService.userTotalBank} 🪙.");
      return;
    }

    setState(() {
      StorageService.userTotalBank -= config.unlockCost;
      StorageService.unlockedDifficulties.add(config.level);
      StorageService.activeDifficulty = config.level;
      StorageService.syncWithDisk();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Уровень сложности ${config.level} успешно разблокирован!'), backgroundColor: Colors.green),
    );
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Внимание!'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ок')),
        ],
      ),
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
          // Глобальный переключатель Blind Mode теперь удобно находится на главном экране выбора режимов!
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: activeTheme.primaryColor.withValues(alpha: 0.1),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Ваш баланс: ${StorageService.userTotalBank} 🪙',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'Сложность: ${StorageService.activeDifficulty}★',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                const Divider(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Слепой режим (Blind Mode)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Границы ячеек исчезают после старта. Награда за ход: x2 🪙',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
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
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: difficulties.length,
              itemBuilder: (context, index) {
                final config = difficulties[index];
                // В РЕЖИМЕ ТЕСТИРОВЩИКА доступны абсолютно все уровни без ограничений!
                final isUnlocked = StorageService.unlockedDifficulties.contains(config.level) || StorageService.devModeActive;
                final isActive = StorageService.activeDifficulty == config.level;

                final wins = StorageService.difficultyWins[config.level] ?? 0;
                final prevWins = StorageService.difficultyWins[config.level - 1] ?? 0;

                Widget trailingWidget;
                if (isActive) {
                  trailingWidget = const Chip(
                    label: Text('Активен', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    backgroundColor: Colors.green,
                  );
                } else if (isUnlocked) {
                  trailingWidget = ElevatedButton(
                    onPressed: () {
                      setState(() {
                        StorageService.activeDifficulty = config.level;
                        StorageService.syncWithDisk();
                      });
                    },
                    child: const Text('Выбрать'),
                  );
                } else {
                  // Заблокировано
                  trailingWidget = ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                    onPressed: () => _tryUnlock(config),
                    icon: const Icon(Icons.lock_open, size: 16, color: Colors.white),
                    label: Text('${config.unlockCost} 🪙', style: const TextStyle(color: Colors.white)),
                  );
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isActive ? activeTheme.primaryColor : Colors.transparent,
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
                              'Уровень сложности ${config.level}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            trailingWidget,
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('• Размер сетки: ${config.gridSize} x ${config.gridSize}'),
                        Text('• Объектов на поле: ${config.objectsCount} (${config.objectsCount == 1 ? "Один" : "Два"})'),
                        Text('• Статичных преград: ${config.obstaclesCount}'),
                        Text('• Макс. шаг: ±${config.maxStep} клетки'),
                        Text('• Награда за ход: ${config.basePoints} 🪙'),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Идеальных побед на уровне: $wins',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            if (!isUnlocked && config.level > 1)
                              Text(
                                'Требуется побед на Ур. ${config.level - 1}: $prevWins / ${config.winsRequiredFromPrevious}',
                                style: TextStyle(
                                  color: prevWins >= config.winsRequiredFromPrevious ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
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
          content: Text('Для покупки темы "${theme.name}" требуется ${theme.price} 🪙.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Понятно')),
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
      SnackBar(content: Text('Вы успешно приобрели тему "${theme.name}"!'), backgroundColor: Colors.green),
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
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ок')),
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
      const SnackBar(content: Text('Покупка успешно совершена!'), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeTheme = getActiveTheme();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Магазин предметов'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: activeTheme.primaryColor.withValues(alpha: 0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Баланс: ${StorageService.userTotalBank} 🪙',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                  const Text('Вспомогательные расходники:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildItemCard(
                          icon: '🛡️',
                          title: 'Щит Спасения',
                          desc: 'Защищает от 1 промаха',
                          price: 1000, // Цена обновлена до 1000
                          onBuy: () => _buyConsumable('shield', 1000),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildItemCard(
                          icon: '👁️',
                          title: 'Рентген-визор',
                          desc: 'Показывает объекты на 3 сек',
                          price: 1500, // Цена обновлена до 1500
                          onBuy: () => _buyConsumable('xray', 1500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('Комплексные Игровые Темы:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 12),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: gameThemes.length,
                    itemBuilder: (context, index) {
                      final theme = gameThemes[index];
                      // В РЕЖИМЕ ТЕСТИРОВЩИКА доступны абсолютно все темы для мгновенного применения!
                      final isUnlocked = StorageService.unlockedThemes.contains(theme.id) || StorageService.devModeActive;
                      final isActive = activeThemeIdNotifier.value == theme.id;

                      Widget actionButton;
                      if (isActive) {
                        actionButton = const Chip(
                          label: Text('Активна', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                          style: ElevatedButton.styleFrom(backgroundColor: theme.primaryColor),
                          onPressed: () => _buyTheme(theme),
                          icon: const Icon(Icons.shopping_cart, size: 16, color: Colors.white),
                          label: Text('${theme.price} 🪙', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        );
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isActive ? theme.primaryColor : Colors.transparent,
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
                                  color: theme.primaryColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Text('🎨', style: TextStyle(fontSize: 24)),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      theme.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${theme.obj1}  /  ${theme.obj2}\nПреграда: ${theme.obstacle}',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
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
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(desc, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center, maxLines: 2),
            const SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: onBuy,
              child: Text('$price 🪙', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
      appBar: AppBar(
        title: const Text('Настройки'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                SwitchListenable(
                  title: 'Тёмная тема',
                  subtitle: 'Комфортный режим для глаз',
                  value: themeNotifier.value == ThemeMode.dark,
                  onChanged: (val) {
                    setState(() {
                      themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
                      StorageService.syncWithDisk();
                    });
                  },
                ),
                const Divider(height: 1),
                SwitchListenable(
                  title: 'Глобальная слепая сетка',
                  subtitle: 'Размывать границы с самого начала (x2 🪙)',
                  value: StorageService.isBlindModeGlobal,
                  onChanged: (val) {
                    setState(() {
                      StorageService.isBlindModeGlobal = val;
                      StorageService.syncWithDisk();
                    });
                  },
                ),
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
                const Divider(height: 1),
                SwitchListenable(
                  title: 'Режим тестировщика',
                  subtitle: 'Включить подсказки реальных позиций',
                  value: StorageService.devModeActive,
                  onChanged: (val) {
                    setState(() {
                      StorageService.devModeActive = val;
                      StorageService.syncWithDisk();
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Настройки Громкости TTS:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Сброс прогресса?'),
                  content: const Text('Это действие безвозвратно удалит монеты, открытые темы и сложности.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
                    TextButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear();
                        await StorageService.loadData();
                        
                        // Использование context.mounted защищает BuildContext от вызовов сквозь асинхронные задержки
                        if (context.mounted) {
                          Navigator.pop(context);
                          Navigator.pop(context);
                        }
                      },
                      child: const Text('Сбросить', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
            child: const Text('Сбросить весь прогресс', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

// =========================================================================
// ЭКРАН 5: ПРОЦЕСС СЕССИИ ИГРЫ (ОБНОВЛЕННЫЙ ACTIONS FLOW)
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

  bool xrayActive = false;
  List<Point<int>> obstacleCoordinates = [];
  List<ObjectState> objects = [];
  PendingMove? currentMove;

  final Random _random = Random();
  bool isGameOver = false;
  bool isPerfect = false;

  // Лог консоли разработчика
  List<String> devLogs = [];

  // Супер-игра стейт
  bool superGameMode = false;
  int superGameStep = 1; // 1 = Ищем объект 1, 2 = Ищем объект 2
  bool superGameFailed = false;
  bool superGameSuccess = false;
  List<int> tappedIndices = [];

  @override
  void initState() {
    super.initState();
    maxRounds = widget.config.gridSize * 2;
    _setupInitialGrid();
    _startMemorizationCountdown();
  }

  void _setupInitialGrid() {
    // 1. Ставим препятствия
    obstacleCoordinates.clear();
    while (obstacleCoordinates.length < widget.config.obstaclesCount) {
      final p = Point(_random.nextInt(widget.config.gridSize), _random.nextInt(widget.config.gridSize));
      if (!obstacleCoordinates.contains(p)) {
        obstacleCoordinates.add(p);
      }
    }

    // 2. Ставим Объекты
    objects.clear();
    final theme = getActiveTheme();

    // Первый объект
    Point<int>? p1;
    while (p1 == null) {
      final p = Point(_random.nextInt(widget.config.gridSize), _random.nextInt(widget.config.gridSize));
      if (!obstacleCoordinates.contains(p)) {
        p1 = p;
      }
    }
    objects.add(ObjectState(id: 1, x: p1.x, y: p1.y, emoji: theme.obj1.split(' ').first));

    // Второй объект (если по условию их 2)
    if (widget.config.objectsCount > 1) {
      Point<int>? p2;
      while (p2 == null) {
        final p = Point(_random.nextInt(widget.config.gridSize), _random.nextInt(widget.config.gridSize));
        if (!obstacleCoordinates.contains(p) && p != p1) {
          p2 = p;
        }
      }
      objects.add(ObjectState(id: 2, x: p2.x, y: p2.y, emoji: theme.obj2.split(' ').first));
    }

    _logDev("--- СПАВН ОБЪЕКТОВ И ПРЕПЯТСТВИЙ ---");
    _logDev("Размер сетки: ${widget.config.gridSize}x${widget.config.gridSize}");
    _logDev("Камни: $obstacleCoordinates");
    for (var obj in objects) {
      _logDev("Объект ${obj.id} [${obj.emoji}] спавн на: (${obj.x}, ${obj.y})");
    }
  }

  void _logDev(String message) {
    setState(() {
      devLogs.add("[LOG] $message");
    });
    debugPrint("[GAME DEV LOG] $message");
  }

  void _startMemorizationCountdown() {
    TTSEngine.speak("Запомни расположение объектов на поле.");
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

    // Выбираем объект для хода
    final activeObj = objects[_random.nextInt(objects.length)];

    // Генерируем сдвиг по правильной системе координат (без инверсии)
    // 0 = Вверх, 1 = Вниз, 2 = Влево, 3 = Вправо
    int direction = _random.nextInt(4);
    int step = 1;
    if (widget.config.maxStep > 1) {
      step = _random.nextInt(widget.config.maxStep) + 1;
    }

    int nextX = activeObj.x;
    int nextY = activeObj.y;
    String directionStr = "";

    switch (direction) {
      case 0: // Вверх
        nextY = activeObj.y - step;
        directionStr = "вверх";
        break;
      case 1: // Вниз
        nextY = activeObj.y + step;
        directionStr = "вниз";
        break;
      case 2: // Влево
        nextX = activeObj.x - step;
        directionStr = "влево";
        break;
      case 3: // Вправо
        nextX = activeObj.x + step;
        directionStr = "вправо";
        break;
    }

    // Проверка условий коллизии / безопасности
    bool isInside = nextX >= 0 && nextX < widget.config.gridSize && nextY >= 0 && nextY < widget.config.gridSize;
    bool landsOnObstacle = obstacleCoordinates.contains(Point(nextX, nextY));

    // Наступил ли на другого персонажа в конце своего хода
    bool landsOnOtherObject = false;
    for (var o in objects) {
      if (o.id != activeObj.id && o.x == nextX && o.y == nextY) {
        landsOnOtherObject = true;
      }
    }

    bool isSafe = isInside && !landsOnObstacle && !landsOnOtherObject;

    String speech = TTSEngine.generateLivelySpeech(activeObj.emoji, directionStr, step);

    setState(() {
      currentMove = PendingMove(
        objectId: activeObj.id,
        objectEmoji: activeObj.emoji,
        directionText: directionStr,
        step: step,
        nextX: nextX,
        nextY: nextY,
        isSafe: isSafe,
        speechText: speech,
      );
    });

    _logDev("РАУНД $currentRound. Ход для ${activeObj.emoji} -> (${activeObj.x}, ${activeObj.y}) -> $directionStr на $step шаг. Цель: ($nextX, $nextY). Безопасен: $isSafe.");

    TTSEngine.speak(speech);
  }

  // =========================================================================
  // ОБРАБОТКА ВЫБОРА ИГРОКА (КНОПКИ С УЧЕТОМ ИСПРАВЛЕНИЯ БАГА ТУПИКОВ)
  // =========================================================================
  void _onPlayerDecision(bool playerSaysSafe) {
    if (currentMove == null) return;

    // ИСПРАВЛЕНИЕ БАГА РЕНТГЕНА:
    // Как только игрок нажимает на кнопку действия, мы немедленно выключаем рентген.
    // Это не позволяет игроку увидеть, куда математически прыгнула фишка на следующем шаге.
    setState(() {
      xrayActive = false;
    });

    bool isCorrect = (playerSaysSafe == currentMove!.isSafe);

    if (isCorrect) {
      // Игрок ответил правильно!
      int reward = widget.config.basePoints;
      if (StorageService.isBlindModeGlobal) reward *= 2; // х2 за Blind Mode

      setState(() {
        if (currentMove!.isSafe) {
          // Ситуация А (Ход безопасен): Объект физически перемещается, увеличиваем раунд
          final activeObj = objects.firstWhere((o) => o.id == currentMove!.objectId);
          activeObj.x = currentMove!.nextX;
          activeObj.y = currentMove!.nextY;
          coinsEarned += reward;
          currentRound++;
          _logDev("УСПЕХ: Объект ${activeObj.emoji} перемещен на (${activeObj.x}, ${activeObj.y}). Раунд пройден.");
        } else {
          // Ситуация Б (Ход опасен): Игрок нажал "Тупик!", предотвратил аварию.
          // Фишка остается на месте, мы даем 50% награды за внимательность, 
          // но раунд НЕ увеличиваем (генерируем новый ход для раунда)!
          coinsEarned += (reward ~/ 2);
          _logDev("УСПЕХ: Предотвращен тупик! Объект остался на месте. Генерируем новую команду для раунда $currentRound.");
        }
      });

      _generateNextStep();
    } else {
      // ОШИБКА ИГРОКА!
      if (StorageService.itemShieldCount > 0) {
        // Срабатывает Щит!
        setState(() {
          StorageService.itemShieldCount--;
        });
        StorageService.syncWithDisk();

        _showCustomDialog(
          title: '🛡️ Щит Спас Вас!',
          content: 'Был израсходован Щит Спасения. Вы застрахованы от этой ошибки, продолжаем сессию!',
          buttonText: 'Уф, спасибо!',
        );
        _logDev("ОШИБКА: Использован автоматический Щит. Сессия спасена.");
        return;
      }

      // Нет щитов — Конец игры
      _triggerGameOver();
    }
  }

  void _triggerGameOver() {
    TTSEngine.speak("Ой! Вы ошиблись и объект попал в тупик.");
    setState(() {
      isGameOver = true;
    });
    StorageService.addSessionToHistory(coinsEarned, false);
  }

  void _triggerPerfectFinish() {
    TTSEngine.speak("Отличная работа! Идеальная сессия. Запуск супер-игры.");
    setState(() {
      superGameMode = true;
      tappedIndices.clear();
    });
  }

  // =========================================================================
  // СУПЕР ИГРА «СУПЕР-ТАП» ПОИСК ОБЪЕКТОВ
  // =========================================================================
  void _onSuperGameCellTap(int index) {
    if (superGameFailed || superGameSuccess) return;

    int col = index % widget.config.gridSize;
    int row = index ~/ widget.config.gridSize;

    // Проверяем ловушки (где стояли препятствия)
    bool clickedObstacle = obstacleCoordinates.contains(Point(col, row));
    if (clickedObstacle) {
      setState(() {
        superGameFailed = true;
        tappedIndices.add(index);
      });
      TTSEngine.speak("Ловушка! Вы наступили на препятствие. Супер-игра окончена.");
      StorageService.addSessionToHistory(coinsEarned, true); // Все равно заслужил идеальное прохождение
      return;
    }

    if (superGameStep == 1) {
      final obj1 = objects[0];
      if (obj1.x == col && obj1.y == row) {
        TTSEngine.speak("Правильно! Нашли первый объект.");
        setState(() {
          tappedIndices.add(index);
          if (objects.length == 1) {
            superGameSuccess = true;
            coinsEarned *= 2; // Удваиваем монеты за идеальный супер-тап
          } else {
            superGameStep = 2; // Переходим к поиску второго
          }
        });
      } else {
        _handleSuperGameMiss(index);
      }
    } else if (superGameStep == 2) {
      final obj2 = objects[1];
      if (obj2.x == col && obj2.y == row) {
        TTSEngine.speak("Отлично! Нашли второй объект. Монеты удвоены!");
        setState(() {
          tappedIndices.add(index);
          superGameSuccess = true;
          coinsEarned *= 2; // Удваиваем монеты
        });
      } else {
        _handleSuperGameMiss(index);
      }
    }
  }

  void _handleSuperGameMiss(int index) {
    setState(() {
      superGameFailed = true;
      tappedIndices.add(index);
    });
    TTSEngine.speak("Промах! Это была пустая ячейка.");
    StorageService.addSessionToHistory(coinsEarned, true);
  }

  void _completePerfectWithBonus() {
    StorageService.addSessionToHistory(coinsEarned, true);
    Navigator.pop(context);
  }

  // =========================================================================
  // РЕНТГЕН-ПОДСКАЗКА
  // =========================================================================
  void _activateXray() {
    if (StorageService.itemXrayCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('У вас нет Рентген-визоров в инвентаре! Купите в магазине.')),
      );
      return;
    }

    setState(() {
      StorageService.itemXrayCount--;
      xrayActive = true;
    });

    StorageService.syncWithDisk();
    TTSEngine.speak("Рентген активирован на три секунды.");

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          xrayActive = false;
        });
      }
    });
  }

  void _showCustomDialog({required String title, required String content, required String buttonText}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(buttonText)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeTheme = getActiveTheme();

    return Scaffold(
      appBar: AppBar(
        title: Text('Раунд $currentRound / $maxRounds'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            TTSEngine.stop();
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
            bool isLandscape = constraints.maxWidth > constraints.maxHeight;

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
  }

  // =========================================================================
  // КОНСТРУКТОР СЕТКИ С ВАЛИДАЦИЕЙ ОТРИСОВКИ В DARK MODE
  // =========================================================================
  Widget _buildGridArea(GameTheme activeTheme) {
    bool isBlind = StorageService.isBlindModeGlobal;

    return Center(
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: activeTheme.primaryColor.withValues(alpha: 0.3), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 15,
                spreadRadius: 2,
              )
            ],
          ),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.config.gridSize * widget.config.gridSize,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: widget.config.gridSize,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              int col = index % widget.config.gridSize;
              int row = index ~/ widget.config.gridSize;

              // Проверка наличия элементов в ячейке
              bool isObstacle = obstacleCoordinates.contains(Point(col, row));
              ObjectState? activeObject;
              for (var o in objects) {
                if (o.x == col && o.y == row) {
                  activeObject = o;
                }
              }

              // Стилизация границ контейнеров ячеек (Отрисовка в Dark Mode)
              bool showGridBorders = !isBlind || isMemorizing || xrayActive || isGameOver;
              Color cellBgColor = Colors.transparent;

              if (showGridBorders) {
                // В темной теме преобразуем белый фон ячеек через прозрачность
                cellBgColor = Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.03);
              }

              // Отрисовка контента
              Widget? cellContent;

              if (superGameMode) {
                // Отрисовка для Супер-Игры
                bool isTapped = tappedIndices.contains(index);
                if (isTapped) {
                  if (isObstacle) {
                    cellBgColor = Colors.red.withValues(alpha: 0.3);
                    cellContent = const Text('❌', style: TextStyle(fontSize: 22));
                  } else if (activeObject != null) {
                    cellBgColor = Colors.green.withValues(alpha: 0.3);
                    cellContent = Text(activeObject.emoji, style: const TextStyle(fontSize: 24));
                  } else {
                    cellBgColor = Colors.red.withValues(alpha: 0.2);
                    cellContent = const Text('💨', style: TextStyle(fontSize: 22));
                  }
                }
              } else {
                // Обычная сессия
                if (isMemorizing || xrayActive || isGameOver) {
                  if (activeObject != null) {
                    cellContent = Text(activeObject.emoji, style: const TextStyle(fontSize: 24));
                  } else if (isObstacle) {
                    cellContent = Text(activeTheme.obstacle.split(' ').first, style: const TextStyle(fontSize: 24));
                  }
                } else if (StorageService.devModeActive) {
                  // РЕЖИМ ТЕСТИРОВЩИКА: Полупрозрачное отображение позиций
                  if (activeObject != null) {
                    cellContent = Opacity(
                      opacity: 0.45,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(activeObject.emoji, style: const TextStyle(fontSize: 20)),
                      ),
                    );
                  } else if (isObstacle) {
                    cellContent = Opacity(
                      opacity: 0.45,
                      child: Text(activeTheme.obstacle.split(' ').first, style: const TextStyle(fontSize: 20)),
                    );
                  }
                }
              }

              // Использование GestureDetector позволяет обрабатывать тапы по ячейкам в фазе Супер-Игры
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
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: showGridBorders
                          ? activeTheme.primaryColor.withValues(alpha: 0.15)
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

  // =========================================================================
  // ПАНЕЛЬ С ТЕКСТОМ И КНОПКАМИ ДЕЙСТВИЯ (ACTION SYSTEM)
  // =========================================================================
  Widget _buildControlsPanel(GameTheme activeTheme) {
    if (isGameOver) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('ИГРА ОКОНЧЕНА', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 8),
            Text('Вы заработали: $coinsEarned 🪙', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: activeTheme.primaryColor),
              onPressed: () {
                setState(() {
                  isGameOver = false;
                  currentRound = 1;
                  coinsEarned = 0;
                  memorizationTime = 4;
                  isMemorizing = true;
                  superGameMode = false;
                  _setupInitialGrid();
                  _startMemorizationCountdown();
                });
              },
              child: const Text('Повторить попытку', style: TextStyle(color: Colors.white)),
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
            const Text(
              '🔥 СУПЕР-ИГРА УДВОЕНИЯ 🔥',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange),
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
              const Text('Упс! Неверный тап. Удвоение аннулировано.', style: TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Завершить сессию'),
              )
            ] else if (superGameSuccess) ...[
              const Text('ПОТРЯСАЮЩЕ! Вы нашли все цели! Награда х2 🪙!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _completePerfectWithBonus,
                child: const Text('Забрать монеты и выйти'),
              )
            ] else ...[
              const Text(
                'Тапните по ячейке поля на память.\nОпасайтесь скрытых ловушек на месте камней!',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              )
            ]
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
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange),
            ),
            const SizedBox(height: 10),
            const Text(
              'Запомните, где стоят объекты и преграды!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ] else ...[
            // Инструкция и зачитанный диктором шаг
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    const Text(
                      'Диктор зачитал ход:',
                      style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentMove?.speechText ?? "Генерация...",
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: activeTheme.primaryColor),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => _onPlayerDecision(true),
                      icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                      label: const Text(
                        'Путь чист',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => _onPlayerDecision(false),
                      icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
                      label: const Text(
                        'Тупик!',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
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
                '🪙 Заработано: $coinsEarned',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              if (StorageService.isBlindModeGlobal)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Слепой режим х2', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          // Окно логов консоли в режиме тестировщика
          if (StorageService.devModeActive && devLogs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              height: 70,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: devLogs.length,
                reverse: true,
                itemBuilder: (context, idx) {
                  return Text(
                    devLogs[devLogs.length - 1 - idx],
                    style: const TextStyle(fontFamily: 'Courier', fontSize: 10, color: Colors.blueGrey),
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