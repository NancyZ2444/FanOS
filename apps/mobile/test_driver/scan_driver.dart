import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory('../../output/scan-ui-qa');
  await directory.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes, flush: true);
      return true;
    },
    responseDataCallback: (data) async {
      final report = <String, dynamic>{...?data}..remove('screenshots');
      await File('${directory.path}/native-result.json')
          .writeAsString(jsonEncode(report));
    },
    writeResponseOnFailure: true,
  );
}
