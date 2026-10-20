import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_client/src/sse/reconnection_plan.dart';
import 'package:typed_openapi_client/src/sse/sse_settings.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import '../helpers/fake_transport.dart';
import '../helpers/scripted_transport.dart';

void main() {
  const watch = OperationRequest(
    OperationInfo(operationId: 'watch', method: 'GET', pathTemplate: '/w'),
    streamStatuses: {200, 204},
  );

  HttpError<Object?, Object?> tooMany(String retryAfter) => HttpError(
    'x',
    statusCode: 429,
    headers: {
      'retry-after': [retryAfter],
    },
  );

  group('a Retry-After wait', () {
    test('ends at once when the call is cancelled, with no timer left', () {
      fakeAsync((async) {
        final cancel = CancelSignal();
        var request = 0;
        final first = ScriptedConnection.open()..write('data: a\n\n');
        final transport = _Direct((_) {
          request++;
          return request == 1
              ? TransportResponse(
                  statusCode: 200,
                  body: first.body.stream,
                  headers: const {
                    'content-type': ['text/event-stream'],
                  },
                )
              : const TransportResponse(
                  statusCode: 429,
                  body: Stream<List<int>>.empty(),
                  headers: {
                    'retry-after': ['120'],
                  },
                );
        });
        final seen = <SseItem<String>>[];
        unawaited(
          ClientSender(transport)
              .openEvents<String, Never>(
                watch,
                (m) => m.data,
                (r) => r.undocumented(),
                call: CallOptions(
                  sse: const SseOptions(
                    reconnect: true,
                    idleTimeout: Duration(seconds: 10),
                  ),
                  cancel: cancel,
                ),
                reconnection: SseReconnection.on,
              )
              .then((r) {
                if (r case Success(:final data)) data.listen(seen.add);
              }),
        );
        async.elapse(const Duration(seconds: 10));
        expect(seen.last, isA<SseReconnecting<String>>());
        async.elapse(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 5));
        expect(request, 2);
        expect(
          (seen.last as SseReconnecting<String>).delay,
          const Duration(seconds: 120),
        );
        cancel.cancel();
        async.flushMicrotasks();
        expect(seen.last, isA<SseDisconnected<String>>());
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('Retry-After at a cooldown step', () {
    ReconnectionPlan plan() => ReconnectionPlan(
      SseSettings.of(
        const SseOptions(
          cooldown: SseCooldown(after: 2, duration: Duration(seconds: 10)),
        ),
      ),
    );

    ReconnectionStep? atCooldown(ReconnectionPlan plan, String? retryAfter) {
      plan
        ..next(null)
        ..next(null);
      return plan.next(
        null,
        failure: retryAfter == null ? null : tooMany(retryAfter),
      );
    }

    test('a longer Retry-After replaces the cooldown', () {
      expect(atCooldown(plan(), '60'), (
        attempt: 3,
        delay: const Duration(seconds: 60),
      ));
    });

    test('a shorter one leaves the cooldown', () {
      expect(atCooldown(plan(), '5'), (
        attempt: 3,
        delay: const Duration(seconds: 10),
      ));
    });

    test('the count starts again after the cooldown', () {
      final p = plan();
      atCooldown(p, '60');
      expect(p.next(null), (attempt: 1, delay: const Duration(seconds: 1)));
    });
  });

  group('SseSettings.shouldRetry', () {
    test('does not ask retryWhen about a Cancelled', () {
      var asked = 0;
      final settings = SseSettings.of(
        SseOptions(
          retryWhen: (_) {
            asked++;
            return true;
          },
        ),
      );
      const cancelled = Cancelled<Object?, Object?>(
        TransportException(.cancelled, 'x'),
        StackTrace.empty,
      );
      expect(settings.shouldRetry(cancelled), isFalse);
      expect(asked, 0);
    });
  });

  test('a reopen that returns Cancelled ends the stream unasked', () async {
    var asked = 0;
    var request = 0;
    final cancel = CancelSignal();
    final transport = _Direct((_) {
      if (++request == 1) {
        return FakeTransport.response('data: a\n\n', 200, 'text/event-stream');
      }
      throw const TransportException(.cancelled, 'gone');
    });
    final result = await ClientSender(transport).openEvents<String, Never>(
      watch,
      (m) => m.data,
      (r) => r.undocumented(),
      call: CallOptions(
        cancel: cancel,
        sse: SseOptions(
          reconnect: true,
          wait: (_) async {},
          retryWhen: (_) {
            asked++;
            return true;
          },
        ),
      ),
      reconnection: SseReconnection.on,
    );
    final items = await (result as Success<Stream<SseItem<String>>, Never>).data
        .toList();
    expect(items.last, isA<SseDisconnected<String>>());
    expect(
      ((items.last as SseDisconnected<String>).cause as TransportException)
          .kind,
      TransportExceptionKind.cancelled,
    );
    expect(request, 2);
    expect(asked, 0);
  });
}

/// A transport that answers at once, with nothing between the response and
/// the client: under `fakeAsync` a wrapper that cancels a finished
/// subscription completes a future outside the fake zone.
final class _Direct implements ClientTransport {
  _Direct(this._respond);

  final TransportResponse Function(TransportRequest request) _respond;

  @override
  Future<TransportResponse> send(TransportRequest request) =>
      Future.value(_respond(request));
}
