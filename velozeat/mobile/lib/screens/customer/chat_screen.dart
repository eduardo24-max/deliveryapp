import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class ChatScreen extends StatefulWidget {
  final String orderId;
  final String title;
  const ChatScreen({super.key, required this.orderId, this.title = 'Chat'});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetch(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final res = await context.read<AppState>().api.messages(widget.orderId);
      final raw = res['messages'];
      if (raw is List) {
        _messages = raw.whereType<Map<String, dynamic>>().toList();
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await context.read<AppState>().api.sendMessage(widget.orderId, text);
      _controller.clear();
      await _fetch(silent: true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final myId = app.user?.id;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const LoadingBox(label: 'Cargando chat...')
                : _messages.isEmpty
                    ? const EmptyState(emoji: '', title: 'Sin mensajes', subtitle: 'Inicia la conversación.')
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final m = _messages[index];
                          final mine = m['senderId'] == myId;
                          return Align(
                            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              constraints: const BoxConstraints(maxWidth: 280),
                              decoration: BoxDecoration(
                                color: mine ? kBrand : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: mine ? null : Border.all(color: kLine),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!mine)
                                    Text('${m['senderName'] ?? ''}',
                                        style: const TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.w700)),
                                  Text('${m['text'] ?? ''}',
                                      style: TextStyle(fontSize: 13, color: mine ? Colors.white : kInk)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kLine))),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(hintText: 'Escribe un mensaje...'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded, color: kBrand),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}