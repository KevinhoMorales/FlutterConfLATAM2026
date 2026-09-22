# Flutter Beyond the Phone: Apple Watch Integration

Proyecto de charla. Flutter **no** pinta el Apple Watch. El Watch es nativo (Swift + SwiftUI). Flutter solo habla con Swift del iPhone; Swift habla con el Watch usando WatchConnectivity.

```
Flutter (Dart)
    -> WatchService
        -> MethodChannel / EventChannel
            -> FlutterWatchChannel.swift
                -> WatchConnectivityManager.swift (iPhone)
                    -> WCSession
                        -> WatchConnectivityManager.swift (Watch)
                            -> ContentView.swift
```

---

## 1. Dart — `lib/models/watch_status.dart`

### `WatchStatus`

Copia en Dart de las propiedades de `WCSession` del iPhone.

No habla con iOS. Solo guarda y traduce un mapa:

```
{
  supported,
  paired,
  watchAppInstalled,
  reachable,
  activationState
}
```

Paso a paso:

1. Swift lee `WCSession` y arma ese mapa.
2. `WatchService.getStatus()` lo recibe.
3. `WatchStatus.fromMap()` lo convierte en un objeto Dart.
4. La UI lee `label`, `supported`, `paired`, etc.

Qué significa cada campo:

| Campo | API de Apple | Cuándo es válido |
|---|---|---|
| `supported` | `WCSession.isSupported()` | Siempre. En iPad o Android es `false`. |
| `activationState` | `activationState` | Siempre: `notActivated`, `inactive`, `activated`. |
| `paired` | `isPaired` | Solo si la session está `activated`. |
| `watchAppInstalled` | `isWatchAppInstalled` | Solo si está `activated`. En Simulator a veces miente. |
| `reachable` | `isReachable` | Solo si está `activated`. Hace falta para `sendMessage`. |

`label` resume el estado en una sola frase para la tarjeta de la UI.

---

## 2. Dart — `lib/services/watch_service.dart`

### `WatchService`

Única clase que los widgets pueden usar. Encapsula los platform channels. **Ningún widget llama a `MethodChannel` directo.**

Usa tres channels con el mismo prefijo:

| Channel | Tipo | Para qué |
|---|---|---|
| `com.example.flutter_watch/watch` | `MethodChannel` | Flutter pide algo y espera respuesta. |
| `com.example.flutter_watch/messages` | `EventChannel` | Swift empuja mensajes que llegan del Watch. |
| `com.example.flutter_watch/status` | `EventChannel` | Swift empuja cambios de `WCSession`. |

Por qué dos tipos: `MethodChannel` es pregunta/respuesta (`sendMessage`, `getStatus`). `EventChannel` es un `Stream`. Flutter oficial usa EventChannel para eventos nativos.

#### `sendMessage(String)`

1. Comprueba que estamos en iOS.
2. Llama `invokeMethod('sendMessageToWatch', { text: ... })`.
3. El mensaje cruza a Swift.
4. Si Swift falla, convierte `PlatformException` en `WatchCommunicationException`.

#### `getStatus()`

1. Llama `getWatchStatus` en Swift.
2. Recibe un `Map`.
3. Lo convierte a `WatchStatus`.
4. Fuera de iOS devuelve `WatchStatus.unsupported()`.

#### `isWatchReachable()`

Pregunta puntual: ¿puedo usar `sendMessage` ahora?

#### `messages` y `statusChanges`

Streams. `WatchDemoPage` se suscribe en `initState` y hace `setState` cuando llega un evento.

### `WatchCommunicationException` / `WatchUnavailableException`

Errores tipados. La UI muestra `error.message` en rojo.

---

## 3. Dart — `lib/main.dart`

### `main()`

Arranca Flutter y monta `FlutterWatchApp`.

### `FlutterWatchApp`

`MaterialApp`. Crea un `WatchService` y se lo pasa a `WatchDemoPage`. No conoce MethodChannel.

### `WatchDemoPage` / `_WatchDemoPageState`

Pantalla de la demo.

Estado que guarda:

- `_status` — snapshot de `WCSession`
- `_lastWatchMessage` — último texto que llegó del Watch
- `_error` — error al enviar
- `_sending` — el botón está ocupado

Paso a paso al abrir la pantalla:

1. `initState` pide `getStatus()`.
2. Se suscribe a `messages` y `statusChanges`.
3. Pinta la tarjeta de estado, el campo de texto y el botón.

Al pulsar **Send Message to Watch**:

