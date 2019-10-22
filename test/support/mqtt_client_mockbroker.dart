import 'dart:async';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:path/path.dart' as path;
import 'package:typed_data/typed_data.dart' as typed;

typedef MessageHandlerFunction = void Function(typed.Uint8Buffer message);

/// Helper methods for test message serialization and deserialization
class MessageSerializationHelper {
  /// Invokes the serialization of a message to get an array of bytes that represent the message.
  static typed.Uint8Buffer getMessageBytes(MqttMessage msg) {
    final typed.Uint8Buffer buff = typed.Uint8Buffer();
    final MqttByteBuffer ms = MqttByteBuffer(buff);
    msg.writeTo(ms);
    ms.seek(0);
    final typed.Uint8Buffer msgBytes = ms.read(ms.length);
    return msgBytes;
  }
}

/// Mocks a broker, such as the RSMB, so that we can test the MqttConnection class, and some bits of the
/// connection handlers that are difficult to test otherwise. standard TCP connection.
class MockBroker {
  MockBroker();

  int brokerPort = 1883;
  ServerSocket listener;
  MessageHandlerFunction handler;
  Socket client;
  MqttByteBuffer networkstream;
  typed.Uint8Buffer headerBytes = typed.Uint8Buffer(1);

  FutureOr<dynamic> start() {
    final Completer<dynamic> completer = Completer<dynamic>();
    ServerSocket.bind('localhost', brokerPort, shared: true)
        .then((dynamic server) {
      listener = server;
      listener.listen(_connectAccept);
      print('MockBroker::we are bound');
      return completer.complete();
    });
    return completer.future;
  }

  void _connectAccept(Socket clientSocket) {
    print('MockBroker::connectAccept');
    client = clientSocket;
    client.listen(_dataArrivedOnConnection);
  }

  void _dataArrivedOnConnection(List<int> data) {
    print('MockBroker::data arrived ${data.toString()}');
    final typed.Uint8Buffer dataBytesBuff = typed.Uint8Buffer();
    dataBytesBuff.addAll(data);
    networkstream = MqttByteBuffer(dataBytesBuff);
    networkstream.seek(0);
    // Assume will have all the data for localhost testing purposes
    final MqttMessage msg = MqttMessage.createFrom(networkstream);
    print(msg.toString());
    if (handler != null) {
      handler(networkstream.buffer);
    }
    networkstream = null;
  }

  /// Sets a function that will be passed the next message received by the faked out broker.
  set setMessageHandler(MessageHandlerFunction messageHandler) =>
      handler = messageHandler;

  /// Sends the message to the client connected to the broker.
  void sendMessage(MqttMessage msg) {
    print('MockBroker::sending message ${msg.toString()}');
    final typed.Uint8Buffer messBuff =
        MessageSerializationHelper.getMessageBytes(msg);
    print('MockBroker::sending message bytes ${messBuff.toString()}');
    client.add(messBuff.toList());
  }

  /// Close the broker socket
  void close() {
    client?.destroy();
  }
}

/// Mocks a broker, such as the RSMB, so that we can test the MqttConnection class, and some bits of the
/// connection handlers that are difficult to test otherwise. websocket connection.
class MockBrokerWs {
  MockBrokerWs();

  int port = 8090;
  MessageHandlerFunction handler;
  MqttByteBuffer networkstream;
  typed.Uint8Buffer headerBytes = typed.Uint8Buffer(1);
  WebSocket _webSocket;

  void _handleMessage(dynamic data) {
    // Listen for incoming data.
    print('MockBrokerWs::data arrived ${data.toString()}');
    final typed.Uint8Buffer dataBytesBuff = typed.Uint8Buffer();
    dataBytesBuff.addAll(data);
    if (networkstream == null) {
      networkstream = MqttByteBuffer(dataBytesBuff);
    } else {
      networkstream.write(dataBytesBuff);
    }
    networkstream.seek(0);
    // Assume will have all the data for localhost testing purposes
    final MqttMessage msg = MqttMessage.createFrom(networkstream);
    print(msg.toString());
    handler(networkstream.buffer);
    networkstream = null;
  }

