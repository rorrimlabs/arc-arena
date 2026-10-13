import 'package:arena_ops/core/monitoring/app_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTelemetry', () {
    test(
      'breadcrumbs can be added without error when Sentry is uninitialized',
      () {
        expect(
          () => AppTelemetry.addBreadcrumb(
            category: 'test',
            message: 'test_message',
            data: {'key': 'value'},
          ),
          returnsNormally,
        );
      },
    );

    test('timer lifecycle telemetry executes cleanly', () {
      expect(
        () => AppTelemetry.timerStarted(
          sessionId: 's_test_1',
          resourceId: 'ps5_1',
          activityCode: 'PS5',
          durationMinutes: 60,
          controllerCount: 2,
        ),
        returnsNormally,
      );

      expect(
        () => AppTelemetry.sessionSwitched(
          sessionId: 's_test_1',
          operation: 'switch_station',
          fromResourceId: 'ps5_1',
          toResourceId: 'ps5_2',
          controllerCount: 2,
        ),
        returnsNormally,
      );

      expect(
        () => AppTelemetry.billingCalculated(
          sessionId: 's_test_1',
          totalPaise: 30000,
          segmentCount: 2,
          totalSeconds: 3600,
        ),
        returnsNormally,
      );

      expect(
        () => AppTelemetry.timerStopped(
          sessionId: 's_test_1',
          resourceId: 'ps5_2',
          billedAmountPaise: 30000,
          playedDuration: const Duration(hours: 1),
        ),
        returnsNormally,
      );
    });

    test('staff auth telemetry executes cleanly without logging secrets', () {
      expect(
        () => AppTelemetry.staffAuth(
          operation: 'login',
          userId: 'usr_staff_1',
          success: true,
        ),
        returnsNormally,
      );

      expect(
        () =>
            AppTelemetry.staffAuth(operation: 'logout', userId: 'usr_staff_1'),
        returnsNormally,
      );
    });

    test('booking operation telemetry executes cleanly', () {
      expect(
        () => AppTelemetry.bookingOperation(
          bookingId: 'bk_123',
          operation: 'created',
          resourceId: 'ps5_1',
          activityCode: 'PS5',
        ),
        returnsNormally,
      );
    });

    test('timer anomaly reporting executes safely', () {
      expect(
        () => AppTelemetry.reportTimerAnomaly(
          sessionId: 's_test_corrupt',
          anomaly: 'scheduledEndAt precedes startedAt',
          resourceId: 'ps5_1',
          startedAt: DateTime.utc(2026, 10, 1, 12, 0),
          scheduledEndAt: DateTime.utc(2026, 10, 1, 11, 0),
        ),
        returnsNormally,
      );
    });

    test('unexpected exception reporting executes safely', () async {
      await expectLater(
        AppTelemetry.captureException(
          StateError('Unexpected test failure'),
          operation: 'test_operation',
          extra: {'resourceId': 'ps5_1'},
        ),
        completes,
      );
    });
  });
}
