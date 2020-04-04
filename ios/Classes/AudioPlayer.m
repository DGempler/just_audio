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
	NSLog(@"checkForDiscontinuity");
	if (!_eventSink) return;
	if ((_state != playing) && !_buffering) return;
	long long now = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
	int position = [self getCurrentPosition];
	long long timeSinceLastUpdate = now - _updateTime;
	long long expectedPosition = _updatePosition + (long long)(timeSinceLastUpdate * _player.rate);
	long long drift = position - expectedPosition;
	// Update if we've drifted or just started observing
	if (_updateTime == 0L) {
		NSLog(@"checkForDiscontinuity just started observing");
		[self broadcastPlaybackEvent];
	} else if (drift < -100) {
		NSLog(@"checkForDiscontinuity time discontinuity detected: %lld", drift);
		// original code
		// _buffering = YES;
		// [self broadcastPlaybackEvent];
		// end original code

		// new code
		if (_seekPos == -1) {
			NSLog(@"checkForDiscontinuity not seeking, assuming buffering is over and setting _buffering to NO");
			_buffering = NO;
			[self broadcastPlaybackEvent];
		} else {
			NSLog(@"checkForDiscontinuity seeking, setting _buffering to YES");
			_buffering = YES;
			[self broadcastPlaybackEvent];
		}
		// end new code
	} else if (_buffering) {
		// new code
		if (_seekPos == -1) {
			NSLog(@"checkForDiscontinuity not seeking and _buffering is YES, setting _buffering to NO");
			_buffering = NO;
			[self broadcastPlaybackEvent];
		} else {
			NSLog(@"checkForDiscontinuity seeking and _buffering is YES, ignoring");
		}
		// end new code

		// original code
		// NSLog(@"checkForDiscontinuity - _buffering is YES - setting to buffering = NO, and _seekPos was: %d", _seekPos);
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
	NSLog(@"JustAudio setUrl, setting state to connecting. url: %@", url);
	_connectionResult = result;
	[self setPlaybackState:connecting];

	// new code not indenting after
	NSLog(@"JustAudio setUrl about to dispatch background thread for everything after setPlaybackState:connecting");
	dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
		NSLog(@"JustAudio setUrl dispatching background thread for everything after setPlaybackState:connecting");
	// end new code

	if (_player) {
		NSLog(@"_player exists");
		[[_player currentItem] removeObserver:self forKeyPath:@"status"];
        if (@available(iOS 10.0, *)) {[_player removeObserver:self forKeyPath:@"timeControlStatus"];}
		[[NSNotificationCenter defaultCenter] removeObserver:_endObserver];
		_endObserver = 0;
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
	if (_player) {
		// new code
		NSLog(@"_player exists, calling replaceCurrentItemWithPlayerItem");
		//Dispatch to background Thread to prevent blocking UI
		// dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
			// NSLog(@"JustAudio setUrl dispatching background thread for replaceCurrentItemWithPlayerItem");
			[_player replaceCurrentItemWithPlayerItem:playerItem];
			NSLog(@"JustAudio setUrl done replaceCurrentItemWithPlayerItem");
		// });
		// end new code

		// original code
		// [_player replaceCurrentItemWithPlayerItem:playerItem];
		// end original code
	} else {
		NSLog(@"_player didn't exist, calling initWithPlayerItem");
		_player = [[AVPlayer alloc] initWithPlayerItem:playerItem];
	}
	if (_timeObserver) {
		NSLog(@"removing _timeObserver");
		[_player removeTimeObserver:_timeObserver];
		_timeObserver = 0;
	}
	if (@available(iOS 10.0, *)) {
		NSLog(@"automaticallyWaitsToMinimizeStalling available");
		_player.automaticallyWaitsToMinimizeStalling = _automaticallyWaitsToMinimizeStalling;
		NSLog(@"adding timeControlStatus listener");
        [_player addObserver:self
        forKeyPath:@"timeControlStatus"
           options:NSKeyValueObservingOptionNew
           context:nil];
	}
	// TODO: learn about the different ways to define weakSelf.
	//__weak __typeof__(self) weakSelf = self;
	//typeof(self) __weak weakSelf = self;
	__unsafe_unretained typeof(self) weakSelf = self;
	NSLog(@"adding addPeriodicTimeObserverForInterval");
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
				NSLog(@"AVPlayerItemStatusReadyToPlay, setting _state as stopped, returning duration");
				[self setPlaybackState:stopped];
				_connectionResult(@((int)(1000 * CMTimeGetSeconds([[_player currentItem] duration]))));
				break;
			case AVPlayerItemStatusFailed:
				NSLog(@"AVPlayerItemStatusFailed");
				_connectionResult(nil);
				break;
			case AVPlayerItemStatusUnknown:
				break;
		}
	}
    if (@available(iOS 10.0, *)) {
        if ([keyPath isEqualToString:@"timeControlStatus"]) {
            NSLog(@"timeControlStatus update");
            AVPlayerTimeControlStatus status = AVPlayerTimeControlStatusPaused;
            NSNumber *statusNumber = change[NSKeyValueChangeNewKey];
            if ([statusNumber isKindOfClass:[NSNumber class]]) {
                status = statusNumber.integerValue;
            }
            switch (status) {
                case AVPlayerTimeControlStatusPaused:
                    NSLog(@"AVPlayerTimeControlStatusPaused");

                    // new code
                    // when pause is called in self stop, this gets triggered and sets state another time
                    if (_state == stopped || _state == connecting || _buffering) {
                      NSLog(@"AVPlayerTimeControlStatusPaused _state was stopped or connecting or buffering, ignoring");
                    } else {
                      NSLog(@"AVPlayerTimeControlStatusPaused _state was NOT stopped or was buffering, setting paused state and buffering to NO");
                      [self setPlaybackBufferingState:paused buffering:NO];
                    }
                    // end new code

                    // original code
                    // [self setPlaybackBufferingState:paused buffering:NO];
                    // end original code
                    break;
                case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
                    NSLog(@"AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate");
                   if (_state != stopped) [self setPlaybackBufferingState:stopped buffering:YES];
                   else [self setPlaybackBufferingState:connecting buffering:YES];
                    break;
                case AVPlayerTimeControlStatusPlaying:
                    // new code
                    NSLog(@"AVPlayerTimeControlStatusPlaying");
                    if (_state == stopped || _buffering) {
                      NSLog(@"AVPlayerTimeControlStatusPlaying _state was stopped or _buffering, setting playing but buffering to YES");
                      [self setPlaybackBufferingState:playing buffering:YES];
                    } else {
                      NSLog(@"AVPlayerTimeControlStatusPlaying _state was NOT stopped, setting buffering to NO");
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
	NSLog(@"JustAudio play");
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
		NSLog(@"play called, _state was stopped, setting buffering to YES and playback state to playing");
		_buffering = YES;
		if (!@available(iOS 10.0, *)) {[self setPlaybackState:playing];}
	} else if (_state == paused) {
		NSLog(@"play called, _state was paused, setting playback state to playing");
		if (!@available(iOS 10.0, *)) {[self setPlaybackState:playing];}
	}  else if (_state == playing) {
		NSLog(@"play called, _state was playing!");
	} else {
		NSLog(@"PLAY WAS CALLED WITH SOMETHING ELSE OHHH NOOOOOOOOO");
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
	NSLog(@"JustAudio pause");
	[_player pause];
    if (!@available(iOS 10.0, *)) {[self setPlaybackState:paused];}
}

- (void)stop {
	NSLog(@"JustAudio stop");
	// TODO: Dmitry - move set stopped up out of completionHandler again?
	// also, this call to pause likely triggers that AVPlayerTimeControl..Paused and broadcasts paused before this stopped!

	// new code
	// // setting state first so AVPlayerTimeControl pause handler triggers with _state == stopped
	// // [self setPlaybackBufferingState:stopped buffering:NO];

	// [self setPlaybackState:stopped];
	// NSLog(@"JustAudio stop pausing player");
	// [_player pause];

	// NSLog(@"JustAudio stop about to seekToTime 0");
	// [_player seekToTime:CMTimeMake(0, 1000)
	//   completionHandler:^(BOOL finished) {
	// 	  NSLog(@"stop seekTo 0 time completionHandler");
	// 	//   if (!@available(iOS 10.0, *)) {[self setPlaybackState:stopped];}
	// 	//   [self setPlaybackState:stopped];
	//   }];
	// end new code

	// newer code
	NSLog(@"JustAudio stop setting _state to stopped and pausing player");
	_state = stopped;
	[_player pause];

	// NSLog(@"JustAudio stop dispatching background thread for _player seekToTime 0");
	// dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
		// NSLog(@"JustAudio stop dispatched background thread for _player seekToTime 0");
		NSLog(@"JustAudio stop about to seekToTime 0");
		[_player seekToTime:CMTimeMake(0, 1000)
			completionHandler:^(BOOL finished) {
				NSLog(@"JustAudio stop _player seekToTime 0 completionHandler");
				[self setPlaybackBufferingState:stopped buffering:NO];
			}];
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
	NSLog(@"JustAudio complete");
	// new code
	// this doesn't work, if next track takes long to load, for some reason UI doesn't get updated with skipToNext
	// [self setPlaybackBufferingState:completed buffering:NO];
	// _state = stopped;
	[_player pause];

	// NSLog(@"JustAudio complete dispatching background thread for _player seekToTime 0");
	// dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
	//   NSLog(@"JustAudio complete dispatched background thread for _player seekToTime 0");
		[_player seekToTime:CMTimeMake(0, 1000)
			completionHandler:^(BOOL finished) {
				NSLog(@"JustAudio complete _player seekToTime 0 completionHandler");
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
	NSLog(@"JustAudio seek setting _buffering to YES and pausing player");
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
	NSLog(@"JustAudio onSeekCompletion, still buffering so not changing but calling _player play");
	[_player play];
	// end new code
	[self broadcastPlaybackEvent];
	result(nil);
}

- (void)dispose {
	NSLog(@"JustAudio dispose");
	if (_state != none) {
		[self stop];
		[self setPlaybackBufferingState:none buffering:NO];
	}
}

@end
