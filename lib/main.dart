import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

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

class SpatialMemoryGame extends StatelessWidget {
  const SpatialMemoryGame({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'Пространственная память',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.light),
            scaffoldBackgroundColor: const Color(0xFFF9FBFA),
            cardColor: Colors.white,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
            scaffoldBackgroundColor: const Color(0xFF131722),
            cardColor: const Color(0xFF1E222D),
            useMaterial3: true,
          ),
          home: const MainMenuScreen(),
        );
      },
    );
  }
}

// =========================================================================
// ГОЛОСОВОЙ ДВИЖОК
// =========================================================================
class TTSEngine {
  static final FlutterTts _flutterTts = FlutterTts();
  static double volume = 0.9;

  static Future<void> init() async {
    await _flutterTts.setLanguage("ru-RU");
    await _flutterTts.setSpeechRate(0.4); 
    await _flutterTts.setPitch(1.0);      
    await _flutterTts.setVolume(volume);
    
    // За обход Silent Mode отвечает audio_session в main().
    // Удален setIosAudioCategory, который вызывал ошибки типов данных.
    await _flutterTts.setSharedInstance(true);
  }

  static Future<void> speak(String text) async {
    await _flutterTts.stop();
    await _flutterTts.setVolume(volume);
    await _flutterTts.speak(text);
  }

  static Future<void> stopEverything() async {
    await _flutterTts.stop();
  }
}

// =========================================================================
// ПОСТОЯННАЯ ПАМЯТЬ НА ДИСКЕ
// =========================================================================
class StorageService {
  static List<String> gameHistoryRaw = [];
  static int userTotalBank = 0; 
  static int currentStreak = 1;
  
  static int perfect3x3 = 0;
  static int perfect4x4 = 0;

  static String selectedSkin = '🌟';
  static String selectedSkinTwo = '🪰'; 
  
  static final List<String> freeSkins = ['🌟', '🪰', '🪲'];
  static final List<String> allPossibleSkins = ['🌟', '🪰', '🪲', '🍬', '🚗', '🔮', '👽', '👑', '🎲'];
  static List<String> unlockedSkins = ['🌟', '🪰', '🪲'];
  
  static int itemShieldCount = 0;   
  static int itemXrayCount = 0;     

  static bool controlsOnLeft = true;
  static bool devShowPositionsDuringGame = false;

  static GameConfig activeConfig = const GameConfig();

  static final Map<String, String> skinNames = {
    '🌟': 'Звезда',
    '🪰': 'Муха',
    '🪲': 'Жук',
    '🍬': 'Конфета',
    '🚗': 'Машинка',
    '🔮': 'Кристалл',
    '👽': 'Пришелец',
    '👑': 'Корона',
    '🎲': 'Кубик',
  };

  static String getSkinName(String emoji) => skinNames[emoji] ?? 'Объект';

  static Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    userTotalBank = prefs.getInt('userTotalBank') ?? 0;
    currentStreak = prefs.getInt('currentStreak') ?? 1;
    perfect3x3 = prefs.getInt('perfect3x3') ?? 0;
    perfect4x4 = prefs.getInt('perfect4x4') ?? 0;
    itemShieldCount = prefs.getInt('itemShieldCount') ?? 0;
    itemXrayCount = prefs.getInt('itemXrayCount') ?? 0;
    selectedSkin = prefs.getString('selectedSkin') ?? '🌟';
    selectedSkinTwo = prefs.getString('selectedSkinTwo') ?? '🪰';
    
    List<String>? loadedSkins = prefs.getStringList('unlockedSkins');
    if (loadedSkins == null) {
      unlockedSkins = List.from(freeSkins);
    } else {
      unlockedSkins = loadedSkins;
      for (var s in freeSkins) {
        if (!unlockedSkins.contains(s)) unlockedSkins.add(s);
      }
    }
    
    int gSize = prefs.getInt('cfg_gridSize') ?? 3;
    int mStep = prefs.getInt('cfg_maxStep') ?? 1;
    bool bMode = prefs.getBool('cfg_isBlindMode') ?? false;
    bool dMode = prefs.getBool('cfg_dualObjectMode') ?? false;
    activeConfig = GameConfig(gridSize: gSize, maxStep: mStep, isBlindMode: bMode, dualObjectMode: dMode);

    gameHistoryRaw = prefs.getStringList('gameHistoryRaw') ?? [];
    controlsOnLeft = prefs.getBool('controlsOnLeft') ?? true;
    
    bool isDark = prefs.getBool('isDarkMode') ?? false;
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  static Future<void> syncWithDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('userTotalBank', userTotalBank);
    await prefs.setInt('currentStreak', currentStreak);
    await prefs.setInt('perfect3x3', perfect3x3);
    await prefs.setInt('perfect4x4', perfect4x4);
    await prefs.setInt('itemShieldCount', itemShieldCount);
    await prefs.setInt('itemXrayCount', itemXrayCount);
    await prefs.setString('selectedSkin', selectedSkin);
    await prefs.setString('selectedSkinTwo', selectedSkinTwo);
    await prefs.setStringList('unlockedSkins', unlockedSkins);
    
