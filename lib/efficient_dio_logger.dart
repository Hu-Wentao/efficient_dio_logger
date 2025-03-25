library efficient_dio_logger;

import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:dio/dio.dart';

const _timeStampKey = '_pdl_timeStamp_';

class EfficientDioLogger extends Interceptor {
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

  /// Print compact json response
  final bool compact;

  /// Width size per logPrint
  final int maxWidth;

  /// Size in which the Uint8List will be split
  static const int chunkSize = 20;

  /// Log printer; defaults logPrint log to console.
  /// In flutter, you'd better use debugPrint.
  /// you can also write log in a file.
  final void Function(Object object) logPrint;

  /// Filter request/response by [RequestOptions]
  final bool Function(RequestOptions options, FilterArgs args)? filter;

  /// Enable logPrint
  final bool enabled;

  /// Determine the width of the dividing line [_printLine]
  /// 决定分割线的宽度 [_printLine]
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
    this.maxWidth = 324,

    /// Whether to truncate large text
    /// 是否截断大文本
    this.compact = true,

    /// logPrint: (l) => log('$l', name: 'EfficientDioLogger'),
    this.logPrint = print,

    /// enabled: kDebugMode,
    this.enabled = true,
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

    final triggerTime = err.requestOptions.extra[_timeStampKey];

    if (error) {
      if (err.type == DioExceptionType.badResponse) {
        final uri = err.response?.requestOptions.uri;
        int diff = 0;
        if (triggerTime is int) {
          diff = DateTime.timestamp().millisecondsSinceEpoch - triggerTime;
        }
        _printBoxed(
          header:
              'DioError ║ Status: ${err.response?.statusCode} ${err.response?.statusMessage} ║ Time: $diff ms',
          text: uri.toString(),
        );
        if (err.response != null && err.response?.data != null) {
          logPrint('╔ ${err.type.toString()}');
          _printResponse(err.response!);
        }
        _printLine('╚');
      } else {
        _printBoxed(
          header:
              'DioError ║ Status: ${err.response?.statusCode} ║ ${err.type}',
          text: '${err.requestOptions.uri}\n'
              '${err.message}',
        );
      }
    }
    handler.next(err);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final extra = Map.of(options.extra);
    options.extra[_timeStampKey] = DateTime.timestamp().millisecondsSinceEpoch;

    if (!enabled ||
        (filter != null &&
            !filter!(options, FilterArgs(false, options.data)))) {
      handler.next(options);
      return;
    }

    if (request) {
      _printRequestHeader(options);
    }
    if (requestHeader) {
      _printMapAsTable(options.queryParameters, header: 'Query Parameters');
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
      _printMapAsTable(requestHeaders, header: 'Headers', printEnd: false);
      _printMapAsTable(extra, header: 'Extras', printEnd: false);
    }
    if (requestBody && options.method != 'GET') {
      final dynamic data = options.data;
      if (data != null) {
        if (data is Map) {
          _printMapAsTable(options.data as Map?, header: 'Body');
        } else if (data is FormData) {
          final formDataMap = <String, dynamic>{}
            ..addEntries(data.fields)
            ..addEntries(data.files);
          _printMapAsTable(formDataMap, header: 'Form data | ${data.boundary}');
        } else {
          _printJson(data);
        }
      }
    }
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

    final triggerTime = response.requestOptions.extra[_timeStampKey];

    int diff = 0;
    if (triggerTime is int) {
      diff = DateTime.timestamp().millisecondsSinceEpoch - triggerTime;
    }
    _printResponseHeader(response, diff);
    if (responseHeader) {
      final responseHeaders = <String, String>{};
      response.headers
          .forEach((k, list) => responseHeaders[k] = list.toString());
      _printMapAsTable(responseHeaders, header: 'Headers');
    }

    if (responseBody) {
      logPrint('╔ Body');
      _printResponse(response);
      _printLine('╚');
    }
    handler.next(response);
  }

  void _printResponse(Response response) {
    if (response.data != null) {
      _printJson(response.data);
    }
  }

  dynamic __processValue(dynamic value) {
    if (value is String) {
      // 处理字符串，限制长度
      value = value.replaceAll('\n', '');
      return (compact && value.length > maxWidth)
          ? '${value.substring(0, maxWidth)}...'
          : value;
    } else if (value is Map<String, dynamic>) {
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
    } else if (value is Uint8List) {
      // 处理图片
      return __processValue(value.toString());
    }
    // 其他类型保持不变
    return value;
  }

  /// 打印json,但是截取value的最大长度 [maxWidth]
  void _printJson(dynamic input) {
    var data = __processValue(input);
    if (data is Map || data is List) {
      data = jsonEncode(data);
    }
    logPrint(data);
  }

  /// 改写为一行打印
  void _printMapAsTable(Map? map, {String? header, printEnd = true}) {
    if (map == null || map.isEmpty) return;
    logPrint('╔ $header ');
    _printJson(map);
    if (printEnd) _printLine('╚');
  }

  void _printResponseHeader(Response response, int responseTime) {
    final uri = response.requestOptions.uri;
    final method = response.requestOptions.method;
    _printBoxed(
      header:
          'Response ║ $method ║ Status: ${response.statusCode} ${response.statusMessage}  ║ Time: $responseTime ms ${EfficientDioLogger.tabStep}'
              .padRight(lineWidth ~/ 3 * 2, '<'),
      text: uri.toString(),
      printEnd: !responseBody,
    );
  }

  void _printRequestHeader(RequestOptions options) {
    final uri = options.uri;
    final method = options.method;
    _printBoxed(
      header: 'Request ║ $method ${EfficientDioLogger.tabStep}'
          .padRight(lineWidth ~/ 3 * 2, '>'),
      text: uri.toString(),
      printEnd: !requestHeader,
    );
  }

  /// printEnd: 如果打印rsp同时又打印rspBody, 那么rsp无需 printEnd 分割线
  void _printBoxed({String? header, String? text, bool printEnd = true}) {
    logPrint('╔╣ $header');
    logPrint('║  $text');
    if (printEnd) _printLine('╚');
  }

  void _printLine([String pre = '', String suf = '╝']) =>
      logPrint('$pre${'═' * (lineWidth - 2)}$suf');
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
