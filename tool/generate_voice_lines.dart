// =========================================================================
// ГЕНЕРАТОР ТЕКСТОВ ДЛЯ НЕЙРО-ОЗВУЧКИ (MemoryFly)
// -------------------------------------------------------------------------
// Запуск:  dart run tool/generate_voice_lines.dart
//
// Создаёт два файла:
//   1) assets/voice/voice_manifest.json — машинный список клипов (id, файл,
//      текст). Его можно пакетно скормить нейро-озвучке (клон голоса диктора).
//   2) VOICE_LINES.md — человекочитаемый список, сгруппированный по типам.
//
// ВАЖНО: имена файлов (.mp3) должны совпадать с тем, что ждёт приложение
// (lib/main.dart -> VoiceService). Эта же логика транслитерации продублирована
// там. Если меняешь словарь — меняй в обоих местах.
// =========================================================================

import 'dart:convert';
import 'dart:io';

// --- Объекты и их глаголы действия (в правильном склонении) ---------------
const List<Map<String, dynamic>> names = [
  {'ru': 'Муха',     'key': 'mukha',    'actions': [['полететь', 'poletet'], ['улететь', 'uletet']]},
  {'ru': 'Жук',      'key': 'zhuk',     'actions': [['проползти', 'propolzti'], ['пойти', 'poyti']]},
  {'ru': 'Дрон',     'key': 'dron',     'actions': [['полететь', 'poletet'], ['улететь', 'uletet']]},
  {'ru': 'Робот',    'key': 'robot',    'actions': [['двинуться', 'dvinutsya'], ['переместиться', 'peremestitsya']]},
  {'ru': 'Рыбка',    'key': 'rybka',    'actions': [['поплыть', 'poplyt'], ['уплыть', 'uplyt']]},
  {'ru': 'Осьминог', 'key': 'osminog',  'actions': [['поплыть', 'poplyt'], ['уплыть', 'uplyt']]},
  {'ru': 'Звезда',   'key': 'zvezda',   'actions': [['полететь', 'poletet'], ['улететь', 'uletet']]},
  {'ru': 'Ракета',   'key': 'raketa',   'actions': [['полететь', 'poletet'], ['улететь', 'uletet']]},
  {'ru': 'Кошка',    'key': 'koshka',   'actions': [['пойти', 'poyti'], ['пробежать', 'probezhat']]},
  {'ru': 'Сокол',    'key': 'sokol',    'actions': [['полететь', 'poletet'], ['улететь', 'uletet']]},
  {'ru': 'Дракон',   'key': 'drakon',   'actions': [['полететь', 'poletet'], ['улететь', 'uletet']]},
  {'ru': 'Единорог', 'key': 'edinorog', 'actions': [['пойти', 'poyti'], ['ускакать', 'uskakat']]},
];

// --- Модальные глаголы (вступление фразы) ---------------------------------
const List<List<String>> modals = [
  ['хочет', 'hochet'],
  ['планирует', 'planiruet'],
  ['собирается', 'sobiraetsya'],
  ['пробует', 'probuet'],
];

// --- Количество клеток (1..4 — на уровнях 9-10 шаг бывает 4) ---------------
const List<List<String>> steps = [
  ['одну клетку', '1'],
  ['две клетки', '2'],
  ['три клетки', '3'],
  ['четыре клетки', '4'],
];

// --- Направления ----------------------------------------------------------
const List<List<String>> dirs = [
  ['влево', 'vlevo'],
  ['вправо', 'vpravo'],
  ['вверх', 'vverh'],
  ['вниз', 'vniz'],
];

// --- Статичные (целые) фразы ----------------------------------------------
const List<List<String>> statics = [
  ['memorize', 'Запомни расположение объектов на поле.'],
  ['game_over', 'Ой! Вы ошиблись и объект попал в тупик.'],
  ['perfect_finish', 'Отличная работа! Идеальная сессия. Запуск супер-игры.'],
  ['supergame_trap', 'Ловушка! Вы наступили на препятствие. Супер-игра окончена.'],
  ['found_first', 'Правильно! Нашли первый объект.'],
  ['found_second', 'Отлично! Нашли второй объект. Монеты удвоены!'],
  ['miss_empty', 'Промах! Это была пустая ячейка.'],
  ['xray_on', 'Рентген активирован на три секунды.'],
];

