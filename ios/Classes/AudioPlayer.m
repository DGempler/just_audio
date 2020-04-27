#import "AudioPlayer.h"
#import <AVFoundation/AVFoundation.h>

// TODO: Check for and report invalid state transitions.
@implementation AudioPlayer {
	NSObject<FlutterPluginRegistrar>* _registrar;
	FlutterMethodChannel* _methodChannel;
	FlutterEventChannel* _eventChannel;
	FlutterEventSink _eventSink;
	NSString* _playerId;
	AVPlayer* _player;
	enum PlaybackState _state;
	long long _updateTime;
	int _updatePosition;
	int _seekPos;
	FlutterResult _connectionResult;
	BOOL _buffering;
	BOOL _stalled;
	id _endObserver;
	id _timeObserver;
	BOOL _automaticallyWaitsToMinimizeStalling;
}

- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar playerId:(NSString*)idParam {
	self = [super init];
	NSAssert(self, @"super init cannot be nil");
	_registrar = registrar;
	_playerId = idParam;
	_methodChannel = [FlutterMethodChannel
		methodChannelWithName:[NSMutableString stringWithFormat:@"com.ryanheise.just_audio.methods.%@", _playerId]
		      binaryMessenger:[registrar messenger]];
	_eventChannel = [FlutterEventChannel
		eventChannelWithName:[NSMutableString stringWithFormat:@"com.ryanheise.just_audio.events.%@", _playerId]
		     binaryMessenger:[registrar messenger]];
	[_eventChannel setStreamHandler:self];
	_state = none;
	_player = nil;
	_seekPos = -1;
	_buffering = NO;
	_stalled = NO;
	_endObserver = 0;
	_timeObserver = 0;
	_automaticallyWaitsToMinimizeStalling = YES;
	__weak __typeof__(self) weakSelf = self;
	[_methodChannel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
		  [weakSelf handleMethodCall:call result:result];
	}];
	return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
	NSArray* args = (NSArray*)call.arguments;
	if ([@"setUrl" isEqualToString:call.method]) {
		[self setUrl:args[0] result:result];
	} else if ([@"setClip" isEqualToString:call.method]) {
		[self setClip:args[0] end:args[1]];
		result(nil);
	} else if ([@"play" isEqualToString:call.method]) {
		[self play];
		result(nil);
	} else if ([@"pause" isEqualToString:call.method]) {
		[self pause];
		result(nil);
	} else if ([@"stop" isEqualToString:call.method]) {
		[self stop];
		result(nil);
	} else if ([@"setVolume" isEqualToString:call.method]) {
		[self setVolume:(float)[args[0] doubleValue]];
		result(nil);
	} else if ([@"setSpeed" isEqualToString:call.method]) {
		[self setSpeed:(float)[args[0] doubleValue]];
		result(nil);
	} else if ([@"setAutomaticallyWaitsToMinimizeStalling" isEqualToString:call.method]) {
		[self setAutomaticallyWaitsToMinimizeStalling:(BOOL)[args[0] boolValue]];
		result(nil);
	} else if ([@"seek" isEqualToString:call.method]) {
		[self seek:[args[0] intValue] result:result];
		result(nil);
	} else if ([@"dispose" isEqualToString:call.method]) {
		[self dispose];
		result(nil);
	} else {
		result(FlutterMethodNotImplemented);
	}
	// TODO
	/* } catch (Exception e) { */
	/* 	e.printStackTrace(); */
	/* 	result.error("Error", null, null); */
	/* } */
}

- (FlutterError*)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)eventSink {
	_eventSink = eventSink;
	return nil;
}

- (FlutterError*)onCancelWithArguments:(id)arguments {
	_eventSink = nil;
	return nil;
}

- (void)checkForDiscontinuity {
	if (!_eventSink) return;
	if ((_state != playing) && !_buffering) return;
	long long now = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
	int position = [self getCurrentPosition];
	long long timeSinceLastUpdate = now - _updateTime;
	long long expectedPosition = _updatePosition + (long long)(timeSinceLastUpdate * _player.rate);
	long long drift = position - expectedPosition;
	// Update if we've drifted or just started observing
	if (_updateTime == 0L) {
		[self broadcastPlaybackEvent];
	} else if (drift < -100) {
		NSLog(@"time discontinuity detected: %lld", drift);
		// original code
		// _buffering = YES;
		// [self broadcastPlaybackEvent];
		// end original code

		// new code
		if (_seekPos == -1) {
			_buffering = NO;
			[self broadcastPlaybackEvent];
		} else {
			_buffering = YES;
			[self broadcastPlaybackEvent];
		}
		// end new code
	} else if (_buffering) {
		// new code
		if (_seekPos == -1) {
			_buffering = NO;
			[self broadcastPlaybackEvent];
		} else {
		}
		// end new code

		// original code
		// _buffering = NO;
		// [self broadcastPlaybackEvent];
		// end original code
	}
}

