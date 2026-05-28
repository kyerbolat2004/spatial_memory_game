import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  // Гарантируем инициализацию нативных плагинов перед запуском UI
  WidgetsFlutterBinding.ensureInitialized();
  
  // Загружаем сохраненные данные из постоянной памяти телефона
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
            primarySwatch: Colors.teal,
            scaffoldBackgroundColor: const Color(0xFFF5F7F6),
            useMaterial3: true,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            primarySwatch: Colors.teal,
            scaffoldBackgroundColor: const Color(0xFF121212),
            useMaterial3: true,
            brightness: Brightness.dark,
          ),
          home: const MainMenuScreen(),
        );
      },
    );
  }
}

// =========================================================================
// УЛУЧШЕННЫЙ И ВНЯТНЫЙ ГОЛОСОВОЙ ДВИЖОК
// =========================================================================
class TTSEngine {
  static final FlutterTts _flutterTts = FlutterTts();
  static double volume = 0.9;

  static Future<void> init() async {
    await _flutterTts.setLanguage("ru-RU");
    await _flutterTts.setSpeechRate(0.4); // Еще немного замедляем для внятности
    await _flutterTts.setPitch(1.0);       // Естественный тембр
    await _flutterTts.setVolume(volume);
  }

  static void speak(String text) async {
    // Принудительно останавливаем прошлую фразу, чтобы избежать каши и наложений
    await _flutterTts.stop();
    await _flutterTts.setVolume(volume);
    await _flutterTts.speak(text);
  }
}

// =========================================================================
// ПОЛНОЦЕННАЯ ВЕЧНАЯ ПАМЯТЬ НА ДИСКЕ (Shared Preferences)
// =========================================================================
class StorageService {
  static List<String> gameHistoryRaw = [];
  static int userTotalBank = 0; 
  static int currentStreak = 1;
  
  static int perfect3x3 = 0;
  static int perfect4x4 = 0;

  static String selectedSkin = '🌟';
  static List<String> unlockedSkins = ['🌟'];
  
  static int itemShieldCount = 0;   
  static int itemXrayCount = 0;     

  /// Загрузка данных при старте приложения
  static Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    userTotalBank = prefs.getInt('userTotalBank') ?? 0;
    currentStreak = prefs.getInt('currentStreak') ?? 1;
    perfect3x3 = prefs.getInt('perfect3x3') ?? 0;
    perfect4x4 = prefs.getInt('perfect4x4') ?? 0;
    itemShieldCount = prefs.getInt('itemShieldCount') ?? 0;
    itemXrayCount = prefs.getInt('itemXrayCount') ?? 0;
    selectedSkin = prefs.getString('selectedSkin') ?? '🌟';
    unlockedSkins = prefs.getStringList('unlockedSkins') ?? ['🌟'];
    gameHistoryRaw = prefs.getStringList('gameHistoryRaw') ?? [];
    
    bool isDark = prefs.getBool('isDarkMode') ?? false;
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  /// Синхронизация и сохранение всех параметров на диск
  static Future<void> syncWithDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('userTotalBank', userTotalBank);
    await prefs.setInt('currentStreak', currentStreak);
    await prefs.setInt('perfect3x3', perfect3x3);
    await prefs.setInt('perfect4x4', perfect4x4);
    await prefs.setInt('itemShieldCount', itemShieldCount);
    await prefs.setInt('itemXrayCount', itemXrayCount);
    await prefs.setString('selectedSkin', selectedSkin);
    await prefs.setStringList('unlockedSkins', unlockedSkins);
    await prefs.setStringList('gameHistoryRaw', gameHistoryRaw);
    await prefs.setBool('isDarkMode', themeNotifier.value == ThemeMode.dark);
  }

  static List<Map<String, dynamic>> get gameHistory {
    return gameHistoryRaw.map((item) {
      final parts = item.split('|');
      return {
        'gridSize': parts[0],
        'score': int.parse(parts[1]),
        'rounds': parts[2],
        'date': parts[3],
        'isPerfect': parts[4] == 'true',
      };
    }).toList();
  }

  static void saveMatch({required int size, required int rounds, required int maxRounds, required int score}) {
    bool isPerfect = (rounds >= maxRounds);
    if (isPerfect) {
      if (size == 3) perfect3x3++;
      if (size == 4) perfect4x4++;
    }

    userTotalBank += score;
    
    // Кодируем структуру в строку для сохранения на диск
    String matchString = '${size}x$size|$score|$rounds/$maxRounds|${DateTime.now().toString().substring(11, 16)}|$isPerfect';
    gameHistoryRaw.insert(0, matchString);
    
    syncWithDisk(); // Пишем на диск
  }
}

