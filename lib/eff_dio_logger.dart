import 'dart:convert';
import 'dart:developer';

import 'package:dio/dio.dart';

class EffDioLogger implements Interceptor {
  /// Enable logPrint
  final bool enabled;

  /// Print compact json response
  final bool compact;

  /// Width size per logPrint
  /// limit data value (base64 image, ...) print maxLength
  final int? maxWidth;

  /// Log printer; defaults logPrint log to console.
  /// In flutter, you'd better use debugPrint.
  /// you can also write log in a file.
  final void Function(Object object) logPrint;

  EffDioLogger({
    this.compact = true,
    this.maxWidth = 324,
    void Function(Object object)? logPrint,
    this.enabled = true,
  }) : logPrint = (logPrint ?? (l) => log('$l', name: 'EffLogger'));

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!enabled) return handler.next(err);
    final js = genByJson(err.response?.data);
    logPrint(
      "ERR ${err.requestOptions.uri.path} <<<<<<<<<<<<<<< \n"
      "$js\n"
      "${err.stackTrace}\n",
    );
    return handler.next(err);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!enabled) return handler.next(options);
    logPrint(
      "REQ ${options.method}: ${options.uri} >>>>>>>>>>>>>>>>\n"
      "${options.data}\n",
    );
    return handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (!enabled) return handler.next(response);
    final js = genByJson(response.data);
    logPrint(
      "RSP ${response.requestOptions.uri.path} <<<<<<<<<<<<<<<\n"
      "$js\n",
    );
    return handler.next(response);
  }

  /// 返回json Str, 但是截取value的最大长度 [maxWidth]
  /// input 可能为 null
  String genByJson(dynamic input) {
    var data = __processValue(input);
    if (data is Map || data is List) {
      data = jsonEncode(data);
    }
    return '$data';
  }

  dynamic __processValue(dynamic value) {
    if (value is Map<String, dynamic>) {
      // 处理嵌套Map
      return {
        for (final entry in value.entries)
          entry.key: __processValue(entry.value),
      };
    } else if (value is List) {
      // 处理List
      return [
        for (final item in value) __processValue(item),
      ];
      // } else if (value is Uint8List) {
      //   // 处理图片
      //   return __processValue(value.toString());
    } else {
      // 其他类型toString
      // 处理字符串，限制长度
      value = '$value'.replaceAll('\n', '');
      return (compact && maxWidth != null && value.length > maxWidth)
          ? '${value.substring(0, maxWidth)}...'
          : value;
    }
  }
}