- (void)broadcastPlaybackEvent {
	if (!_eventSink) return;
	long long now = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
	_updatePosition = [self getCurrentPosition];
	_updateTime = now;
	_eventSink(@[
		@(_state),
		@(_buffering),
		@(_updatePosition),
		@(_updateTime),
		// TODO: buffer position
		@(_updatePosition),
	]);
}

- (int)getCurrentPosition {
	if (_state == none || _state == connecting) {
		return 0;
	} else if (_seekPos != -1) {
		return _seekPos;
	} else {
		return (int)(1000 * CMTimeGetSeconds([_player currentTime]));
	}
}

- (void)setPlaybackState:(enum PlaybackState)state {
	//enum PlaybackState oldState = _state;
	_state = state;
	// TODO: Investigate when we need to start and stop
	// observing item position.
	/* if (oldState != playing && state == playing) { */
	/* 	[self startObservingPosition]; */
	/* } */
	[self broadcastPlaybackEvent];
}

- (void)setPlaybackBufferingState:(enum PlaybackState)state buffering:(BOOL)buffering {
	_buffering = buffering;
	[self setPlaybackState:state];
}

- (void)setUrl:(NSString*)url result:(FlutterResult)result {
	// TODO: error if already connecting
	_connectionResult = result;
	[self setPlaybackState:connecting];

	// new code not indenting after
	dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
	// end new code

	if (_player) {
		[[_player currentItem] removeObserver:self forKeyPath:@"status"];
		[[_player currentItem] removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
        if (@available(iOS 10.0, *)) {[_player removeObserver:self forKeyPath:@"timeControlStatus"];}
		[[NSNotificationCenter defaultCenter] removeObserver:_endObserver];
		_endObserver = 0;

		[[NSNotificationCenter defaultCenter]
			removeObserver:self
			name:AVPlayerItemPlaybackStalledNotification
			object:_player.currentItem];

        [[NSNotificationCenter defaultCenter]
			removeObserver:self
			name:AVPlayerItemFailedToPlayToEndTimeNotification
			object:_player.currentItem];
	}

	AVPlayerItem *playerItem;

	//Allow iOs playing both external links and local files.
	if ([url hasPrefix:@"file://"]) {
		playerItem = [[AVPlayerItem alloc] initWithURL:[NSURL fileURLWithPath:[url substringFromIndex:7]]];
	} else {
		playerItem = [[AVPlayerItem alloc] initWithURL:[NSURL URLWithString:url]];
	}

	[playerItem addObserver:self
		     forKeyPath:@"status"
			options:NSKeyValueObservingOptionNew
			context:nil];

	[playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:nil];

	// TODO: Add observer for _endObserver.
	_endObserver = [[NSNotificationCenter defaultCenter]
		addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
			    object:playerItem
			     queue:nil
			usingBlock:^(NSNotification* note) {
				NSLog(@"Reached play end time");
				[self complete];
			}
	];

	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(playbackStalled:)
		name:AVPlayerItemPlaybackStalledNotification
		object:playerItem];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemFailedToPlayToEndTime:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:playerItem];

	if (_player) {
		// new code
		//Dispatch to background Thread to prevent blocking UI
		// dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
			[_player replaceCurrentItemWithPlayerItem:playerItem];
		// });
		// end new code

		// original code
		// [_player replaceCurrentItemWithPlayerItem:playerItem];
		// end original code
	} else {
		_player = [[AVPlayer alloc] initWithPlayerItem:playerItem];
	}
	if (_timeObserver) {
		[_player removeTimeObserver:_timeObserver];
		_timeObserver = 0;
	}
	if (@available(iOS 10.0, *)) {
		_player.automaticallyWaitsToMinimizeStalling = _automaticallyWaitsToMinimizeStalling;
        [_player addObserver:self
        forKeyPath:@"timeControlStatus"
           options:NSKeyValueObservingOptionNew
           context:nil];
	}
	// TODO: learn about the different ways to define weakSelf.
	//__weak __typeof__(self) weakSelf = self;
	//typeof(self) __weak weakSelf = self;
	__unsafe_unretained typeof(self) weakSelf = self;
	_timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(200, 1000)
		queue:nil
		usingBlock:^(CMTime time) {
			[weakSelf checkForDiscontinuity];
		}
	];
	// We send result after the playerItem is ready in observeValueForKeyPath.

	// new code not indentend before
	});
	// end new code

}

