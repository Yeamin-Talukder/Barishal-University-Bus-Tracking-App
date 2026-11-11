/// Releases of the app as published on GitHub, and the rules for choosing
/// the update a phone should get.
library;

/// Where the app's releases live. Downloads are accepted only from here.
abstract final class UpdateSource {
  static const String owner = 'Yeamin-Talukder';
  static const String repo = 'Barishal-University-Bus-Tracking-App';

  /// A copy of the release list kept by the project website, refreshed
  /// every few hours. It is read first because GitHub's own API answers only
  /// 60 requests an hour from one network, which a campus can use up.
  static const String siteFeed =
      'https://yeamin-talukder.github.io/$repo/release.json';

  /// GitHub's API, the fallback.
  static const String apiFeed =
      'https://api.github.com/repos/$owner/$repo/releases?per_page=20';

  /// Every APK the app downloads must start with this.
  static const String downloadPrefix =
      'https://github.com/$owner/$repo/releases/download/';
}

/// A version number such as 1.2.0, compared part by part. A pre-release
/// suffix (1.2.0-beta) ranks below the plain number.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, {this.preRelease = ''});

  final int major;
  final int minor;
  final int patch;
  final String preRelease;

  static final RegExp _pattern = RegExp(
    r'(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?',
  );

  /// Reads "1.2.0", "v1.2.0", "1.2" or "1.2.0+7" (the build number is
  /// ignored). Returns null when there is no number to read.
  static AppVersion? tryParse(String? text) {
    if (text == null) return null;
    final match = _pattern.firstMatch(
      text.trim().replaceFirst(RegExp('^[vV]'), ''),
    );
    if (match == null) return null;
    return AppVersion(
      int.parse(match.group(1)!),
      int.tryParse(match.group(2) ?? '') ?? 0,
      int.tryParse(match.group(3) ?? '') ?? 0,
      preRelease: match.group(4) ?? '',
    );
  }

  @override
  int compareTo(AppVersion other) {
    for (final (a, b) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (a != b) return a.compareTo(b);
    }
    if (preRelease == other.preRelease) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;
    return preRelease.compareTo(other.preRelease);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  @override
  String toString() =>
      '$major.$minor.$patch${preRelease.isEmpty ? '' : '-$preRelease'}';
}

/// What kind of phone an APK is built for.
enum ApkBuild {
  arm64('64-bit', 'Almost every phone from the last eight years'),
  armv7('32-bit', 'Older or low-cost phones'),
  x86_64('x86 64-bit', 'Emulators and some tablets'),
  x86('x86', 'Emulators'),
  universal('Universal', 'Every phone, larger download'),
  unknown('Android', '');

  const ApkBuild(this.label, this.description);

  final String label;
  final String description;

  static ApkBuild fromFileName(String name) {
    final n = name.toLowerCase();
    if (n.contains('universal')) return universal;
    if (n.contains('arm64') || n.contains('aarch64')) return arm64;
    if (n.contains('armv7') || n.contains('armeabi')) return armv7;
    if (n.contains('x86_64')) return x86_64;
    if (n.contains('x86')) return x86;
    return unknown;
  }

  /// The build for an Android ABI name such as "arm64-v8a".
  static ApkBuild? forAbi(String abi) => switch (abi) {
    'arm64-v8a' => arm64,
    'armeabi-v7a' || 'armeabi' => armv7,
    'x86_64' => x86_64,
    'x86' => x86,
    _ => null,
  };
}

/// One APK file of a release.
class ReleaseApk {
  const ReleaseApk({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
    this.downloads = 0,
  });

  final String name;
  final String url;

  /// Bytes.
  final int size;

  /// Lower-case hex SHA-256 from GitHub, when GitHub gives one.
  final String? sha256;
  final int downloads;

  ApkBuild get build => ApkBuild.fromFileName(name);

  /// Only files from the project's own GitHub releases, over HTTPS.
  bool get isTrusted => url.startsWith(UpdateSource.downloadPrefix);
}

class AppRelease {
  const AppRelease({
    required this.tag,
    required this.version,
    required this.apks,
    this.title,
    this.notes = '',
    this.publishedAt,
    this.pageUrl,
    this.preRelease = false,
  });