// =========================================================================
// КОНФИГУРАЦИЯ И ВАЛИДАТОР
// =========================================================================
class GameConfig {
  final int gridSize;
  final int maxStep;
  final bool isBlindMode;

  const GameConfig({this.gridSize = 3, this.maxStep = 1, this.isBlindMode = false});

  int get pointsPerMove {
    int base = 10;
    if (gridSize == 4) base += 5;
    if (gridSize == 5) base += 10;
    if (maxStep > 1) base += 5 * (maxStep - 1);
    if (isBlindMode) base = (base * 1.5).round();
    return base;
  }
}

class MoveResult {
  final int dx;
  final int dy;
  final String textDescription;
  const MoveResult({required this.dx, required this.dy, required this.textDescription});
}

class GameValidator {
  final GameConfig config;
  int _currentX = 0;
  int _currentY = 0;
  int _lastValidX = 0;
  int _lastValidY = 0;
  final Random _random = Random();

  GameValidator({required this.config}) {
    _currentX = config.gridSize ~/ 2;
    _currentY = config.gridSize ~/ 2;
    _saveValidPosition();
  }

  int get currentX => _currentX;
  int get currentY => _currentY;
  int get totalRounds => config.gridSize * config.gridSize;

  void _saveValidPosition() { _lastValidX = _currentX; _lastValidY = _currentY; }
  void rollbackToLastValid() { _currentX = _lastValidX; _currentY = _lastValidY; }
  bool isInsideBounds() => _currentX >= 0 && _currentX < config.gridSize && _currentY >= 0 && _currentY < config.gridSize;

  bool _canExitFromCurrentPosition() {
    for (int dx = -config.maxStep; dx <= config.maxStep; dx++) {
      for (int dy = -config.maxStep; dy <= config.maxStep; dy++) {
        if (dx == 0 && dy == 0) continue;
        int tx = _currentX + dx; int ty = _currentY + dy;
        if (tx < 0 || tx >= config.gridSize || ty < 0 || ty >= config.gridSize) return true;
      }
    }
    return false;
  }

  MoveResult generateNextMove() {
    if (isInsideBounds()) _saveValidPosition();
    int roll = _random.nextInt(100) + 1;
    bool shouldStayInside = roll <= 75;
    if (!shouldStayInside && !_canExitFromCurrentPosition()) shouldStayInside = true;

    int dx = 0; int dy = 0; bool moveFound = false;
    while (!moveFound) {
      dx = _random.nextInt(config.maxStep * 2 + 1) - config.maxStep;
      dy = _random.nextInt(config.maxStep * 2 + 1) - config.maxStep;
      if (dx == 0 && dy == 0) continue;
      int nextX = _currentX + dx; int nextY = _currentY + dy;
      bool isNextInside = nextX >= 0 && nextX < config.gridSize && nextY >= 0 && nextY < config.gridSize;
      if (shouldStayInside && isNextInside) moveFound = true;
      if (!shouldStayInside && !isNextInside) moveFound = true;
    }
    _currentX += dx; _currentY += dy;
    return MoveResult(dx: dx, dy: dy, textDescription: _buildHumanReadableText(dx, dy));
  }

  String _buildHumanReadableText(int dx, int dy) {
    List<String> parts = [];
    if (dy != 0) parts.add("${dy.abs()} ${_getWordForm(dy.abs())} ${dy < 0 ? 'вверх' : 'вниз'}");
    if (dx != 0) parts.add("${dx.abs()} ${_getWordForm(dx.abs())} ${dx < 0 ? 'влево' : 'вправо'}");
    return parts.isEmpty ? "Остается на месте" : parts.join(", ");
  }

