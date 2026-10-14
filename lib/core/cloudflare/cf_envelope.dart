import 'cf_errors.dart';

/// Pagination block of a v4 list response.
class ResultInfo {
  const ResultInfo({this.page, this.totalPages, this.cursor});

  factory ResultInfo.fromJson(Map<String, dynamic> json) => ResultInfo(
        page: (json['page'] as num?)?.toInt(),
        totalPages: (json['total_pages'] as num?)?.toInt(),
        cursor: (json['cursor'] ?? json['cursors']?['after']) as String?,
      );

  final int? page;
  final int? totalPages;
  final String? cursor;

  bool get hasNextPage {
    if (cursor != null && cursor!.isNotEmpty) return true;
    if (page != null && totalPages != null) return page! < totalPages!;
    return false;
  }
}

/// Decoded Cloudflare v4 envelope: `{success, errors, messages, result, result_info}`.
class CfResponse {
  const CfResponse({required this.result, this.resultInfo, this.messages = const []});

  final Object? result;
  final ResultInfo? resultInfo;
  final List<String> messages;

  Map<String, dynamic> get map {
    final r = result;
    if (r is Map<String, dynamic>) return r;
    throw CfProtocolException('Expected an object result, got ${r.runtimeType}');
  }

  List<Map<String, dynamic>> get list {
    final r = result;
    if (r is List) return r.whereType<Map<String, dynamic>>().toList();
    if (r == null) return const [];
    throw CfProtocolException('Expected a list result, got ${r.runtimeType}');
  }

  static CfResponse parse(Object? body, int statusCode) {
    if (body is! Map<String, dynamic>) {
      if (statusCode >= 200 && statusCode < 300) {
        return CfResponse(result: body);
      }
      throw CfApiException(statusCode: statusCode, errors: const []);
    }
    final success = body['success'];
    final errors = (body['errors'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CfApiError.fromJson)
        .toList();
    if (success == false || statusCode >= 400) {
      if (statusCode == 401 || errors.any((e) => e.code == 1000 || e.code == 6003)) {
        throw const CfAuthException();
      }
      throw CfApiException(statusCode: statusCode, errors: errors);
    }
    final info = body['result_info'];
    return CfResponse(
      result: body.containsKey('result') ? body['result'] : body,
      resultInfo: info is Map<String, dynamic> ? ResultInfo.fromJson(info) : null,
      messages: (body['messages'] as List? ?? const [])
          .map((m) => m is Map ? '${m['message'] ?? ''}' : '$m')
          .where((m) => m.isNotEmpty)
          .toList(),
    );
  }
}
