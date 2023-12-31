import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

final class IsolateConfig {
  final int id;
  final int port;
  final SendPort sendPort;

  IsolateConfig({
    required this.id,
    required this.port,
    required this.sendPort,
  });
}

// Configure routes.
final _router = Router()..get('/echo', _echoHandler);

Future<Response> _echoHandler(Request request) async {
  final unixTime = DateTime.now().millisecondsSinceEpoch;

  if (request.url.queryParameters case {'delay': String delay}) {
    await Future.delayed(Duration(milliseconds: int.parse(delay)));
  }

  return Response.ok(jsonEncode({'data': unixTime}));
}

void main(List<String> args) async {
  final isolatesCount = args.isNotEmpty ? int.parse(args.first) : 1;
  // Start a server for each isolate.
  for (var i = 0; i < isolatesCount; i++) {
    final port = 8080;
    final receivePort = ReceivePort();

    Completer<SendPort> sendPort = Completer();

    final config = IsolateConfig(
      id: i,
      port: port,
      sendPort: receivePort.sendPort,
    );
    await Isolate.spawn(
      _startServer,
      config,
      errorsAreFatal: false,
    );

    receivePort.listen((message) {
      if (message is SendPort) {
        sendPort.complete(message);
      }
      if (message == 'Ready') {
        print('Isolate $i is ready');
      }
    });
  }
}

Future<void> _startServer(IsolateConfig config) async {
  final server = await serve(
    _router,
    InternetAddress.anyIPv4,
    config.port,
    shared: true,
    backlog: 120,
  );

  final receivePort = ReceivePort();

  config.sendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message == 'close') {
      server.close();
    }
  });

  config.sendPort.send('Ready');
}
