import 'package:dio/dio.dart';

HttpClientAdapter createHttpClientAdapter(dynamic securityContext) {
  final HttpClientAdapter browserHttpClientAdapter = HttpClientAdapter();
  return browserHttpClientAdapter;
}
