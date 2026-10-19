import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'conformance_context.dart';
import 'stream_routes.dart';

/// The cases of bodies that arrive in pieces: a large one in chunks and a
/// cancel while a body is still coming.
final class StreamingCases {
  /// Creates the cases on [context].
  const StreamingCases(this.context);

  /// The server and the transport under test.
  final ConformanceContext context;

  /// Declares the cases.
  void register() {
    context
      ..testCase('a large chunked body arrives whole', _large)
      ..testCase('a cancel during the body is Cancelled', _cancelDuringBody);
  }

  Future<void> _large() async {
    final result = await context.sender.send(
      ConformanceContext.request('/large-stream', responseKind: .bytes),
      (r) => r.success(r.bytes),
    );
    final success = result as Success<Object?, dynamic>;
    final bytes = (success.data as List<int>);
    expect(bytes.length, StreamRoutes.largeLength);
    expect(success.headers['content-length'], isNull);
    var checksum = 0;
    for (final byte in bytes) {
      checksum += byte;
    }
    expect(checksum, _expectedChecksum());
    expect(bytes.last, StreamRoutes.largeByte(StreamRoutes.largeLength - 1));
  }

  static int _expectedChecksum() {
    var sum = 0;
    for (var i = 0; i < StreamRoutes.largeLength; i++) {
      sum += StreamRoutes.largeByte(i);
    }
    return sum;
  }

  Future<void> _cancelDuringBody() async {
    final signal = CancelSignal();
    final result = await context.sender.send(
      ConformanceContext.request('/trickle', responseKind: .text),
      (r) => r.success(r.body),
      call: CallOptions(
        cancel: signal,
        onReceiveProgress: (received, _) {
          if (received > 0) signal.cancel('mid-body');
        },
      ),
    );
    expect(result, isA<Cancelled<Object?, dynamic>>());
    await context.waitForServer((s) => s['disconnects']!['/trickle'] == 1);
  }
}