    await prefs.setInt('cfg_gridSize', activeConfig.gridSize);
    await prefs.setInt('cfg_maxStep', activeConfig.maxStep);
    await prefs.setBool('cfg_isBlindMode', activeConfig.isBlindMode);
    await prefs.setBool('cfg_dualObjectMode', activeConfig.dualObjectMode);

    await prefs.setStringList('gameHistoryRaw', gameHistoryRaw);
    await prefs.setBool('controlsOnLeft', controlsOnLeft);
    await prefs.setBool('isDarkMode', themeNotifier.value == ThemeMode.dark);
  }

  static void saveMatch({required int size, required int rounds, required int maxRounds, required int score}) {
    bool isPerfect = (rounds >= maxRounds);
    if (isPerfect) {
      if (size == 3) perfect3x3++;
      if (size == 4) perfect4x4++;
    }

    userTotalBank += score;
    String matchString = '${size}x$size|$score|$rounds/$maxRounds|${DateTime.now().toString().substring(11, 16)}|$isPerfect';
    gameHistoryRaw.insert(0, matchString);
    syncWithDisk();
  }
}

// =========================================================================
// КОНФИГУРАЦИЯ И АНТИ-КОЛЛИЗИОННЫЙ ВАЛИДАТОР СЕТКИ
// =========================================================================
class GameConfig {
  final int gridSize;
  final int maxStep;
  final bool isBlindMode;
  final bool dualObjectMode;

  const GameConfig({
    this.gridSize = 3,
    this.maxStep = 1,
    this.isBlindMode = false,
    this.dualObjectMode = false,
  });

  int get pointsPerMove {
    int base = 10;
    if (gridSize == 4) base += 5;
    if (gridSize == 5) base += 10;
    if (maxStep > 1) base += 5 * (maxStep - 1);
    if (isBlindMode) base = (base * 1.5).round();
    if (dualObjectMode) base *= 2; 
    return base;
  }
}

class MoveResult {
  final String textDescription;
  const MoveResult({required this.textDescription});
}

class ObjectState {
  int x = 0;
  int y = 0;
  int lastValidX = 0;
  int lastValidY = 0;
  final String skin;

  ObjectState(int startX, int startY, this.skin) {
    x = startX;
    y = startY;
    saveValid();
  }

  void saveValid() { lastValidX = x; lastValidY = y; }
  void rollback() { x = lastValidX; y = lastValidY; }
}

class GameValidator {
  final GameConfig config;
  late ObjectState obj1;
  late ObjectState obj2;
  final Random _random = Random();

  int get currentX => obj1.x;
  int get currentY => obj1.y;

  GameValidator({required this.config}) {
    int center = config.gridSize ~/ 2;
    obj1 = ObjectState(center, center, StorageService.selectedSkin);
    
    int obj2X = center == 0 ? 1 : 0;
    int obj2Y = config.gridSize - 1;
    if (obj2X == center && obj2Y == center) {
      obj2X = (center + 1) % config.gridSize;
    }
    obj2 = ObjectState(obj2X, obj2Y, StorageService.selectedSkinTwo);
  }

  int get totalRounds => config.gridSize * config.gridSize;

  bool isInsideBounds(ObjectState obj) => 
      obj.x >= 0 && obj.x < config.gridSize && obj.y >= 0 && obj.y < config.gridSize;

  bool areBothInside() => isInsideBounds(obj1) && isInsideBounds(obj2);

  void saveGlobalValidPositions() {
    if (isInsideBounds(obj1)) obj1.saveValid();
    if (isInsideBounds(obj2)) obj2.saveValid();
  }

  void rollbackGlobalPositions() {
    obj1.rollback();
    obj2.rollback();
  }

  void rollbackToLastValid() {
    rollbackGlobalPositions();
  }

  MoveResult generateNextMove() {
    saveGlobalValidPositions();

    bool moveFirst = _random.nextBool() || !config.dualObjectMode;
    bool moveSecond = _random.nextBool() && config.dualObjectMode;
    if (!moveFirst && !moveSecond) moveFirst = true;

    String desc1 = "";
    String desc2 = "";

    if (moveFirst) desc1 = _shiftObject(obj1, null);
    if (moveSecond) desc2 = _shiftObject(obj2, moveFirst ? obj1 : null);

    String finalVoice = "";
    String name1 = StorageService.getSkinName(obj1.skin);
    String name2 = StorageService.getSkinName(obj2.skin);

    if (desc1.isNotEmpty && desc2.isNotEmpty) {
      finalVoice = "$name1 $desc1. $name2 $desc2.";
    } else if (desc1.isNotEmpty) {
      finalVoice = "$name1 $desc1.";
    } else {
      finalVoice = "$name2 $desc2.";
    }

    return MoveResult(textDescription: finalVoice);
  }

