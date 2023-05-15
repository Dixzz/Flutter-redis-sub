import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:redis/redis.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Redis Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Redis Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;
  final AndroidNotificationDetails androidNotificationDetails =
      const AndroidNotificationDetails('12210', 'defChannel',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker');

  final AndroidNotificationDetails androidOnGoingNotificationDetails =
      const AndroidNotificationDetails('12211', 'defOnGoing',
          priority: Priority.min,
          playSound: false,
          enableLights: false,
          autoCancel: false,
          enableVibration: false,
          ongoing: true);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var listening = false;
  RedisConnection? _conn;

  final InitializationSettings initializationSettings =
      const InitializationSettings(
          android: AndroidInitializationSettings('launch_background'),
          iOS: DarwinInitializationSettings());
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  StreamSubscription? subs;

  @override
  void dispose() {
    super.dispose();
    _closeConn();
  }

  void _closeConn() {
    log('Closing all');
    _conn?.close();
    subs?.cancel();
    subs = null;
    _conn = null;
    flutterLocalNotificationsPlugin.cancel(defListenerNotId);
    setState(() {
      listening = false;
    });
  }

  late final NotificationDetails notificationDetails =
      NotificationDetails(android: widget.androidNotificationDetails);
  late final NotificationDetails notificationOnGoingDetails =
      NotificationDetails(android: widget.androidOnGoingNotificationDetails);
  late final rnd = math.Random();

  static void launch(String? content) {
    if (content == null || content.isEmpty) return;

    log('Cont $content');
    Future(() async {
      final Map<String, dynamic> body = jsonDecode(content) ?? {};
      final contentBody = body['content'];
      final contentType = body['type'];
      if (contentType == 'selection') {
        Clipboard.setData(ClipboardData(text: contentBody));
        Fluttertoast.showToast(msg: 'Copied');
      } else if (contentType == 'page') {
        final u = Uri.parse(contentBody);
        if (await canLaunchUrl(u)) {
          launchUrl(u, mode: LaunchMode.externalApplication);
        } else {
          log('Could not launch $u');
        }
      } else if (contentType == 'image') {
        final Directory tempDir = await getTemporaryDirectory();
        final tt = File("${tempDir.path}/temp.jpg");
        if (!tt.existsSync()) {
          tt.createSync();
        }
        tt.writeAsBytesSync(base64Decode(contentBody));
        OpenFilex.open(tt.path);
      }
    });
  }

  @pragma('vm:entry-point')
  static notificationTapBackground(NotificationResponse notificationResponse) {
    launch(notificationResponse.payload);
  }

  final defListenerNotId = 10111;

  @override
  void initState() {
    super.initState();

    // WidgetsBinding.instance.addObserver(this);
    Future(() async {
      if (Platform.isAndroid) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestPermission();
      } else if (Platform.isIOS) {
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions();
      }

      await flutterLocalNotificationsPlugin.initialize(initializationSettings,
          onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
          onDidReceiveNotificationResponse: notificationTapBackground);
    });
  }

  Future<void> beginRedisConn() async {
    _closeConn();
    _conn ??= RedisConnection();
    final command = await _conn!.connectSecure(
        dotenv.env['host'], int.parse(dotenv.env['port']!));
    await command
        .send_object(["AUTH", dotenv.env['username'], dotenv.env['password']]);
    final pubSub = PubSub(command);
    pubSub.subscribe([dotenv.env['defChannel']!]);

    await flutterLocalNotificationsPlugin.show(
        defListenerNotId, 'Listening events', null, notificationOnGoingDetails);

    subs = pubSub.getStream().listen(
        (event) async {
          log('Gawd $event');
          if (subs?.isPaused == true) return;
          final type = event[0];
          if (type == 'subscribe') {
            setState(() {
              listening = true;
            });
          } else if (type == 'message') {
            final content = event[2];
            await flutterLocalNotificationsPlugin.show(rnd.nextInt(1000),
                'plain title', 'Click to view!', notificationDetails,
                payload: content);
          }
        },
        cancelOnError: true,
        onDone: _closeConn,
        onError: (_, s) {
          log('Cr Error $s');
          _closeConn();
        });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
        appBar: AppBar(
          // Here we take the value from the MyHomePage object that was created by
          // the App.build method, and use it to set our appbar title.
          title: Text(widget.title),
        ),
        body: Center(
          child: Wrap(direction: Axis.vertical,crossAxisAlignment: WrapCrossAlignment.center,spacing: 8,children: [
            Text(listening ? 'Listening for events' : 'Click to start'),
            ElevatedButton(onPressed: !listening ? beginRedisConn : _closeConn, child: Text(!listening ? 'Start' : 'Stop'))
          ],),
        ));
  }
}
