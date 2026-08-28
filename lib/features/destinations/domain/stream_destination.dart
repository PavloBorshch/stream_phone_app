import '../../video_settings/domain/video_overrides.dart';

enum StreamPlatform {
  twitch,
  kick,
  custom;

  String get displayName => switch (this) {
    StreamPlatform.twitch => 'Twitch',
    StreamPlatform.kick => 'Kick',
    StreamPlatform.custom => 'Custom RTMP',
  };
}

/// One place this app can publish to. `rtmpUrl`/`secureKeyId` are always
/// populated — even for OAuth-linked platforms — because OAuth linking
/// (where available at all) only *fills in* this form for the user; manual
/// entry must keep working the same way for every platform (PLAN.md §3.1).
///
/// The actual stream key lives in [SecureTokenStore] under [secureKeyId],
/// never here — this model only carries the reference.
class StreamDestination {
  const StreamDestination({
    required this.id,
    required this.platform,
    required this.displayName,
    required this.rtmpUrl,
    required this.secureKeyId,
    required this.enabled,
    this.overrides = VideoOverrides.none,
  });

  final String id;
  final StreamPlatform platform;
  final String displayName;
  final String rtmpUrl;
  final String secureKeyId;
  final bool enabled;

  /// Per-destination deviations from the global video settings (PLAN.md
  /// Phase 5). [VideoOverrides.none] — every field null — means this
  /// destination simply follows the global settings.
  final VideoOverrides overrides;

  factory StreamDestination.fromJson(Map<String, dynamic> json) {
    return StreamDestination(
      id: json['id'] as String,
      platform: StreamPlatform.values.byName(json['platform'] as String),
      displayName: json['displayName'] as String,
      rtmpUrl: json['rtmpUrl'] as String,
      secureKeyId: json['secureKeyId'] as String,
      enabled: json['enabled'] as bool? ?? true,
      overrides: json['overrides'] == null
          ? VideoOverrides.none
          : VideoOverrides.fromJson(json['overrides'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform.name,
    'displayName': displayName,
    'rtmpUrl': rtmpUrl,
    'secureKeyId': secureKeyId,
    'enabled': enabled,
    if (!overrides.isEmpty) 'overrides': overrides.toJson(),
  };

  StreamDestination copyWith({bool? enabled, VideoOverrides? overrides}) {
    return StreamDestination(
      id: id,
      platform: platform,
      displayName: displayName,
      rtmpUrl: rtmpUrl,
      secureKeyId: secureKeyId,
      enabled: enabled ?? this.enabled,
      overrides: overrides ?? this.overrides,
    );
  }
}
