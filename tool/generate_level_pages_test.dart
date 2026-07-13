// ГЕНЕРАТОР СТРАНИЦ УРОВНЕЙ 2-10 (docs/levels/*.docx) И ФИКСТУР ТЕСТОВ.
// Запуск: flutter test tool/generate_level_pages_test.dart
// Пишет XML-содержимое docx в build/level_pages/<имя>/ (упаковка в .docx —
// отдельным шагом, см. tool/pack_level_pages.ps1) и перегенерирует
// test/level_round_fixtures.dart. Источник правил — lib/main.dart.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:spatial_memory_game/main.dart';

// ---------- Вспомогательные утилиты OOXML ----------

String esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String para(String text, {bool bold = false, int halfPoints = 0}) {
  final props = StringBuffer();
  if (bold || halfPoints > 0) {
    props.write('<w:rPr>');
    if (bold) props.write('<w:b/>');
    if (halfPoints > 0) props.write('<w:sz w:val="$halfPoints"/>');
    props.write('</w:rPr>');
  }
  return '<w:p><w:r>$props<w:t xml:space="preserve">${esc(text)}</w:t>'
      '</w:r></w:p>';
}

String heading(String text) => para(text, bold: true, halfPoints: 28);

String table(List<List<String>> rows) {
  final b = StringBuffer('<w:tbl><w:tblPr><w:tblBorders>');
  for (final side in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) {
    b.write('<w:$side w:val="single" w:sz="4" w:space="0" w:color="808080"/>');
  }
  b.write('</w:tblBorders></w:tblPr>');
  for (final row in rows) {
    b.write('<w:tr>');
    for (final cell in row) {
      b.write('<w:tc><w:tcPr></w:tcPr>${para(cell)}</w:tc>');
    }
    b.write('</w:tr>');
  }
  b.write('</w:tbl>');
  // Пустой абзац после таблицы — разделитель, требуемый Word.
  b.write('<w:p/>');
  return b.toString();
}

const contentTypesXml = '<?xml version="1.0" encoding="UTF-8" '
    'standalone="yes"?>\n'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '</Types>';

const relsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '</Relationships>';