1. Lee el `TextField`.
2. Llama `watchService.sendMessage(texto)`.
3. Si Swift responde error, lo muestra.
4. No pinta el mensaje en el Watch: eso lo hace SwiftUI al otro lado.

Cuando el Watch responde:

1. Swift emite el String por EventChannel.
2. `messages.listen` corre.
3. `setState` guarda `_lastWatchMessage`.
4. Aparece *Message received from Apple Watch*.

### `_StatusCard` / `_StatusLine`

Solo UI. Reciben un `WatchStatus` y lo dibujan. El refresh vuelve a llamar `getStatus()`.

---

## 4. Swift iOS — `ios/Runner/AppDelegate.swift`

### `AppDelegate`

Punto de entrada del proceso iPhone. Subclase de `FlutterAppDelegate`.

iOS 26 exige UIScene. Por eso también implementa `FlutterImplicitEngineDelegate`: el engine de Flutter ya no se inicializa como antes en `didFinishLaunching`.

Paso a paso al lanzar la app:

1. `application(_:didFinishLaunchingWithOptions:)` corre.
2. Activa `WatchConnectivityManager.shared` lo antes posible (eso es del proceso, no de la UI).
3. Cuando Flutter crea el engine implícito, llama `didInitializeImplicitFlutterEngine`.
4. Ahí se registran plugins y `FlutterWatchChannel`.

Importante: no uses `window?.rootViewController` aquí. Con UIScene la ventana vive en `FlutterSceneDelegate`.

---

## 5. Swift iOS — `ios/Runner/FlutterWatchChannel.swift`

### `FlutterWatchChannel`

Puente Flutter ↔ Swift. No habla con el Watch. Solo traduce channels a llamadas del manager.

Al registrar:

1. Crea el `FlutterMethodChannel` con el mismo nombre que Dart.
2. Crea dos `FlutterEventChannel` (mensajes y status).
3. Conecta callbacks del manager a los `eventSink`.

Cuando Dart llama un método:

| Método Dart | Qué hace Swift |
|---|---|
| `sendMessageToWatch` | Lee `{ text }` y llama `WatchConnectivityManager.sendMessage`. |
| `getWatchStatus` | Devuelve el mapa de `currentStatus()`. |
| `isWatchReachable` | Devuelve un `Bool`. |

Si el envío falla, responde `FlutterError` con un código (`notPaired`, `notActivated`, …). Dart lo convierte en excepción.

### `WatchEventStreamHandler`

Implementa `FlutterStreamHandler`.

- `onListen`: Flutter se suscribió. Guarda el `eventSink`.
- `onCancel`: hot restart o nadie escucha. Pone el sink en `nil`.

El sink de status, al escuchar, emite el estado actual de una vez para que la UI no empiece vacía.

Los callbacks de `WCSession` llegan en background. El manager ya saltó a main antes de tocar el sink.

---

## 6. Swift iOS — `ios/Runner/WatchConnectivityManager.swift`

### `WatchConnectivityManager` (iPhone)

Único dueño de `WCSession` en el iPhone. Singleton.

Flutter no importa WatchConnectivity. Esta clase sí.

#### Arranque

1. `activate()` comprueba `WCSession.isSupported()`.
2. Asigna `delegate = self`.
3. Llama `activate()` (asíncrono).
4. Cuando termina, llega `session(_:activationDidCompleteWith:error:)`.

#### Enviar a el Watch — `sendMessage(_:completion:)`

1. Exige session soportada, activada y paired.
2. Arma `{ "text": "...", "sentAt": timestamp }`.
3. Siempre llama `updateApplicationContext`. No pide `isReachable`. En Simulator es lo que suele funcionar.
4. Si `isReachable == true`, también llama `sendMessage` (inmediato, con reply).
5. Avisa a Flutter con `success` o un `WatchSendError`.

#### Recibir del Watch

Cualquier entrada (`didReceiveMessage` o `didReceiveApplicationContext`) pasa por `handleIncomingMessage`:

1. Saca la clave `text`.
2. Salta a main.
3. Llama `onMessageReceived`.
4. `FlutterWatchChannel` lo emite por EventChannel.

#### Delegate — por qué existe cada método

