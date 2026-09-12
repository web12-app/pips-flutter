import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api.dart';

import '../widgets.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({super.key});
  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  Key refresh = UniqueKey();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Messages'), actions: [
          IconButton(icon: const Icon(Icons.person_add_alt), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSearchPage()))),
        ]),
        body: FutureBuilder<List<dynamic>>(
          key: refresh,
          future: PipsApi.inbox(),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Loading();
            final items = (s.data ?? []);
            if (items.isEmpty) return const EmptyState(icon: '💬', text: 'No conversations yet.');
            return RefreshIndicator(onRefresh: () async => setState(() => refresh = UniqueKey()), child: ListView.builder(itemCount: items.length, itemBuilder: (_, i) {
              final c = Map<String, dynamic>.from(items[i] as Map);
              final peer = (c['peer'] ?? c['username'] ?? c['with'] ?? '').toString();
              return ListTile(
                leading: CircleAvatar(backgroundColor: AppTheme.blue, child: Text(peer.isEmpty ? '?' : peer[0].toUpperCase(), style: const TextStyle(color: Colors.white))),
                title: Text(peer, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text((c['last'] ?? c['last_msg'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(peer: peer))).then((_) => setState(() => refresh = UniqueKey())),
              );
            }));
          },
        ),
      );
}

class ChatPage extends StatefulWidget {
  final String peer;
  const ChatPage({super.key, required this.peer});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ctrl = TextEditingController();
  Key refresh = UniqueKey();
  bool sending = false;

  Future<void> send(String text, [String? fileId]) async {
    setState(() => sending = true);
    try { await PipsApi.sendMessage(widget.peer, text, fileId); ctrl.clear(); setState(() => refresh = UniqueKey()); }
    on ApiException catch (e) { if (mounted) toast(context, e.message); }
    if (mounted) setState(() => sending = false);
  }

  Future<void> attach() async {
    final r = await FilePicker.platform.pickFiles();
    final f = r?.files.single;
    if (f == null || f.path == null) return;
    setState(() => sending = true);
    try {
      final up = await PipsApi.uploadSingle(File(f.path!), f.name, 'application/octet-stream', 'private', (_) {});
      await PipsApi.sendMessage(widget.peer, '', up['id']?.toString() ?? '');
      setState(() => refresh = UniqueKey());
    } on ApiException catch (e) { if (mounted) toast(context, e.message); }
    if (mounted) setState(() => sending = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('@${widget.peer}')),
        body: Column(children: [
          Expanded(child: FutureBuilder<List<dynamic>>(
            key: refresh,
            future: PipsApi.chat(widget.peer),
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const Loading();
              final msgs = (s.data ?? []).reversed.toList();
              return ListView.builder(reverse: true, padding: const EdgeInsets.all(12), itemCount: msgs.length, itemBuilder: (_, i) {
                final m = Map<String, dynamic>.from(msgs[i] as Map);
                final mine = (m['from'] ?? m['sender'] ?? '').toString() == PipsApi.username;
                final liked = m['liked'] == true;
                final fid = (m['file_id'] ?? '').toString();
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(color: mine ? AppTheme.blue : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (!mine) Text((m['from'] ?? '').toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.blue)),
                      if ((m['text'] ?? '').toString().isNotEmpty) Text(m['text'].toString(), style: TextStyle(color: mine ? Colors.white : Colors.black87)),
                      if (fid.isNotEmpty) GestureDetector(
                        onTap: () => toast(context, 'file_id: $fid'),
                        child: Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)), child: Text('📎 $fid', style: const TextStyle(fontSize: 12))),
                      ),
                      GestureDetector(
                        onTap: () async { try { await PipsApi.like(widget.peer, (m['id'] ?? '').toString()); setState(() => refresh = UniqueKey()); } on ApiException catch (_) {} },
                        child: Padding(padding: const EdgeInsets.only(top: 4), child: Icon(liked ? Icons.favorite : Icons.favorite_border, size: 14, color: liked ? Colors.red : (mine ? Colors.white70 : Colors.grey))),
                      ),
                    ]),
                  ),
                );
              });
            },
          )),
          SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 8), child: Row(children: [
            IconButton(icon: const Icon(Icons.attach_file), onPressed: sending ? null : attach),
            Expanded(child: TextField(controller: ctrl, decoration: InputDecoration(hintText: 'Message…', filled: true, fillColor: const Color(0xFFF8FAFC), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16)), onSubmitted: send)),
            IconButton(icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send, color: AppTheme.blue), onPressed: sending ? null : () => send(ctrl.text)),
          ]))),
        ]),
      );
}

class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key});
  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  String q = '';
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search users…', border: InputBorder.none),
          onChanged: (v) => setState(() => q = v),
        )),
        body: FutureBuilder<List<dynamic>>(
          future: PipsApi.socialUsers(q),
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return const Loading();
            final users = (s.data ?? []);
            if (users.isEmpty) return const EmptyState(icon: '👥', text: 'No users found.');
            return ListView.builder(itemCount: users.length, itemBuilder: (_, i) {
              final u = Map<String, dynamic>.from(users[i] as Map);
              final name = (u['username'] ?? u['name'] ?? '').toString();
              final following = u['following'] == true;
              return ListTile(
                leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
                title: Text(name),
                trailing: OutlinedButton(
                  onPressed: () async { try { following ? await PipsApi.unfollow(name) : await PipsApi.follow(name); setState(() {}); } on ApiException catch (e) { if (context.mounted) toast(context, e.message); } },
                  child: Text(following ? 'Unfollow' : 'Follow'),
                ),
              );
            });
          },
        ),
      );
}
