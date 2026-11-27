import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants.dart';
import '../../models/iptv_playlist.dart';

/// Persistence seam separating IPTV playlists, bookmarks, view configs,
/// global settings, and EPG sources from Hive and in-memory test stores.
abstract interface class IptvStorageAdapter {
  Future<List<IptvPlaylist>> getSavedPlaylists();
  Future<void> savePlaylist(IptvPlaylist playlist);
  Future<void> saveAllPlaylists(List<IptvPlaylist> playlists);
  Future<void> deletePlaylist(String id);

  IptvGlobalSettings loadGlobalSettings();
  Future<void> saveGlobalSettings(IptvGlobalSettings settings);

  Map<String, IptvViewConfig> loadViewConfigs();
  Future<void> saveViewConfigs(Map<String, IptvViewConfig> configs);

  Map<String, IptvBookmarkItem> loadBookmarks();
  Future<void> saveBookmarks(Map<String, IptvBookmarkItem> bookmarks);

  List<IptvEpgSource> loadSavedEpgSources();
  Future<void> saveEpgSources(List<IptvEpgSource> sources);
}

/// Production Hive-backed [IptvStorageAdapter].
class HiveIptvStorageAdapter implements IptvStorageAdapter {
  static const String _boxName = 'iptv_playlists';
  static const String _globalSettingsKey = 'iptv_global_settings_v1';
  static const String _bookmarksKey = 'iptv_bookmarks_map_v1';
  static const String _viewConfigsKey = 'iptv_view_configs_map_v1';
  static const String _epgSourcesKey = 'iptv_epg_sources_v1';

  Box? _box;

  Future<Box> _getBox() async {
    if (_box != null && _box!.isOpen) return _box!;
    _box = await Hive.openBox(_boxName);
    return _box!;
  }

  Box? _settingsBoxOrNull() {
    try {
      if (!Hive.isBoxOpen(AppConstants.settingsBox)) return null;
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<IptvPlaylist>> getSavedPlaylists() async {
    try {
      final box = await _getBox();
      final playlists = <IptvPlaylist>[];
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is String) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          playlists.add(IptvPlaylist.fromJson(decoded));
        } else if (raw is Map) {
          playlists.add(IptvPlaylist.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
      return playlists;
    } catch (e) {
      debugPrint('[IptvStorage] Error loading playlists: $e');
      return [];
    }
  }

  @override
  Future<void> savePlaylist(IptvPlaylist playlist) async {
    try {
      final box = await _getBox();
      await box.put(playlist.id, jsonEncode(playlist.toJson()));
    } catch (e) {
      debugPrint('[IptvStorage] Error saving playlist: $e');
    }
  }

  @override
  Future<void> saveAllPlaylists(List<IptvPlaylist> playlists) async {
    try {
      final box = await _getBox();
      await box.clear();
      for (final p in playlists) {
        await box.put(p.id, jsonEncode(p.toJson()));
      }
    } catch (e) {
      debugPrint('[IptvStorage] Error saving all playlists: $e');
    }
  }

  @override
  Future<void> deletePlaylist(String id) async {
    try {
      final box = await _getBox();
      await box.delete(id);
    } catch (e) {
      debugPrint('[IptvStorage] Error deleting playlist: $e');
    }
  }

  @override
  IptvGlobalSettings loadGlobalSettings() {
    try {
      final box = _settingsBoxOrNull();
      final raw = box?.get(_globalSettingsKey);
      if (raw is String && raw.isNotEmpty) {
        return IptvGlobalSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      } else if (raw is Map) {
        return IptvGlobalSettings.fromJson(Map<String, dynamic>.from(raw));
      }
    } catch (e) {
      debugPrint('[IptvStorage] loadGlobalSettings error: $e');
    }
    return const IptvGlobalSettings();
  }

  @override
  Future<void> saveGlobalSettings(IptvGlobalSettings settings) async {
    try {
      final box = _settingsBoxOrNull();
      if (box == null) return;
      await box.put(_globalSettingsKey, jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('[IptvStorage] saveGlobalSettings error: $e');
    }
  }

  @override
  Map<String, IptvViewConfig> loadViewConfigs() {
    try {
      final box = _settingsBoxOrNull();
      final raw = box?.get(_viewConfigsKey);
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map;
        return decoded.map(
          (k, v) => MapEntry(
            k.toString(),
            IptvViewConfig.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        );
      } else if (raw is Map) {
        return raw.map(
          (k, v) => MapEntry(
            k.toString(),
            IptvViewConfig.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        );
      }
    } catch (e) {
      debugPrint('[IptvStorage] loadViewConfigs error: $e');
    }
    return const {};
  }

  @override
  Future<void> saveViewConfigs(Map<String, IptvViewConfig> configs) async {
    try {
      final box = _settingsBoxOrNull();
      if (box == null) return;
      final encoded = configs.map((k, v) => MapEntry(k, v.toJson()));
      await box.put(_viewConfigsKey, jsonEncode(encoded));
    } catch (e) {
      debugPrint('[IptvStorage] saveViewConfigs error: $e');
    }
  }

  @override
  Map<String, IptvBookmarkItem> loadBookmarks() {
    try {
      final box = _settingsBoxOrNull();
      final raw = box?.get(_bookmarksKey);
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map;
        final out = <String, IptvBookmarkItem>{};
        for (final entry in decoded.entries) {
          if (entry.value is Map) {
            try {
              out[entry.key.toString()] = IptvBookmarkItem.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              );
            } catch (_) {}
          }
        }
        return out;
      }
    } catch (e) {
      debugPrint('[IptvStorage] loadBookmarks error: $e');
    }
    return const {};
  }

  @override
  Future<void> saveBookmarks(Map<String, IptvBookmarkItem> bookmarks) async {
    try {
      final box = _settingsBoxOrNull();
      if (box == null) return;
      final encoded = bookmarks.map((k, v) => MapEntry(k, v.toJson()));
      await box.put(_bookmarksKey, jsonEncode(encoded));
    } catch (e) {
      debugPrint('[IptvStorage] saveBookmarks error: $e');
    }
  }

  @override
  List<IptvEpgSource> loadSavedEpgSources() {
    try {
      final box = _settingsBoxOrNull();
      final raw = box?.get(_epgSourcesKey);
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        return decoded
            .whereType<Map>()
            .map((m) => IptvEpgSource.fromJson(Map<String, dynamic>.from(m)))
            .where((s) => s.url.trim().isNotEmpty)
            .toList();
      }
    } catch (e) {
      debugPrint('[IptvStorage] loadSavedEpgSources error: $e');
    }
    return const [];
  }

  @override
  Future<void> saveEpgSources(List<IptvEpgSource> sources) async {
    try {
      final box = _settingsBoxOrNull();
      if (box == null) return;
      final encoded = sources.map((s) => s.toJson()).toList();
      await box.put(_epgSourcesKey, jsonEncode(encoded));
    } catch (e) {
      debugPrint('[IptvStorage] saveEpgSources error: $e');
    }
  }
}

/// Pure in-memory [IptvStorageAdapter] for widget and unit tests without Hive.
class InMemoryIptvStorageAdapter implements IptvStorageAdapter {
  InMemoryIptvStorageAdapter([List<IptvPlaylist>? initialPlaylists])
      : _playlists = List<IptvPlaylist>.from(initialPlaylists ?? const []);

