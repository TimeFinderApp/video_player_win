export 'video_player_win_plugin.dart';
import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'video_player_win_platform_interface.dart';

enum WinDataSourceType { asset, network, file, contentUri }

class WinVideoPlayerValue {
  final Duration duration;
  final bool hasError;
  final bool isBuffering;
  final bool isInitialized;
  final bool isLooping;
  final bool isPlaying;
  final bool isCompleted;
  final double playbackSpeed;
  final Duration position;
  final Size size;
  final double volume;

  int textureId = -1; //for internal use only

  double get aspectRatio => size.isEmpty ? 1 : size.width / size.height;

  WinVideoPlayerValue({
    this.duration = Duration.zero,
    this.hasError = false,
    this.size = Size.zero,
    this.position = Duration.zero,
    //Caption caption = Caption.none,
    //Duration captionOffset = Duration.zero,
    //List<DurationRange> buffered = const <DurationRange>[],
    this.isInitialized = false,
    this.isPlaying = false,
    this.isLooping = false,
    this.isBuffering = false,
    this.isCompleted = false,
    this.volume = 1.0,
    this.playbackSpeed = 1.0,
    //int rotationCorrection = 0,
    //String? errorDescription
  });

  WinVideoPlayerValue copyWith({
    Duration? duration,
    bool? hasError,
    bool? isBuffering,
    bool? isInitialized,
    bool? isLooping,
    bool? isPlaying,
    bool? isCompleted,
    double? playbackSpeed,
    Duration? position,
    Size? size,
    double? volume,
  }) {
    return WinVideoPlayerValue(
      duration: duration ?? this.duration,
      hasError: hasError ?? this.hasError,
      isBuffering: isBuffering ?? this.isBuffering,
      isInitialized: isInitialized ?? this.isInitialized,
      isLooping: isLooping ?? this.isLooping,
      isPlaying: isPlaying ?? this.isPlaying,
      isCompleted: isCompleted ?? this.isCompleted,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      position: position ?? this.position,
      size: size ?? this.size,
      volume: volume ?? this.volume,
    );
  }
}

class WinVideoPlayerController extends ValueNotifier<WinVideoPlayerValue> {
  late final bool _isBridgeMode; // true if used by 'video_player' package
  int textureId_ = -1;
  final String dataSource;
  late final WinDataSourceType dataSourceType;
  bool _isLooping = false;

  // used by flutter official "video_player" package
  final _eventStreamController = StreamController<VideoEvent>();

  Stream<VideoEvent> get videoEventStream => _eventStreamController.stream;

  Future<Duration?> get position async {
    var pos = await _getCurrentPosition();
    return Duration(milliseconds: pos);
  }

  WinVideoPlayerController._(this.dataSource, this.dataSourceType,
      {bool isBridgeMode = false})
      : super(WinVideoPlayerValue()) {
    if (dataSourceType == WinDataSourceType.contentUri) {
      throw UnsupportedError(
          "VideoPlayerController.contentUri() not supported in Windows");
    }
    if (dataSourceType == WinDataSourceType.asset) {
      throw UnsupportedError(
          "VideoPlayerController.asset() not implement yet.");
    }

    _isBridgeMode = isBridgeMode;
    //VideoPlayerWinPlatform.instance.registerPlayer(_textureId, this);
  }
  static final Finalizer<int> _finalizer = Finalizer((textureId) {
    log("[video_player_win] gc free a player that didn't dispose() yet !!!!!");
    VideoPlayerWinPlatform.instance.unregisterPlayer(textureId);
    VideoPlayerWinPlatform.instance.dispose(textureId);
  });

  WinVideoPlayerController.file(File file, {bool isBridgeMode = false})
      : this._(file.path, WinDataSourceType.file, isBridgeMode: isBridgeMode);
  WinVideoPlayerController.network(String dataSource,
      {bool isBridgeMode = false})
      : this._(dataSource, WinDataSourceType.network,
            isBridgeMode: isBridgeMode);
  WinVideoPlayerController.asset(String dataSource, {String? package})
      : this._(dataSource, WinDataSourceType.asset);
  WinVideoPlayerController.contentUri(Uri contentUri)
      : this._("", WinDataSourceType.contentUri);

  Timer? _positionTimer;
  void _cancelTrackingPosition() => _positionTimer?.cancel();
  void _startTrackingPosition() async {
    // NOTE: 'video_player' package already auto get position periodically,
    // so do nothing if _isBridgeMode = true
    if (_isBridgeMode) return;

    _positionTimer =
        Timer.periodic(const Duration(milliseconds: 300), (Timer timer) async {
      if (!value.isInitialized || value.hasError) {
        timer.cancel();
        return;
      }

      //log("[video_player_win] ui: position timer tick");
      final pos = await position;
      if (textureId_ > 0) value = value.copyWith(position: pos);

      if (!value.isPlaying || value.isCompleted) {
        timer.cancel();
      }
    });
  }

