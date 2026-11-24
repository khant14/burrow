import 'package:material_ui/material_ui.dart';

import '../../models/host.dart';
import '../../state/app_state.dart';
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

  void _save() {
    final hostname = _hostname.text.trim();
    if (hostname.isEmpty) return;
    widget.onSave(
      Host(
        id: widget.host?.id ?? newId(),
        label: _label.text.trim().isEmpty ? hostname : _label.text.trim(),
        hostname: hostname,
        port: int.tryParse(_port.text) ?? 22,
        username: _user.text.trim(),
        group: _group.text.trim(),
        auth: _auth,
        keyPath: _auth == AuthMethod.key ? _key.text.trim() : null,
        jumpHost: _jump.text.trim().isEmpty ? null : _jump.text.trim(),
        forwards: _forwards.text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
      ),
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
                        child: TextField(
                          controller: _key,
                          decoration: const InputDecoration(
                            labelText: 'Private key',
                          ),
                        ),
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
