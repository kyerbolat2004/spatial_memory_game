import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:spatial_memory_game/main.dart';

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

      // Ожидаемая таблица сумм шагов по уровням 1..10.
      const expected = {
        1: [1, 2], 2: [2, 2], 3: [2, 2], 4: [2, 3], 5: [3, 3],
        6: [3, 3], 7: [3, 4], 8: [4, 4], 9: [4, 4], 10: [4, 4],
      };
      for (final d in difficulties) {
        expect([d.minSteps, d.maxSteps], expected[d.level],
            reason: 'Уровень ${d.level}: неверная таблица шагов');
      }
    });

    test('generateMoveSegments: сумма в бюджете, правила соблюдены', () {
      final rand = Random(12345);
      for (final d in difficulties) {
        for (int i = 0; i < 500; i++) {
          final seg = generateMoveSegments(d, rand);
          final total = seg.fold<int>(0, (s, e) => s + e);
          // сумма клеток в бюджете уровня
          expect(total, inInclusiveRange(d.minSteps, d.maxSteps),
              reason: 'L${d.level} seg=$seg total=$total');
          // 1 или 2 сегмента, каждый 1..4 клетки
          expect(seg.length, inInclusiveRange(1, 2));
          for (final s in seg) {
            expect(s, inInclusiveRange(1, 4), reason: 'L${d.level} seg=$seg');
          }
          // со 2-го уровня хотя бы один сегмент >= 2 (нет ходов из одних 1-к)
          if (d.level >= 2) {
            expect(seg.any((s) => s >= 2), isTrue,
                reason: 'L${d.level}: все сегменты <2 -> $seg');
          }
        }
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

      expect(clips.length, 122, reason: 'ожидается 122 клипа в манифесте');
      expect(missingMale, isEmpty, reason: 'нет мужских: $missingMale');
      expect(missingFemale, isEmpty, reason: 'нет женских: $missingFemale');
    });
  });
}