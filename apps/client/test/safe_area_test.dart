// Phones in landscape and tablets get the wide layout: it must stay clear of the
// status bar, a side notch and the navigation bar.
import 'package:burrow/main.dart';
import 'package:burrow/state/app_state.dart';
import 'package:burrow/state/health.dart';
import 'package:burrow/state/sync.dart';
import 'package:burrow/state/workspace.dart';
import 'package:burrow/ui/widgets/art.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final size in [const Size(900, 410), const Size(390, 844)]) {
    testWidgets('logo clears system bars at $size', (tester) async {
      const insets = FakeViewPadding(left: 40, top: 30, bottom: 24);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = insets;
      tester.view.viewPadding = insets;
      addTearDown(tester.view.reset);
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
      expect(mark.top, greaterThanOrEqualTo(30));
      if (size.width > 700) expect(mark.left, greaterThanOrEqualTo(40));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
