import 'dart:async';

import 'package:flutter/material.dart';

import 'models/watch_status.dart';
import 'services/watch_service.dart';

void main() {
  runApp(const FlutterWatchApp());
}

/// App Flutter del iPhone. No conoce MethodChannel ni WatchConnectivity.
class FlutterWatchApp extends StatelessWidget {
  const FlutterWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter ↔ Apple Watch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF02569B),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      // Un solo WatchService para toda la pantalla.
      home: WatchDemoPage(watchService: WatchService()),
    );
  }
}

/// Pantalla de la demo: estado, enviar, último mensaje del Watch.
class WatchDemoPage extends StatefulWidget {
  const WatchDemoPage({super.key, required this.watchService});

  final WatchService watchService;

  @override
  State<WatchDemoPage> createState() => _WatchDemoPageState();
}

class _WatchDemoPageState extends State<WatchDemoPage> {
  final _messageController = TextEditingController(text: 'Hello from Flutter');

  WatchStatus _status = WatchStatus.unsupported();
  String? _lastWatchMessage;
  String? _error;
  bool _sending = false;

  StreamSubscription<String>? _messagesSubscription;
  StreamSubscription<WatchStatus>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    // 1) Pedimos el snapshot actual de WCSession.
    _loadStatus();
    // 2) Escuchamos mensajes que llegan del Watch (EventChannel).
    _messagesSubscription = widget.watchService.messages.listen((message) {
      setState(() {
        _lastWatchMessage = message;
        _error = null;
      });
    });
    // 3) Escuchamos pairing / reachability / activación.
    _statusSubscription = widget.watchService.statusChanges.listen((status) {
      setState(() => _status = status);
    });
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _statusSubscription?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final status = await widget.watchService.getStatus();
    if (!mounted) {
      return;
    }
    setState(() => _status = status);
  }

  /// Flutter → WatchService → Swift → WCSession → Apple Watch.
  Future<void> _sendToWatch() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Write a message first.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await widget.watchService.sendMessage(text);
    } on WatchCommunicationException catch (error) {
      setState(() => _error = error.message);
    } on WatchUnavailableException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter ↔ Apple Watch'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StatusCard(status: _status, onRefresh: _loadStatus),
          const SizedBox(height: 20),
          TextField(
            controller: _messageController,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendToWatch(),
            decoration: const InputDecoration(
              labelText: 'Message',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sending ? null : _sendToWatch,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.watch),
            label: Text(
              _sending ? 'Sending…' : 'Send Message to Watch',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 28),
          Text(
            'Last message from Apple Watch',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _lastWatchMessage == null
                    ? 'No message yet.'
                    : _lastWatchMessage!,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
          if (_lastWatchMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              'Message received from Apple Watch',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta que solo pinta un [WatchStatus]. No habla con channels.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.onRefresh});

  final WatchStatus status;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final reachable = status.reachable;
    final color = !status.supported
        ? Colors.grey
        : reachable
        ? Colors.green
        : Colors.orange;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.watch, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh status',
                ),
              ],
            ),
            const SizedBox(height: 8),
            _StatusLine(label: 'Supported', value: status.supported),
            _StatusLine(label: 'Session', value: status.activationState),
            _StatusLine(label: 'Paired', value: status.paired),
            _StatusLine(label: 'Watch app installed', value: status.watchAppInstalled),
            _StatusLine(label: 'Reachable', value: status.reachable),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value});

  final String label;
  final Object value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('$label: $value'),
    );
  }
}