  List<IptvPlaylist> _playlists;
  IptvGlobalSettings _settings = const IptvGlobalSettings();
  Map<String, IptvViewConfig> _viewConfigs = {};
  Map<String, IptvBookmarkItem> _bookmarks = {};
  List<IptvEpgSource> _epgSources = [];

  @override
  Future<List<IptvPlaylist>> getSavedPlaylists() async =>
      List<IptvPlaylist>.unmodifiable(_playlists);

  @override
  Future<void> savePlaylist(IptvPlaylist playlist) async {
    _playlists = [playlist, ..._playlists.where((p) => p.id != playlist.id)];
  }

  @override
  Future<void> saveAllPlaylists(List<IptvPlaylist> playlists) async {
    _playlists = List<IptvPlaylist>.from(playlists);
  }

  @override
  Future<void> deletePlaylist(String id) async {
    _playlists = _playlists.where((p) => p.id != id).toList();
  }

  @override
  IptvGlobalSettings loadGlobalSettings() => _settings;

  @override
  Future<void> saveGlobalSettings(IptvGlobalSettings settings) async {
    _settings = settings;
  }

  @override
  Map<String, IptvViewConfig> loadViewConfigs() => _viewConfigs;

  @override
  Future<void> saveViewConfigs(Map<String, IptvViewConfig> configs) async {
    _viewConfigs = Map<String, IptvViewConfig>.from(configs);
  }

  @override
  Map<String, IptvBookmarkItem> loadBookmarks() => _bookmarks;

  @override
  Future<void> saveBookmarks(Map<String, IptvBookmarkItem> bookmarks) async {
    _bookmarks = Map<String, IptvBookmarkItem>.from(bookmarks);
  }

  @override
  List<IptvEpgSource> loadSavedEpgSources() => _epgSources;

  @override
  Future<void> saveEpgSources(List<IptvEpgSource> sources) async {
    _epgSources = List<IptvEpgSource>.from(sources);
  }
}
