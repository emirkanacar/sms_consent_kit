import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_consent_kit/sms_consent_kit.dart';
import 'package:sms_consent_kit/src/transport/messages.g.dart';

import 'support/fake_transport.dart';

void main() {
  late FakeTransport transport;
  late List<String> codes;
  late List<SmsConsentResult> results;
  late GlobalKey<NavigatorState> navigator;

  setUp(() {
    transport = FakeTransport();
    codes = <String>[];
    results = <SmsConsentResult>[];
    navigator = GlobalKey<NavigatorState>();
  });

  tearDown(() {
    SmsConsent.instance = null;
    transport.close();
  });

  /// Creates the shared instance inside the test zone, so its timers are
  /// the test's fake timers.
  void useFake() => SmsConsent.instance = SmsConsent.withTransport(transport);

  Route<void> page(Widget child) =>
      PageRouteBuilder<void>(pageBuilder: (_, __, ___) => child);

  Widget app(Widget home) => WidgetsApp(
        navigatorKey: navigator,
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, __) => builder(context),
        ),
        home: home,
      );

  Widget scope({
    bool enabled = true,
    bool cancelWhenRouteHidden = true,
    Key? key,
  }) =>
      SmsConsentScope(
        key: key,
        enabled: enabled,
        cancelWhenRouteHidden: cancelWhenRouteHidden,
        onCode: codes.add,
        onResult: results.add,
        child: const SizedBox(),
      );

  int lastId() => transport.requests.last.sessionId;

  testWidgets('starts on mount and delivers the code', (tester) async {
    useFake();
    await tester.pumpWidget(app(scope()));
    await tester.pump();
    expect(transport.requests, hasLength(1));

    transport.emit(lastId(), EventTypeMessage.received,
        message: 'Your code is 482913');
    await tester.pump();

    expect(codes, ['482913']);
    expect(results, [
      const SmsConsentReceived('Your code is 482913', code: '482913'),
    ]);
  });

  testWidgets('without a code only onResult is called', (tester) async {
    useFake();
    await tester.pumpWidget(app(scope()));
    await tester.pump();
    transport.emit(lastId(), EventTypeMessage.received, message: 'Hello');
    await tester.pump();

    expect(codes, isEmpty);
    expect(results, [const SmsConsentReceived('Hello')]);
  });

  testWidgets('dispose cancels; nothing is reported afterwards (EC-10)',
      (tester) async {
    useFake();
    await tester.pumpWidget(app(scope()));
    await tester.pump();
    final id = lastId();

    await tester.pumpWidget(app(const SizedBox()));
    await tester.pump();
    expect(transport.calls, contains('cancel:$id'));

    transport.emit(id, EventTypeMessage.received, message: 'Code 482913');
    await tester.pump();
    expect(codes, isEmpty);
    expect(results, isEmpty);
  });

  testWidgets('a covering route cancels; no restart on return (EC-01, EC-11)',
      (tester) async {
    useFake();
    await tester.pumpWidget(app(scope()));
    await tester.pump();
    final id = lastId();

    navigator.currentState!.push(page(const SizedBox()));
    await tester.pumpAndSettle();
    expect(results, [const SmsConsentCancelled(CancelReason.routeHidden)]);
    expect(transport.calls, contains('cancel:$id'));

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(transport.requests, hasLength(1));
  });

  testWidgets('cancelWhenRouteHidden: false keeps listening', (tester) async {
    useFake();
    await tester.pumpWidget(app(scope(cancelWhenRouteHidden: false)));
    await tester.pump();

    navigator.currentState!.push(page(const SizedBox()));
    await tester.pumpAndSettle();
    expect(results, isEmpty);
    expect(SmsConsent.instance.activeSession, isNotNull);
  });

  testWidgets('popping its route does not report routeHidden', (tester) async {
    useFake();
    await tester.pumpWidget(app(const SizedBox()));
    navigator.currentState!.push(page(scope()));
    await tester.pumpAndSettle();
    expect(transport.requests, hasLength(1));

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(results,
        everyElement(const SmsConsentCancelled(CancelReason.scopeDisposed)));
    expect(SmsConsent.instance.activeSession, isNull);
  });

  testWidgets('mounted under another route, starts once visible',
      (tester) async {
    useFake();
    await tester.pumpWidget(WidgetsApp(
      navigatorKey: navigator,
      color: const Color(0xFF000000),
      onGenerateRoute: (_) => page(const SizedBox()),
      onGenerateInitialRoutes: (_) => [page(scope()), page(const SizedBox())],
    ));
    await tester.pump();
    expect(find.byType(SmsConsentScope, skipOffstage: false), findsOneWidget);
    expect(transport.requests, isEmpty);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(transport.requests, hasLength(1));
  });

  testWidgets('enabled toggles the session', (tester) async {
    useFake();
    await tester.pumpWidget(app(scope(enabled: false)));
    await tester.pump();
    expect(transport.requests, isEmpty);

    await tester.pumpWidget(app(scope()));
    await tester.pump();
    expect(transport.requests, hasLength(1));

    await tester.pumpWidget(app(scope(enabled: false)));
    await tester.pump();
    expect(results, [const SmsConsentCancelled(CancelReason.manual)]);

    await tester.pumpWidget(app(scope()));
    await tester.pump();
    expect(transport.requests, hasLength(2));
  });

  testWidgets('restart replaces the session silently (EC-22)', (tester) async {
    useFake();
    await tester.pumpWidget(app(scope()));
    await tester.pump();
    final first = lastId();

    final state = tester.state<SmsConsentScopeState>(
      find.byType(SmsConsentScope),
    );
    state.restart();
    await tester.pump();

    expect(transport.requests, hasLength(2));
    expect(transport.calls, contains('cancel:$first'));
    expect(results, isEmpty);
    expect(state.session?.id, lastId());

    transport.emit(lastId(), EventTypeMessage.received, message: 'code 1234');
    await tester.pump();
    expect(codes, ['1234']);
  });

  testWidgets('restart is a no-op while disabled', (tester) async {
    useFake();
    await tester.pumpWidget(app(scope(enabled: false)));
    tester.state<SmsConsentScopeState>(find.byType(SmsConsentScope)).restart();
    await tester.pump();
    expect(transport.requests, isEmpty);
  });

  testWidgets('of finds the scope', (tester) async {
    useFake();
    late BuildContext inner;
    await tester.pumpWidget(app(SmsConsentScope(
      onCode: (_) {},
      child: Builder(builder: (context) {
        inner = context;
        return const SizedBox();
      }),
    )));
    expect(SmsConsentScope.of(inner), isA<SmsConsentScopeState>());
    expect(SmsConsentScope.maybeOf(navigator.currentContext!), isNull);
  });

  testWidgets('two scopes: the last mounted wins (EC-09)', (tester) async {
    useFake();
    final firstResults = <SmsConsentResult>[];
    await tester.pumpWidget(app(Column(children: [
      SmsConsentScope(
        onCode: (_) {},
        onResult: firstResults.add,
        child: const SizedBox(),
      ),
      scope(),
    ])));
    await tester.pump();

    expect(firstResults, [const SmsConsentCancelled(CancelReason.replaced)]);
    expect(SmsConsent.instance.activeSession?.id, lastId());
  });
}
