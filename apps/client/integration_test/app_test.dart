import 'package:burrow/main.dart';
import 'package:burrow/state/app_state.dart';
import 'package:burrow/state/health.dart';
import 'package:burrow/state/sync.dart';
import 'package:burrow/state/workspace.dart';
import 'package:burrow/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('starts on the empty state', (tester) async {
    final app = await AppState.load();
    await tester.pumpWidget(BurrowApp(app: app, workspace: Workspace(), health: HealthMonitor(app), sync: SyncService(app, secrets: MemorySecrets(), auto: false)));
    await tester.pumpAndSettle();
    expect(find.text('Add a host'), findsWidgets);
  });
}
