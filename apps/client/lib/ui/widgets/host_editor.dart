import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/host.dart';
import '../../state/app_state.dart';
import '../../state/keys.dart';
import '../theme.dart';
import 'common.dart';

/// Opens the host editor: a centered dialog on desktop, a full-screen page on mobile.
Future<void> editHost(
  BuildContext context, {
  Host? host,
  required bool compact,
}) {
  final app = Scope.of(context).app;
  final groups = app.hosts
      .map((h) => h.group)
      .where((g) => g.isNotEmpty)
      .toSet()
      .toList();
  Widget editor(BuildContext ctx) => HostEditor(
    host: host,
    groups: groups,
    onSave: (h) {
      app.upsertHost(h);
      Navigator.pop(ctx);
    },
    onDelete: host == null
        ? null
        : () {
            app.removeHost(host);
            Navigator.pop(ctx);
          },
  );
  if (compact) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: ctx.c.raised,
          body: SafeArea(child: editor(ctx)),
        ),
      ),
    );
  }
  return showFadeDialog(
    context,
    (ctx) => Material(
      type: MaterialType.transparency,
      child: Container(
        width: 460,
        constraints: const BoxConstraints(maxHeight: 640),
        decoration: BoxDecoration(
          color: ctx.c.raised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ctx.c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: editor(ctx),
      ),
    ),
  );
}

class HostEditor extends StatefulWidget {
  const HostEditor({
    super.key,
    this.host,
    required this.groups,
    required this.onSave,
    this.onDelete,
  });
  final Host? host;
  final List<String> groups;
  final ValueChanged<Host> onSave;
  final VoidCallback? onDelete;

  @override
  State<HostEditor> createState() => _HostEditorState();
}

class _HostEditorState extends State<HostEditor> {
  late final _label = TextEditingController(text: widget.host?.label);
  late final _hostname = TextEditingController(text: widget.host?.hostname);
  late final _port = TextEditingController(text: '${widget.host?.port ?? 22}');
  late final _user = TextEditingController(text: widget.host?.username);
  late final _group = TextEditingController(text: widget.host?.group);
  late final _key = TextEditingController(
    text: widget.host?.keyPath ?? '~/.ssh/id_ed25519',
  );
  late final _jump = TextEditingController(text: widget.host?.jumpHost);
  late final _forwards = TextEditingController(
    text: widget.host?.forwards.join('\n'),
  );
  late AuthMethod _auth = widget.host?.auth ?? AuthMethod.key;
  late bool _advanced =
      (widget.host?.jumpHost?.isNotEmpty ?? false) ||
      (widget.host?.forwards.isNotEmpty ?? false);

  late final String _id = widget.host?.id ?? newId();

  /// A key held in the keychain for this host (pasted or picked from a file).
  bool _storedKey = false;

  /// Key text picked or pasted in this editor, saved with the host.
  String? _newPem;

  @override
  void initState() {
    super.initState();
    if (widget.host != null) {
      KeyStore.read(_id).then((k) {
        if (mounted && k != null) setState(() => _storedKey = true);
      });
    }
  }

