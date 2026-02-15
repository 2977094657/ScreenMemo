import 'package:flutter_test/flutter_test.dart';
import 'package:screen_memo/services/user_memory_index_service.dart';

void main() {
  test('UserMemoryIndexState.fromRow decodes cursor/stats json', () {
    final UserMemoryIndexState st = UserMemoryIndexState.fromRow({
      'source': UserMemoryIndexService.kSourceSegmentsVisionV1,
      'status': 'paused',
      'cursor_json': '{"last_segment_end_time":100,"last_segment_id":5}',
      'stats_json': '{"processed_segments":12,"errors":1}',
      'started_at': 1,
      'finished_at': null,
      'updated_at': 2,
      'error': null,
    });

    expect(st.source, UserMemoryIndexService.kSourceSegmentsVisionV1);
    expect(st.status, 'paused');
    expect(st.cursor['last_segment_end_time'], 100);
    expect(st.cursor['last_segment_id'], 5);
    expect(st.stats['processed_segments'], 12);
    expect(st.stats['errors'], 1);
  });

  test('isAfterCursor matches (end_time,id) ordering semantics', () {
    // Same end_time: larger id is after.
    expect(
      UserMemoryIndexService.isAfterCursor(
        segmentEndTime: 100,
        segmentId: 6,
        cursorEndTime: 100,
        cursorSegmentId: 5,
      ),
      isTrue,
    );
    // Same end_time: smaller/equal id is not after.
    expect(
      UserMemoryIndexService.isAfterCursor(
        segmentEndTime: 100,
        segmentId: 5,
        cursorEndTime: 100,
        cursorSegmentId: 5,
      ),
      isFalse,
    );
    // Larger end_time is after regardless of id.
    expect(
      UserMemoryIndexService.isAfterCursor(
        segmentEndTime: 101,
        segmentId: 1,
        cursorEndTime: 100,
        cursorSegmentId: 999,
      ),
      isTrue,
    );
    // Smaller end_time is not after.
    expect(
      UserMemoryIndexService.isAfterCursor(
        segmentEndTime: 99,
        segmentId: 999,
        cursorEndTime: 100,
        cursorSegmentId: 1,
      ),
      isFalse,
    );
  });
}
