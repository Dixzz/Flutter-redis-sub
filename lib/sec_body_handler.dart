import 'package:basic_utils/basic_utils.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

late Encrypter _dec;

Future<void> initEncrption() async {
  var m =
      (await rootBundle.load(dotenv.get('keystore'))).buffer.asUint8List();

  final pk = Pkcs12Utils.parsePkcs12(m, password: "P@ssw0rd");
  String pem = pk[0];
  _dec = Encrypter(RSA(
      privateKey: RSAKeyParser().parse(pem) as RSAPrivateKey, publicKey: null));
}

String decrypt(String response) {
  final pair = response.split("@!");
  final key =
      Key.fromBase64(_dec.decrypt64(pair[0], iv: IV.fromBase64(pair[2])));
  final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
  final body = encrypter.decrypt64(pair[1], iv: IV.fromBase64(pair[2]));
  return body;
}