  String _getWordForm(int count) => count == 1 ? "клетка" : (count >= 2 && count <= 4 ? "клетки" : "клеток");
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
  GameConfig _activeConfig = const GameConfig();

  @override
  void initState() {
    super.initState();
    TTSEngine.init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'МЕНТАЛЬНЫЕ ГРАНИЦЫ',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.teal.shade700, letterSpacing: 1.2),
              ),
              const SizedBox(height: 8),
              Center(
                child: Chip(
                  avatar: const Icon(Icons.local_fire_department, color: Colors.orange),
                  label: Text('Страйк: ${StorageService.currentStreak} дн.'),
                ),
              ),
              const SizedBox(height: 32),
              _menuBtn(Icons.play_arrow_rounded, 'Старт сессии', Colors.teal, () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => GameScreen(config: _activeConfig)));
              }),
              const SizedBox(height: 12),
              _menuBtn(Icons.lock_open_rounded, 'Усложнения (Прогресс)', Colors.indigo, () async {
                final cfg = await Navigator.push(context, MaterialPageRoute(builder: (_) => const UpgradesScreen()));
                if (cfg != null) setState(() => _activeConfig = cfg);
              }),
              const SizedBox(height: 12),
              _menuBtn(Icons.shopping_bag_rounded, 'Магазин предметов', Colors.amber.shade800, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopScreen())).then((_) => setState(() {}))),
              const SizedBox(height: 12),
              _menuBtn(Icons.settings_rounded, 'Настройки', Colors.blueGrey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())).then((_) => setState(() {}))),
              const SizedBox(height: 12),
              _menuBtn(Icons.history_rounded, 'Журнал игр', Colors.grey, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()))),
              const SizedBox(height: 30),
              Text('Баланс кошелька: ${StorageService.userTotalBank} 🪙', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuBtn(IconData icon, String label, Color col, VoidCallback action) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(backgroundColor: col, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      onPressed: action,
      icon: Icon(icon, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}

// =========================================================================
// ЭКРАН 2: НАСТРОЙКИ
// =========================================================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDark = themeNotifier.value == ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки системы')),
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
          const Text('Гардероб объектов (Скины)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            children: ['🌟', '🍬', '🚗', '🔮', '👽'].map((skin) {
              bool isUnlocked = StorageService.unlockedSkins.contains(skin);
              bool isSelected = StorageService.selectedSkin == skin;

              return ChoiceChip(
                label: Text(skin, style: const TextStyle(fontSize: 24)),
                selected: isSelected,
                onSelected: isUnlocked ? (selected) {
                  if (selected) {
                    setState(() => StorageService.selectedSkin = skin);
                    StorageService.syncWithDisk();
                  }
                } : null,
                disabledColor: Colors.grey.shade300,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// ЭКРАН 3: УСЛОЖНЕНИЯ
// =========================================================================
class UpgradesScreen extends StatefulWidget {
  const UpgradesScreen({super.key});
  @override
  State<UpgradesScreen> createState() => _UpgradesScreenState();
}

class _UpgradesScreenState extends State<UpgradesScreen> {
  int _size = 3;
  int _step = 1;
  bool _blind = false;

  @override
  Widget build(BuildContext context) {
    bool canUnlockTier2 = StorageService.perfect3x3 >= 7;
    bool canUnlockTier3 = StorageService.perfect4x4 >= 7;

    return Scaffold(
      appBar: AppBar(title: const Text('Дерево усложнений')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.teal.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Text('🏆 Ваша статистика идеальных сессий:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade900)),
                    const SizedBox(height: 6),
                    Text('Сетка 3х3: ${StorageService.perfect3x3} / 7 побед ${StorageService.perfect3x3 >= 7 ? "✅" : ""}', style: const TextStyle(fontSize: 14, color: Colors.black)),
                    Text('Сетка 4х4: ${StorageService.perfect4x4} / 7 побед ${StorageService.perfect4x4 >= 7 ? "✅" : ""}', style: const TextStyle(fontSize: 14, color: Colors.black)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Доступная геометрия поля (Размер):', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                ChoiceChip(label: const Text('3 x 3 (База)'), selected: _size == 3, onSelected: (_) => setState(() => _size = 3)),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text('4 x 4 ${canUnlockTier2 ? "" : "🔒"}'),
                  selected: _size == 4,
                  onSelected: canUnlockTier2 ? (_) => setState(() => _size = 4) : null,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text('5 x 5 ${canUnlockTier3 ? "" : "🔒"}'),
                  selected: _size == 5,
                  onSelected: canUnlockTier3 ? (_) => setState(() => _size = 5) : null,
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Сверх-усложнения (Доступны после побед на 4х4):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ListTile(
              enabled: canUnlockTier3,
              title: const Text('Дальность шага (До 2-х клеток)'),
              trailing: ChoiceChip(label: const Text('X2 Сдвиг'), selected: _step == 2, onSelected: canUnlockTier3 ? (val) => setState(() => _step = val ? 2 : 1) : null),
            ),
            SwitchListTile(
              title: const Text('Слепая сетка'),
              subtitle: const Text('Полное растворение рамок при старте раунда'),
              value: _blind,
              onChanged: canUnlockTier3 ? (val) => setState(() => _blind = val) : null,
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                onPressed: () => Navigator.pop(context, GameConfig(gridSize: _size, maxStep: _step, isBlindMode: _blind)),
                child: const Text('Активировать конфигурацию', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// ЭКРАН 4: МАГАЗИН ПРЕДМЕТОВ
// =========================================================================
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  void _buyItem(String name, int price, VoidCallback onSuccess) {
    if (StorageService.userTotalBank >= price) {
      setState(() {
        StorageService.userTotalBank -= price;
        onSuccess();
      });
      StorageService.syncWithDisk();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Успешно куплено: $name!')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Недостаточно монет в кошельке!')));
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
          const Text('Расходные материалы (Инвентарь)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Card(
            child: ListTile(
              title: const Text('🛡️... Щит спасения (Второй шанс)'),
              subtitle: Text('Защищает от 1 ошибки. В наличии: ${StorageService.itemShieldCount}'),
              trailing: ElevatedButton(onPressed: () => _buyItem('Щит спасения', 1000, () => StorageService.itemShieldCount++), child: const Text('1000 🪙')),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('👁️ Рентген-подсказка'),
              subtitle: Text('Подсвечивает объект на 1.5 сек. В наличии: ${StorageService.itemXrayCount}'),
              trailing: ElevatedButton(onPressed: () => _buyItem('Рентген-подсказка', 2000, () => StorageService.itemXrayCount++), child: const Text('2000 🪙')),
            ),
          ),
          const Divider(height: 30),
          const Text('Косметические образы', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          _skinRow('🍬 Конфета', '🍬', 300),
          _skinRow('🚗 Машинка', '🚗', 500),
          _skinRow('🔮 Кристалл', '🔮', 700),
          _skinRow('👽 Пришелец', '👽', 1000),
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
          : ElevatedButton(onPressed: () => _buyItem(title, cost, () => StorageService.unlockedSkins.add(char)), child: Text('$cost 🪙')),
      ),
    );
  }
}

// =========================================================================
// ЭКРАН 5: ИГРОВОЙ ПРОЦЕСС
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
  String _moveMessage = "Запомните положение объекта";
  bool _isShowingPhase = true;
  bool _isShieldActiveNow = false;
  bool _xrayActive = false;

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
    
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() { _isShowingPhase = false; _triggerSystemMove(); });
    });
  }

  void _triggerSystemMove() {
    final move = _validator.generateNextMove();
    setState(() { _moveMessage = "Слушайте команду:\n${move.textDescription}"; });
    TTSEngine.speak(move.textDescription);
  }

  void _useXray() {
    if (StorageService.itemXrayCount > 0 && !_isShowingPhase && !_xrayActive) {
      setState(() {
        StorageService.itemXrayCount--;
        _xrayActive = true;
      });
      StorageService.syncWithDisk();
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _xrayActive = false);
      });
    }
  }

  void _processAnswer(bool claimedInside) {
    bool actualInside = _validator.isInsideBounds();

    if (claimedInside == actualInside) {
      _score += widget.config.pointsPerMove;
      if (!actualInside) {
        _validator.rollbackToLastValid();
        setState(() {
          _moveMessage = "Правильно! Возврат на легальную позицию.";
        });
        TTSEngine.speak("Объект вернулся обратно");
      }
      if (_currentRound >= _validator.totalRounds) {
        _endSession(true);
      } else {
        setState(() { _currentRound++; _triggerSystemMove(); });
      }
    } else {
      if (_isShieldActiveNow) {
        setState(() { _isShieldActiveNow = false; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🛡️ Щит спас вас от проигрыша! Продолжаем.')));
        _validator.rollbackToLastValid();
        _triggerSystemMove();
      } else {
        _endSession(false);
      }
    }
  }

  void _endSession(bool success) {
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
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('За ход: +${widget.config.pointsPerMove}', style: const TextStyle(fontWeight: FontWeight.bold)),
                if (StorageService.itemXrayCount > 0 && !_isShowingPhase)
                  ElevatedButton.icon(onPressed: _useXray, icon: const Icon(Icons.visibility), label: Text('Рентген (${StorageService.itemXrayCount})'))
                else
                  const SizedBox(),
                Text('Счет: $_score', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
              ],
            ),
            const Spacer(),
            Text(_moveMessage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            AspectRatio(
              aspectRatio: 1,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.config.gridSize * widget.config.gridSize,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: widget.config.gridSize, crossAxisSpacing: 6, mainAxisSpacing: 6),
                itemBuilder: (context, index) {
                  int x = index % widget.config.gridSize; int y = index ~/ widget.config.gridSize;
                  bool isTarget = (_validator.currentX == x && _validator.currentY == y);
                  bool showObj = _isShowingPhase || _xrayActive;
                  bool hideBorder = widget.config.isBlindMode && !_isShowingPhase;

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: themeNotifier.value == ThemeMode.dark ? 0.1 : 1.0),
                      border: hideBorder ? null : Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(child: (showObj && isTarget) ? Text(StorageService.selectedSkin, style: const TextStyle(fontSize: 32)) : null),
                  );
                },
              ),
            ),
            const Spacer(),
            if (!_isShowingPhase)
              Row(
                children: [
                  Expanded(child: SizedBox(height: 54, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), onPressed: () => _processAnswer(true), child: const Text('Внутри', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))),
                  const SizedBox(width: 16),
                  Expanded(child: SizedBox(height: 54, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => _processAnswer(false), child: const Text('Вылетел', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// ЭКРАН 6: ИТОГИ СЕССИИ И СУПЕР-ИГРА
// =========================================================================
class ResultsScreen extends StatefulWidget {
  final int score;
  final bool wasPerfect;
  final GameValidator validator;
  final GameConfig config;
  final int roundsPassed;

  const ResultsScreen({super.key, required this.score, required this.wasPerfect, required this.validator, required this.config, required this.roundsPassed});
  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _bonusPlayed = false;
  late int _finalScore;
  int? _selectedBonusIndex;
  late int _correctBonusIndex;
  bool _wonBonus = false;

  @override
  void initState() {
    super.initState();
    _finalScore = widget.score;
    _correctBonusIndex = widget.validator.currentY * widget.config.gridSize + widget.validator.currentX;
  }

  String _getRank() {
    if (widget.score == 0) return "Песок памяти ⏳";
    if (!widget.wasPerfect) return "Искатель путей 🗺️";
    if (widget.config.gridSize == 3) return "Мастер Базы 🔮";
    return "Архитектор Пространства 👑";
  }

  void _handleBonusChoice(int index) {
    if (_bonusPlayed) return;
    setState(() {
      _selectedBonusIndex = index; _bonusPlayed = true;
      if (index == _correctBonusIndex) { 
        _wonBonus = true; 
        _finalScore *= 2; 
        StorageService.userTotalBank += widget.score; 
        StorageService.syncWithDisk();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Icon(widget.wasPerfect ? Icons.workspace_premium_rounded : Icons.heart_broken_rounded, size: 80, color: widget.wasPerfect ? Colors.amber : Colors.redAccent),
              const SizedBox(height: 10),
              Text(
                widget.wasPerfect ? 'ИДЕАЛЬНАЯ СЕССИЯ!' : 'ИГРА ОКОНЧЕНА',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: widget.wasPerfect ? Colors.teal : Colors.redAccent),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text('Присвоенный ранг:', style: TextStyle(color: Theme.of(context).hintColor)),
                      Text(
                        _getRank(), 
                        style: TextStyle(
                          fontSize: 18, 
                          fontWeight: FontWeight.bold, 
                          color: isDarkMode ? Colors.white : Colors.black54
                        )
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statTile(context, 'Раунды', '${widget.roundsPassed}/${widget.validator.totalRounds}'),
                          _statTile(context, 'Награда', '+${widget.score} 🪙'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (widget.wasPerfect && !_bonusPlayed) ...[
                const Text('🔥 СУПЕР-ИГРА УДВОЕНИЯ 🔥\nГде сейчас находится скрытый объект?', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                const SizedBox(height: 8),
                Expanded(
                  child: GridView.builder(
                    itemCount: widget.config.gridSize * widget.config.gridSize,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: widget.config.gridSize, crossAxisSpacing: 4, mainAxisSpacing: 4),
                    itemBuilder: (context, index) => InkWell(
                      onTap: () => _handleBonusChoice(index),
                      child: Container(decoration: BoxDecoration(color: Colors.indigo.shade50.withValues(alpha: 0.2), border: Border.all(color: Colors.indigo)), child: const Center(child: Icon(Icons.help_center_outlined, color: Colors.indigo))),
                    ),
                  ),
                ),
              ] else if (widget.wasPerfect && _bonusPlayed) ...[
                Text(_wonBonus ? '🎯 Очки увеличены х2! Общая награда: $_finalScore 🪙' : '💨 Увы, промах! Множитель сгорел.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _wonBonus ? Colors.green : Colors.orange)),
                const SizedBox(height: 8),
                Expanded(
                  child: GridView.builder(
                    itemCount: widget.config.gridSize * widget.config.gridSize,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: widget.config.gridSize, crossAxisSpacing: 4, mainAxisSpacing: 4),
                    itemBuilder: (context, index) {
                      Color bg = (index == _correctBonusIndex) ? Colors.green.shade200 : ((index == _selectedBonusIndex) ? Colors.red.shade200 : Colors.grey.shade100);
                      return Container(decoration: BoxDecoration(color: bg, border: Border.all(color: Colors.grey)));
                    },
                  ),
                ),
              ] else ...[
                const Spacer(),
              ],
              const SizedBox(height: 16),
              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => GameScreen(config: widget.config))), child: const Text('Повторить сессию', style: TextStyle(color: Colors.white))),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => Navigator.popUntil(context, (route) => route.isFirst), child: const Text('В меню')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statTile(BuildContext context, String label, String value) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)), 
        Text(
          value, 
          style: TextStyle(
            fontSize: 18, 
            fontWeight: FontWeight.bold, 
            color: isDarkMode ? Colors.teal.shade300 : Colors.black
          )
        )
      ],
    );
  }
}

// =========================================================================
// ЭКРАН 7: ЖУРНАЛ ИГР
// =========================================================================
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logs = StorageService.gameHistory;
    return Scaffold(
      appBar: AppBar(title: const Text('Журнал игр')),
      body: logs.isEmpty
          ? const Center(child: Text('История игр пуста.', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final item = logs[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(item['gridSize'], style: const TextStyle(fontSize: 12))),
                    title: Text('Очки: ${item['score']} 🪙', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Раунды: ${item['rounds']}'),
                    trailing: Icon(item['isPerfect'] ? Icons.star : Icons.star_border, color: Colors.amber),
                  ),
                );
              },
            ),
    );
  }
}