  String _shiftObject(ObjectState obj, ObjectState? otherObj) {
    int roll = _random.nextInt(100) + 1;
    bool shouldStayInside = roll <= 70; 

    int dx = 0; int dy = 0; bool found = false;
    int attempts = 0;

    while (!found && attempts < 100) {
      attempts++;
      dx = _random.nextInt(config.maxStep * 2 + 1) - config.maxStep;
      dy = _random.nextInt(config.maxStep * 2 + 1) - config.maxStep;
      if (dx == 0 && dy == 0) continue;

      int tx = obj.x + dx; int ty = obj.y + dy;
      bool isNextInside = tx >= 0 && tx < config.gridSize && ty >= 0 && ty < config.gridSize;

      if (otherObj != null && tx == otherObj.x && ty == otherObj.y) {
        continue;
      }

      if (shouldStayInside && isNextInside) found = true;
      if (!shouldStayInside && !isNextInside) found = true;
    }

    obj.x += dx;
    obj.y += dy;
    return _buildHumanReadableText(dx, dy);
  }

  String _buildHumanReadableText(int dx, int dy) {
    List<String> parts = [];
    if (dy != 0) parts.add("на ${dy.abs()} ${_getWordForm(dy.abs())} ${dy < 0 ? 'вверх' : 'вниз'}");
    if (dx != 0) parts.add("на ${dx.abs()} ${_getWordForm(dx.abs())} ${dx < 0 ? 'влево' : 'вправо'}");
    return parts.isEmpty ? "остается на месте" : parts.join(" и ");
  }

  String _getWordForm(int count) => count == 1 ? "клетку" : (count >= 2 && count <= 4 ? "клетки" : "клеток");
}

