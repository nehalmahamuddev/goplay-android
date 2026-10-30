import '../core/constants.dart';

/// Data model representing the remote update configuration.
class UpdateInfo {
  final String latestVersion;
  final String minimumVersion;
  final bool forceUpdate;
  final String apkUrl;
  final List<String> releaseNotes;
  final DateTime publishedAt;

  const UpdateInfo({
    required this.latestVersion,
    required this.minimumVersion,
    required this.forceUpdate,
    required this.apkUrl,
    required this.releaseNotes,
    required this.publishedAt,
  });

  /// Factory constructor to parse standard update.json.
  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      latestVersion: (json['latestVersion'] ?? json['versionName'] ?? '') as String,
      minimumVersion: (json['minimumVersion'] ?? '1.0.0') as String,
      forceUpdate: json['forceUpdate'] as bool? ?? json['mandatory'] as bool? ?? false,
      apkUrl: (json['apkUrl'] ?? '') as String,
      releaseNotes: List<String>.from(json['releaseNotes'] ?? const []),
      publishedAt: json['publishedAt'] != null
          ? DateTime.tryParse(json['publishedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Factory constructor to parse GitHub Releases API response.
  factory UpdateInfo.fromGithubRelease(Map<String, dynamic> json) {
    // 1. Extract Tag & Version
    final tagName = (json['tag_name'] as String? ?? '').trim();
    // Strip leading 'v' or 'V' and trailing tags like "-release"
    final cleanVersion = tagName.replaceFirst(RegExp(r'^[vV]'), '').split('-').first.trim();

    // 2. Find APK asset
    final assets = json['assets'] as List<dynamic>? ?? [];
    String apkDownloadUrl = '';
    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final contentType = (asset['content_type'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk') || contentType == 'application/vnd.android.package-archive') {
          apkDownloadUrl = asset['browser_download_url'] as String? ?? '';
          break;
        }
      }
    }

    // Fallback direct download URL if asset wasn't matched explicitly
    if (apkDownloadUrl.isEmpty && tagName.isNotEmpty) {
      apkDownloadUrl =
          'https://github.com/${AppConstants.githubOwner}/${AppConstants.githubRepo}/releases/download/$tagName/goplay.apk';
    }

    // 3. Parse Release Notes from Body & check for mandatory flag
    final body = json['body'] as String? ?? '';
    final bodyUpper = body.toUpperCase();
    final isForce = bodyUpper.contains('[MANDATORY]') || bodyUpper.contains('[FORCE_UPDATE]');

    final notes = <String>[];
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      // Skip markdown headers or dividers
      if (line.startsWith('##') || line.startsWith('---') || line.startsWith('===')) continue;
      // Clean bullet points
      var cleaned = line;
      if (cleaned.startsWith('•') || cleaned.startsWith('-') || cleaned.startsWith('*')) {
        cleaned = cleaned.substring(1).trim();
      }
      // Remove markdown links e.g. [text](url) -> text
      cleaned = cleaned.replaceAllMapped(RegExp(r'\[(.*?)\]\(.*?\)'), (m) => m[1] ?? '');
      // Filter out [MANDATORY] / [FORCE_UPDATE] tag indicators from display notes list
      final upperCleaned = cleaned.toUpperCase().trim();
      if (upperCleaned == '[MANDATORY]' || upperCleaned == '[FORCE_UPDATE]') {
        continue;
      }
      if (cleaned.isNotEmpty && !cleaned.toLowerCase().contains('full changelog')) {
        notes.add(cleaned);
      }
    }

    if (notes.isEmpty) {
      notes.add('Bug fixes and performance improvements.');
    }

    final publishedAtStr = json['published_at'] as String?;
    final publishedAt = publishedAtStr != null
        ? DateTime.tryParse(publishedAtStr) ?? DateTime.now()
        : DateTime.now();

    return UpdateInfo(
      latestVersion: cleanVersion.isNotEmpty ? cleanVersion : tagName,
      minimumVersion: '1.0.0',
      forceUpdate: isForce,
      apkUrl: apkDownloadUrl,
      releaseNotes: notes,
      publishedAt: publishedAt,
    );
  }

  /// Factory constructor when resolving tag directly from GitHub web redirect.
  factory UpdateInfo.fromTag({
    required String tag,
    String? apkUrl,
    List<String>? releaseNotes,
    bool isForce = false,
    DateTime? publishedAt,
  }) {
    final cleanVersion = tag.replaceFirst(RegExp(r'^[vV]'), '').split('-').first.trim();
    final finalApkUrl = (apkUrl != null && apkUrl.isNotEmpty)
        ? apkUrl
        : 'https://github.com/${AppConstants.githubOwner}/${AppConstants.githubRepo}/releases/download/$tag/goplay.apk';
    return UpdateInfo(
      latestVersion: cleanVersion.isNotEmpty ? cleanVersion : tag,
      minimumVersion: '1.0.0',
      forceUpdate: isForce,
      apkUrl: finalApkUrl,
      releaseNotes: releaseNotes ?? const [
        'Latest updates and performance improvements from GitHub Release.',
      ],
      publishedAt: publishedAt ?? DateTime.now(),
    );
  }

  /// Convert model back to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'latestVersion': latestVersion,
      'minimumVersion': minimumVersion,
      'forceUpdate': forceUpdate,
      'apkUrl': apkUrl,
      'releaseNotes': releaseNotes,
      'publishedAt': publishedAt.toIso8601String(),
    };
  }
}

/// Helper class for comparing semantic versions.
class VersionUtils {
  /// Compares two semantic version strings (e.g., '1.10.0' and '1.9.9').
  /// Returns:
  ///   1 if version1 > version2
  ///  -1 if version1 < version2
  ///   0 if version1 == version2
  static int compare(String version1, String version2) {
    // Strip build numbers (+...) or pre-release tags (-...)
    final cleanV1 = version1.replaceFirst(RegExp(r'^[vV]'), '').split('+').first.split('-').first;
    final cleanV2 = version2.replaceFirst(RegExp(r'^[vV]'), '').split('+').first.split('-').first;

    final parts1 = cleanV1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = cleanV2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final length = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (int i = 0; i < length; i++) {
      final val1 = i < parts1.length ? parts1[i] : 0;
      final val2 = i < parts2.length ? parts2[i] : 0;

      if (val1 > val2) return 1;
      if (val1 < val2) return -1;
    }

    // If main semantic versions are identical, compare build codes (suffixes after '+')
    final hasBuild1 = version1.contains('+');
    final hasBuild2 = version2.contains('+');
    if (hasBuild1 || hasBuild2) {
      final build1Str = hasBuild1 ? version1.split('+').last.split('-').first : '';
      final build2Str = hasBuild2 ? version2.split('+').last.split('-').first : '';
      final build1 = int.tryParse(build1Str) ?? 0;
      final build2 = int.tryParse(build2Str) ?? 0;
      
      if (build1 > build2) return 1;
      if (build1 < build2) return -1;
    }

    return 0;
  }
}