| Método | Obligatorio | Para qué |
|---|---|---|
| `activationDidCompleteWith` | Sí | La session ya se puede usar. |
| `sessionDidBecomeInactive` | Sí en iOS | El usuario cambió de Watch. |
| `sessionDidDeactivate` | Sí en iOS | Hay que volver a `activate()`. |
| `sessionReachabilityDidChange` | No | `isReachable` cambió. |
| `sessionWatchStateDidChange` | No | Pairing / app instalada. |
| `didReceiveMessage` | Si usas `sendMessage` | Mensaje inmediato sin reply. |
| `didReceiveMessage:replyHandler:` | Si el sender manda reply | Hay que llamar `replyHandler`. |
| `didReceiveApplicationContext` | Si usas context | Llegó el último estado. |

### `WatchSendError`

Errores que cruzan a Flutter como `FlutterError.code`.

---

## 7. Swift Watch — `ios/WatchApp/WatchApp.swift`

### `WatchApp`

`@main` de watchOS. Cero Flutter.

1. Crea (o reutiliza) `WatchConnectivityManager.shared` como `@StateObject`.
2. Eso activa `WCSession` en el Watch.
3. Inyecta el manager en `ContentView` con `environmentObject`.

---

## 8. Swift Watch — `ios/WatchApp/ContentView.swift`

### `ContentView`

Única pantalla del Watch.

Lee el manager publicado:

- `connectionLabel` — texto de conexión
- `lastMessage` — último texto de Flutter
- `sendError` — si falló el envío
- `isReachable` — color verde / naranja

Al pulsar **Send to iPhone** llama `connectivity.sendToiPhone()`. El texto por defecto es `Message received from Apple Watch`.

SwiftUI se redibuja solo porque el manager es `ObservableObject` y esas propiedades son `@Published`.

---

## 9. Swift Watch — `ios/WatchApp/WatchConnectivityManager.swift`

### `WatchConnectivityManager` (Watch)

Misma idea que en iPhone, otro proceso. También es `ObservableObject` para SwiftUI.

Diferencias respecto al iPhone:

- No tiene `isPaired` ni `isWatchAppInstalled`.
- Tiene `isCompanionAppInstalled` (¿está instalada la app del iPhone?).
- No implementa `sessionDidBecomeInactive` / `sessionDidDeactivate` (solo iOS, multi-watch).

Paso a paso al abrir el Watch:

1. El `init` llama `activate()`.
2. Cuando la session activa, actualiza `@Published`.
3. Si ya había un `receivedApplicationContext`, muestra ese texto (por si Flutter envió antes).

Al enviar al iPhone:

1. `updateApplicationContext` (funciona sin reachable).
2. Si el iPhone está reachable, también `sendMessage`.

Al recibir:

1. Delegate en background.
2. Salto a main.
3. `lastMessage = text`.
4. SwiftUI pinta el nuevo texto.

---

## 10. Qué pasa de verdad con un mensaje

### Flutter → Apple Watch

1. El usuario escribe y pulsa **Send Message to Watch**.
2. `WatchDemoPage` llama `WatchService.sendMessage`.
3. Dart envía `sendMessageToWatch` por MethodChannel.
4. `FlutterWatchChannel` extrae `text`.
5. `WatchConnectivityManager` (iPhone) comprueba la session.
6. Envía `{ text, sentAt }` con `updateApplicationContext` y, si puede, `sendMessage`.
7. watchOS entrega el diccionario al delegate del Watch.
8. El manager del Watch publica `lastMessage`.
9. `ContentView` muestra `"Hello from Flutter"`.

### Apple Watch → Flutter

1. El usuario pulsa **Send to iPhone**.
2. El Watch envía `{ text: "Message received from Apple Watch" }`.
3. El iPhone lo recibe en el delegate (background).
4. El manager salta a main y llama `onMessageReceived`.
5. `FlutterWatchChannel` emite el String por EventChannel.
6. `WatchService.messages` lo entrega al widget.
7. Flutter pinta el texto y la etiqueta *Message received from Apple Watch*.

Flutter nunca importa WatchConnectivity. El Watch nunca importa Dart. Swift en el iPhone es el único puente.

---

## 11. Cómo correrlo

```bash
flutter pub get
open FlutterConfLATAM2026.xcworkspace
```

1. Empareja iPhone Simulator + Watch Simulator (Devices and Simulators → Paired Apple Watch).
2. Scheme **Runner** + iPhone → Cmd+R.
3. Scheme **WatchApp** + el Watch emparejado → Cmd+R.
4. Las dos UIs visibles.
5. Envía en un sentido y en el otro.

`flutter run` no instala el Watch. Hay que correr el scheme **WatchApp**.

En Simulator, `isWatchAppInstalled` e `isReachable` suelen mentir. Por eso el envío usa también `updateApplicationContext`.