  Future<void> start() {
    final Completer<void> completer = Completer<void>();
    HttpServer.bind(InternetAddress.loopbackIPv4, port).then((dynamic server) {
      print(
          'Mockbroker WS server is running on http://${server.address.address}:$port/');
      server.listen((HttpRequest request) {
        if (request.uri.path == '/ws') {
          WebSocketTransformer.upgrade(request).then((WebSocket websocket) {
            _webSocket = websocket;
            websocket.listen(_handleMessage);
          });
        }
      });
      return completer.complete();
    });
    return completer.future;
  }

  /// Sets a function that will be passed the next message received by the faked out broker.
  set setMessageHandler(MessageHandlerFunction messageHandler) =>
      handler = messageHandler;

  /// Sends the message to the client connected to the broker.
  void sendMessage(MqttMessage msg) {
    print('MockBrokerWs::sending message ${msg.toString()}');
    final typed.Uint8Buffer messBuff =
        MessageSerializationHelper.getMessageBytes(msg);
    print('MockBrokerWS::sending message bytes ${messBuff.toString()}');
    _webSocket.add(messBuff.toList());
  }

  /// Close the broker socket
  void close() {
    _webSocket.close();
  }
}

/// Mocks a broker, such as the RSMB, so that we can test the MqttConnection class, and some bits of the
/// connection handlers that are difficult to test otherwise. standard TCP connection.
class MockBrokerSecure {
  MockBrokerSecure();

  int brokerPort = 8883;
  SecureServerSocket listener;
  MessageHandlerFunction handler;
  SecureSocket client;
  MqttByteBuffer networkstream;
  typed.Uint8Buffer headerBytes = typed.Uint8Buffer(1);
  String pemName;

  Future<void> start() {
    final Completer<void> completer = Completer<void>();
    final SecurityContext context = SecurityContext();
    final String currDir = path.current + path.separator;
    context.useCertificateChain(
        currDir + path.join('test', 'pem', '$pemName.cert'));
    context.usePrivateKey(currDir + path.join('test', 'pem', '$pemName.key'));
    SecureServerSocket.bind('localhost', brokerPort, context)
        .then((SecureServerSocket server) {
      listener = server;
      listener.listen(_connectAccept);
      print('MockBrokerSecure::we are bound');
      return completer.complete();
    });
    return completer.future;
  }

  void _connectAccept(SecureSocket clientSocket) {
    print('MockBrokerSecure::connectAccept');
    client = clientSocket;
    client.listen(_dataArrivedOnConnection);
  }

  void _dataArrivedOnConnection(List<int> data) {
    print('MockBrokerSecure::data arrived ${data.toString()}');
    final typed.Uint8Buffer dataBytesBuff = typed.Uint8Buffer();
    dataBytesBuff.addAll(data);
    if (networkstream == null) {
      networkstream = MqttByteBuffer(dataBytesBuff);
    } else {
      networkstream.write(dataBytesBuff);
    }
    networkstream.seek(0);
    // Assume will have all the data for localhost testing purposes
    final MqttMessage msg = MqttMessage.createFrom(networkstream);
    print(msg.toString());
    handler(networkstream.buffer);
    networkstream = null;
  }

  /// Sets a function that will be passed the next message received by the faked out broker.
  set setMessageHandler(MessageHandlerFunction messageHandler) =>
      handler = messageHandler;

  /// Sends the message to the client connected to the broker.
  void sendMessage(MqttMessage msg) {
    print('MockBrokerSecure::sending message ${msg.toString()}');
    final typed.Uint8Buffer messBuff =
        MessageSerializationHelper.getMessageBytes(msg);
    print('MockBrokerSecure::sending message bytes ${messBuff.toString()}');
    client.add(messBuff.toList());
  }

  /// Close the broker socket
  void close() {
    listener?.close();
  }
}
