import 'dart:convert';

import 'package:mockito/mockito.dart';
import 'package:parse_server_sdk/parse_server_sdk.dart';
import 'package:test/test.dart';

import '../../parse_query_test.mocks.dart';
import '../../test_utils.dart';

void main() {
  setUpAll(() async {
    await initializeParse();
  });

  tearDown(() {
    ParseCoreData().queryViaPost = false;
  });

  group('queryStringToPostBody', () {
    test('decodes each parameter like Parse Server does for a GET', () {
      final QueryBuilder<ParseObject> queryBuilder =
          QueryBuilder<ParseObject>.name('Diet_Plans')
            ..whereEqualTo('name', 'some+test=test')
            ..whereGreaterThan('fat', 10)
            ..setLimit(50)
            ..setAmountToSkip(5)
            ..orderByDescending('updatedAt')
            ..keysToReturn(<String>['name', 'fat']);

      final String query = Uri(query: queryBuilder.buildQuery()).query;
      final Map<String, dynamic> body = queryStringToPostBody(query);

      expect(body['where'], <String, dynamic>{
        'name': 'some+test=test',
        'fat': <String, dynamic>{r'$gt': 10},
      });
      expect(body['limit'], 50);
      expect(body['skip'], 5);
      expect(body['order'], '-updatedAt');
      expect(body['keys'], 'name,fat');
    });

    test('returns an empty body for an empty query string', () {
      expect(queryStringToPostBody(''), isEmpty);
    });
  });

  group('queryViaPost', () {
    late MockParseClient client;

    setUp(() {
      client = MockParseClient();
      when(
        client.get(
          any,
          options: anyNamed('options'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        ),
      ).thenAnswer(
        (_) async => ParseNetworkResponse(statusCode: 200, data: '{"results":[]}'),
      );
      when(
        client.post(any, data: anyNamed('data'), options: anyNamed('options')),
      ).thenAnswer(
        (_) async =>
            ParseNetworkResponse(statusCode: 200, data: '{"results":[]}'),
      );
    });

    QueryBuilder<ParseObject> buildQuery() =>
        QueryBuilder<ParseObject>(ParseObject('Diet_Plans', client: client))
          ..whereEqualTo('name', 'plan')
          ..setLimit(10);

    Map<String, dynamic> capturedPostBody() {
      final VerificationResult verification = verify(
        client.post(
          captureAny,
          data: captureAnyNamed('data'),
          options: anyNamed('options'),
        ),
      );
      expect(
        Uri.parse(verification.captured[0] as String).query,
        isEmpty,
        reason: 'the parameters must travel in the body, not in the URL',
      );
      return jsonDecode(verification.captured[1] as String);
    }

    test('defaults to GET', () async {
      await buildQuery().query();

      verify(
        client.get(
          any,
          options: anyNamed('options'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        ),
      ).called(1);
      verifyNever(
        client.post(any, data: anyNamed('data'), options: anyNamed('options')),
      );
    });

    test('global flag sends the query as POST with _method GET', () async {
      ParseCoreData().queryViaPost = true;

      await buildQuery().query();

      verifyNever(
        client.get(
          any,
          options: anyNamed('options'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        ),
      );
      final Map<String, dynamic> body = capturedPostBody();
      expect(body['_method'], 'GET');
      expect(body['where'], <String, dynamic>{'name': 'plan'});
      expect(body['limit'], 10);
    });

    test('query-level flag overrides the global flag', () async {
      ParseCoreData().queryViaPost = true;

      await (buildQuery()..queryViaPost = false).query();

      verify(
        client.get(
          any,
          options: anyNamed('options'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        ),
      ).called(1);
      verifyNever(
        client.post(any, data: anyNamed('data'), options: anyNamed('options')),
      );
    });

    test('query-level flag forces POST when the global flag is off', () async {
      await (buildQuery()..queryViaPost = true).query();

      expect(capturedPostBody()['_method'], 'GET');
    });

    test('count and a copied query keep the query-level flag', () async {
      final QueryBuilder<ParseObject> queryBuilder = buildQuery()
        ..queryViaPost = true;

      await queryBuilder.count();
      Map<String, dynamic> body = capturedPostBody();
      expect(body['count'], 1);
      expect(body['_method'], 'GET');

      await QueryBuilder<ParseObject>.copy(queryBuilder).query();
      body = capturedPostBody();
      expect(body['_method'], 'GET');
      expect(body['where'], <String, dynamic>{'name': 'plan'});
    });
  });
}