// =========================================================================
// ЭКРАН 1: ГЛАВНОЕ МЕНЮ
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
    TTSEngine.init();
  }

  void _showHowToPlay() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.menu_book, color: Colors.indigo),
            SizedBox(width: 10),
            Text('Полное руководство', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const MaxHeightScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🎯 Главная цель игры:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
              Text('Удержать в голове точное местоположение невидимых фишек на поле, ориентируясь исключительно на слух.'),
              SizedBox(height: 12),
              Text('📋 Пошаговый процесс:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('1. Изучение старта: Первые 4 секунды раунда фишки видны. Запомни их стартовые клетки.'),
              Text('2. Движение: Рамки и фишки исчезают. Диктор зачитывает команды сдвига. Мысленно веди объекты по клеткам.'),
              Text('3. Контроль границ: После каждого хода ты обязан дать ответ.'),
              SizedBox(height: 12),
              Text('🕹️ Назначение кнопок:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('• Кнопка "Внутри": Нажимай, если уверен, что ВСЕ фишки до единой находятся в пределах игровой сетки.'),
              Text('• Кнопка "Вылетел": Нажимай, если ХОТЯ БЫ ОДНА фишка сделала шаг за край поля.'),
              SizedBox(height: 12),
              Text('💎 Расходники и Магазин:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('• 🛡️ Щит: Автоматически страхует от одного неверного ответа в сессии, не позволяя проиграть.'),
              Text('• 👁️ Рентген: Кнопка в верхнем углу экрана. Проявляет сетку и все фишки на 2.5 секунды прямо во время слепого хода.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Всё понятно!'))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  Text(
                    'МЕНТАЛЬНЫЕ ГРАНИЦЫ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28, 
                      fontWeight: FontWeight.w900, 
                      color: Theme.of(context).colorScheme.primary, 
                      letterSpacing: 1.2
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Chip(
                      side: BorderSide.none,
                      backgroundColor: Colors.orange.withValues(alpha: 0.15),
                      avatar: const Icon(Icons.local_fire_department, color: Colors.orange),
                      label: Text('Страйк: ${StorageService.currentStreak} дн.', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                    ),
                  ),
                  const SizedBox(height: 30),
                  _menuBtn(Icons.play_arrow_rounded, 'Старт сессии', const Color(0xFF14B8A6)),
                  _menuBtn(Icons.lock_open_rounded, 'Усложнения (Прогресс)', const Color(0xFF6366F1)),
                  _menuBtn(Icons.shopping_bag_rounded, 'Магазин предметов', const Color(0xFFF59E0B)),
                  _menuBtn(Icons.help_outline_rounded, 'Инструкция к игре', const Color(0xFF10B981)),
                  _menuBtn(Icons.settings_rounded, 'Настройки', const Color(0xFF64748B)),
                  const SizedBox(height: 24),
                  Text(
                    'Баланс кошелька: ${StorageService.userTotalBank} 🪙', 
                    textAlign: TextAlign.center, 
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuBtn(IconData icon, String label, Color col) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: col, 
          elevation: 2,
          padding: const EdgeInsets.symmetric(vertical: 15), 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))
        ),
        onPressed: () {
          if (label == 'Старт сессии') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => GameScreen(config: StorageService.activeConfig)));
          } else if (label == 'Усложнения (Прогресс)') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const UpgradesScreen())).then((_) => setState(() {}));
          } else if (label == 'Магазин предметов') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopScreen())).then((_) => setState(() {}));
          } else if (label == 'Инструкция к игре') {
            _showHowToPlay();
          } else if (label == 'Настройки') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())).then((_) => setState(() {}));
          }
        },
        icon: Icon(icon, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class MaxHeightScrollView extends StatelessWidget {
  final Widget child;
  const MaxHeightScrollView({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      child: SingleChildScrollView(child: child),
    );
  }
}

// =========================================================================
// РЕЖИМ ТЕСТИРОВЩИКА
// =========================================================================
class DeveloperPanelScreen extends StatefulWidget {
  const DeveloperPanelScreen({super.key});
  @override
  State<DeveloperPanelScreen> createState() => _DeveloperPanelScreenState();
}

class _DeveloperPanelScreenState extends State<DeveloperPanelScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚙️ Пульт Тестировщика v2.5'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Ресурсы', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => StorageService.userTotalBank += 10000);
                    StorageService.syncWithDisk();
                  }, 
                  child: const Text('🪙 +10k монет')
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      StorageService.itemShieldCount = 0;
                      StorageService.itemXrayCount = 0;
                      StorageService.userTotalBank = 0;
                    });
                    StorageService.syncWithDisk();
                  }, 
                  child: const Text('🧹 Обнулить ресурсы')
                ),
              ),
            ],
          ),
          const Divider(height: 30),
          const Text('Тумблеры усложнений поля и контента:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red)),
          SwitchListTile(
            title: const Text('Открыть все сетки и прогресс'),
            subtitle: const Text('Имитирует пройденные квалификации 3х3 и 4х4'),
            value: StorageService.perfect3x3 >= 7 && StorageService.perfect4x4 >= 7,
            onChanged: (bool value) {
              setState(() {
                StorageService.perfect3x3 = value ? 7 : 0;
                StorageService.perfect4x4 = value ? 7 : 0;
              });
              StorageService.syncWithDisk();
            },
          ),
          SwitchListTile(
            title: const Text('Разблокировать все скины магазина'),
            subtitle: const Text('Добавляет все образы в гардероб без оплаты'),
            value: StorageService.unlockedSkins.length == StorageService.allPossibleSkins.length,
            onChanged: (bool value) {
              setState(() {
                if (value) {
                  StorageService.unlockedSkins = List.from(StorageService.allPossibleSkins);
                } else {
                  StorageService.unlockedSkins = List.from(StorageService.freeSkins);
                  StorageService.selectedSkin = '🌟';
                  StorageService.selectedSkinTwo = '🪰';
                }
              });
              StorageService.syncWithDisk();
            },
          ),
          SwitchListTile(
            title: const Text('Чит-режим: "Радар"'),
            subtitle: const Text('Объекты остаются видимыми на протяжении всей сессии'),
            value: StorageService.devShowPositionsDuringGame,
            onChanged: (val) {
              setState(() => StorageService.devShowPositionsDuringGame = val);
            },
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black87),
            onPressed: () => TTSEngine.speak("Проверка речевого синтезатора"),
            icon: const Icon(Icons.record_voice_over, color: Colors.white),
            label: const Text('Проверить TTS', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// НАСТРОЙКИ СИСТЕМЫ
// =========================================================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDark = themeNotifier.value == ThemeMode.dark;
  int _developerClickCount = 0; 
  bool _isDevModeUnlocked = false; 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            setState(() {
              _developerClickCount++;
              if (_developerClickCount >= 5 && !_isDevModeUnlocked) {
                _isDevModeUnlocked = true;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🛠️ Режим тестировщика разблокирован!')),
                );
              }
            });
          },
          child: const Text('Настройки системы'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Звуковое сопровождение', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ListTile(
            leading: const Icon(Icons.volume_up),
            title: const Text('Громкость голосового ассистента'),
            subtitle: Slider(
              value: TTSEngine.volume,
              min: 0.0, max: 1.0,
              divisions: 10,
              onChanged: (val) {
                setState(() => TTSEngine.volume = val);
                StorageService.syncWithDisk();
              },
            ),
          ),
          const Divider(),
          const Text('Кастомизация (Ландшафт)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          SwitchListTile(
            title: const Text('Кнопки действий слева'),
            secondary: const Icon(Icons.swap_horizontal_circle_outlined),
            value: StorageService.controlsOnLeft,
            onChanged: (val) {
              setState(() => StorageService.controlsOnLeft = val);
              StorageService.syncWithDisk();
            },
          ),
          const Divider(),
          const Text('Визуальное оформление', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          SwitchListTile(
            title: const Text('Тёмный режим интерфейса'),
            secondary: const Icon(Icons.dark_mode),
            value: _isDark,
            onChanged: (val) {
              setState(() {
                _isDark = val;
                themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
              });
              StorageService.syncWithDisk();
            },
          ),
          const Divider(),
          const Text('Гардероб первого объекта', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: StorageService.unlockedSkins.map((skin) {
              bool isSelected = StorageService.selectedSkin == skin;
              return ChoiceChip(
                label: Text(skin, style: const TextStyle(fontSize: 22)),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => StorageService.selectedSkin = skin);
                    StorageService.syncWithDisk();
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 15),
          const Text('Гардероб второго объекта', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: StorageService.unlockedSkins.map((skin) {
              bool isSelected = StorageService.selectedSkinTwo == skin;
              return ChoiceChip(
                label: Text(skin, style: const TextStyle(fontSize: 22)),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => StorageService.selectedSkinTwo = skin);
                    StorageService.syncWithDisk();
                  }
                },
              );
            }).toList(),
          ),
          if (_isDevModeUnlocked) ...[
            const Divider(height: 40),
            Card(
              color: Colors.red.shade50,
              child: ListTile(
                leading: const Icon(Icons.bug_report, color: Colors.red),
                title: const Text('Режим Тестировщика', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.red),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DeveloperPanelScreen())).then((_) => setState(() {}));
                },
              ),
            ),
          ]
        ],
      ),
    );
  }
}

