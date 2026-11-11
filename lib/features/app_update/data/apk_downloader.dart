import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/app_release.dart';

/// Lets a download be stopped from the outside.
class CancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void onCancel(void Function() listener) => _listeners.add(listener);
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

/// The file did not match the SHA-256 that GitHub published for it.
class ChecksumMismatch implements Exception {
  const ChecksumMismatch();
}

class DownloadFailed implements Exception {
  const DownloadFailed(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Downloads an APK into the app's own storage and checks it.
abstract class ApkDownloader {
  /// [onProgress] gets the bytes received and the total (0 when unknown).
  /// [onVerifying] is called once the bytes are in, before the checksum.
  Future<File> download(
    ReleaseApk apk, {
    required void Function(int received, int total) onProgress,
    required void Function() onVerifying,
    required CancelToken cancel,
  });

  /// Removes downloaded updates, to free the space once installed or
  /// abandoned.
  Future<void> clear();
}

class HttpApkDownloader implements ApkDownloader {
  HttpApkDownloader({
    Future<Directory> Function()? directory,
    HttpClient Function()? client,
  }) : _directory = directory ?? _defaultDirectory,
       _client = client ?? HttpClient.new;

  final Future<Directory> Function() _directory;
  final HttpClient Function() _client;

  static Future<Directory> _defaultDirectory() async {
    final base = await getTemporaryDirectory();
    return Directory('${base.path}${Platform.pathSeparator}updates')
        .create(recursive: true);
  }

  @override
  Future<File> download(
    ReleaseApk apk, {
    required void Function(int received, int total) onProgress,
    required void Function() onVerifying,
    required CancelToken cancel,
  }) async {
    if (!apk.isTrusted) {
      throw const DownloadFailed(
        'This file is not from the app\'s own releases.',
      );
    }
    final dir = await _directory();
    final target = File('${dir.path}${Platform.pathSeparator}${apk.name}');

    // Already downloaded and intact: no need to fetch it again.
    if (await target.exists() &&
        await target.length() == apk.size &&
        apk.size > 0) {
      onProgress(apk.size, apk.size);
      onVerifying();
      if (apk.sha256 == null || await _hashOf(target) == apk.sha256) {
        return target;
      }
      await target.delete();
    }

    final part = File('${target.path}.part');
    final client = _client()..connectionTimeout = const Duration(seconds: 15);
    cancel.onCancel(() => client.close(force: true));
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(apk.url));
      request.headers.set(HttpHeaders.userAgentHeader, 'BU-Bus-Tracker-app');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw DownloadFailed('The server answered ${response.statusCode}.');
      }
      final total = response.contentLength > 0
          ? response.contentLength
          : apk.size;
      sink = part.openWrite();
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      var received = 0;
      onProgress(0, total);
      await for (final chunk in response) {
        if (cancel.isCancelled) throw const DownloadCancelled();
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.close();
      sink = null;
      hasher.close();
      if (cancel.isCancelled) throw const DownloadCancelled();

      onVerifying();
      if (apk.size > 0 && received != apk.size) {
        throw const DownloadFailed(
          'The download ended early. Please try again.',
        );
      }
      if (apk.sha256 != null && digestSink.value.toString() != apk.sha256) {
        throw const ChecksumMismatch();
      }
      if (await target.exists()) await target.delete();
      return await part.rename(target.path);
    } on DownloadCancelled {
      rethrow;
    } on ChecksumMismatch {
      rethrow;
    } on DownloadFailed {
      rethrow;
    } catch (error) {
      if (cancel.isCancelled) throw const DownloadCancelled();
      throw DownloadFailed(_friendly(error));
    } finally {
      await sink?.close();
      client.close(force: true);
      // A finished download has been renamed away; anything left is partial.
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {}
      }
    }
  }

  @override
  Future<void> clear() async {
    try {
      final dir = await _directory();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  static Future<String> _hashOf(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static String _friendly(Object error) {
    if (error is SocketException || error is HandshakeException) {
      return 'No connection to the download server. Check your internet and try again.';
    }
    if (error is FileSystemException) {
      return 'There is not enough free space on this phone for the update.';
    }
    if (error is TimeoutException) {
      return 'The download stopped responding. Please try again.';
    }
    return 'The download did not finish. Please try again.';
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? _value;
  Digest get value => _value!;
  @override
  void add(Digest data) => _value = data;
  @override
  void close() {}
}
