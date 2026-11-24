import 'package:material_ui/material_ui.dart';

import '../../state/sync.dart';
import '../theme.dart';
import 'common.dart';

/// Sync section of Settings. Optional: Burrow works fully without an account.
class SyncSection extends StatelessWidget {
  const SyncSection({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = Scope.of(context).sync;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final c = context.c;
        final small = TextStyle(fontSize: 12, color: c.muted);
        if (!sync.signedIn) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Optional. Keep hosts in step across your devices through a '
                'Burrow sync server you run. Everything is encrypted on this '
                'device first.',
                style: small,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => showSyncSignIn(context),
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('Set up sync'),
              ),
            ],
          );
        }
        final (label, color) = switch (sync.status) {
          SyncStatus.syncing => ('Syncing…', c.muted),
          SyncStatus.offline => (
            'Offline. Changes will sync when the server is back.',
            c.muted,
          ),
          SyncStatus.error => (sync.error ?? 'Sync failed', c.danger),
          _ => (_lastSyncedText(sync.lastSynced), c.success),
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${sync.email}  ·  ${Uri.tryParse(sync.server ?? '')?.authority ?? sync.server}',
              style: TextStyle(fontSize: 13, color: c.text),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: sync.status == SyncStatus.syncing
                      ? null
                      : sync.syncNow,
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Sync now'),
                ),
                TextButton(
                  onPressed: () => _confirmSignOut(context, sync),
                  child: const Text('Sign out'),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: c.danger),
                  onPressed: () => _confirmDelete(context, sync),
                  child: const Text('Delete account'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

String _lastSyncedText(DateTime? t) {
  if (t == null) return 'Signed in';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Synced just now';
  if (d.inHours < 1) return 'Synced ${d.inMinutes} min ago';
  if (d.inDays < 1) return 'Synced ${d.inHours} h ago';
  return 'Synced ${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

Widget _card(BuildContext ctx, {required List<Widget> children}) {
  final c = ctx.c;
  return Material(
    type: MaterialType.transparency,
    child: Container(
      width: 380,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  bool danger = false,
}) async {
  final ok = await showFadeDialog<bool>(context, (ctx) {
    final c = ctx.c;
    return _card(
      ctx,
      children: [
        Heading(title, size: 20),
        const SizedBox(height: 8),
        Text(body, style: TextStyle(fontSize: 12.5, color: c.muted)),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: danger
                  ? FilledButton.styleFrom(
                      backgroundColor: c.danger,
                      foregroundColor: Colors.white,
                    )
                  : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      ],
    );
  });
  return ok ?? false;
}

Future<void> _confirmSignOut(BuildContext context, SyncService sync) async {
  if (await _confirm(
    context,
    title: 'Sign out of sync?',
    body:
        'Your hosts stay on this device and on the server. Changes here will '
        'stop syncing until you sign in again.',
    action: 'Sign out',
  )) {
    await sync.signOut();
  }
}

Future<void> _confirmDelete(BuildContext context, SyncService sync) async {
  if (!await _confirm(
    context,
    title: 'Delete your sync account?',
    body:
        'This permanently deletes ${sync.email} and everything synced to '
        '${Uri.tryParse(sync.server ?? '')?.authority ?? 'the server'}. '
        'Hosts on this device are kept. Other devices keep their copies but '
        'stop syncing.',
    action: 'Delete account',
    danger: true,
  )) {
    return;
  }
  try {
    await sync.deleteAccount();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Could not delete the account: $e')),
      );
    }
  }
}

Future<void> showSyncSignIn(BuildContext context) {
  final sync = Scope.of(context).sync;
  return showFadeDialog(context, (_) => _SignInDialog(sync: sync));
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog({required this.sync});
  final SyncService sync;

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  final _server = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _create = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_server.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _password.text.isEmpty) {
      setState(() => _error = 'Fill in the server, email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.sync.signIn(
        server: _server.text,
        email: _email.text,
        password: _password.text,
        create: _create,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const gap = SizedBox(height: 12);
    return _card(
      context,
      children: [
        Heading(
          _create ? 'Create a sync account' : 'Sign in to sync',
          size: 20,
        ),
        const SizedBox(height: 4),
        Text(
          'Your password never leaves this device. It encrypts your hosts '
          'before upload, so it can\'t be reset. Keep it somewhere safe.',
          style: TextStyle(fontSize: 12.5, color: c.muted),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _server,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Server',
            hintText: 'localhost:8080 or https://sync.example.com',
          ),
        ),
        gap,
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        gap,
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: [
            _create ? AutofillHints.newPassword : AutofillHints.password,
          ],
          decoration: InputDecoration(
            labelText: 'Password',
            helperText: _create ? 'At least 8 characters' : null,
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(fontSize: 12, color: c.danger)),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _create = !_create),
              child: Text(_create ? 'I have an account' : 'Create account'),
            ),
            const Spacer(),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_create ? 'Create and sync' : 'Sign in'),
            ),
          ],
        ),
      ],
    );
  }
}
