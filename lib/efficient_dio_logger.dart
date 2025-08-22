library efficient_dio_logger;

import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:efficient_dio_logger/eff_dio_logger.dart';
export 'eff_dio_logger.dart';

const _timeStampKey = '_pdl_timeStamp_';

class EfficientDioLogger extends EffDioLogger {
  /// Print request [Options]
  final bool request;

  /// Print request header [Options.headers]
  final bool requestHeader;

  /// Print request data [Options.data]
  final bool requestBody;

  /// Print [Response.data]
  final bool responseBody;

  /// Print [Response.headers]
  final bool responseHeader;

  /// Print error message
  final bool error;

  /// InitialTab count to logPrint json response
  static const int kInitialTab = 1;

  /// 1 tab length
  static const String tabStep = '    ';

  /// Size in which the Uint8List will be split
  static const int chunkSize = 20;

  /// Filter request/response by [RequestOptions]
  final bool Function(RequestOptions options, FilterArgs args)? filter;

  /// Determine the width of the dividing line [printLine]
  /// 决定分割线的宽度 [printLine]
  final int lineWidth;

  factory EfficientDioLogger({
    bool request = true,
    bool requestHeader = false,
    bool requestBody = false,
    bool responseHeader = false,
    bool responseBody = true,
    bool error = true,
    bool Function(RequestOptions options, FilterArgs args)? filter,
    int lineWidth = 162,
    int maxWidth = 324,
    bool compact = true,
    void Function(Object object)? logPrint,
    bool enabled = true, // enabled: kDebugMode,
  }) =>
      EfficientDioLogger.of(
        request: request,
        requestHeader: requestHeader,
        requestBody: requestBody,
        responseHeader: responseHeader,
        responseBody: responseBody,
        error: error,
        filter: filter,
        lineWidth: lineWidth,
        maxWidth: maxWidth,
        compact: compact,
        logPrint: logPrint ?? (l) => log('$l', name: 'EffLogger'),
        enabled: enabled,
      );

