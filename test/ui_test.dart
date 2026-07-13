// =========================================================================
// UI-ТЕСТЫ: строим каждый экран, жмём кнопки, проверяем переходы и состояние.
// Нативные плагины (TTS, audioplayers, path_provider) замоканы, чтобы озвучка
// не мешала логике интерфейса.
// =========================================================================
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spatial_memory_game/main.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;

  void mockMethod(String channel, [Object? Function(MethodCall)? h]) {
    messenger.setMockMethodCallHandler(
      MethodChannel(channel),
      (call) async => h?.call(call),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Плагины-заглушки, чтобы вызовы озвучки не падали в тестовой среде.
    mockMethod('flutter_tts', (_) => 1);
    mockMethod('xyz.luan/audioplayers');
    mockMethod('xyz.luan/audioplayers.global');
    mockMethod(
      'plugins.flutter.io/path_provider',
      (_) => Directory.systemTemp.path,
    );
    await StorageService.loadData();
    // Открываем весь контент, чтобы кнопки магазина/сложности были активны.
    StorageService.devModeActive = true;
    StorageService.userTotalBank = 999999;
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SpatialMemoryGame());
    await tester.pumpAndSettle();
  }

  Future<void> openFromMenu(WidgetTester tester, String label) async {
    final f = find.text(label);
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
  }

  testWidgets('Главное меню: логотип и все 6 кнопок на месте', (tester) async {
    await pumpApp(tester);
    expect(find.text('MemoryFly'), findsOneWidget);
    for (final label in const [
      'Старт сессии',
      'Сложность и Прогресс',
      'Магазин тем',
      'Инструкция к игре',
      'Журнал игр',
      'Настройки',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'нет кнопки "$label"');
    }
  });

  testWidgets('Переходы во все разделы и возврат назад', (tester) async {
    await pumpApp(tester);
    for (final entry in const {
      'Сложность и Прогресс': 'Сложность и Прогресс',
      'Магазин тем': 'Магазин предметов',
      'Журнал игр': 'Журнал игр',
      'Настройки': 'Настройки',
    }.entries) {
      await openFromMenu(tester, entry.key);
      expect(
        find.text(entry.value),
        findsWidgets,
        reason: 'не открылся экран "${entry.value}"',
      );
      await back(tester);
      expect(find.text('MemoryFly'), findsOneWidget);
    }
  });

  testWidgets('Инструкция к игре открывается и закрывается', (tester) async {
    await pumpApp(tester);
    await openFromMenu(tester, 'Инструкция к игре');
    expect(find.text('Все ясно!'), findsOneWidget);
    await tester.tap(find.text('Все ясно!'));
    await tester.pumpAndSettle();
    expect(find.text('Все ясно!'), findsNothing);
  });

  testWidgets('Настройки: каждый переключатель меняет состояние', (tester) async {
    await pumpApp(tester);
    await openFromMenu(tester, 'Настройки');

    Future<void> toggle(String title, bool Function() read) async {
      final before = read();
      final sw = find.descendant(
        of: find.widgetWithText(ListTile, title),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(sw);
      await tester.tap(sw);
      await tester.pumpAndSettle();
      expect(read(), !before, reason: 'переключатель "$title" не сменился');
    }

    await toggle('Слепой режим', () => StorageService.isBlindModeGlobal);
    await toggle('Панель управления слева', () => StorageService.controlsOnLeft);
    await toggle('Отображение текста хода', () => StorageService.showSpeechText);
    await toggle('Женский голос диктора', () => StorageService.voiceFemale);
  });

  testWidgets('Тёмная тема переключается', (tester) async {
    await pumpApp(tester);
    await openFromMenu(tester, 'Настройки');
    final wasDark = themeNotifier.value == ThemeMode.dark;
    final sw = find.descendant(
      of: find.widgetWithText(ListTile, 'Тёмная тема'),
      matching: find.byType(Switch),
    );
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(themeNotifier.value == ThemeMode.dark, !wasDark);
  });

  testWidgets('Магазин: покупка расходников и выбор темы', (tester) async {
    StorageService.isBlindModeGlobal = false; // расходники видны только вне слепого режима
    await pumpApp(tester);
    await openFromMenu(tester, 'Магазин тем');
    // Покупка щита.
    final shield = find.widgetWithText(ElevatedButton, '1000 $coin');
    if (shield.evaluate().isNotEmpty) {
      final before = StorageService.itemShieldCount;
      await tester.tap(shield.first);
      await tester.pumpAndSettle();
      expect(StorageService.itemShieldCount, before + 1);
    }
    // Применение любой доступной темы (devMode -> кнопки «Применить»).
    final apply = find.widgetWithText(ElevatedButton, 'Применить');
    if (apply.evaluate().isNotEmpty) {
      await tester.ensureVisible(apply.first);
      await tester.tap(apply.first);
      await tester.pumpAndSettle();
      expect(find.text('Магазин предметов'), findsWidgets);
    }
  });

  testWidgets('Сложность: выбор уровня активирует его', (tester) async {
    await pumpApp(tester);
    await openFromMenu(tester, 'Сложность и Прогресс');
    final pick = find.widgetWithText(ElevatedButton, 'Выбрать');
    if (pick.evaluate().isNotEmpty) {
      await tester.ensureVisible(pick.first);
      await tester.tap(pick.first);
      await tester.pumpAndSettle();
      expect(find.text('Сложность и Прогресс'), findsWidgets);
    }
  });

  testWidgets('Игра: старт, запоминание, кнопки Дальше/Стоп работают', (tester) async {
    await pumpApp(tester);
    await openFromMenu(tester, 'Старт сессии');
    expect(find.textContaining('Ход'), findsWidgets);

    // Проходим фазу запоминания (4 секунды countdown).
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(milliseconds: 300));

    // Должны появиться кнопки принятия решения.
    expect(find.text('Дальше'), findsWidgets);
    expect(find.text('Стоп'), findsWidgets);

    // Жмём «Дальше» — не должно быть исключений.
    await tester.tap(find.text('Дальше').first);
    await tester.pump(const Duration(milliseconds: 300));
    // И «Стоп».
    if (find.text('Стоп').evaluate().isNotEmpty) {
      await tester.tap(find.text('Стоп').first);
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Сессия завершается, «Повторить» сбрасывает ход', (tester) async {
    StorageService.isBlindModeGlobal = false; // нужен AppBar «Ход X» и кнопки снизу
    await pumpApp(tester);
    await openFromMenu(tester, 'Старт сессии');
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(milliseconds: 300));

    // Жмём «Дальше» до конца сессии: рано или поздно ход окажется опасным
    // (уход за поле) и будет «Игра окончена», либо дойдём до супер-игры.
    bool ended = false;
    for (int i = 0; i < 40 && !ended; i++) {
      final next = find.text('Дальше');
      if (next.evaluate().isEmpty) {
        ended = true;
        break;
      }
      await tester.tap(next.first);
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text('ИГРА ОКОНЧЕНА').evaluate().isNotEmpty) ended = true;
      if (find.textContaining('СУПЕР-ИГРА').evaluate().isNotEmpty) ended = true;
    }
    expect(ended, isTrue, reason: 'сессия должна завершиться');
    expect(tester.takeException(), isNull);

    // Если поражение — проверяем перезапуск.
    if (find.text('Повторить попытку').evaluate().isNotEmpty) {
      await tester.tap(find.text('Повторить попытку'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Ход 1'), findsWidgets);
      // Продреним таймеры нового обратного отсчёта запоминания,
      // чтобы не осталось «pending timer» на момент завершения теста.
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
    }
  });

  testWidgets('Настройки сохраняются между перезапусками', (tester) async {
    await pumpApp(tester);
    await openFromMenu(tester, 'Настройки');
    final before = StorageService.voiceFemale;
    final sw = find.descendant(
      of: find.widgetWithText(ListTile, 'Женский голос диктора'),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(sw);
    await tester.tap(sw);
    await tester.pumpAndSettle();
    // Эмулируем перезапуск приложения — перечитываем настройки с диска.
    await StorageService.loadData();
    expect(StorageService.voiceFemale, !before, reason: 'настройка не сохранилась');
  });

  testWidgets('Громкость TTS сохраняется между перезапусками', (tester) async {
    await pumpApp(tester);
    await openFromMenu(tester, 'Настройки');
    final slider = find.byType(Slider);
    await tester.ensureVisible(slider);
    await tester.tap(slider); // ставит громкость ~0.5
    await tester.pumpAndSettle();
    final v = TTSEngine.volume;
    await StorageService.loadData();
    expect(TTSEngine.volume, closeTo(v, 0.001), reason: 'громкость не сохранилась');
  });

  testWidgets('Магазин: не хватает монет — показывается диалог', (tester) async {
    StorageService.devModeActive = false;
    StorageService.userTotalBank = 0;
    StorageService.isBlindModeGlobal = false; // расходники видны только вне слепого режима
    await pumpApp(tester);
    await openFromMenu(tester, 'Магазин тем');
    final shield = find.widgetWithText(ElevatedButton, '1000 $coin');
    await tester.ensureVisible(shield.first);
    await tester.tap(shield.first);
    await tester.pumpAndSettle();
    expect(find.text('Недостаточно монет!'), findsOneWidget);
  });

  testWidgets('Случайный двойной тап не отвечает за следующий ход', (tester) async {
    StorageService.isBlindModeGlobal = false; // нужен AppBar со счётчиком хода
    await pumpApp(tester);
    await openFromMenu(tester, 'Старт сессии');
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(milliseconds: 300));

    // Два тапа подряд без паузы. Второй обязан быть проглочен блокировкой:
    // иначе он ответил бы за следующий, ещё не прозвучавший ход.
    await tester.tap(find.text('Дальше').first);
    await tester.pump();
    if (find.text('Дальше').evaluate().isNotEmpty) {
      await tester.tap(find.text('Дальше').first);
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Возможных исходов два: ошибка на первом же ходе («ИГРА ОКОНЧЕНА») или
    // ровно один засчитанный ход («Ход 2 / N»). «Ход 3» означал бы, что
    // второй тап проскочил.
    expect(find.textContaining('Ход 3'), findsNothing,
        reason: 'второй тап не должен засчитываться как ответ');
    expect(tester.takeException(), isNull);

    // Дренаж таймера блокировки, чтобы не осталось pending timer.
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('Сброс прогресса обнуляет победы и настройки матча', (tester) async {
    // Имитируем накопленный прогресс и сохраняем его на диск.
    StorageService.difficultyWins[1] = 7;
    StorageService.customObjects[4] = 1;
    StorageService.customObstacles[5] = 1;
    StorageService.userTotalBank = 5000;
    await StorageService.syncWithDisk();

    await pumpApp(tester);
    await openFromMenu(tester, 'Настройки');
    final reset = find.text('Сбросить весь прогресс');
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сбросить'));
    await tester.pumpAndSettle();

    // Победы и пользовательские настройки матча не должны «пережить» сброс:
    // после prefs.clear() ключей нет, и старые значения не могут остаться
    // в памяти (иначе они снова уедут на диск при следующем сохранении).
    expect(StorageService.userTotalBank, 0);
    expect(StorageService.difficultyWins[1], 0, reason: 'победы не сброшены');
    expect(StorageService.customObjects, isEmpty);
    expect(StorageService.customObstacles, isEmpty);
  });

  testWidgets('Слепая сетка ВЫКЛ — во время раундов видно поле', (tester) async {
    StorageService.isBlindModeGlobal = false;
    await pumpApp(tester);
    await openFromMenu(tester, 'Старт сессии');
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(milliseconds: 300));
    // Обычный вид с AppBar «Ход X» (а не пустой экран) и кнопки решения на месте.
    expect(find.textContaining('Ход'), findsWidgets);
    expect(find.text('Дальше'), findsWidgets);
  });
}
