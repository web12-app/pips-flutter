import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'viewer.dart';

// ---------------------------------------------------------------- time labels
String _hmm(DateTime d) {
  final h = d.hour == 0 ? 12 : d.hour > 12 ? d.hour - 12 : d.hour;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// List-row stamp: Now · 8:05 PM · Yesterday · Jun 12
String _relStamp(String at) {
  try {
    final d = DateTime.parse(at).toLocal();
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'Now';
    if (d.year == now.year && d.month == now.month && d.day == now.day) return _hmm(d);
    if (diff.inDays == 1) return 'Yesterday';
    return '${_months[d.month - 1]} ${d.day}';
  } catch (_) {
    return '';
  }
}

/// Date divider inside a conversation: "Today, Jun 14"
String _dayLabel(String at) {
  try {
    final d = DateTime.parse(at).toLocal();
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today, ${_months[now.month - 1]} ${now.day}';
    }
    if (now.difference(d).inDays == 1) return 'Yesterday';
    return '${_months[d.month - 1]} ${d.day}${d.year == now.year ? '' : ', ${d.year}'}';
  } catch (_) {
    return '';
  }
}

String _stampOf(String at) {
  try {
    return _hmm(DateTime.parse(at).toLocal());
  } catch (_) {
    return '';
  }
}

bool _sameDay(String a, String b) {
  try {
    final da = DateTime.parse(a).toLocal();
    final db = DateTime.parse(b).toLocal();
    return da.year == db.year && da.month == db.month && da.day == db.day;
  } catch (_) {
    return false;
  }
}

// =================================================================== INBOX
class InboxPage extends StatefulWidget {
  const InboxPage({super.key});
  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  Key refresh = UniqueKey();
  String q = '';
  String filter = 'All';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hc = HomeColors.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 18), onPressed: () => Navigator.of(context).maybePop()),
          const Spacer(),
          const Text('Messages', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, letterSpacing: 0.2)),
          const Spacer(),
          IconButton(icon: const Icon(Icons.camera_alt_outlined), onPressed: () => toast(context, 'Camera chats coming soon')),
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSearchPage())).then((_) => setState(() => refresh = UniqueKey()))),
        ]),
      ),
      body: Column(children: [
        // search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: hc.surfaceSoft,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: hc.line),
            ),
            child: Row(children: [
              const Icon(Icons.search, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => q = v),
                  decoration: const InputDecoration(border: InputBorder.none, hintText: 'Search', isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ]),
          ),
        ),
        // filter chips (like the reference: All / Contacts / Unknown / New)
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final f in const ['All', 'Contacts', 'Unknown', 'New'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _chip(f, filter == f),
                ),
            ],
          ),
        ),
        // conversation list
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            key: refresh,
            future: _inboxData(),
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
              final items = (s.data ?? const <Map<String, dynamic>>[]).where((m) {
                final peer = (m['peer'] ?? '').toString().toLowerCase();
                if (q.isNotEmpty && !peer.contains(q.toLowerCase()) && !(m['last'] ?? '').toString().toLowerCase().contains(q.toLowerCase())) return false;
                switch (filter) {
                  case 'Unread':
                    return (m['unread'] ?? 0) != 0;
                  case 'Contacts':
                    return m['known'] == true;
                  case 'Unknown':
                    return m['known'] == false;
                  case 'New':
                    try {
                      return DateTime.now().difference(DateTime.parse(m['at'].toString())).inHours < 24;
                    } catch (_) {
                      return false;
                    }
                  default:
                    return true;
                }
              }).toList();
              if (items.isEmpty) return EmptyState(icon: '💬', text: q.isNotEmpty ? 'No conversations match.' : 'No conversations yet.');
              return RefreshIndicator(
                onRefresh: () async => setState(() => refresh = UniqueKey()),
                child: ListView.builder(itemCount: items.length, itemBuilder: (_, i) {
                  final c = items[i];
                  final peer = (c['peer'] ?? '').toString();
                  final last = (c['last'] ?? '').toString();
                  final unread = c['unread'] == true ? 1 : (c['unread'] is num ? (c['unread'] as num).toInt() : 0);
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(peer: peer))).then((_) => setState(() => refresh = UniqueKey())),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(children: [
                          AvatarTile(username: peer, radius: 21),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(peer, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5))),
                                if (c['owner'] == true)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(color: AppTheme.blueSoft, borderRadius: BorderRadius.circular(99)),
                                    child: const Text('OWNER', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: AppTheme.blue)),
                                  ),
                              ]),
                              const SizedBox(height: 2),
                              Text(
                                c['file'] == true && last.isEmpty ? '📎 File shared' : (last.isEmpty ? (c['file'] == true ? '📎 File' : '…') : last),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: hc.text2),
                              ),
                            ]),
                          ),
                          const SizedBox(width: 8),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(_relStamp(c['at']?.toString() ?? ''), style: TextStyle(fontSize: 11, color: hc.text2, fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w500)),
                            if (unread > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(color: dark ? const Color(0xFF3A3A3C) : const Color(0xFF111827), borderRadius: BorderRadius.circular(99)),
                                  child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                                ),
                              ),
                          ]),
                        ]),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ]),
    );
  }

  /// Inbox + "known" (followed) flag for the Contacts / Unknown chips.
  Future<List<Map<String, dynamic>>> _inboxData() async {
    final inbox = await PipsApi.inbox();
    List<dynamic> users;
    try {
      users = await PipsApi.socialUsers('');
    } catch (_) {
      users = const [];
    }
    final followed = <String>{
      for (final u in users)
        if (u is Map && u['following'] == true) (u['username'] ?? '').toString().toLowerCase(),
    };
    return [
      for (final r in inbox)
        if (r is Map)
          {
            ...Map<String, dynamic>.from(r),
            'known': followed.contains(((r['peer'] ?? '')).toString().toLowerCase()),
          },
    ];
  }

  Widget _chip(String label, bool on) => GestureDetector(
        onTap: () => setState(() => filter = label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: on ? const Color(0xFF111827) : HomeColors.of(context).surfaceSoft,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: on ? Colors.transparent : HomeColors.of(context).line),
          ),
          child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? Colors.white : HomeColors.of(context).text1)),
        ),
      );
}

