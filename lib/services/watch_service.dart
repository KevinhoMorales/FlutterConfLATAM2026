import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/watch_status.dart';

/// API Dart del puente iPhone ↔ Apple Watch.
///
/// Los widgets solo hablan con esta clase. Aquí se esconden:
/// - MethodChannel: Flutter pide algo a Swift y espera respuesta.
/// - EventChannel: Swift empuja eventos (mensajes del Watch y status).
class WatchService {
  WatchService({
    MethodChannel? methodChannel,
    EventChannel? messagesChannel,
    EventChannel? statusChannel,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel(_methodChannelName),
       _messagesChannel =
           messagesChannel ?? const EventChannel(_messagesChannelName),
       _statusChannel =
           statusChannel ?? const EventChannel(_statusChannelName);

  // Los nombres deben coincidir exactamente con FlutterWatchChannel.swift.
  static const _methodChannelName = 'com.example.flutter_watch/watch';
  static const _messagesChannelName = 'com.example.flutter_watch/messages';
  static const _statusChannelName = 'com.example.flutter_watch/status';

  final MethodChannel _methodChannel;
  final EventChannel _messagesChannel;
  final EventChannel _statusChannel;

  // Se crean una sola vez para no abrir varios streams nativos.
  Stream<String>? _messages;
  Stream<WatchStatus>? _statusChanges;

  /// Flutter → MethodChannel → Swift → WCSession → Apple Watch.
  Future<void> sendMessage(String message) async {
    if (!_isIos) {
      throw const WatchUnavailableException('Watch connectivity is iOS-only.');
    }
    try {
      await _methodChannel.invokeMethod<void>(
        'sendMessageToWatch',
        <String, dynamic>{'text': message},
      );
    } on PlatformException catch (error) {
      // Swift respondió FlutterError; lo volvemos un error Dart tipado.
      throw WatchCommunicationException(
        code: error.code,
        message: error.message ?? 'Failed to send message to the Watch.',
      );
    }
  }

  /// Pregunta puntual a Swift: ¿cómo está WCSession ahora?
  Future<WatchStatus> getStatus() async {
    if (!_isIos) {
      return WatchStatus.unsupported();
    }
    try {
      final raw = await _methodChannel.invokeMapMethod<String, dynamic>(
        'getWatchStatus',
      );
      if (raw == null) {
        return WatchStatus.unsupported();
      }
      return WatchStatus.fromMap(raw);
    } on PlatformException {
      return WatchStatus.unsupported();
    }
  }

  Future<bool> isWatchReachable() async {
    if (!_isIos) {
      return false;
    }
    try {
      final value = await _methodChannel.invokeMethod<bool>('isWatchReachable');
      return value ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Mensajes que llegan del Watch en vivo (EventChannel).
  Stream<String> get messages {
    if (!_isIos) {
      return const Stream<String>.empty();
    }
    return _messages ??= _messagesChannel.receiveBroadcastStream().map((event) {
      return event as String;
    });
  }

  /// Cambios de pairing / reachability / activación en vivo.
  Stream<WatchStatus> get statusChanges {
    if (!_isIos) {
      return Stream<WatchStatus>.value(WatchStatus.unsupported());
    }
    return _statusChanges ??= _statusChannel.receiveBroadcastStream().map((
      event,
    ) {
      return WatchStatus.fromMap(Map<String, dynamic>.from(event as Map));
    });
  }

  bool get _isIos =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}

/// Swift no pudo enviar (session, pairing, etc.).
class WatchCommunicationException implements Exception {
  const WatchCommunicationException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'WatchCommunicationException($code): $message';
}

/// La plataforma actual no tiene WatchConnectivity (Android, web, …).
class WatchUnavailableException implements Exception {
  const WatchUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'WatchUnavailableException: $message';
}
