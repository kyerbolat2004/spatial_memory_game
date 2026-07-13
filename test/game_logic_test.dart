import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:spatial_memory_game/main.dart';

import 'level_round_fixtures.dart';

void main() {
  group('Spatial Memory Game - Logic & Theme Engine Tests', () {
    test('GameThemes Config Mapping Verification', () {
      // Изучаем настройки стартовой темы «Микромир»
      final microworld = gameThemes.firstWhere((t) => t.id == 'microworld');
      expect(microworld.name, 'Микромир');
      // Эмодзи хранятся в запасном (Android 10-safe) варианте, на новых
      // системах их повышает em(). Проверяем стабильную часть — имена
      // объектов, к которым привязана озвучка.
      expect(microworld.obj1.endsWith('Муха'), true);
      expect(microworld.obj2.endsWith('Жук'), true);
      expect(microworld.obstacle.endsWith('Камень'), true);
      expect(microworld.primaryColor, Colors.teal);
      expect(microworld.price, 0);

      // Изучаем сложную премиальную тему «Мифы и Магия»
      final magic = gameThemes.firstWhere((t) => t.id == 'magic');
      expect(magic.name, 'Мифы и Магия');
      expect(magic.price, 30000);
    });

    test('Difficulties Level Progression Integrity', () {
      // Проверяем стартовый уровень сложности
      final level1 = difficulties.firstWhere((d) => d.level == 1);
      expect(level1.gridSize, 3);
      expect(level1.objectsCount, 1);
      expect(level1.obstaclesCount, 0);
      expect(level1.maxSteps, 2);

      // Проверяем хардкорный пятый уровень сложности
      final level5 = difficulties.firstWhere((d) => d.level == 5);
      expect(level5.gridSize, 6);
      expect(level5.objectsCount, 2);
      expect(level5.obstaclesCount, 2);
      expect(level5.maxSteps, 3);
    });

    test('Step Constraints: сумма шагов по уровням', () {
      // На 1 уровне (сетка 3х3) сумма шагов 1..2 (допустимы одиночные).
      final level1 = difficulties.firstWhere((d) => d.level == 1);
      expect(level1.minSteps, 1);
      expect(level1.maxSteps, 2);

      // Со 2 уровня минимум суммы шагов — 2 (одиночных ходов нет).
      for (final d in difficulties.where((d) => d.level >= 2)) {
        expect(d.minSteps, greaterThanOrEqualTo(2),
            reason: 'Уровень ${d.level}: минимум 2 шага');
        expect(d.maxSteps, greaterThanOrEqualTo(d.minSteps),
            reason: 'Уровень ${d.level}: maxSteps >= minSteps');
        expect(d.maxSteps, lessThanOrEqualTo(4),
            reason: 'Уровень ${d.level}: не больше 4 (лимит озвучки)');
      }

      // Ожидаемая таблица сумм шагов по уровням 1..10:
      // диапазон «от 2 до лимита уровня» (уровень 1 — своё ТЗ, 1..2).
      const expected = {
        1: [1, 2], 2: [2, 2], 3: [2, 2], 4: [2, 3], 5: [2, 3],
        6: [2, 3], 7: [2, 4], 8: [2, 4], 9: [2, 4], 10: [2, 4],
      };
      for (final d in difficulties) {
        expect([d.minSteps, d.maxSteps], expected[d.level],
            reason: 'Уровень ${d.level}: неверная таблица шагов');
      }
    });

    test('Пулы вариаций уровней: размеры и свойства сегментов', () {
      const expectedSizes = {
        1: 16, 2: 4, 3: 4, 4: 40, 5: 40,
        6: 40, 7: 88, 8: 88, 9: 88, 10: 88,
      };
      const horizontal = {'влево', 'вправо'};
      for (final d in difficulties) {
        final pool = buildMovePool(d);
        expect(pool.length, expectedSizes[d.level],
            reason: 'L${d.level}: неверный размер пула');
        expect(pool.toSet().length, pool.length,
            reason: 'L${d.level}: дубликаты в пуле');
        for (final m in pool) {
          final segs = moveSegmentsFor(m);
          // Сумма шагов строго в бюджете уровня.
          final int total = segs.fold(0, (s, e) => s + e.step);
          expect(total, inInclusiveRange(d.minSteps, d.maxSteps),
              reason: 'L${d.level}: $m вне бюджета');
          // 1-2 сегмента, каждый 1..4 клетки (лимит озвучки).
          expect(segs.length, inInclusiveRange(1, 2),
              reason: 'L${d.level}: $m');
          for (final s in segs) {
            expect(s.step, inInclusiveRange(1, 4), reason: 'L${d.level}: $m');
          }
          // Нулевых ходов (возврат в ту же клетку) нет ни на одном уровне.
          final o = moveOffset(m);
          expect(o == const Point(0, 0), isFalse,
              reason: 'L${d.level}: $m — нулевой ход запрещён');
          if (segs.length == 2) {
            // Уровень 1 (своё ТЗ): только перпендикулярные Г-ходы.
            if (d.level == 1) {
              expect(
                horizontal.contains(segs[0].dir) !=
                    horizontal.contains(segs[1].dir),
                isTrue,
                reason: 'L1: $m не перпендикулярен',
              );
            }
            // Со 2-го уровня нет ходов из двух одиночных сегментов (1+1).
            if (d.level >= 2) {
              expect(segs.any((s) => s.step >= 2), isTrue,
                  reason: 'L${d.level}: $m — ход 1+1 запрещён');
            }
          }
        }
        // Со 2-го уровня в пуле есть двойные и обратные ходы (если бюджет
        // позволяет два сегмента, то есть maxSteps >= 3).
        if (d.level >= 2 && d.maxSteps >= 3) {
          expect(pool.any((m) => m.contains('+')), isTrue,
              reason: 'L${d.level}: нет двойных ходов');
          bool hasReverse = false;
          for (final m in pool.where((m) => !m.contains('+'))) {
            final segs = moveSegmentsFor(m);
            if (segs.length == 2 &&
                horizontal.contains(segs[0].dir) ==
                    horizontal.contains(segs[1].dir)) {
              hasReverse = true;
            }
          }
          expect(hasReverse, isTrue, reason: 'L${d.level}: нет обратных ходов');
        }
      }
    });

    test('roundLength: число ходов раунда по уровням', () {
      const expected = {
        1: 16, 2: 16, 3: 16, 4: 24, 5: 20,
        6: 20, 7: 48, 8: 28, 9: 28, 10: 28,
      };
      for (final d in difficulties) {
        expect(roundLength(d), expected[d.level],
            reason: 'L${d.level}: неверная длина раунда');
      }
    });

    test('generateRoundPlan: состав, дележ и баланс 50/50 на всех уровнях', () {
      final rand = Random(2024);
      for (final d in difficulties) {
        final pool = buildMovePool(d);
        final bool sampled = pool.length >= d.movesPerRound;
        final int reps = sampled ? 1 : d.movesPerRound ~/ pool.length;
        for (int iter = 0; iter < 25; iter++) {
          // Случайная расстановка: клетки объектов и преград не совпадают.
          final cells = <Point<int>>{};
          while (cells.length < d.objectsCount + d.obstaclesCount) {
            cells.add(
              Point(rand.nextInt(d.gridSize), rand.nextInt(d.gridSize)),
            );
          }
          final list = cells.toList();
          final objectStarts = list.sublist(0, d.objectsCount);
          final obstacles = list.sublist(d.objectsCount);

          final plan = generateRoundPlan(
            config: d,
            objectStarts: objectStarts,
            obstacles: obstacles,
            rand: rand,
          );

          expect(plan.length, roundLength(d));
          final counts = <String, int>{};
          for (final p in plan) {
            counts[p.move] = (counts[p.move] ?? 0) + 1;
          }
          if (sampled) {
            // Выборка без повторов, все вариации из пула.
            for (final e in counts.entries) {
              expect(e.value, 1, reason: 'L${d.level}: повтор ${e.key}');
              expect(pool.contains(e.key), isTrue,
                  reason: 'L${d.level}: ${e.key} вне пула');
            }
          } else {
            // Малый пул тиражируется: каждая вариация ровно reps раз.
            for (final m in pool) {
              expect(counts[m], reps, reason: 'L${d.level}: вариация $m');
            }
          }
          // Дележ ходов между объектами поровну.
          if (d.objectsCount == 2) {
            expect(
              plan.where((p) => p.objectId == 1).length,
              plan.length ~/ 2,
              reason: 'L${d.level}: дележ между объектами',
            );
          }
          // Баланс ровно 50/50.
          expect(
            roundPlanSafeCount(
              plan: plan,
              objectStarts: objectStarts,
              obstacles: obstacles,
              gridSize: d.gridSize,
            ),
            plan.length ~/ 2,
            reason: 'L${d.level}: баланс не 50/50 (расстановка $list)',
          );
        }
      }
    });

    test('90 готовых раундов из страниц уровней 2-10: ответы и баланс', () {
      expect(levelRoundFixtures.length, 90);
      for (final fx in levelRoundFixtures) {
        final config = difficulties.firstWhere((d) => d.level == fx.level);
        expect(config.gridSize, fx.gridSize,
            reason: 'L${fx.level}: сетка страницы не совпадает с конфигом');
        expect(fx.moves.length, roundLength(config),
            reason: 'L${fx.level}: длина раунда');

        final plan = [
          for (int i = 0; i < fx.moves.length; i++)
            PlannedMove(fx.objectIndex[i] + 1, fx.moves[i]),
        ];
        final objectStarts = [for (final o in fx.objects) Point(o[0], o[1])];
        final obstacles = [for (final o in fx.obstacles) Point(o[0], o[1])];

        final answers = roundPlanAnswers(
          plan: plan,
          objectStarts: objectStarts,
          obstacles: obstacles,
          gridSize: fx.gridSize,
        );
        expect(answers, fx.expected,
            reason: 'L${fx.level}: ответы страницы разошлись с симуляцией');
        expect(answers.where((a) => a).length, answers.length ~/ 2,
            reason: 'L${fx.level}: баланс раунда');
      }
    });

    test('Reward scales down with fewer objects/obstacles', () {
      final level7 = difficulties.firstWhere((d) => d.level == 7);
      // Уменьшение до минимума (1 объект, 1 преграда) даёт меньшую награду,
      // чем полный набор уровня.
      final full = level7.pointsFor(level7.objectsCount, level7.obstaclesCount);
      final reduced = level7.pointsFor(1, 1);
      expect(reduced < full, isTrue);
    });

    test('Math Grid Boundary Safe Movement Physics Simulator', () {
      // Инициализируем имитацию сетки 3x3 (Сложность 1)
      const int gridSize = 3;

      // Тест-кейс А: Объект в центре (1, 1). Сдвиг на 1 клетку вправо.
      int currentX = 1;
      int currentY = 1;
      int step = 1;

      int nextX = currentX + step;
      int nextY = currentY;

      bool isInside = nextX >= 0 && nextX < gridSize && nextY >= 0 && nextY < gridSize;
      expect(isInside, isTrue); // Объект находится на координате (2, 1) — внутри границ

      // Тест-кейс Б: Объект совершает опасный прыжок влево на 2 клетки из центра (1, 1)
      step = 2;
      nextX = currentX - step; // 1 - 2 = -1 (за пределами сетки)
      
      isInside = nextX >= 0 && nextX < gridSize && nextY >= 0 && nextY < gridSize;
      expect(isInside, isFalse); // Должен вернуть FALSE
    });

    test('Voice assets: каждый клип манифеста есть в муж. и жен. наборах', () {
      // Готовность релиза: приложение склеивает фразу из клипов по манифесту.
      // Если хотя бы одного .mp3 не хватает (муж. в assets/voice/ или жен. в
      // assets/voice/female/), фраза озвучится системным голосом — это баг.
      final manifest =
          jsonDecode(File('assets/voice/voice_manifest.json').readAsStringSync())
              as Map<String, dynamic>;
      final clips = (manifest['clips'] as List).cast<Map<String, dynamic>>();

      final missingMale = <String>[];
      final missingFemale = <String>[];
      for (final c in clips) {
        final file = c['file'] as String;
        if (!File('assets/voice/$file').existsSync()) missingMale.add(file);
        if (!File('assets/voice/female/$file').existsSync()) {
          missingFemale.add(file);
        }
      }

      // Не меньше исходных 122: манифест растёт при добавлении новых фраз
      // (found_single, game_over_safe, miss_wrong_order и т.п.).
      expect(clips.length, greaterThanOrEqualTo(122),
          reason: 'манифест не должен терять клипы');
      expect(missingMale, isEmpty, reason: 'нет мужских: $missingMale');
      expect(missingFemale, isEmpty, reason: 'нет женских: $missingFemale');
    });
  });

  // =======================================================================
  // УРОВЕНЬ 1: раунд из 16 фиксированных вариаций хода (по ТЗ уровня 1)
  // =======================================================================
  group('Уровень 1 - Раунды из 16 вариаций', () {
    // Пул из ТЗ уровня 1: 4 одиночных, 4 двойных, 8 Г-образных.
    const level1Moves = [
      'Л', 'П', 'В', 'Н',
      'ЛЛ', 'ПП', 'ВВ', 'НН',
      'ВП', 'ПВ', 'ВЛ', 'ЛВ', 'НП', 'ПН', 'НЛ', 'ЛН',
    ];
    final level1 = difficulties.firstWhere((d) => d.level == 1);

    // Баланс раунда уровня 1 от стартовой клетки (обёртка над общим движком).
    int safeCount(List<String> moves, int x, int y) => roundPlanSafeCount(
          plan: [for (final m in moves) PlannedMove(1, m)],
          objectStarts: [Point(x, y)],
          obstacles: const [],
          gridSize: 3,
        );

    test('Пул: ровно 16 вариаций из ТЗ, без противоположных пар', () {
      final pool = buildMovePool(level1);
      expect(pool.toSet(), level1Moves.toSet(),
          reason: 'пул уровня 1 должен совпадать с ТЗ');

      final singles = pool.where((m) => m.length == 1);
      final doubles = pool.where((m) => m.length == 2 && m[0] == m[1]);
      final lShaped = pool.where((m) => m.length == 2 && m[0] != m[1]);
      expect(singles.length, 4, reason: 'одиночных должно быть 4');
      expect(doubles.length, 4, reason: 'двойных должно быть 4');
      expect(lShaped.length, 8, reason: 'Г-образных должно быть 8');

      // Противоположные пары (возврат на место) запрещены ТЗ.
      for (final banned in const ['ВН', 'НВ', 'ЛП', 'ПЛ']) {
        expect(pool.contains(banned), isFalse,
            reason: 'в пуле не должно быть $banned');
      }
    });

    test('Математика пула из ТЗ: 144 комбинации, 68 ДАЛЬШЕ / 76 СТОП', () {
      int valid = 0;
      final Map<String, int> perCell = {};
      for (int x = 0; x < 3; x++) {
        for (int y = 0; y < 3; y++) {
          int cellValid = 0;
          for (final m in level1Moves) {
            final o = moveOffset(m);
            final nx = x + o.x, ny = y + o.y;
            if (nx >= 0 && nx < 3 && ny >= 0 && ny < 3) {
              valid++;
              cellValid++;
            }
          }
          perCell['$x$y'] = cellValid;
        }
      }
      expect(valid, 68, reason: 'валидных ходов по ТЗ — 68');
      expect(9 * 16 - valid, 76, reason: 'тупиковых ходов по ТЗ — 76');
      // Доступно ходов из клетки: центр 12, сторона 8, угол 6.
      expect(perCell['11'], 12, reason: 'центр');
      expect(perCell['10'], 8, reason: 'сторона');
      expect(perCell['00'], 6, reason: 'угол');
    });

    test('moveSegmentsFor: вариации переводятся в сегменты озвучки', () {
      // Двойной ход — один сегмент из 2 клеток («на две клетки вверх»).
      final vv = moveSegmentsFor('ВВ');
      expect(vv.length, 1);
      expect(vv.first.dir, 'вверх');
      expect(vv.first.step, 2);

      // Г-образный — два перпендикулярных сегмента по 1 клетке.
      final vp = moveSegmentsFor('ВП');
      expect(vp.length, 2);
      expect(vp[0].dir, 'вверх');
      expect(vp[1].dir, 'вправо');
      expect(vp.every((s) => s.step == 1), isTrue);

      // Одиночный — один сегмент в 1 клетку.
      final n = moveSegmentsFor('Н');
      expect(n.length, 1);
      expect(n.first.dir, 'вниз');
      expect(n.first.step, 1);

      // Ход из двух длинных сегментов («ННН» + «П» и т.п.).
      final nnnp = moveSegmentsFor('НННП');
      expect(nnnp.length, 2);
      expect(nnnp[0].dir, 'вниз');
      expect(nnnp[0].step, 3);
      expect(nnnp[1].dir, 'вправо');
      expect(nnnp[1].step, 1);
    });

    test('generateRoundPlan L1: все 16 вариаций и баланс 8/8 из любой клетки',
        () {
      final rand = Random(7);
      for (int x = 0; x < 3; x++) {
        for (int y = 0; y < 3; y++) {
          for (int i = 0; i < 300; i++) {
            final plan = generateRoundPlan(
              config: level1,
              objectStarts: [Point(x, y)],
              obstacles: const [],
              rand: rand,
            );
            expect(plan.map((p) => p.move).toSet(), level1Moves.toSet(),
                reason: 'старт ($x,$y): раунд должен содержать все 16 вариаций');
            expect(
              roundPlanSafeCount(
                plan: plan,
                objectStarts: [Point(x, y)],
                obstacles: const [],
                gridSize: 3,
              ),
              8,
              reason: 'старт ($x,$y): баланс должен быть ровно 8/8',
            );
          }
        }
      }
    });

    test('10 эталонных раундов из ТЗ: 16 уникальных вариаций и ровно 8/8', () {
      // Формат старта — столбецСтрока (1..3), как в ТЗ.
      const reference = [
        ['21', 'НН', 'ЛВ', 'В', 'ВВ', 'ВП', 'ПН', 'ПВ', 'П', 'ВЛ', 'Л', 'ЛН', 'ЛЛ', 'НП', 'ПП', 'НЛ', 'Н'],
        ['11', 'ВЛ', 'В', 'ВВ', 'П', 'НЛ', 'ЛЛ', 'НН', 'НП', 'ПП', 'ПН', 'ВП', 'ЛВ', 'ЛН', 'Л', 'Н', 'ПВ'],
        ['33', 'П', 'ПВ', 'ЛВ', 'НЛ', 'ВП', 'Л', 'НП', 'ПП', 'НН', 'ПН', 'ЛН', 'В', 'ВВ', 'ЛЛ', 'Н', 'ВЛ'],
        ['22', 'ЛВ', 'В', 'Л', 'НН', 'ПВ', 'ВП', 'ЛЛ', 'ВВ', 'ПН', 'ЛН', 'НП', 'ВЛ', 'Н', 'ПП', 'НЛ', 'П'],
        ['33', 'ПП', 'ВП', 'НН', 'ВВ', 'ЛВ', 'Н', 'ЛН', 'ПН', 'НЛ', 'НП', 'ПВ', 'В', 'ЛЛ', 'П', 'Л', 'ВЛ'],
        ['23', 'ПН', 'ЛН', 'В', 'ВП', 'П', 'ЛВ', 'НП', 'НН', 'ПП', 'ВЛ', 'ПВ', 'ВВ', 'Н', 'НЛ', 'ЛЛ', 'Л'],
        ['12', 'ЛЛ', 'НН', 'ПН', 'ПВ', 'Л', 'НП', 'НЛ', 'ЛН', 'ВВ', 'Н', 'ЛВ', 'В', 'П', 'ВП', 'ПП', 'ВЛ'],
        ['13', 'ВП', 'Л', 'ЛН', 'ЛВ', 'ВВ', 'ПН', 'ПП', 'НП', 'НЛ', 'ПВ', 'П', 'ВЛ', 'НН', 'В', 'Н', 'ЛЛ'],
        ['22', 'ПП', 'ВВ', 'В', 'НП', 'НН', 'П', 'ПН', 'Н', 'ЛН', 'Л', 'ВП', 'НЛ', 'ЛВ', 'ПВ', 'ЛЛ', 'ВЛ'],
        ['23', 'ВВ', 'ВП', 'ПВ', 'Л', 'В', 'НП', 'НЛ', 'П', 'Н', 'ЛН', 'ПН', 'ЛЛ', 'НН', 'ЛВ', 'ПП', 'ВЛ'],
      ];

      for (int i = 0; i < reference.length; i++) {
        final start = reference[i].first;
        final moves = reference[i].sublist(1);
        // столбецСтрока (1-based) -> внутренние координаты (0-based).
        final x = int.parse(start[0]) - 1;
        final y = int.parse(start[1]) - 1;

        expect(moves.toSet(), level1Moves.toSet(),
            reason: 'раунд ${i + 1}: должны быть все 16 вариаций без повторов');
        expect(safeCount(moves, x, y), 8,
            reason: 'раунд ${i + 1} (старт $start): баланс должен быть 8/8');
      }
    });

    test('Экономика уровня 1: 10 монет за ход, 5 за предотвращённый тупик', () {
      final level1 = difficulties.firstWhere((d) => d.level == 1);
      expect(level1.pointsFor(1, 0), 10, reason: 'награда за ход из ТЗ');
      expect(level1.pointsFor(1, 0) ~/ 2, 5, reason: 'половина за тупик');
      // Остальные уровни считаются по прежней формуле — проверка, что
      // фиксированная награда не задела уровень 2.
      final level2 = difficulties.firstWhere((d) => d.level == 2);
      expect(level2.pointsFor(level2.objectsCount, level2.obstaclesCount),
          greaterThan(10));
    });
  });
}