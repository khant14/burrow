// The phone header keeps the logo and name on one row, at narrow widths and large text.
import 'package:burrow/main.dart';
import 'package:burrow/state/app_state.dart';
import 'package:burrow/state/health.dart';
import 'package:burrow/state/sync.dart';
import 'package:burrow/state/workspace.dart';
import 'package:burrow/ui/widgets/art.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('logo and name share a row ($width wide, text x$scale)', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
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
        await tester.pump();
        final mark = tester.getRect(find.byType(BurrowMark).first);
        final name = tester.getRect(find.text('Burrow').first);
        expect(name.left, greaterThan(mark.right));
        expect(
          (name.center.dy - mark.center.dy).abs(),
          lessThan(mark.height / 2),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
