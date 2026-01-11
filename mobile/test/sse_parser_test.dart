import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/sse_parser.dart';

void main() {
  test('parseSseLines emits events separated by blank lines', () async {
    final input = Stream<String>.fromIterable([
      'event: chunk',
      'data: {"delta_text":"hi","sequence":0}',
      '',
      'event: done',
      'data: {"assistant_text":"hi","session_id":"s"}',
      '',
    ]);

    final events = await parseSseLines(input).toList();

    expect(events.length, 2);
    expect(events[0].event, 'chunk');
    expect(events[0].data, '{"delta_text":"hi","sequence":0}');
    expect(events[1].event, 'done');
  });
}
