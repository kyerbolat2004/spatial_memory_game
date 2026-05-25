import 'package:flutter_test/flutter_test.dart';
// Вместо 'spatial_memory_game' укажи имя твоего проекта из pubspec.yaml
import 'package:spatial_memory_game/main.dart'; 

void main() {
  // Настройка окружения перед тестами (необходима, так как в main.dart есть привязка к плагинам)
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Тестирование Валидатора (GameValidator)', () {
    
    test('Старт сессии: объект должен инициализироваться строго в центре сетки 3х3', () {
      const config = GameConfig(gridSize: 3);
      final validator = GameValidator(config: config);

      // Проверяем, что X и Y равны 1 (центр сетки при индексации от 0)
      expect(validator.currentX, 1);
      expect(validator.currentY, 1);
    });

    test('Механика отката: rollbackToLastValid должен возвращать объект на прошлую позицию', () {
      const config = GameConfig(gridSize: 3);
      final validator = GameValidator(config: config);

      int startX = validator.currentX;
      int startY = validator.currentY;

      // Симулируем ход программы
      validator.generateNextMove();

      // Вызываем принудительный откат (как при правильном ответе на вылет)
      validator.rollbackToLastValid();

      // Проверяем, вернулись ли координаты в исходную точку
      expect(validator.currentX, startX);
      expect(validator.currentY, startY);
    });

    test('Экономика: проверка правильности начисления базовых очков за ход', () {
      const config = GameConfig(gridSize: 3);
      expect(config.pointsPerMove, 10); // На базе должно быть ровно 10 очков
    });
  });
}