// =================================================================== CHAT
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

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<void> send(String text, [String? fileId]) async {
    if (text.trim().isEmpty && (fileId == null || fileId.isEmpty)) return;
    setState(() => sending = true);
    try {
      await PipsApi.sendMessage(widget.peer, text.trim(), fileId);
      ctrl.clear();
      setState(() => refresh = UniqueKey());
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => sending = false);
  }

  Future<void> attach({bool imageOnly = false}) async {
    final r = await FilePicker.platform.pickFiles(type: imageOnly ? FileType.image : FileType.any);
    final f = r?.files.first;
    if (f == null || f.path == null) return;
    setState(() => sending = true);
    try {
      final up = await PipsApi.uploadSingle(File(f.path!), f.name, 'application/octet-stream', 'private', (_) {});
      final entry = (up['entry'] ?? up) as Map;
      await PipsApi.sendMessage(widget.peer, '', (entry['id'] ?? '').toString());
      setState(() => refresh = UniqueKey());
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) setState(() => sending = false);
  }

  void _showEmoji() {
    final emojis = '😀 😁 😂 🤣 😊 😍 😘 😎 🤔 😅 😢 😭 😡 🙏 👍 👎 👏 🙌 💪 🔥  🎉 ❤️ 💔 💯 ✅ ❌ ⚡ 🚀 📌 📎'.split(' ');
    showSheet(context, Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Add emoji', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 8,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1,
          shrinkWrap: true,
          children: [
            for (final e in emojis)
              Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    ctrl.text += e;
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: HomeColors.of(context).surfaceSoft, borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text(e, style: const TextStyle(fontSize: 20))),
                  ),
                ),
              ),
          ],
        ),
      ]),
    ));
  }

  void _openFile(Map<String, dynamic> f) {
    final e = Entry({
      'id': f['id'] ?? '',
      'name': f['name'] ?? 'file',
      'size': f['size'] ?? 0,
      'visibility': f['visibility'] ?? 'private',
      'mime': f['mime'] ?? '',
    });
    Navigator.push(context, MaterialPageRoute(builder: (_) => ViewerPage(e: e)));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hc = HomeColors.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(children: [
          AvatarTile(username: widget.peer, radius: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.peer, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              FutureBuilder<List<dynamic>>(
                key: const ValueKey('status'),
                future: PipsApi.chat(widget.peer).catchError((_) => <dynamic>[]),
                builder: (_, s) {
                  bool online = false;
                  if (s.hasData) {
                    final msgs = (s.data ?? []).toList();
                    if (msgs.isNotEmpty) {
                      try {
                        final lastAt = (msgs.last['at'] ?? '').toString();
                        online = DateTime.now().difference(DateTime.parse(lastAt)).inMinutes < 60;
                      } catch (_) {}
                    }
                  }
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    if (online) const SizedBox(width: 6, height: 6, child: DecoratedBox(decoration: BoxDecoration(color: AppTheme.green, shape: BoxShape.circle))),
                    if (online) const SizedBox(width: 4),
                    Text(online ? 'Online' : 'Offline', style: TextStyle(fontSize: 11, color: online ? AppTheme.green : hc.text2, fontWeight: FontWeight.w600)),
                  ]);
                },
              ),
            ]),
          ),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () => toast(context, 'Video calls coming soon')),
          IconButton(icon: const Icon(Icons.call_outlined), onPressed: () => toast(context, 'Voice calls coming soon')),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: FutureBuilder<List<dynamic>>(
            key: refresh,
            future: PipsApi.chat(widget.peer),
            builder: (_, s) {
              if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
              final msgs = (s.data ?? []).reversed.toList();
              if (msgs.isEmpty) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AvatarTile(username: widget.peer, radius: 34),
                    const SizedBox(height: 10),
                    Text('@${widget.peer}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: hc.text1)),
                    const SizedBox(height: 4),
                    Text('Say hi 👋 — messages appear here.', style: TextStyle(fontSize: 12.5, color: hc.text2)),
                  ]),
                );
              }
              final rows = <Widget>[];
              String? prevAt;
              bool anyPrev = false;
              for (final raw in msgs) {
                final m = Map<String, dynamic>.from(raw as Map);
                final at = (m['at'] ?? '').toString();
                final mine = (m['from'] ?? m['sender'] ?? '').toString() == PipsApi.username;
                bool dayChanged = !anyPrev || !_sameDay(prevAt!, at);
                bool newGroup = dayChanged;
                if (!dayChanged) {
                  final gapMin = DateTime.parse(at).difference(DateTime.parse(prevAt)).inMinutes;
                  newGroup = gapMin > 20;
                }
                if (dayChanged) {
                  rows.add(Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(color: hc.surfaceSoft, borderRadius: BorderRadius.circular(99)),
                        child: Text(_dayLabel(at), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: hc.text2)),
                      ),
                    ),
                  ));
                }
                if (newGroup) {
                  rows.add(Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Center(child: Text(_stampOf(at), style: TextStyle(fontSize: 10.5, color: hc.text2))),
                  ));
                }
                rows.add(Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  child: Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: _bubble(m, mine, dark, (f) => _openFile(f), onLike: () async {
                      try {
                        await PipsApi.like(widget.peer, (m['id'] ?? '').toString());
                        if (mounted) setState(() => refresh = UniqueKey());
                      } on ApiException catch (_) {}
                    }),
                  ),
                ));
                prevAt = at;
                anyPrev = true;
              }
              return ListView(children: [...rows, const SizedBox(height: 8)]);
            },
          ),
        ),
        // input bar — emoji · field · attach · black round send (like the reference)
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.emoji_emotions_outlined, color: hc.text2),
                onPressed: _showEmoji,
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: hc.surfaceSoft,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: hc.line),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        onSubmitted: send,
                        decoration: InputDecoration(border: InputBorder.none, hintText: 'Message…', isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 12)),
                      ),
                    ),
                    IconButton(icon: Icon(Icons.photo_camera_outlined, size: 19, color: hc.text2), onPressed: sending ? null : () => attach(imageOnly: true)),
                    IconButton(icon: Icon(Icons.attach_file, size: 18, color: hc.text2), onPressed: sending ? null : () => attach()),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: sending ? null : () => send(ctrl.text),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF111827) : const Color(0xFF111827),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bubble(Map<String, dynamic> m, bool mine, bool dark, void Function(Map<String, dynamic>) openFile, {required VoidCallback onLike}) {
    final hc = HomeColors.of(context);
    final text = (m['text'] ?? '').toString();
    final f = m['file'];
    final hasFile = f is Map && (f['id']?.toString().isNotEmpty ?? false);
    final liked = m['liked'] == true || (m['likes'] is List && (m['likes'] as List).contains(PipsApi.username));
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
      decoration: BoxDecoration(
        color: mine ? AppTheme.blue : (dark ? const Color(0xFF2A2A2C) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mine ? Colors.transparent : hc.line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      padding: EdgeInsets.zero,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 9, 13, 9),
          child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            if (hasFile)
              GestureDetector(
                onTap: () => openFile(Map<String, dynamic>.from(f)),
                child: Container(
                  margin: EdgeInsets.only(bottom: text.isEmpty ? 0 : 8, top: 0),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: mine ? Colors.white.withValues(alpha: 0.18) : (dark ? const Color(0xFF3A3A3C) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.insert_drive_file, size: 17, color: Colors.white70),
                    const SizedBox(width: 8),
                    Flexible(child: Text((f['name'] ?? 'file').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: mine ? Colors.white : hc.text1))),
                  ]),
                ),
              ),
            if (text.isNotEmpty)
              Text(text, style: TextStyle(color: mine ? Colors.white : hc.text1, fontSize: 14, height: 1.35)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 8, 4),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
            GestureDetector(
              onTap: onLike,
              child: Icon(liked ? Icons.favorite : Icons.favorite_border, size: 13, color: liked ? const Color(0xFFEF4444) : (mine ? Colors.white54 : hc.text2)),
            ),
            const SizedBox(width: 5),
            Text(_stampOf(m['at']?.toString() ?? ''), style: TextStyle(fontSize: 10, color: mine ? Colors.white54 : hc.text2)),
          ]),
        ),
      ]),
    );
  }
}