String documentXml(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:body>$body<w:sectPr/></w:body></w:document>';

// ---------- Игровые утилиты ----------

const horizontalDirs = {'влево', 'вправо'};

String superscript(int n) {
  const map = {
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
    '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  };
  return n.toString().split('').map((c) => map[c]!).join();
}

String thousands(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

// Имя клетки в нотации страницы: столбецСтрока (1-based); на сетке 10 —
// через дефис (номера двухзначные).
String cellName(Point<int> p, int grid) =>
    grid >= 10 ? '${p.x + 1}-${p.y + 1}' : '${p.x + 1}${p.y + 1}';

// Классификация вариации для разделов 3-5.
String moveGroup(String move) {
  final segs = moveSegmentsFor(move);
  final int total = segs.fold(0, (s, e) => s + e.step);
  if (segs.length == 1) return 'Прямые на $total клетки';
  final a = segs[0].step, b = segs[1].step;
  if (move.contains('+')) return 'Двойные ($a+$b)';
  final bool sameAxis = horizontalDirs.contains(segs[0].dir) ==
      horizontalDirs.contains(segs[1].dir);
  return sameAxis ? 'Обратные ($a+$b)' : 'Г-образные ($a+$b)';
}

double log10Factorial(int n) {
  double r = 0;
  for (int i = 2; i <= n; i++) {
    r += log(i) / ln10;
  }
  return r;
}

double log10Combinations(int n, int k) =>
    log10Factorial(n) - log10Factorial(k) - log10Factorial(n - k);

void main() {
  test('Генерация страниц уровней 2-10 и фикстур', () {
    final stagingRoot = Directory('build/level_pages');
    if (stagingRoot.existsSync()) stagingRoot.deleteSync(recursive: true);
    stagingRoot.createSync(recursive: true);

    final fixturesBuf = StringBuffer()
      ..writeln('// СГЕНЕРИРОВАНО tool/generate_level_pages_test.dart —')
      ..writeln('// тем же генератором, что и страницы docs/levels/*.docx.')
      ..writeln('// Не редактировать вручную.')
      ..writeln('class LevelRoundFixture {')
      ..writeln('  final int level;')
      ..writeln('  final int gridSize;')
      ..writeln('  final List<List<int>> objects;')
      ..writeln('  final List<List<int>> obstacles;')
      ..writeln('  final List<int> objectIndex;')
      ..writeln('  final List<String> moves;')
      ..writeln('  final List<bool> expected;')
      ..writeln(
          '  const LevelRoundFixture(this.level, this.gridSize, this.objects,')
      ..writeln(
          '      this.obstacles, this.objectIndex, this.moves, this.expected);')
      ..writeln('}')
      ..writeln('')
      ..writeln('const List<LevelRoundFixture> levelRoundFixtures = [');

    for (final config in difficulties.where((d) => d.level >= 2)) {
      final int grid = config.gridSize;
      final int cells = grid * grid;
      final pool = buildMovePool(config);
      final int target = config.movesPerRound;
      final bool sampled = pool.length >= target;
      final int reps = sampled ? 1 : target ~/ pool.length;
      final int half = target ~/ 2;
      final bool twoObjects = config.objectsCount == 2;
      final bool hasObstacles = config.obstaclesCount > 0;

      // --- Статистика пула на чистом поле ---
      int validTotal = 0;
      final Map<String, int> validByGroup = {};
      final List<List<int>> perCell =
          List.generate(grid, (_) => List.filled(grid, 0));
      for (int x = 0; x < grid; x++) {
        for (int y = 0; y < grid; y++) {
          for (final m in pool) {
            final o = moveOffset(m);
            final nx = x + o.x, ny = y + o.y;
            if (nx >= 0 && nx < grid && ny >= 0 && ny < grid) {
              validTotal++;
              perCell[y][x]++;
              validByGroup[moveGroup(m)] =
                  (validByGroup[moveGroup(m)] ?? 0) + 1;
            }
          }
        }
      }
      final int minPerCell =
          perCell.expand((r) => r).reduce((a, b) => a < b ? a : b);
      final int maxPerCell =
          perCell.expand((r) => r).reduce((a, b) => a > b ? a : b);

      // Группы пула в порядке появления.
      final Map<String, List<String>> groups = {};
      for (final m in pool) {
        groups.putIfAbsent(moveGroup(m), () => []).add(m);
      }

      // --- Готовые раунды (детерминированный генератор) ---
      final rand = Random(1000 + config.level);
      final rounds = <Map<String, dynamic>>[];
      while (rounds.length < 10) {
        final cellsUsed = <Point<int>>{};
        while (cellsUsed.length <
            config.objectsCount + config.obstaclesCount) {
          cellsUsed.add(Point(rand.nextInt(grid), rand.nextInt(grid)));
        }
        final list = cellsUsed.toList();
        final objectStarts = list.sublist(0, config.objectsCount);
        final obstacles = list.sublist(config.objectsCount);
        final plan = generateRoundPlan(
          config: config,
          objectStarts: objectStarts,
          obstacles: obstacles,
          rand: rand,
        );
        final answers = roundPlanAnswers(
          plan: plan,
          objectStarts: objectStarts,
          obstacles: obstacles,
          gridSize: grid,
        );
        // Берём только идеально сбалансированные раунды.
        if (answers.where((a) => a).length != half) continue;
        rounds.add({
          'objects': objectStarts,
          'obstacles': obstacles,
          'plan': plan,
          'answers': answers,
        });
      }

      // --- Фикстуры ---
      for (final r in rounds) {
        final objs = r['objects'] as List<Point<int>>;
        final obst = r['obstacles'] as List<Point<int>>;
        final plan = r['plan'] as List<PlannedMove>;
        final answers = r['answers'] as List<bool>;
        String pts(List<Point<int>> l) =>
            '[${l.map((c) => '[${c.x}, ${c.y}]').join(', ')}]';
        fixturesBuf
          ..writeln('  LevelRoundFixture(${config.level}, $grid, '
              '${pts(objs)}, ${pts(obst)},')
          ..writeln(
              '      [${plan.map((p) => p.objectId - 1).join(', ')}],')
          ..writeln("      [${plan.map((p) => "'${p.move}'").join(', ')}],")
          ..writeln('      [${answers.join(', ')}]),');
      }

      // --- Сборка document.xml ---
      final body = StringBuffer();
      body.write(para('Уровень ${config.level} (сетка $grid×$grid)',
          bold: true, halfPoints: 36));

      body.write(heading('1. Поле и правила'));
      body.write(para('Поле: $grid×$grid = $cells клеток. '
          '${twoObjects ? 'На поле два объекта (① и ②); каждый ход объявляется для одного из них.' : 'Объект стоит на одной клетке.'}'));
      if (hasObstacles) {
        body.write(para(
            'Преграды: ${config.obstaclesCount} шт. Занимают клетки поля; '
            'расположение показывается на запоминании и дальше держится в уме.'));
      }
      body.write(para('Движение — вверх / вниз / влево / вправо. '
          'Диагоналей нет.'));
      final budget = config.minSteps == config.maxSteps
          ? 'ровно ${config.minSteps} шага'
          : 'от ${config.minSteps} до ${config.maxSteps} шагов';
      body.write(para('1 клетка = 1 шаг. Бюджет хода: $budget. '
          'Ход состоит из 1 или 2 сегментов (сегмент — отрезок по одной '
          'оси); ходов из двух одиночных сегментов нет — хотя бы один '
          'сегмент ≥ 2 клеток.'));
      if (config.maxSteps >= 3) {
        body.write(para('Типы ходов: прямые, Г-образные (перпендикулярные '
            'сегменты), двойные (два сегмента одного направления — «...и ещё '
            'на...») и обратные (сегменты противоположных направлений). '
            'Обратных ходов с нулевым итогом (возврат в ту же клетку, '
            'например «2 вверх и 2 вниз») в пуле нет.'));
      }
      final stopReasons = StringBuffer('Ход за край поля');
      if (hasObstacles) stopReasons.write(' / на преграду');
      if (twoObjects) stopReasons.write(' / на клетку другого объекта');
      body.write(para('Проверяется только клетка приземления. $stopReasons — '
          'тупик (объект стоит, ответ «СТОП»); иначе объект перелетает на '
          'новую клетку (ответ «ДАЛЬШЕ»).'));
      final flyOver = StringBuffer(
          'Промежуточные клетки траектории объект перелетает');
      if (hasObstacles || twoObjects) {
        flyOver.write(' — в том числе ');
        flyOver.write([
          if (hasObstacles) 'преграды',
          if (twoObjects) 'другой объект',
        ].join(' и '));
      }
      body.write(para('$flyOver.'));
      body.write(para(
          'Максимальное количество объектов на поле: ${config.objectsCount}.'
          '${hasObstacles ? ' Преград: ${config.obstaclesCount}.' : ''}'));
      body.write(para('Доступ к уровню: ${thousands(config.unlockCost)} монет '
          'и ${config.winsRequiredFromPrevious} побед на уровне '
          '${config.level - 1}.'));

      body.write(heading('2. Обозначения'));
      body.write(para(grid >= 10
          ? 'Клетки — формат столбец-строка (через дефис, т.к. номера '
              'двухзначные):'
          : 'Клетки — формат столбецСтрока:'));
      body.write(table([
        ['', for (int c = 1; c <= grid; c++) 'Ст. $c'],
        for (int r = 1; r <= grid; r++)
          [
            'Строка $r',
            for (int c = 1; c <= grid; c++)
              cellName(Point(c - 1, r - 1), grid),
          ],
      ]));
      body.write(para('Направления шагов: В — вверх, Н — вниз, Л — влево, '
          'П — вправо.'));
      body.write(para('Запись хода — последовательность букв: каждая буква = '
          '1 шаг (1 клетка), порядок букв = порядок шагов. Одинаковые буквы '
          'подряд — один сегмент (напр. ВВП = «на две клетки вверх, затем на '
          'одну вправо»). Знак «+» разделяет два сегмента одного направления: '
          'ЛЛ+ЛЛ = «на две клетки влево и ещё на две клетки влево».'));

      body.write(heading('3. Типы ходов и шаги'));
      int stepsTotal = 0;
      final typeRows = <List<String>>[
        ['Тип хода', 'Вариаций', 'Шагов за ход', 'Всего шагов'],
      ];
      groups.forEach((label, moves) {
        final int perMove = moveSegmentsFor(moves.first)
            .fold(0, (s, e) => s + e.step);
        typeRows.add([
          label,
          '${moves.length}',
          '$perMove',
          '${moves.length * perMove}',
        ]);
        stepsTotal += moves.length * perMove;
      });
      typeRows.add(['Итого', '${pool.length}', '—', '$stepsTotal']);
      body.write(table(typeRows));

      body.write(heading('4. Все ${pool.length} вариаций ходов'));
      body.write(table([
        for (final e in groups.entries)
          ['${e.key} (${e.value.length})', e.value.join(' · ')],
      ]));
      body.write(para('Ходы считаются по траектории: в одну и ту же клетку '
          'могут вести разные пути (напр. ВПП и ППВ, или ЛЛЛ и ЛЛ+Л) — это '
          'разные вариации.'));

      body.write(heading('5. Пул комбинаций «клетка + ход»'));
      body.write(para('$cells клеток × ${pool.length} ходов = '
          '${thousands(cells * pool.length)} вариаций.'));
      body.write(para('Валидных (ДАЛЬШЕ) на чистом поле — учтён только край: '
          '${thousands(validTotal)}.'));
      body.write(para('Тупиковых (СТОП) от края поля: '
          '${thousands(cells * pool.length - validTotal)}.'));
      body.write(para('По видам: ${validByGroup.entries.map(
            (e) => '${e.key.toLowerCase()} ${thousands(e.value)}',
          ).join(' · ')}.'));
      if (hasObstacles || twoObjects) {
        body.write(para('Каждая занятая клетка ('
            '${[if (hasObstacles) 'преграда', if (twoObjects) 'другой объект'].join(' или ')}'
            ') дополнительно переводит в СТОП все комбинации, приземляющиеся '
            'на неё. Число таких комбинаций равно числу ДАЛЬШЕ-ходов из этой '
            'клетки (таблица в разделе 6): набор смещений симметричен, '
            'поэтому «прилётов» в клетку ровно столько же, сколько '
            '«вылетов» из неё.'));
      }

      body.write(heading('6. Сколько ходов доступно из клетки'));
      body.write(para('Число ДАЛЬШЕ-ходов (из ${pool.length}) из каждой '
          'клетки чистого поля (без учёта преград и других объектов):'));
      body.write(table([
        ['', for (int c = 1; c <= grid; c++) 'Ст. $c'],
        for (int r = 0; r < grid; r++)
          ['Строка ${r + 1}', for (int c = 0; c < grid; c++) '${perCell[r][c]}'],
      ]));
      body.write(para('Минимум — в углах ($minPerCell ходов, '
          '${pool.length - minPerCell} тупиков), максимум — в центре поля '
          '($maxPerCell ходов, ${pool.length - maxPerCell} тупиков).'));

      body.write(heading('7. Раунд'));
      if (sampled) {
        body.write(para('Раунд = $target ходов — случайная выборка $target '
            'разных вариаций из пула (${pool.length} вариаций), каждая не '
            'больше одного раза за раунд. Старт — случайная расстановка.'));
      } else {
        body.write(para('Раунд = $target ходов: пул из ${pool.length} '
            'вариаций проходится $reps раза — каждая вариация встречается '
            'ровно $reps раза. Старт — случайная расстановка.'));
      }
      body.write(para('Старт: случайные клетки '
          '${twoObjects ? 'объектов ① и ②' : 'объекта'}'
          '${hasObstacles ? ' и преград' : ''} — клетки не совпадают.'));
      if (twoObjects) {
        body.write(para('Каждый ход адресован конкретному объекту; ходы '
            'поделены между объектами поровну ($half/$half).'));
      }
      body.write(para('Баланс раунда: ровно $half ДАЛЬШЕ / $half СТОП '
          '(50/50).'));
      // Оценка числа вариантов раунда: порядки ходов × дележ × раскладки.
      double log10Orders;
      if (sampled) {
        // Упорядоченные выборки target из pool: pool!/(pool-target)!.
        log10Orders = 0;
        for (int i = 0; i < target; i++) {
          log10Orders += log(pool.length - i) / ln10;
        }
      } else {
        // Перестановки мультимножества: target!/(reps!)^pool.
        log10Orders =
            log10Factorial(target) - pool.length * log10Factorial(reps);
      }
      double log10Total = log10Orders;
      if (twoObjects) log10Total += log10Combinations(target, half);
      double log10Layouts = log(cells) / ln10;
      if (twoObjects) log10Layouts += log(cells - 1) / ln10;
      if (hasObstacles) {
        log10Layouts += log10Combinations(
            cells - config.objectsCount, config.obstaclesCount);
      }
      log10Total += log10Layouts;
      final int exp = log10Total.floor();
      final double mant = pow(10, log10Total - exp).toDouble();
      body.write(para('Возможных вариантов раунда (порядок ходов × '
          '${twoObjects ? 'дележ между объектами × ' : ''}раскладки поля): '
          '≈ ${mant.toStringAsFixed(1).replaceAll('.', ',')}·10${superscript(exp)} — '
          'повторяемость ≈ ноль.'));

      body.write(heading('8. Готовые раунды (10 сбалансированных, '
          '$half/$half)'));
      body.write(para('После каждого хода в скобках указан правильный ответ: '
          'Д = «ДАЛЬШЕ», С = «СТОП». При ответе «ДАЛЬШЕ» объект перемещается '
          'в клетку приземления — следующие ходы считаются уже от неё.'
          '${twoObjects ? ' Значок ①/② — какому объекту адресован ход.' : ''}'));
      final roundRows = <List<String>>[
        ['№', 'Расстановка', 'Ходы'],
      ];
      for (int i = 0; i < rounds.length; i++) {
        final objs = rounds[i]['objects'] as List<Point<int>>;
        final obst = rounds[i]['obstacles'] as List<Point<int>>;
        final plan = rounds[i]['plan'] as List<PlannedMove>;
        final answers = rounds[i]['answers'] as List<bool>;
        final layout = StringBuffer('старт ');
        if (twoObjects) {
          layout.write('① ${cellName(objs[0], grid)}, '
              '② ${cellName(objs[1], grid)}');
        } else {
          layout.write(cellName(objs[0], grid));
        }
        if (obst.isNotEmpty) {
          final sorted = obst.toList()
            ..sort((a, b) => (a.x * 100 + a.y) - (b.x * 100 + b.y));
          layout.write('; преграды: '
              '${sorted.map((p) => cellName(p, grid)).join(', ')}');
        }
        final movesText = [
          for (int j = 0; j < plan.length; j++)
            '${twoObjects ? (plan[j].objectId == 1 ? '①' : '②') : ''}'
                '${plan[j].move}(${answers[j] ? 'Д' : 'С'})',
        ].join(' · ');
        roundRows.add(['${i + 1}', layout.toString(), movesText]);
      }
      body.write(table(roundRows));
      body.write(para(sampled
          ? 'Каждая вариация встречается не больше одного раза. Старт и '
              'преграды фиксированы для раунда. Баланс каждого раунда: '
              '$half ДАЛЬШЕ / $half СТОП.'
          : 'Каждая вариация встречается ровно $reps раза. Старт и преграды '
              'фиксированы для раунда. Баланс каждого раунда: $half ДАЛЬШЕ / '
              '$half СТОП.'));

      // --- Запись файлов docx-структуры ---
      final name = 'Уровень ${config.level} (сетка $grid×$grid)';
      final dir = Directory('build/level_pages/$name');
      Directory('${dir.path}/_rels').createSync(recursive: true);
      Directory('${dir.path}/word').createSync(recursive: true);
      File('${dir.path}/[Content_Types].xml')
          .writeAsStringSync(contentTypesXml);
      File('${dir.path}/_rels/.rels').writeAsStringSync(relsXml);
      File('${dir.path}/word/document.xml')
          .writeAsStringSync(documentXml(body.toString()));

      // ignore: avoid_print
      print('Уровень ${config.level}: пул ${pool.length}, раунд $target, '
          '10 раундов сгенерированы');
    }

    fixturesBuf.writeln('];');
    File('test/level_round_fixtures.dart')
        .writeAsStringSync(fixturesBuf.toString());
    // ignore: avoid_print
    print('Фикстуры записаны: test/level_round_fixtures.dart');
  });
}