- (void)playbackStalled:(NSNotification *)notification {
    NSLog(@"playbackStalled");
	_stalled = YES;
}

- (void) playerItemFailedToPlayToEndTime:(NSNotification *)notification
{
    NSLog(@"playerItemFailedToPlayToEndTime");
    NSError *error = notification.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
	NSLog(@" error => %@ ", error );
	[self stop];
	[self setPlaybackState:error];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
		ofObject:(id)object
		change:(NSDictionary<NSString *,id> *)change
		context:(void *)context {
	if ([keyPath isEqualToString:@"status"]) {
		AVPlayerItemStatus status = AVPlayerItemStatusUnknown;
		NSNumber *statusNumber = change[NSKeyValueChangeNewKey];
		if ([statusNumber isKindOfClass:[NSNumber class]]) {
			status = statusNumber.integerValue;
		}
		switch (status) {
			case AVPlayerItemStatusReadyToPlay:
				[self setPlaybackState:stopped];
				_connectionResult(@((int)(1000 * CMTimeGetSeconds([[_player currentItem] duration]))));
				break;
			case AVPlayerItemStatusFailed:
				NSLog(@"AVPlayerItemStatusFailed");
				NSLog(@" error => %@ ", _player.currentItem.error );
				[self stop];
				[self setPlaybackState:error];
				_connectionResult(nil);
				break;
			case AVPlayerItemStatusUnknown:
				break;
		}
	}

	if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
		if (_stalled && _player.currentItem.playbackLikelyToKeepUp) {
			_stalled = NO;
			[self play];
		}
	}

    if (@available(iOS 10.0, *)) {
        if ([keyPath isEqualToString:@"timeControlStatus"]) {
            AVPlayerTimeControlStatus status = AVPlayerTimeControlStatusPaused;
            NSNumber *statusNumber = change[NSKeyValueChangeNewKey];
            if ([statusNumber isKindOfClass:[NSNumber class]]) {
                status = statusNumber.integerValue;
            }
            switch (status) {
                case AVPlayerTimeControlStatusPaused:
                    // new code
                    // when pause is called in self stop, this gets triggered and sets state another time
                    if (_state == stopped || _state == connecting || _buffering) {
                    } else if (_stalled) {
                        [self setPlaybackBufferingState:paused buffering:YES];
                    } else {
                      [self setPlaybackBufferingState:paused buffering:NO];
                    }
                    // end new code

                    // original code
                    // [self setPlaybackBufferingState:paused buffering:NO];
                    // end original code
                    break;
                case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
                   if (_state != stopped) [self setPlaybackBufferingState:stopped buffering:YES];
                   else [self setPlaybackBufferingState:connecting buffering:YES];
                    break;
                case AVPlayerTimeControlStatusPlaying:
                    // new code
                    if (_state == stopped || _buffering) {
                      [self setPlaybackBufferingState:playing buffering:YES];
                    } else {
                      [self setPlaybackBufferingState:playing buffering:NO];
                    }
                    // end new code

                    // original code
                    // [self setPlaybackBufferingState:playing buffering:NO];
                    // end original code
                    break;
            }
        }
    }
}

- (void)setClip:(NSNumber*)start end:(NSNumber*)end {
	// TODO
}

- (void)play {
	// TODO: dynamically adjust the lag.
	//int lag = 6;
	//int start = [self getCurrentPosition];

	// original code
	// [_player play];
  // if (!@available(iOS 10.0, *)) {[self setPlaybackState:playing];}
	// end original code

	// new code
	[_player play];
	if (_state == stopped) {
		_buffering = YES;
		if (!@available(iOS 10.0, *)) {[self setPlaybackState:playing];}
	} else if (_state == paused) {
		if (!@available(iOS 10.0, *)) {[self setPlaybackState:playing];}
	}  else if (_state == playing) {
	} else {
		if (!@available(iOS 10.0, *)) {[self setPlaybackState:playing];}
	}
	// end new code


	// TODO: convert this Android code to iOS
	/* if (endDetector != null) { */
	/* 	handler.removeCallbacks(endDetector); */
	/* } */
	/* if (untilPosition != null) { */
	/* 	final int duration = Math.max(0, untilPosition - start - lag); */
	/* 	handler.postDelayed(new Runnable() { */
	/* 		@Override */
	/* 		public void run() { */
	/* 			final int position = getCurrentPosition(); */
	/* 			if (position > untilPosition - 20) { */
	/* 				pause(); */
	/* 			} else { */
	/* 				final int duration = Math.max(0, untilPosition - position - lag); */
	/* 				handler.postDelayed(this, duration); */
	/* 			} */
	/* 		} */
	/* 	}, duration); */
	/* } */
}

