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
      expect(level1.maxStep, 1);

      // Проверяем хардкорный пятый уровень сложности
      final level5 = difficulties.firstWhere((d) => d.level == 5);
      expect(level5.gridSize, 6);
      expect(level5.objectsCount, 2);
      expect(level5.obstaclesCount, 2);
      expect(level5.maxStep, 2);
    });

    test('Step Constraints: single only on level 1, min 2 from level 2', () {
      // На 1 уровне (сетка 3х3) допустимы одинарные шаги.
      final level1 = difficulties.firstWhere((d) => d.level == 1);
      expect(level1.minStep, 1);
      expect(level1.maxStep, 1);
      expect(level1.allowDoubleMove, isFalse);

      // Со 2 уровня одинарные шаги исключены: минимум две клетки.
      for (final d in difficulties.where((d) => d.level >= 2)) {
        expect(d.minStep, 2, reason: 'Уровень ${d.level}: минимум 2 клетки');
        expect(
          d.maxStep >= d.minStep,
          isTrue,
          reason: 'Уровень ${d.level}: maxStep должен быть >= minStep',
        );
      }

      // Сдвоенные ходы разрешены только на крупных сетках (с уровня 5).
      final level5 = difficulties.firstWhere((d) => d.level == 5);
      expect(level5.allowDoubleMove, isTrue);
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
  });
}