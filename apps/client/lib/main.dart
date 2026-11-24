import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'src/rust/frb_generated.dart';
import 'state/app_state.dart';
import 'state/health.dart';
import 'state/sync.dart';
import 'state/workspace.dart';
import 'ui/desktop/desktop_shell.dart';
import 'ui/mobile/mobile_shell.dart';
import 'ui/theme.dart';
import 'ui/widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final app = await AppState.load();
  final sync = SyncService(app);
  unawaited(sync.restore());
  runApp(
    BurrowApp(
      app: app,
      workspace: Workspace(),
      health: HealthMonitor(app),
      sync: sync,
    ),
  );
}

class BurrowApp extends StatelessWidget {
  const BurrowApp({
    super.key,
    required this.app,
    required this.workspace,
    required this.health,
    required this.sync,
  });
  final AppState app;
  final Workspace workspace;
  final HealthMonitor health;
  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    return Scope(
      app: app,
      workspace: workspace,
      health: health,
      sync: sync,
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => MaterialApp(
          title: 'Burrow SSH',
          debugShowCheckedModeBanner: false,
          themeMode: app.themeMode,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeAnimationDuration: kFast,
          // Follow Dynamic Type, capped where fixed layouts would clip.
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            maxScaleFactor: 2.0,
            child: child!,
          ),
          // Same app, two layouts: keyboard-first sidebar + tabs when wide, thumb-first list when narrow.
          home: LayoutBuilder(
            builder: (context, box) =>
                box.maxWidth < 700 ? const MobileShell() : const DesktopShell(),
          ),
        ),
      ),
    );
  }
}