// =========================================================================
// ДЕРЕВО УСЛОЖНЕНИЙ
// =========================================================================
class UpgradesScreen extends StatefulWidget {
  const UpgradesScreen({super.key});
  @override
  State<UpgradesScreen> createState() => _UpgradesScreenState();
}

class _UpgradesScreenState extends State<UpgradesScreen> {
  late int _size;
  late int _step;
  late bool _blind;
  late bool _dual;

  @override
  void initState() {
    super.initState();
    _size = StorageService.activeConfig.gridSize;
    _step = StorageService.activeConfig.maxStep;
    _blind = StorageService.activeConfig.isBlindMode;
    _dual = StorageService.activeConfig.dualObjectMode;
  }

  @override
  Widget build(BuildContext context) {
    bool canUnlockTier2 = StorageService.perfect3x3 >= 7;

    return Scaffold(
      appBar: AppBar(title: const Text('Дерево усложнений')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Card(
              color: Colors.teal.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Text('🏆 Статистика чистых сессий:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade900)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text('Сетка 3х3: ${StorageService.perfect3x3} / 7 Побед ${StorageService.perfect3x3 >= 7 ? "✅" : ""}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                        Text('Сетка 4х4: ${StorageService.perfect4x4} / 7 Побед ${StorageService.perfect4x4 >= 7 ? "✅" : ""}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Размерность геометрии поля:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(label: const Text('3 x 3'), selected: _size == 3, onSelected: (_) => setState(() => _size = 3)),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('4 x 4 ${canUnlockTier2 ? "" : "🔒"}'), 
                    selected: _size == 4, 
                    onSelected: canUnlockTier2 ? (_) => setState(() => _size = 4) : null
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('5 x 5 ${StorageService.perfect4x4 >= 7 ? "" : "🔒"}'), 
                    selected: _size == 5, 
                    onSelected: StorageService.perfect4x4 >= 7 ? (_) => setState(() => _size = 5) : null
                  ),
                ],
              ),
            ),
            const Divider(height: 30),
            const Text('Модификаторы раунда:', style: TextStyle(fontWeight: FontWeight.bold)),
            SwitchListTile(
              title: const Text('Слебая сетка'),
              subtitle: const Text('Отсутствие рамок с самого старта раунда'),
              value: _blind,
              onChanged: (val) => setState(() => _blind = val),
            ),
            SwitchListTile(
              title: Text('Слежка за двумя объектами ${canUnlockTier2 ? "" : "🔒"}'), 
              value: _dual,
              onChanged: canUnlockTier2 ? (val) => setState(() => _dual = val) : null,
            ),
            ListTile(
              enabled: canUnlockTier2,
              title: Text('Дальность сдвига шага ${canUnlockTier2 ? "" : "🔒"}'),
              trailing: ChoiceChip(
                label: const Text('X2 Сдвиг'), 
                selected: _step == 2, 
                onSelected: canUnlockTier2 ? (val) => setState(() => _step = val ? 2 : 1) : null
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                onPressed: () {
                  StorageService.activeConfig = GameConfig(gridSize: _size, maxStep: _step, isBlindMode: _blind, dualObjectMode: _dual);
                  StorageService.syncWithDisk();
                  Navigator.pop(context);
                },
                child: const Text('Сохранить конфигурацию', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// МАГАЗИН БОНУСОВ
// =========================================================================
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  void _buyItem(int price, VoidCallback onSuccess) {
    if (StorageService.userTotalBank >= price) {
      setState(() {
        StorageService.userTotalBank -= price;
        onSuccess();
      });
      StorageService.syncWithDisk();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Маркетплейс бонусов')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: Text('Баланс: ${StorageService.userTotalBank} 🪙', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.amber))),
          const SizedBox(height: 20),
          const Text('Инвентарь поддержки', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Card(
            child: ListTile(
              title: const Text('🛡️ Щит спасения'), 
              subtitle: Text('Защита от 1 ошибки. В наличии: ${StorageService.itemShieldCount}'),
              trailing: ElevatedButton(onPressed: () => _buyItem(1000, () => StorageService.itemShieldCount++), child: const Text('1000 🪙')),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('👁️ Рентген-подсказка'),
              subtitle: Text('Подсветка на 2.5 сек. В наличии: ${StorageService.itemXrayCount}'),
              trailing: ElevatedButton(onPressed: () => _buyItem(2000, () => StorageService.itemXrayCount++), child: const Text('2000 🪙')),
            ),
          ),
          const Divider(height: 30),
          const Text('Косметические образы', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          _skinRow('🍬 Конфета', '🍬', 300),
          _skinRow('🚗 Машинка', '🚗', 500),
          _skinRow('🔮 Кристалл', '🔮', 700),
          _skinRow('👽 Пришелец', '👽', 1000),
          _skinRow('👑 Корона', '👑', 1500),
          _skinRow('🎲 Кубик', '🎲', 2000),
        ],
      ),
    );
  }

  Widget _skinRow(String title, String char, int cost) {
    bool owned = StorageService.unlockedSkins.contains(char);
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: owned 
          ? const Text('Куплено', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
          : ElevatedButton(onPressed: () => _buyItem(cost, () => StorageService.unlockedSkins.add(char)), child: Text('$cost 🪙')),
      ),
    );
  }
}

// =========================================================================
// ИГРОВОЙ ЭКРАН
// =========================================================================
class GameScreen extends StatefulWidget {
  final GameConfig config;
  const GameScreen({super.key, required this.config});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late GameValidator _validator;
  int _currentRound = 1;
  int _score = 0;
  String _moveMessage = "Запомните положение объектов на поле";
  
  bool _isShowingPhase = true;
  bool _isShieldActiveNow = false;
  bool _showShieldWarningBanner = false; 
  bool _xrayActive = false;
  bool _forceShowGridStructure = false; 

  @override
  void initState() {
    super.initState();
    if (StorageService.itemShieldCount > 0) {
      StorageService.itemShieldCount--;
      _isShieldActiveNow = true;
      StorageService.syncWithDisk();
    }
    _setupGame();
  }

  void _setupGame() {
    _validator = GameValidator(config: widget.config);
    _currentRound = 1;
    _score = 0;
    _isShowingPhase = true;
    _showShieldWarningBanner = false;
    
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() { _isShowingPhase = false; _triggerSystemMove(); });
    });
  }

  void _triggerSystemMove() {
    final move = _validator.generateNextMove();
    setState(() { _moveMessage = move.textDescription; });
    TTSEngine.speak(move.textDescription);
  }

  void _useXray() {
    if (StorageService.itemXrayCount > 0 && !_isShowingPhase && !_xrayActive) {
      setState(() {
        StorageService.itemXrayCount--;
        _xrayActive = true;
        if (widget.config.isBlindMode) {
          _forceShowGridStructure = true; 
        }
      });
      StorageService.syncWithDisk();
      
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted && _xrayActive) {
          setState(() {
            _xrayActive = false;
            _forceShowGridStructure = false; 
          });
        }
      });
    }
  }

  void _processAnswer(bool claimedInside) {
    setState(() {
      _xrayActive = false;
      _forceShowGridStructure = false;
    });

    bool actualInside = _validator.areBothInside();

    if (claimedInside == actualInside) {
      _score += widget.config.pointsPerMove;
      if (!actualInside) {
        _validator.rollbackGlobalPositions();
        setState(() { _moveMessage = "Верно! Возврат на позиции."; });
        TTSEngine.speak("Объекты вернулись назад");
      }
      if (_currentRound >= _validator.totalRounds) {
        _endSession(true);
      } else {
        setState(() { _currentRound++; _triggerSystemMove(); });
      }
    } else {
      if (_isShieldActiveNow) {
        setState(() { 
          _isShieldActiveNow = false; 
          _showShieldWarningBanner = true; 
        });
        _validator.rollbackGlobalPositions();
        
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showShieldWarningBanner = false);
        });

        _triggerSystemMove();
      } else {
        _endSession(false);
      }
    }
  }

  void _endSession(bool success) {
    TTSEngine.stopEverything();

    StorageService.saveMatch(size: widget.config.gridSize, rounds: _currentRound, maxRounds: _validator.totalRounds, score: _score);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ResultsScreen(
      score: _score,
      wasPerfect: success,
      validator: _validator,
      config: widget.config,
      roundsPassed: _currentRound,
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Раунд $_currentRound/${_validator.totalRounds}'),
        centerTitle: true,
        leading: _isShieldActiveNow ? const Center(child: Text('🛡️', style: TextStyle(fontSize: 20))) : null,
        actions: [
          if (StorageService.itemXrayCount > 0 && !_isShowingPhase)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: TextButton.icon(
                style: TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer),
                onPressed: _useXray, 
                icon: const Icon(Icons.visibility), 
                label: Text('Рентген (${StorageService.itemXrayCount})', style: const TextStyle(fontWeight: FontWeight.bold))
              ),
            ),
        ],
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return LayoutBuilder(
            builder: (context, constraints) {
              if (orientation == Orientation.landscape) {
                return SafeArea(child: _buildLandscapeLayout(constraints));
              } else {
                return _buildPortraitLayout();
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildPortraitLayout() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          if (_showShieldWarningBanner) _buildShieldNotificationWidget(),
          _buildHeaderStats(),
          const Spacer(),
          _buildVoiceInstructionCard(),
          const Spacer(),
          AspectRatio(aspectRatio: 1, child: _buildGridSystem()),
          const Spacer(),
          if (!_isShowingPhase) _buildActionButtons(false),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout(BoxConstraints constraints) {
    Widget gridSide = Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          padding: const EdgeInsets.all(2.0),
          child: _buildGridSystem(),
        ),
      ),
    );

    Widget controlSide = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showShieldWarningBanner) _buildShieldNotificationWidget(),
          _buildHeaderStats(),
          _buildVoiceInstructionCard(),
          if (!_isShowingPhase) _buildActionButtons(true),
        ],
      ),
    );

    if (widget.config.isBlindMode && !_isShowingPhase && !_forceShowGridStructure) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: controlSide,
        ),
      );
    }

    return Row(
      children: [
        Expanded(child: StorageService.controlsOnLeft ? controlSide : gridSide),
        Expanded(child: StorageService.controlsOnLeft ? gridSide : controlSide),
      ],
    );
  }

  Widget _buildShieldNotificationWidget() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
      child: const Text(
        '🛡️ Щит спас вас! Продолжаем ход.', 
        style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 11), 
        textAlign: TextAlign.center
      ),
    );
  }

  Widget _buildHeaderStats() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('За ход: +${widget.config.pointsPerMove}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        Text('Счет: $_score', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
      ],
    );
  }

  Widget _buildVoiceInstructionCard() {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 10.0),
        child: Text(
          _moveMessage, 
          textAlign: TextAlign.center, 
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildGridSystem() {
    bool hideGridStructure = widget.config.isBlindMode && !_isShowingPhase && !_forceShowGridStructure;
    if (hideGridStructure) {
      return const SizedBox.shrink(); 
    }

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.config.gridSize * widget.config.gridSize,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.config.gridSize, 
        crossAxisSpacing: 4, 
        mainAxisSpacing: 4
      ),
      itemBuilder: (context, index) {
        int x = index % widget.config.gridSize; 
        int y = index ~/ widget.config.gridSize;
        
        bool isObj1 = (_validator.obj1.x == x && _validator.obj1.y == y);
        bool isObj2 = (_validator.obj2.x == x && _validator.obj2.y == y) && widget.config.dualObjectMode;
        
        bool renderSkins = _isShowingPhase || _xrayActive || StorageService.devShowPositionsDuringGame;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: themeNotifier.value == ThemeMode.dark ? 0.08 : 1.0),
            border: Border.all(color: Colors.grey.shade400, width: 1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: renderSkins 
              ? Text(
                  isObj1 ? _validator.obj1.skin : (isObj2 ? _validator.obj2.skin : ""),
                  style: const TextStyle(fontSize: 22)
                )
              : const SizedBox.shrink(),
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(bool landscapeMode) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: landscapeMode ? 44 : 52, 
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal, 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
              onPressed: () => _processAnswer(true),
              child: const Text('Внутри', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: landscapeMode ? 44 : 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent, 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
              onPressed: () => _processAnswer(false),
              child: const Text('Вылетел', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ],
    );
  }
}

