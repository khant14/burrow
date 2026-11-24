// Layout checks for the sync dialogs: no overflow at default and large text sizes.
import 'package:burrow/main.dart';
import 'package:burrow/state/app_state.dart';
import 'package:burrow/state/health.dart';
import 'package:burrow/state/sync.dart';
import 'package:burrow/state/workspace.dart';
import 'package:burrow/ui/widgets/sync_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final scale in [1.0, 1.3, 2.0]) {
    for (final create in [false, true]) {
      testWidgets('sign-in dialog fits (create: $create, text x$scale)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        final app = await AppState.load(path: '/nonexistent/burrow.json');
        final health = HealthMonitor(app);
        addTearDown(health.dispose);
        await tester.pumpWidget(
          BurrowApp(
            app: app,
            workspace: Workspace(),
            health: health,
            sync: SyncService(app, secrets: MemorySecrets(), auto: false),
          ),
        );
        final ctx = tester.element(find.byType(Scaffold).first);
        showSyncSignIn(ctx);
        await tester.pumpAndSettle();
        if (create) {
          final link = find.text('New here? Create an account');
          await tester.ensureVisible(link);
          await tester.pumpAndSettle();
          await tester.tap(link);
          await tester.pumpAndSettle();
          expect(find.text('Create a sync account'), findsOneWidget);
        }
        // Show an error line too, the tallest state.
        await tester.ensureVisible(find.byType(FilledButton).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
