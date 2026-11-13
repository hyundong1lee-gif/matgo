import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/wallet.dart';
import 'net/nearby_transport.dart';
import 'ui/lobby_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Wallet.i.load();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(MatgoApp());
}

class MatgoApp extends StatelessWidget {
  MatgoApp({super.key}) : t = NearbyTransport();

  final NearbyTransport t;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '블루투스 맞고',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.green,
        useMaterial3: true,
      ),
      home: LobbyPage(t: t),
    );
  }
}