// =========================================================================
// ЭКРАН РЕЗУЛЬТАТОВ
// =========================================================================
class ResultsScreen extends StatefulWidget {
  final int score;
  final bool wasPerfect;
  final GameValidator validator;
  final GameConfig config;
  final int roundsPassed;

  const ResultsScreen({
    super.key, 
    required this.score, 
    required this.wasPerfect, 
    required this.validator, 
    required this.config, 
    required this.roundsPassed
  });
  
  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _bonusPlayed = false;
  late int _finalScore;
  
  int? _selectedIdx1;
  int? _selectedIdx2;
  
  late int _correctIdx1;
  late int _correctIdx2;
  
  int _clickState = 0; 
  bool _wonBonus = false;

  @override
  void initState() {
    super.initState();
    _finalScore = widget.score;
    _correctIdx1 = widget.validator.obj1.lastValidY * widget.config.gridSize + widget.validator.obj1.lastValidX;
    _correctIdx2 = widget.validator.obj2.lastValidY * widget.config.gridSize + widget.validator.obj2.lastValidX;
  }

  String _getRank() {
    if (widget.score == 0) return "Песок памяти ⏳";
    if (!widget.wasPerfect) return "Искатель путей 🗺️";
    if (widget.config.dualObjectMode) return "Двухпоточный Разум 🔮";
    return "Архитектор Пространства 👑";
  }

