/// Copia en Dart de las propiedades de [WCSession] que el iPhone nos manda.
///
/// Esta clase no habla con iOS. Solo guarda un snapshot para que la UI
/// pueda pintar el estado sin conocer WatchConnectivity.
///
/// [activationState] siempre es válido. [paired], [watchAppInstalled] y
/// [reachable] solo tienen sentido cuando [isActivated] es true.
class WatchStatus {
  const WatchStatus({
    required this.supported,
    required this.paired,
    required this.watchAppInstalled,
    required this.reachable,
    required this.activationState,
  });

  /// Estado seguro para Android, web o iPad: WatchConnectivity no aplica.
  factory WatchStatus.unsupported() {
    return const WatchStatus(
      supported: false,
      paired: false,
      watchAppInstalled: false,
      reachable: false,
      activationState: 'notActivated',
    );
  }

  /// Traduce el mapa que manda Swift (`currentStatus()`).
  factory WatchStatus.fromMap(Map<String, dynamic> map) {
    return WatchStatus(
      supported: map['supported'] as bool? ?? false,
      paired: map['paired'] as bool? ?? false,
      watchAppInstalled: map['watchAppInstalled'] as bool? ?? false,
      reachable: map['reachable'] as bool? ?? false,
      activationState: map['activationState'] as String? ?? 'notActivated',
    );
  }

  /// [WCSession.isSupported]. En iPad o fuera de iOS es false.
  final bool supported;

  /// [WCSession.isPaired]. ¿Hay un Apple Watch emparejado?
  final bool paired;

  /// [WCSession.isWatchAppInstalled]. ¿Está instalada la Watch app companion?
  /// En Simulator esta flag a veces miente.
  final bool watchAppInstalled;

  /// [WCSession.isReachable]. ¿Puedo usar sendMessage ahora mismo?
  final bool reachable;

  /// `notActivated`, `inactive` o `activated`.
  final String activationState;

  bool get isActivated => activationState == 'activated';

  /// Una línea para la tarjeta de la demo.
  String get label {
    if (!supported) {
      return 'Watch not available';
    }
    if (!isActivated) {
      return 'Session $activationState';
    }
    if (!paired) {
      return 'Watch not paired';
    }
    if (reachable) {
      return 'Watch reachable';
    }
    if (watchAppInstalled) {
      return 'Watch installed, not reachable';
    }
    return 'Watch paired — open WatchApp on the Watch';
  }

  Map<String, dynamic> toMap() {
    return {
      'supported': supported,
      'paired': paired,
      'watchAppInstalled': watchAppInstalled,
      'reachable': reachable,
      'activationState': activationState,
    };
  }
}
