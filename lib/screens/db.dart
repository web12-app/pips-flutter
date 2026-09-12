import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';

class DbPage extends StatefulWidget {
  const DbPage({super.key});
  @override
  State<DbPage> createState() => _DbPageState();
}

class _DbPageState extends State<DbPage> {
  Key refresh = UniqueKey();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Pips DB')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final c = TextEditingController();
            final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('New document'), content: TextField(controller: c, decoration: const InputDecoration(hintText: 'name.md')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Create'))]));
            if (name != null && name.isNotEmpty) {
              try {
                final r = await PipsApi.dbCreate(name, '# $name\n', 'private');
                final id = r['id']?.toString() ?? '';
                setState(() => refresh = UniqueKey());
                if (id.isNotEmpty && context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => DbEditorPage(id: id, name: name)));
              } on ApiException catch (ex) { if (context.mounted) toast(context, ex.message); }
            }
          },
          icon: const Icon(Icons.add), label: const Text('New doc'),
        ),
        body: FutureBuilder<List<dynamic>>(
          key: refresh,
          future: PipsApi.dbFiles(),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Loading();
            final items = (s.data ?? []);
            if (items.isEmpty) return const EmptyState(icon: '🗄️', text: 'No documents yet.');
            return ListView.builder(itemCount: items.length, itemBuilder: (_, i) {
              final d = Map<String, dynamic>.from(items[i] as Map);
              final name = (d['name'] ?? 'doc').toString();
              return ListTile(
                leading: const IconTile(icon: Icons.table_chart_rounded, bg: Color(0xFFF3E8FF), fg: AppTheme.purple),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('v${d['version'] ?? 1} · ${fmtDate(d['updated_at']?.toString() ?? d['created_at']?.toString())}'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DbEditorPage(id: (d['id'] ?? '').toString(), name: name))),
              );
            });
          },
        ),
      );
}

class DbEditorPage extends StatefulWidget {
  final String id, name;
  const DbEditorPage({super.key, required this.id, required this.name});
  @override
  State<DbEditorPage> createState() => _DbEditorPageState();
}

class _DbEditorPageState extends State<DbEditorPage> {
  final ctrl = TextEditingController();
  bool loaded = false, busy = false;
  int version = 1;

  @override
  void initState() {
    super.initState();
    PipsApi.dbRead(widget.id).then((c) => setState(() { ctrl.text = c; loaded = true; })).catchError((e) { setState(() => loaded = true); });
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await PipsApi.dbWrite(widget.id, ctrl.text);
      version++;
      if (mounted) toast(context, 'Saved — new immutable version');
    } on ApiException catch (ex) { if (mounted) toast(context, ex.message); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.name), actions: [
          TextButton.icon(onPressed: busy ? null : save, icon: const Icon(Icons.save), label: Text(busy ? '…' : 'Save')),
          PopupMenuButton<String>(onSelected: (a) async {
            try {
              if (a == 'del') {
                final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text('Delete ${widget.name}?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))]));
                if (ok == true) { await PipsApi.dbRemove(widget.id); if (context.mounted) Navigator.pop(context); }
              }
              if (a == 'move') {
                final c = TextEditingController();
                final p = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Move to path'), content: TextField(controller: c, decoration: const InputDecoration(hintText: '/folder/sub')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Move'))]));
                if (p != null && p.isNotEmpty) { await PipsApi.dbMove(widget.id, p); if (context.mounted) toast(context, 'Moved'); }
              }
            } on ApiException catch (ex) { if (context.mounted) toast(context, ex.message); }
          }, itemBuilder: (_) => const [PopupMenuItem(value: 'move', child: Text('Move path')), PopupMenuItem(value: 'del', child: Text('Delete'))]),
        ]),
        body: !loaded ? const Loading() : TextField(
          controller: ctrl,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(16), hintText: 'Start writing…'),
        ),
      );
}