  void _handleBonusChoice(int index) {
    if (_bonusPlayed) return;

    if (!widget.config.dualObjectMode) {
      setState(() {
        _selectedIdx1 = index;
        _bonusPlayed = true;
        _clickState = 2;
        if (index == _correctIdx1) {
          _wonBonus = true;
          _finalScore *= 2;
          StorageService.userTotalBank += widget.score;
          StorageService.syncWithDisk();
        }
      });
    } else {
      if (_clickState == 0) {
        setState(() {
          _selectedIdx1 = index;
          _clickState = 1; 
        });
      } else if (_clickState == 1) {
        setState(() {
          _selectedIdx2 = index;
          _bonusPlayed = true;
          _clickState = 2;
          
          if (_selectedIdx1 == _correctIdx1 && _selectedIdx2 == _correctIdx2) {
            _wonBonus = true;
            _finalScore *= 3;
            StorageService.userTotalBank += (widget.score * 2);
            StorageService.syncWithDisk();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(widget.wasPerfect ? Icons.workspace_premium_rounded : Icons.heart_broken_rounded, size: 64, color: widget.wasPerfect ? Colors.amber : Colors.redAccent),
              Text(
                widget.wasPerfect ? 'ИДЕАЛЬНАЯ СЕССИЯ!' : 'ИГРА ОКОНЧЕНА',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: widget.wasPerfect ? Colors.teal : Colors.redAccent),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Text('Присвоенный ранг: ${_getRank()}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Text('Раунды: ${widget.roundsPassed}/${widget.validator.totalRounds}'),
                          Text('Награда: +$_finalScore 🪙', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (widget.wasPerfect) ...[
                Text(
                  _clickState == 0 
                      ? '🔥 СУПЕР-ИГРА! Шаг 1 из 2 🔥\nГде прячется объект ${widget.validator.obj1.skin} ?'
                      : _clickState == 1
                          ? '🔥 Отлично! Шаг 2 из 2 🔥\nГде прячется объект ${widget.validator.obj2.skin} ?'
                          : _wonBonus ? '🎯 Идеально! Очки умножены!' : '💨 Промах! В следующий раз повезет.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    color: _clickState == 2 ? (_wonBonus ? Colors.green : Colors.orange) : Colors.indigo
                  )
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: GridView.builder(
                    itemCount: widget.config.gridSize * widget.config.gridSize,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: widget.config.gridSize, crossAxisSpacing: 4, mainAxisSpacing: 4),
                    itemBuilder: (context, index) {
                      Color cellColor = Colors.indigo.withValues(alpha: 0.05);
                      Widget cellChild = const Center(child: Icon(Icons.help_center_outlined, size: 18, color: Colors.indigo));

                      if (_clickState == 1) {
                        if (index == _selectedIdx1) {
                          bool isCorrect = _selectedIdx1 == _correctIdx1;
                          cellColor = isCorrect ? Colors.green.shade200 : Colors.red.shade200;
                          cellChild = Center(child: Text(widget.validator.obj1.skin, style: const TextStyle(fontSize: 20)));
                        }
                      } else if (_clickState == 2) {
                        if (index == _correctIdx1) {
                          cellColor = Colors.green.shade300;
                          cellChild = Center(child: Text(widget.validator.obj1.skin, style: const TextStyle(fontSize: 20)));
                        } else if (index == _correctIdx2 && widget.config.dualObjectMode) {
                          cellColor = Colors.green.shade400;
                          cellChild = Center(child: Text(widget.validator.obj2.skin, style: const TextStyle(fontSize: 20)));
                        } else if (index == _selectedIdx1) {
                          cellColor = Colors.red.shade200;
                          cellChild = const Center(child: Text('❌', style: TextStyle(fontSize: 18)));
                        } else if (index == _selectedIdx2) {
                          cellColor = Colors.red.shade300;
                          cellChild = const Center(child: Text('❌', style: TextStyle(fontSize: 18)));
                        } else {
                          cellChild = const SizedBox.shrink();
                        }
                      }

                      return InkWell(
                        onTap: _bonusPlayed ? null : () => _handleBonusChoice(index),
                        child: Container(
                          decoration: BoxDecoration(color: cellColor, border: Border.all(color: Colors.grey.shade400)),
                          child: cellChild,
                        ),
                      );
                    },
                  ),
                ),
              ] else ...[
                const Spacer(),
              ],
              const SizedBox(height: 12),
              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => GameScreen(config: widget.config))), child: const Text('Повторить сессию', style: TextStyle(color: Colors.white))),
              const SizedBox(height: 6),
              OutlinedButton(onPressed: () => Navigator.popUntil(context, (route) => route.isFirst), child: const Text('В главное меню')),
            ],
          ),
        ),
      ),
    );
  }
}