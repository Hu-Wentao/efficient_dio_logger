import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:efficient_dio_logger/efficient_dio_logger.dart';

main() {
  Dio dio = Dio();
  dio.interceptors.add(EfficientDioLogger());

  // or customization:
  dio.interceptors.add(EfficientDioLogger(
    request: true,
    requestHeader: true,
    requestBody: true,
    responseHeader: false,
    responseBody: true,
    error: true,
    // set your console width
    lineWidth: 160,
    // set max content text length (Recommended use lineWidth*2)
    maxWidth: 320,
    // if true, value that has more than maxWidth(=320) characters will be truncated
    compact: true,
    // or use `print()`, may cause the log to be incomplete.
    logPrint: (l) => log('$l', name: 'EffLogger'),
    // or use `kDebugMode` (recommend)
    enabled: true,
    filter: (options, args) {
      // don't print requests with uris containing '/posts'
      if (options.path.contains('/posts')) {
        return false;
      }
      // don't print responses with unit8 list data
      // else, if compact=true, Uint8 list will be printed as 'Uint8List(length: maxWidth)'
      if (args.isResponse && args.hasUint8ListData) {
        return false;
      }
      return true;
    },
  ));
}