  void onPlaybackEvent_(int state) {
    switch (state) {
      // MediaEventType in win32 api
      case 1: // MEBufferingStarted
        log("[video_player_win] playback event: buffering start");
        value = value.copyWith(isInitialized: true, isBuffering: true);
        _eventStreamController
            .add(VideoEvent(eventType: VideoEventType.bufferingStart));
        break;
      case 2: // MEBufferingStopped
        log("[video_player_win] playback event: buffering finish");
        value = value.copyWith(isInitialized: true, isBuffering: false);
        _eventStreamController
            .add(VideoEvent(eventType: VideoEventType.bufferingEnd));
        break;
      case 3: // MESessionStarted , occurs when user call play() or seekTo() in playing mode
        //log("[video_player_win] playback event: playing");
        value = value.copyWith(
            isInitialized: true, isPlaying: true, isCompleted: false);
        _startTrackingPosition();
        _eventStreamController
            .add(VideoEvent(eventType: VideoEventType.isPlayingStateUpdate));
        break;
      case 4: // MESessionPaused
        //log("[video_player_win] playback event: paused");
        value = value.copyWith(isPlaying: false);
        _cancelTrackingPosition();
        _eventStreamController
            .add(VideoEvent(eventType: VideoEventType.isPlayingStateUpdate));
        break;
      case 5: // MESessionStopped
        log("[video_player_win] playback event: stopped");
        value = value.copyWith(isPlaying: false);
        _cancelTrackingPosition();
        _eventStreamController
            .add(VideoEvent(eventType: VideoEventType.isPlayingStateUpdate));
        break;
      case 6: // MESessionEnded
        log("[video_player_win] playback event: play ended");
        value = value.copyWith(isPlaying: false, position: value.duration);
        if (_isLooping) {
          seekTo(Duration.zero);
        } else {
          value = value.copyWith(isCompleted: true);
          _cancelTrackingPosition();
          _eventStreamController
              .add(VideoEvent(eventType: VideoEventType.completed));
        }
        break;
      case 7: // MEError
        log("[video_player_win] playback event: error");
        value = value.copyWith(
            isInitialized: false, hasError: true, isPlaying: false);
        _cancelTrackingPosition();
        break;
    }
  }

  Future<void> initialize() async {
    WinVideoPlayerValue? pv = await VideoPlayerWinPlatform.instance
        .openVideo(this, textureId_, dataSource);
    if (pv == null) {
      log("[video_player_win] controller intialize (open video) failed");
      value = value.copyWith(hasError: true, isInitialized: false);
      _eventStreamController.add(VideoEvent(
          eventType: VideoEventType.initialized, duration: null, size: null));
      return;
    }
    textureId_ = pv.textureId;
    value = pv;
    _finalizer.attach(this, textureId_, detach: this);

    _eventStreamController.add(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: pv.duration,
      size: pv.size,
    ));
    log("flutter: video player file opened: id=$textureId_");
  }

  Future<void> play() async {
    if (!value.isInitialized) throw ArgumentError("video file not opened yet");
    await VideoPlayerWinPlatform.instance.play(textureId_);
  }

  Future<void> pause() async {
    if (!value.isInitialized) throw ArgumentError("video file not opened yet");
    await VideoPlayerWinPlatform.instance.pause(textureId_);
  }

  Future<void> seekTo(Duration time) async {
    if (!value.isInitialized) throw ArgumentError("video file not opened yet");

    await VideoPlayerWinPlatform.instance
        .seekTo(textureId_, time.inMilliseconds);
    value = value.copyWith(position: time, isCompleted: false);
  }

  Future<int> _getCurrentPosition() async {
    if (!value.isInitialized) throw ArgumentError("video file not opened yet");
    int pos =
        await VideoPlayerWinPlatform.instance.getCurrentPosition(textureId_);

    if (textureId_ < 0) return 0;
    value = value.copyWith(position: Duration(milliseconds: pos));
    return pos;
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (!value.isInitialized) throw ArgumentError("video file not opened yet");
    await VideoPlayerWinPlatform.instance.setPlaybackSpeed(textureId_, speed);
    value = value.copyWith(playbackSpeed: speed);
  }

  Future<void> setVolume(double volume) async {
    if (!value.isInitialized) throw ArgumentError("video file not opened yet");
    await VideoPlayerWinPlatform.instance.setVolume(textureId_, volume);
    value = value.copyWith(volume: volume);
  }

  Future<void> setLooping(bool looping) async {
    _isLooping = looping;
    value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> dispose() async {
    VideoPlayerWinPlatform.instance.unregisterPlayer(textureId_);
    await VideoPlayerWinPlatform.instance.dispose(textureId_);

    _finalizer.detach(this);
    _cancelTrackingPosition();

    textureId_ = -1;
    value.textureId = -1;
    super.dispose();

    log("flutter: video player dispose: id=$textureId_");
  }
}

class WinVideoPlayer extends StatefulWidget {
  final WinVideoPlayerController controller;
  final FilterQuality filterQuality;

  // ignore: unused_element
  const WinVideoPlayer(this.controller,
      {Key? key, this.filterQuality = FilterQuality.low})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _WinVideoPlayerState();
}

class _WinVideoPlayerState extends State<WinVideoPlayer> {
  @override
  void didUpdateWidget(WinVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller != oldWidget.controller) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: widget.controller.value.aspectRatio,
          child: Texture(
            textureId: widget.controller.textureId_,
            filterQuality: widget.filterQuality,
          ),
        ),
      ),
    );
  }
}