// =================================================================== find people
class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key});
  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  String q = '';
  Key refresh = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final hc = HomeColors.of(context);
    return Scaffold(
      appBar: AppBar(title: TextField(
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Search people…', border: InputBorder.none),
        onChanged: (v) => setState(() => q = v),
      )),
      body: FutureBuilder<List<dynamic>>(
        key: refresh,
        future: PipsApi.socialUsers(q),
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return const SkeletonScreen();
          final users = (s.data ?? []);
          if (users.isEmpty) return const EmptyState(icon: '👥', text: 'No users found.');
          return ListView.builder(itemCount: users.length, itemBuilder: (_, i) {
            final u = Map<String, dynamic>.from(users[i] as Map);
            final name = (u['username'] ?? u['name'] ?? '').toString();
            final following = u['following'] == true;
            return ListTile(
              leading: AvatarTile(username: name, radius: 20),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(following ? 'Following' : 'Not following', style: TextStyle(fontSize: 11.5, color: hc.text2)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                OutlinedButton(
                  onPressed: () async {
                    try {
                      following ? await PipsApi.unfollow(name) : await PipsApi.follow(name);
                      setState(() => refresh = UniqueKey());
                    } on ApiException catch (e) {
                      if (context.mounted) toast(context, e.message);
                    }
                  },
                  child: Text(following ? 'Unfollow' : 'Follow', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Message',
                  icon: const Icon(Icons.chat_bubble_outline, color: AppTheme.blue),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(peer: name)));
                  },
                ),
              ]),
            );
          });
        },
      ),
    );
  }
}
