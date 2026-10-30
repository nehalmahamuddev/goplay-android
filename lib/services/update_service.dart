import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants.dart';
import '../models/update_info.dart';

class UpdateService {
  final Dio _dio;

  UpdateService(this._dio);

  /// Fetches update info exclusively from GitHub Releases.
  /// Uses GitHub Releases API as primary, falling back to direct GitHub web redirect
  /// (which has no rate limits) if the REST API is rate-limited or unavailable.
  Future<UpdateInfo> fetchLatestRelease() async {
    // 1. Primary: Fetch from GitHub REST API
    try {
      final response = await _dio.get(
        AppConstants.githubLatestReleaseUrl,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'GoPlay-App/${AppConstants.appVersion}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
            'Expires': '0',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final jsonMap = data is Map<String, dynamic>
            ? data
            : (data is String ? jsonDecode(data) as Map<String, dynamic> : null);

        if (jsonMap != null) {
          final isDraft = jsonMap['draft'] as bool? ?? false;
          final isPrerelease = jsonMap['prerelease'] as bool? ?? false;
          if (!isDraft && !isPrerelease) {
            final info = UpdateInfo.fromGithubRelease(jsonMap);
            if (info.apkUrl.isNotEmpty) {
              return info;
            }
          }
        }
      }
    } catch (_) {
      // GitHub REST API rate limited (HTTP 403), network error, or offline -> proceed to GitHub Web fallback
    }

    // 2. Fallback: Direct GitHub Web Redirect (Zero rate limits, zero middleman)
    return fetchLatestReleaseFromWebRedirect();
  }

  /// Fallback mechanism that checks GitHub's public web release redirect.
  /// https://github.com/owner/repo/releases/latest returns HTTP 302 Found redirecting
  /// to https://github.com/owner/repo/releases/tag/vX.Y.Z
  Future<UpdateInfo> fetchLatestReleaseFromWebRedirect() async {
    try {
      final response = await _dio.get(
        AppConstants.githubLatestWebReleaseUrl,
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
          headers: {
            'User-Agent': 'GoPlay-App/${AppConstants.appVersion}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
            'Expires': '0',
          },
        ),
      );

      String? redirectLocation = response.headers.value('location');
      if (redirectLocation == null || redirectLocation.isEmpty) {
        redirectLocation = response.realUri.toString();
      }

      if (redirectLocation.contains('/tag/')) {
        final tag = redirectLocation.split('/tag/').last.split('?').first.split('#').first.trim();
        if (tag.isNotEmpty) {
          return UpdateInfo.fromTag(tag: tag);
        }
      }
    } catch (_) {
      // If HEAD/no-redirect failed, try with redirects followed
      try {
        final response = await _dio.get(
          AppConstants.githubLatestWebReleaseUrl,
          options: Options(
            followRedirects: true,
            maxRedirects: 5,
            headers: {
              'User-Agent': 'GoPlay-App/${AppConstants.appVersion}',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
              'Expires': '0',
            },
          ),
        );
        final realUriStr = response.realUri.toString();
        if (realUriStr.contains('/tag/')) {
          final tag = realUriStr.split('/tag/').last.split('?').first.split('#').first.trim();
          if (tag.isNotEmpty) {
            return UpdateInfo.fromTag(tag: tag);
          }
        }
      } catch (_) {}
    }

    throw Exception('Unable to check GitHub Releases. Please verify your internet connection.');
  }

  /// Gets the current application version using [package_info_plus].
  Future<String> getCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  /// Downloads the APK to the application temporary directory with progress tracking and cancellation support.
  Future<File> downloadApk({
    required String url,
    required String fileName,
    required ProgressCallback onProgress,
    required CancelToken cancelToken,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      
      // Auto-delete old downloaded APKs to conserve space
      await deleteOldApks();
      
      final savePath = '${tempDir.path}/$fileName';
      
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            HttpHeaders.acceptEncodingHeader: '*',
          },
        ),
      );
      
      final file = File(savePath);
      if (!await file.exists()) {
        throw Exception('Downloaded file not found at $savePath');
      }
      return file;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw Exception('Download cancelled');
      }
      throw Exception('Download failed: ${e.message ?? e.toString()}');
    } catch (e) {
      throw Exception('Download failed: $e');
    }
  }

  /// Deletes all previously downloaded APK files in the temporary directory to clean up space.
  Future<void> deleteOldApks() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);
      if (await dir.exists()) {
        final list = dir.listSync();
        for (final item in list) {
          if (item is File && item.path.endsWith('.apk')) {
            try {
              await item.delete();
            } catch (_) {
              // Fail silently for cleanup errors
            }
          }
        }
      }
    } catch (_) {
      // Fail silently for cleanup errors
    }
  }

  /// Checks if the app has permission to install packages (Android 8+).
  Future<bool> isInstallPermissionGranted() async {
    if (Platform.isAndroid) {
      return await Permission.requestInstallPackages.isGranted;
    }
    return true;
  }

  /// Requests the package installation permission (opens System Settings).
  Future<bool> requestInstallPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.request();
      return status.isGranted;
    }
    return true;
  }

  /// Launches the package installer for the downloaded APK.
  Future<bool> installApk(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('APK file not found for installation: $filePath');
      }
      
      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
      
      if (result.type != ResultType.done) {
        throw Exception('Failed to open APK installer: ${result.message}');
      }
      return true;
    } catch (e) {
      throw Exception('Error installing APK: $e');
    }
  }
}