class Clip {
  final String id;
  final String text;
  final String group;
  Clip(this.id, this.text, this.group);

  Map<String, String> toJson() => {'id': id, 'file': '$id.mp3', 'text': text, 'group': group};
}

void main() {
  final List<Clip> clips = [];

  // 1) Статичные фразы
  for (final s in statics) {
    clips.add(Clip(s[0], s[1], 'static'));
  }

  // 2) Вступления: "{Имя} {модальный} {действие} на"
  for (final n in names) {
    final ru = n['ru'] as String;
    final nameKey = n['key'] as String;
    final actions = (n['actions'] as List).cast<List>();
    for (final m in modals) {
      for (final a in actions) {
        final id = 'intro_${nameKey}_${m[1]}_${a[1]}';
        final text = '$ru ${m[0]} ${a[0]} на';
        clips.add(Clip(id, text, 'intro'));
      }
    }
  }

  // 3) Движения: "{N клетк..} {направление}"
  for (final st in steps) {
    for (final d in dirs) {
      final id = 'motion_${st[1]}_${d[1]}';
      final text = '${st[0]} ${d[0]}';
      clips.add(Clip(id, text, 'motion'));
    }
  }

  // 4) Связки для второго сегмента хода:
  //    «и на»     — перпендикулярный ход (влево + вверх);
  //    «и ещё на» — сдвоенный ход в том же направлении (вверх + вверх).
  clips.add(Clip('connector_i_na', 'и на', 'connector'));
  clips.add(Clip('connector_i_eshe_na', 'и ещё на', 'connector'));

  // --- Запись JSON-манифеста ---
  final manifest = {
    'version': 1,
    'note': 'Сгенерировано tool/generate_voice_lines.dart. Имена файлов менять нельзя.',
    'clips': clips.map((c) => c.toJson()).toList(),
  };
  final jsonStr = const JsonEncoder.withIndent('  ').convert(manifest);
  Directory('assets/voice').createSync(recursive: true);
  File('assets/voice/voice_manifest.json').writeAsStringSync('$jsonStr\n');

  // --- Запись человекочитаемого MD ---
  final sb = StringBuffer();
  sb.writeln('# Тексты для нейро-озвучки — MemoryFly');
  sb.writeln();
  sb.writeln('Всего клипов: **${clips.length}**. Каждый клип нужно озвучить голосом диктора');
  sb.writeln('и сохранить как `assets/voice/<file>` (формат `.mp3`).');
  sb.writeln();
  sb.writeln('> Имя файла менять НЕЛЬЗЯ — приложение ищет ровно эти имена.');
  sb.writeln('> В приложении фраза собирается из 1-3 клипов подряд, например:');
  sb.writeln('> `intro_koshka_planiruet_poyti` + `motion_2_vverh` + `connector_i_na` + `motion_1_vpravo`');
  sb.writeln('> = «Кошка планирует пойти на две клетки вверх и на одну клетку вправо».');
  sb.writeln();

  void section(String title, String group) {
    final list = clips.where((c) => c.group == group).toList();
    sb.writeln('## $title (${list.length})');
    sb.writeln();
    sb.writeln('| Файл | Текст для озвучки |');
    sb.writeln('| --- | --- |');
    for (final c in list) {
      sb.writeln('| `${c.id}.mp3` | ${c.text} |');
    }
    sb.writeln();
  }

  section('Статичные фразы', 'static');
  section('Вступления (объект + действие)', 'intro');
  section('Движения (клетки + направление)', 'motion');
  section('Связка', 'connector');

  File('VOICE_LINES.md').writeAsStringSync(sb.toString());

  stdout.writeln('Готово. Клипов: ${clips.length}');
  stdout.writeln(' - assets/voice/voice_manifest.json');
  stdout.writeln(' - VOICE_LINES.md');
}