  Future<void> _pasteKey() async {
    final ctrl = TextEditingController();
    final pem = await showFadeDialog<String>(context, (ctx) {
      final c = ctx.c;
      return Material(
        type: MaterialType.transparency,
        child: Container(
          width: 460,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Heading('Paste a private key', size: 20),
              const SizedBox(height: 4),
              Text(
                'Burrow keeps it in your keychain, on this device only.',
                style: TextStyle(fontSize: 12.5, color: c.muted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                minLines: 5,
                maxLines: 8,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontFamily: kMono, fontSize: 11.5),
                decoration: const InputDecoration(
                  hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, ctrl.text),
                    child: const Text('Use key'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
    _useKey(pem);
  }

  Future<void> _chooseKeyFile() async {
    final f = await openFile(initialDirectory: expandHome('~/.ssh'));
    if (f == null) return;
    if (!isApple) {
      setState(() => _key.text = f.path);
      return;
    }
    _useKey(await f.readAsString());
  }

  void _useKey(String? pem) {
    if (pem == null || !mounted) return;
    if (!KeyStore.looksLikeKey(pem)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text("That doesn't look like a private key.")),
      );
      return;
    }
    setState(() {
      _newPem = pem;
      _storedKey = true;
    });
  }

  Future<void> _save() async {
    final hostname = _hostname.text.trim();
    if (hostname.isEmpty) return;
    if (_auth == AuthMethod.key && _newPem != null) {
      await KeyStore.write(_id, _newPem!);
    } else if (_auth == AuthMethod.password && _storedKey) {
      await KeyStore.delete(_id);
    }
    if (!mounted) return;
    widget.onSave(
      Host(
        id: _id,
        label: _label.text.trim().isEmpty ? hostname : _label.text.trim(),
        hostname: hostname,
        port: int.tryParse(_port.text) ?? 22,
        username: _user.text.trim(),
        group: _group.text.trim(),
        auth: _auth,
        keyPath: _auth == AuthMethod.key && !isApple ? _key.text.trim() : null,
        jumpHost: _jump.text.trim().isEmpty ? null : _jump.text.trim(),
        forwards: _forwards.text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
      ),
    );
  }

  /// Apple apps can't read ~/.ssh, so the key is pasted or picked and kept in the keychain.
  /// Elsewhere a path works, and the file picker fills it in.
  Widget _keyField(BurrowColors c) {
    if (!isApple) {
      return TextField(
        controller: _key,
        decoration: InputDecoration(
          labelText: 'Private key',
          suffixIcon: IconButton(
            tooltip: 'Choose key file',
            icon: Icon(Icons.folder_open, size: 18, color: c.muted),
            onPressed: _chooseKeyFile,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              _storedKey ? Icons.key : Icons.key_off,
              size: 18,
              color: _storedKey ? c.success : c.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _storedKey
                    ? 'Key saved in your keychain'
                    : 'Add the private key for this host',
                style: TextStyle(fontSize: 13, color: c.text),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _pasteKey,
              icon: const Icon(Icons.content_paste, size: 16),
              label: Text(_storedKey ? 'Replace key' : 'Paste key'),
            ),
            OutlinedButton.icon(
              onPressed: _chooseKeyFile,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Choose file'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const gap = SizedBox(height: 12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
          child: Row(
            children: [
              Heading(
                widget.host == null
                    ? 'A new host'
                    : 'Edit ${widget.host!.label}',
                size: 19,
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close, size: 18, color: c.muted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'A name you\'ll recognize, like prod-web',
                ),
              ),
              gap,
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _hostname,
                      autofocus: widget.host == null,
                      decoration: const InputDecoration(
                        labelText: 'Host',
                        hintText: '10.0.0.4 or example.com',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Port'),
                    ),
                  ),
                ],
              ),
              gap,
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _user,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Autocomplete<String>(
                      initialValue: TextEditingValue(text: _group.text),
                      optionsBuilder: (v) => widget.groups.where(
                        (g) => g.toLowerCase().contains(v.text.toLowerCase()),
                      ),
                      onSelected: (v) => _group.text = v,
                      fieldViewBuilder: (ctx, ctrl, focus, _) {
                        ctrl.addListener(() => _group.text = ctrl.text);
                        return TextField(
                          controller: ctrl,
                          focusNode: focus,
                          decoration: const InputDecoration(
                            labelText: 'Burrow',
                            hintText: 'Production',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SegmentedButton<AuthMethod>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: c.hover,
                  selectedForegroundColor: c.text,
                  foregroundColor: c.muted,
                  side: BorderSide(color: c.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                segments: const [
                  ButtonSegment(value: AuthMethod.key, label: Text('SSH key')),
                  ButtonSegment(
                    value: AuthMethod.password,
                    label: Text('Password'),
                  ),
                ],
                selected: {_auth},
                onSelectionChanged: (s) => setState(() => _auth = s.first),
              ),
              AnimatedSize(
                duration: kFast,
                alignment: Alignment.topCenter,
                child: _auth == AuthMethod.key
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _keyField(c),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'We\'ll ask for the password when you open a tunnel, and never write it to disk.',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                      ),
              ),
              const SizedBox(height: 14),
              HoverRow(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                onTap: () => setState(() => _advanced = !_advanced),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: _advanced ? 0.25 : 0,
                      duration: kFast,
                      child: Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: c.muted,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Advanced',
                      style: TextStyle(
                        fontSize: 13,
                        color: c.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Jump hosts, port forwarding. Most hosts don\'t need these.',
                      style: TextStyle(fontSize: 12, color: c.faint),
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: kFast,
                alignment: Alignment.topCenter,
                child: !_advanced
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          children: [
                            TextField(
                              controller: _jump,
                              decoration: const InputDecoration(
                                labelText: 'Jump host',
                                hintText: 'user@bastion:22',
                              ),
                            ),
                            gap,
                            TextField(
                              controller: _forwards,
                              minLines: 2,
                              maxLines: 4,
                              style: const TextStyle(
                                fontFamily: kMono,
                                fontSize: 12.5,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Port forwards',
                                hintText: 'L 8080:localhost:80\nD 1080',
                                alignLabelWithHint: true,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Row(
            children: [
              if (widget.onDelete != null)
                TextButton(
                  onPressed: widget.onDelete,
                  style: TextButton.styleFrom(foregroundColor: c.danger),
                  child: const Text('Delete'),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _save,
                child: Text(widget.host == null ? 'Add host' : 'Save'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
