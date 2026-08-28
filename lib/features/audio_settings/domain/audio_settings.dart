/// Which physical mic the capture session should prefer. [automatic] leaves
/// routing to the OS (which follows headset/Bluetooth connection changes on
/// its own); the explicit choices pin a source so a connected headset can be
/// bypassed in favour of the phone's own mic, or vice versa.
enum MicSource {
  automatic('Automatic', 'Follow the system audio route'),
  builtIn('Built-in mic', 'Always use the phone microphone'),
  wiredHeadset('Wired headset', 'Use a wired headset mic when connected'),
  bluetooth('Bluetooth', 'Use a Bluetooth headset mic when connected');

  const MicSource(this.displayName, this.description);

  final String displayName;
  final String description;

  static MicSource fromName(String? name) {
    return MicSource.values.firstWhere(
      (value) => value.name == name,
      orElse: () => MicSource.automatic,
    );
  }
}

enum AudioSampleRate {
  hz44100(44100, '44.1 kHz'),
  hz48000(48000, '48 kHz');

  const AudioSampleRate(this.hz, this.displayName);

  final int hz;
  final String displayName;

  static AudioSampleRate fromName(String? name) {
    return AudioSampleRate.values.firstWhere(
      (value) => value.name == name,
      orElse: () => AudioSampleRate.hz48000,
    );
  }
}

enum AudioChannels {
  mono(1, 'Mono'),
  stereo(2, 'Stereo');

  const AudioChannels(this.count, this.displayName);

  final int count;
  final String displayName;

  static AudioChannels fromName(String? name) {
    return AudioChannels.values.firstWhere(
      (value) => value.name == name,
      orElse: () => AudioChannels.stereo,
    );
  }
}

class AudioSettings {
  const AudioSettings({
    required this.micSource,
    required this.sampleRate,
    required this.bitrateKbps,
    required this.channels,
    required this.headphoneMonitoring,
  });

  final MicSource micSource;
  final AudioSampleRate sampleRate;
  final int bitrateKbps;
  final AudioChannels channels;

  /// Routes captured mic audio back to connected headphones so the streamer
  /// can hear themselves. Ignored when nothing is plugged in — enabling it on
  /// the speaker would feed back into the mic.
  final bool headphoneMonitoring;

  /// AAC bitrates the Audio Settings screen offers. Anything below 64 kbps
  /// is audibly poor for stereo music-bearing streams; anything above 192 is
  /// wasted on the AAC-LC encoders these platforms ship.
  static const bitrateOptionsKbps = [64, 96, 128, 160, 192];

  static const defaults = AudioSettings(
    micSource: MicSource.automatic,
    sampleRate: AudioSampleRate.hz48000,
    bitrateKbps: 128,
    channels: AudioChannels.stereo,
    headphoneMonitoring: false,
  );

  factory AudioSettings.fromJson(Map<String, dynamic> json) {
    return AudioSettings(
      micSource: MicSource.fromName(json['micSource'] as String?),
      sampleRate: AudioSampleRate.fromName(json['sampleRate'] as String?),
      bitrateKbps: json['bitrateKbps'] as int? ?? defaults.bitrateKbps,
      channels: AudioChannels.fromName(json['channels'] as String?),
      headphoneMonitoring: json['headphoneMonitoring'] as bool? ?? defaults.headphoneMonitoring,
    );
  }

  Map<String, dynamic> toJson() => {
    'micSource': micSource.name,
    'sampleRate': sampleRate.name,
    'bitrateKbps': bitrateKbps,
    'channels': channels.name,
    'headphoneMonitoring': headphoneMonitoring,
  };

  AudioSettings copyWith({
    MicSource? micSource,
    AudioSampleRate? sampleRate,
    int? bitrateKbps,
    AudioChannels? channels,
    bool? headphoneMonitoring,
  }) {
    return AudioSettings(
      micSource: micSource ?? this.micSource,
      sampleRate: sampleRate ?? this.sampleRate,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      channels: channels ?? this.channels,
      headphoneMonitoring: headphoneMonitoring ?? this.headphoneMonitoring,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AudioSettings &&
        other.micSource == micSource &&
        other.sampleRate == sampleRate &&
        other.bitrateKbps == bitrateKbps &&
        other.channels == channels &&
        other.headphoneMonitoring == headphoneMonitoring;
  }

  @override
  int get hashCode =>
      Object.hash(micSource, sampleRate, bitrateKbps, channels, headphoneMonitoring);
}
