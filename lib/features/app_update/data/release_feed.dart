import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/app_release.dart';

/// Where the list of releases comes from.
abstract class ReleaseFeed {
  Future<List<AppRelease>> fetch();
}

/// Reads the website's copy of the release list first, then GitHub's API if
/// that fails or is empty. Throws [ReleaseFeedException] when neither can be
/// read.
class GithubReleaseFeed implements ReleaseFeed {
  GithubReleaseFeed({HttpClient Function()? client})
    : _client = client ?? HttpClient.new;

  final HttpClient Function() _client;

  @override
  Future<List<AppRelease>> fetch() async {
    Object? lastError;
    for (final url in [UpdateSource.siteFeed, UpdateSource.apiFeed]) {
      try {
        final releases = parseReleases(await _getJson(url));
        if (releases.isNotEmpty) return releases;
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) throw ReleaseFeedException('$lastError');
    return const [];
  }

  Future<Object?> _getJson(String url) async {
    final client = _client()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'BU-Bus-Tracker-app')
        // The website's copy changes every few hours; never use a stale one.
        ..set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      return jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }
}

class ReleaseFeedException implements Exception {
  const ReleaseFeedException(this.message);
  final String message;
  @override
  String toString() => 'ReleaseFeedException: $message';
}
