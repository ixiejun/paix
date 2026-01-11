import 'dart:convert';

class SseEvent {
  const SseEvent({required this.event, required this.data});

  final String event;
  final String data;
}

Stream<SseEvent> parseSseLines(Stream<String> lines) async* {
  String? currentEvent;
  String? currentData;

  await for (final line in lines) {
    if (line.isEmpty) {
      if (currentEvent != null && currentData != null) {
        yield SseEvent(event: currentEvent, data: currentData);
      }
      currentEvent = null;
      currentData = null;
      continue;
    }

    if (line.startsWith(':')) {
      continue;
    }

    if (line.startsWith('event:')) {
      currentEvent = line.substring('event:'.length).trim();
      continue;
    }

    if (line.startsWith('data:')) {
      final next = line.substring('data:'.length).trim();
      if (currentData == null || currentData.isEmpty) {
        currentData = next;
      } else {
        currentData = '$currentData\n$next';
      }
      continue;
    }
  }

  if (currentEvent != null && currentData != null) {
    yield SseEvent(event: currentEvent, data: currentData);
  }
}

Stream<String> utf8LinesFromByteStream(Stream<List<int>> bytes) {
  return bytes.transform(utf8.decoder).transform(const LineSplitter());
}
