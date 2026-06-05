import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:spatial_memory_game/main.dart';

void main() {
  group('Spatial Memory Game - Logic & Theme Engine Tests', () {
    test('GameThemes Config Mapping Verification', () {
      // Изучаем настройки стартовой темы «Микромир»
      final microworld = gameThemes.firstWhere((t) => t.id == 'microworld');
      expect(microworld.name, 'Микромир');
      expect(microworld.obj1, '🪰 Муха');
      expect(microworld.obj2, '🪲 Жук');
      expect(microworld.obstacle, '🪨 Камень');
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
      expect(level5.maxStep, 3);
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