  EfficientDioLogger.of({
    this.request = true,
    this.requestHeader = true,
    this.requestBody = true,
    this.responseHeader = false,
    this.responseBody = true,
    this.error = true,
    this.filter,

    /// Generally set to be less than or equal to the console width, or the width of the console - (log.name.length (if any) + 2)
    /// 一般设为小于等于console宽度,或 console的宽度 - (log.name.length(如果有的话)+2)
    this.lineWidth = 162,

    /// The maximum length of a single string. If it exceeds the maximum length, it will be truncated. It is used to truncate the overlong text value of JSON. It is usually set to twice [lineWidth].
    /// 单个string最大长度,超过将被截断; 用于截断json的超长文本value;一般设为[lineWidth]的2倍
    super.maxWidth = 324,

    /// Whether to truncate large text
    /// 是否截断大文本
    super.compact = true,

    /// logPrint: (l) => log('$l', name: 'EfficientDioLogger'),
    super.logPrint = print,

    /// enabled: kDebugMode,
    super.enabled = true,
  });

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!enabled ||
        (filter != null &&
            !filter!(
                err.requestOptions, FilterArgs(true, err.response?.data)))) {
      handler.next(err);
      return;
    }
    final logBuff = StringBuffer();

    final triggerTime = err.requestOptions.extra[_timeStampKey];

    if (error) {
      int diff = 0;
      final now = DateTime.timestamp();
      if (triggerTime is int) {
        diff = now.millisecondsSinceEpoch - triggerTime;
      }
      if (err.type == DioExceptionType.badResponse) {
        final uri = err.response?.requestOptions.uri;
        logBuff.write(printBoxed(
          header:
              '❌ Dio.BadResponse ║ Status: ${err.response?.statusCode} ${err.response?.statusMessage} ║ Time: $now | $diff ms',
          text: '\t $uri\n'
              '${err.message}\n'
              '${err.stackTrace}\n',
          buffOnly: true,
        ));
        if (err.response != null && err.response?.data != null) {
          logBuff.write(StringBuffer(
            '\t ╔ ${err.type.toString()} \n'
            '${genByJson(err.response?.data)}\n',
          ));
        }
      } else {
        logBuff.write(printBoxed(
          header:
              '❌ DioError ║ Status: ${err.response?.statusCode} ║ ${err.type} ║ Time: $now | $diff ms',
          text: '\t ${err.requestOptions.uri}\n'
              '${err.message}\n'
              '${err.error}\n' // 用户可能通过拦截器处理并包装Error,此处调用包装后的Error.toString
              'data: ${genByJson(err.response?.data)}\n'
              '${err.stackTrace}\n',
          buffOnly: true,
        ));
      }
    }
    logPrint(logBuff.toString());
    handler.next(err);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    StringBuffer logCache = StringBuffer();
    final extra = Map.of(options.extra);
    options.extra[_timeStampKey] = DateTime.timestamp().millisecondsSinceEpoch;

    if (!enabled ||
        (filter != null &&
            !filter!(options, FilterArgs(false, options.data)))) {
      handler.next(options);
      return;
    }

    if (request) {
      logCache.write(printRequestHeader(options, buffOnly: true));
    }
    if (requestHeader) {
      logCache.write(
        printMapAsTable(options.queryParameters,
            header: 'Query Parameters', buffOnly: true),
      );
      final requestHeaders = <String, dynamic>{};
      requestHeaders.addAll(options.headers);
      if (options.contentType != null) {
        requestHeaders['contentType'] = options.contentType?.toString();
      }
      requestHeaders['responseType'] = options.responseType.toString();
      requestHeaders['followRedirects'] = options.followRedirects;
      if (options.connectTimeout != null) {
        requestHeaders['connectTimeout'] = options.connectTimeout?.toString();
      }
      if (options.receiveTimeout != null) {
        requestHeaders['receiveTimeout'] = options.receiveTimeout?.toString();
      }
      logCache.writeAll([
        printMapAsTable(requestHeaders,
            header: 'Headers', printEnd: false, buffOnly: true),
        printMapAsTable(extra,
            header: 'Extras', printEnd: false, buffOnly: true)
      ].where((_) => _ != null));
    }
    if (requestBody && options.method != 'GET') {
      final dynamic data = options.data;
      if (data != null) {
        if (data is Map) {
          logCache.write(printMapAsTable(
            options.data as Map?,
            header: 'Body',
            buffOnly: true,
          ));
        } else if (data is FormData) {
          final formDataMap = <String, dynamic>{}
            ..addEntries(data.fields)
            ..addEntries(data.files);
          logCache.write(printMapAsTable(
            formDataMap,
            header: 'Form data | ${data.boundary}',
          ));
        } else {
          final buff = StringBuffer(genByJson(data));
          logCache.write(buff);
        }
      }
    }
    // 一次性打印
    logPrint(logCache.toString());
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (!enabled ||
        (filter != null &&
            !filter!(
                response.requestOptions, FilterArgs(true, response.data)))) {
      handler.next(response);
      return;
    }

    final buff = StringBuffer();
    final triggerTime = response.requestOptions.extra[_timeStampKey];

    int diff = 0;
    if (triggerTime is int) {
      diff = DateTime.timestamp().millisecondsSinceEpoch - triggerTime;
    }
    buff.write(printResponseHeader(response, diff, buffOnly: true));
    if (responseHeader) {
      final responseHeaders = <String, String>{};
      response.headers
          .forEach((k, list) => responseHeaders[k] = list.toString());
      buff.write(
          printMapAsTable(responseHeaders, header: 'Headers', buffOnly: true));
    }

    if (responseBody) {
      buff.write(StringBuffer(
        '\t ╔ Body \n'
        '${genByJson(response.data)}\n'
        '${genLine('\t ╚')}',
      ));
    }

    logPrint(buff.toString());
    handler.next(response);
  }

  // dynamic __processValue(dynamic value) {
  //   if (value is Map<String, dynamic>) {
  //     // 处理嵌套Map
  //     return {
  //       for (final entry in value.entries)
  //         entry.key: __processValue(entry.value),
  //     };
  //   } else if (value is List) {
  //     // 处理List
  //     return [
  //       for (final item in value) __processValue(item),
  //     ];
  //     // } else if (value is Uint8List) {
  //     //   // 处理图片
  //     //   return __processValue(value.toString());
  //   } else {
  //     // 其他类型toString
  //     // 处理字符串，限制长度
  //     value = '$value'.replaceAll('\n', '');
  //     return (compact && value.length > maxWidth)
  //         ? '${value.substring(0, maxWidth)}...'
  //         : value;
  //   }
  // }

  // /// 返回json Str, 但是截取value的最大长度 [maxWidth]
  // /// input 可能为 null
  // String genByJson(dynamic input) {
  //   var data = __processValue(input);
  //   if (data is Map || data is List) {
  //     data = jsonEncode(data);
  //   }
  //   return '$data';
  // }

  /// 改写为一行打印
  StringBuffer? printMapAsTable(
    Map? map, {
    String? header,
    printEnd = false,
    bool buffOnly = false,
  }) {
    if (map == null || map.isEmpty) return StringBuffer();
    final buff = StringBuffer(
      '\t ╔ $header \n'
      '${genByJson(map)}\n'
      '${printEnd ? genLine('\t ╚') : ''}',
    );
    if (!buffOnly) logPrint(buff);
    return buffOnly ? buff : null;
  }

  StringBuffer? printResponseHeader(Response response, int responseTime,
      {bool buffOnly = false}) {
    final uri = response.requestOptions.uri;
    final method = response.requestOptions.method;
    final rspEmoji = {
          2: '🟢', // 2xx: 200
          3: '↪️', // 3xx: redirect ...
          4: '❓', // 4xx: 403, 404 ...
          5: '❗', // 5xx:
        }[(response.statusCode ?? 200) % 100] ??
        '✔️';
    return printBoxed(
      header:
          '$rspEmoji Response ║ $method ║ Status: ${response.statusCode} ${response.statusMessage}  ║ Time: ${DateTime.now()} | $responseTime ms ${EfficientDioLogger.tabStep}'
              .padRight(lineWidth ~/ 3 * 2, '<'),
      text: '\t $uri',
      printEnd: !responseBody,
      buffOnly: buffOnly,
    );
  }

  StringBuffer? printRequestHeader(RequestOptions options,
      {bool buffOnly = false}) {
    final uri = options.uri;
    final method = options.method;
    final now = DateTime.now();
    return printBoxed(
      header: '➡️ Request ║ $method ${EfficientDioLogger.tabStep} ║ Time: $now '
          .padRight(lineWidth ~/ 3 * 2, '>'),
      text: '\t $uri',
      printEnd: !requestHeader,
      buffOnly: buffOnly,
    );
  }

  /// printEnd: 如果打印rsp同时又打印rspBody, 那么rsp无需 printEnd 分割线
  StringBuffer? printBoxed(
      {String? header,
      String? text,
      bool printEnd = false,
      bool buffOnly = false}) {
    final buff = StringBuffer('╔╣ $header \n'
        '$text \n'
        '${printEnd ? genLine('\t ╚') : ''}');
    if (!buffOnly) logPrint(buff);
    return buffOnly ? buff : null;
  }

  String genLine([String pre = '', String suf = '╝']) =>
      '$pre${'═' * (lineWidth - pre.length - suf.length)}$suf';

  void printLine([String pre = '', String suf = '╝']) =>
      logPrint(genLine(pre, suf));
}

/// Filter arguments
class FilterArgs {
  /// If the filter is for a request or response
  final bool isResponse;

  /// if the [isResponse] is false, the data is the [RequestOptions.data]
  /// if the [isResponse] is true, the data is the [Response.data]
  final dynamic data;

  /// Returns true if the data is a string
  bool get hasStringData => data is String;

  /// Returns true if the data is a map
  bool get hasMapData => data is Map;

  /// Returns true if the data is a list
  bool get hasListData => data is List;

  /// Returns true if the data is a Uint8List
  bool get hasUint8ListData => data is Uint8List;

  /// Returns true if the data is a json data
  bool get hasJsonData => hasMapData || hasListData;

  /// Default constructor
  const FilterArgs(this.isResponse, this.data);
}