  final String tag;
  final AppVersion version;
  final List<ReleaseApk> apks;
  final String? title;

  /// The release text, as written on GitHub (Markdown).
  final String notes;
  final DateTime? publishedAt;
  final String? pageUrl;
  final bool preRelease;

  /// The APK this phone should install: the first of the phone's ABIs (in
  /// its order of preference) that the release has a build for, else a
  /// universal build. Null when none fits.
  ReleaseApk? apkFor(List<String> abis) {
    final trusted = apks.where((a) => a.isTrusted).toList();
    for (final abi in abis) {
      final wanted = ApkBuild.forAbi(abi);
      if (wanted == null) continue;
      for (final apk in trusted) {
        if (apk.build == wanted) return apk;
      }
    }
    for (final apk in trusted) {
      if (apk.build == ApkBuild.universal) return apk;
    }
    // A release with a single APK of unknown kind is assumed to be universal.
    if (trusted.length == 1 && trusted.single.build == ApkBuild.unknown) {
      return trusted.single;
    }
    return null;
  }
}

/// Reads GitHub's release list, or the website's copy of it
/// (`{ "releases": [...] }`). Drafts, releases without a version number and
/// files that are not APKs are left out.
List<AppRelease> parseReleases(Object? json) {
  final list = switch (json) {
    {'releases': final List<dynamic> releases} => releases,
    final List<dynamic> releases => releases,
    _ => const <dynamic>[],
  };
  final result = <AppRelease>[];
  for (final item in list) {
    if (item is! Map || item['draft'] == true) continue;
    final tag = '${item['tag_name'] ?? ''}';
    final version =
        AppVersion.tryParse(tag) ??
        AppVersion.tryParse('${item['name'] ?? ''}');
    if (version == null) continue;
    final apks = <ReleaseApk>[];
    for (final asset in (item['assets'] as List<dynamic>? ?? const [])) {
      if (asset is! Map) continue;
      final name = '${asset['name'] ?? ''}';
      final url = '${asset['browser_download_url'] ?? ''}';
      if (!name.toLowerCase().endsWith('.apk') || url.isEmpty) continue;
      final digest = asset['digest'];
      apks.add(
        ReleaseApk(
          name: name,
          url: url,
          size: (asset['size'] as num?)?.toInt() ?? 0,
          sha256: digest is String && digest.startsWith('sha256:')
              ? digest.substring(7).toLowerCase()
              : null,
          downloads: (asset['download_count'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    result.add(
      AppRelease(
        tag: tag,
        version: version,
        apks: apks,
        title: item['name'] as String?,
        notes: (item['body'] as String?) ?? '',
        publishedAt: DateTime.tryParse('${item['published_at'] ?? ''}'),
        pageUrl: item['html_url'] as String?,
        preRelease: item['prerelease'] == true,
      ),
    );
  }
  return result;
}

/// The newest release that is newer than [current] and has an APK for this
/// phone, or null. Pre-releases count only when [includePreReleases].
({AppRelease release, ReleaseApk apk})? findUpdate(
  List<AppRelease> releases, {
  required AppVersion current,
  required List<String> abis,
  bool includePreReleases = false,
}) {
  ({AppRelease release, ReleaseApk apk})? best;
  for (final release in releases) {
    if (release.preRelease && !includePreReleases) continue;
    if (!(release.version > current)) continue;
    final apk = release.apkFor(abis);
    if (apk == null) continue;
    if (best == null || release.version > best.release.version) {
      best = (release: release, apk: apk);
    }
  }
  return best;
}

/// The release text as plain lines for the app: Markdown headings, bold
/// marks and links reduced to their words, blank runs collapsed.
String plainReleaseNotes(String markdown) {
  final lines = <String>[];
  for (var line in markdown.replaceAll('\r', '').split('\n')) {
    line = line
        .replaceAll(RegExp(r'^#{1,6}\s*'), '')
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!)
        .replaceAll(RegExp(r'\*\*|__|`'), '')
        .replaceFirst(RegExp(r'^\s*[-*]\s+'), '• ')
        .trimRight();
    if (line.isEmpty && (lines.isEmpty || lines.last.isEmpty)) continue;
    lines.add(line);
  }
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n');
}