- (void)pause {
	[_player pause];
    if (!@available(iOS 10.0, *)) {[self setPlaybackState:paused];}
}

- (void)stop {
	// TODO: Dmitry - move set stopped up out of completionHandler again?
	// also, this call to pause likely triggers that AVPlayerTimeControl..Paused and broadcasts paused before this stopped!

	// new code
	// // setting state first so AVPlayerTimeControl pause handler triggers with _state == stopped
	// // [self setPlaybackBufferingState:stopped buffering:NO];

	// [self setPlaybackState:stopped];
	// [_player pause];

	// [_player seekToTime:CMTimeMake(0, 1000)
	//   completionHandler:^(BOOL finished) {
	// 	//   if (!@available(iOS 10.0, *)) {[self setPlaybackState:stopped];}
	// 	//   [self setPlaybackState:stopped];
	//   }];
	// end new code

	// newer code
	_state = stopped;
	_buffering = NO;
	[_player pause];

	// dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
		if (_stalled) {
			_stalled = NO;
			[self setPlaybackState:stopped];
		} else if (_player.status == AVPlayerItemStatusReadyToPlay) {
			[_player seekToTime:CMTimeMake(0, 1000)
				completionHandler:^(BOOL finished) {
					[self setPlaybackBufferingState:stopped buffering:NO];
				}];
		} else {
			NSLog(@"player.status was not AVPlayerItemStatusReadyToPlay on stop");
		}
	// });
	// end newer code

	// original code
	// [_player pause];
	// [_player seekToTime:CMTimeMake(0, 1000)
	//   completionHandler:^(BOOL finished) {
	// 	  [self setPlaybackBufferingState:stopped buffering:NO];
	//   }];
	// end original code
}

- (void)complete {
	// new code
	// this doesn't work, if next track takes long to load, for some reason UI doesn't get updated with skipToNext
	// [self setPlaybackBufferingState:completed buffering:NO];
	// _state = stopped;
	[_player pause];

	// dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
		[_player seekToTime:CMTimeMake(0, 1000)
			completionHandler:^(BOOL finished) {
				[self setPlaybackBufferingState:completed buffering:NO];
			}
		];
	// });
	// end new code

	// original code
	// [_player pause];
	// [_player seekToTime:CMTimeMake(0, 1000)
	//   completionHandler:^(BOOL finished) {
	//     [self setPlaybackBufferingState:completed buffering:NO];
	//   }];
	// original code
}

- (void)setVolume:(float)volume {
	[_player setVolume:volume];
}

- (void)setSpeed:(float)speed {
	if (speed == 1.0
        || (speed < 1.0 && _player.currentItem.canPlaySlowForward)
        || (speed > 1.0 && _player.currentItem.canPlayFastForward)) {
		_player.rate = speed;
	}
}

-(void)setAutomaticallyWaitsToMinimizeStalling:(bool)automaticallyWaitsToMinimizeStalling {
	_automaticallyWaitsToMinimizeStalling = automaticallyWaitsToMinimizeStalling;
	if (@available(iOS 10.0, *)) {
		if(_player) {
			_player.automaticallyWaitsToMinimizeStalling = automaticallyWaitsToMinimizeStalling;
		}
	}
}

- (void)seek:(int)position result:(FlutterResult)result {
	_seekPos = position;
	NSLog(@"seek. enter buffering");
	_buffering = YES;

	// new code
	[_player pause];
	// end new code


	[self broadcastPlaybackEvent];
	[_player seekToTime:CMTimeMake(position, 1000)
	  completionHandler:^(BOOL finished) {
		  NSLog(@"seek completed");
		  [self onSeekCompletion:result];
	  }];
}

- (void)onSeekCompletion:(FlutterResult)result {
	_seekPos = -1;

	// original code
	// _buffering = NO;
	// end original code

	// new code
	[_player play];
	// end new code
	[self broadcastPlaybackEvent];
	result(nil);
}

- (void)dispose {
	if (_state != none) {
		[self stop];
		[self setPlaybackBufferingState:none buffering:NO];
	}
}

@end
