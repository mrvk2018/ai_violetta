import 'dart:math';

class AssistantController {
  AssistantController({Random? random}) : _random = random ?? Random();

  final Random _random;

  final List<String> goodbyePhrases = <String>[
    'Я рядышком, на связи! Зови, если что',
    'Я тут, в ушке. Позови — и я сразу появлюсь',
  ];

  String playRandomGoodbye() {
    final int randomIndex = _random.nextInt(goodbyePhrases.length);
    return goodbyePhrases[randomIndex];
  }
}
