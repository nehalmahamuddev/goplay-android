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

  /// Fetches update info from GitHub Releases API, falling back to static update.json if needed.
  Future<UpdateInfo> fetchLatestRelease() async {
    try {
      // 1. Primary: Fetch from GitHub Releases API
      final response = await _dio.get(
        AppConstants.githubLatestReleaseUrl,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github.v3+json',
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
          final info = UpdateInfo.fromGithubRelease(jsonMap);
          // If a valid APK was found in the GitHub release
          if (info.apkUrl.isNotEmpty) {
            return info;
          }
        }
      }
    } catch (_) {
      // GitHub API rate limited or offline, proceed to fallback
    }

    // 2. Fallback: Fetch from static update.json
    return fetchUpdateInfo(AppConstants.fallbackUpdateJsonUrl);
  }

  /// Fetches the update configuration from the remote JSON file.
  Future<UpdateInfo> fetchUpdateInfo(String url) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
            'Expires': '0',
          },
        ),
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return UpdateInfo.fromJson(data);
        } else if (data is String) {
          return UpdateInfo.fromJson(jsonDecode(data) as Map<String, dynamic>);
        }
        throw Exception('Invalid update.json format');
      }
      throw Exception('Failed to fetch update info: ${response.statusCode}');
    } on DioException catch (e) {
      throw Exception('Network error checking for updates: ${e.message ?? e.toString()}');
    } catch (e) {
      throw Exception('Failed to parse update info: $e');
    }
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
        for (final file in list) {
          if (file is File && file.path.endsWith('.apk')) {
            try {
              await file.delete();
            } catch (_) {
              // Ignore failure to delete stale files
            }
          }
        }
      }
    } catch (_) {
      // Ignore directory read errors
    }
  }

  /// Requests install permissions (for Android 8.0+) and opens the APK file.
  Future<OpenResult> installApk(String filePath) async {
    try {
      if (Platform.isAndroid) {
        // Check REQUEST_INSTALL_PACKAGES permission
        final status = await Permission.requestInstallPackages.status;
        if (!status.isGranted) {
          final requestStatus = await Permission.requestInstallPackages.request();
          if (!requestStatus.isGranted) {
            throw Exception('Permission to install packages was denied');
          }
        }
      }

      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
      return result;
    } catch (e) {
      throw Exception('Failed to trigger installation: $e');
    }
  }
}
