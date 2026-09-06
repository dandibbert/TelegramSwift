//
//  VideoStreamingTestModalController.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 12/11/2018.
//  Copyright © 2018 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import TelegramCore
import TelegramMediaPlayer
import SwiftSignalKit
import Postbox
import RangeSet
import IOKit.pwr_mgt
import TelegramMedia


private func makePlayer(account: Account, reference: FileMediaReference, fetchAutomatically: Bool = false) -> (UniversalVideoContentView & NSView) {
    let player: (UniversalVideoContentView & NSView)
    if isHLSVideo(file: reference.media) {
        player = HLSVideoJSNativeContentView(accountId: account.id, postbox: account.postbox, userLocation: reference.userLocation, fileReference: reference, streamVideo: true, loopVideo: false, enableSound: true, baseRate: FastSettings.playingVideoRate, fetchAutomatically: false, volume: FastSettings.volumeRate, initialQuality: FastSettings.videoQuality)
    } else {
        player = NativeMediaPlayer(postbox: account.postbox, reference: reference, fetchAutomatically: fetchAutomatically)
    }
    return player
}

enum SVideoStyle {
    case regular
    case pictureInPicture
}



class SVideoController: GenericViewController<SVideoView>, PictureInPictureControl {
    private(set) var enhancedInput: PlayerInputController?
    private(set) var enhancedPresentation: PlayerPresentation = .gallery
    var enhancedInitialPresentation: PlayerPresentation = .mini
    var enhancedResumeOnGallery: Bool?
    private var enhancedRawStatus: MediaPlayerStatus?
    private var enhancedCurrentRate: Double = 1
    private var enhancedSettingsObserver: NSObjectProtocol?

    
    
   
    
    
    var style: SVideoStyle = .regular
    private var fullScreenWindow: Window?
    private var fullScreenRestoreState: (rect: NSRect, view: NSView)?
    private(set) var mediaPlayer: (UniversalVideoContentView & NSView)!
    private let reference: FileMediaReference
    private let statusDisposable = MetaDisposable()
    private let bufferingDisposable = MetaDisposable()
    private let hideOnIdleDisposable = MetaDisposable()
    private let hideControlsDisposable = MetaDisposable()
    private let account: Account
    private let context: AccountContext
    private var pictureInPicture: Bool = false
    private var hideControls: ValuePromise<Bool> = ValuePromise(true, ignoreRepeated: true)
    private var controlsIsHidden: Bool = false
    var togglePictureInPictureImpl:((Bool, PictureInPictureControl)->Void)?
    
    private var isPaused: Bool = true
    private var forceHiddenControls: Bool = false
    private var _videoFramePreview: MediaPlayerFramePreview?
    private var mode: PictureInPictureControlMode = .normal
    
    private var updateControls: SwiftSignalKit.Timer?
    
    private var videoFramePreview: MediaPlayerFramePreview? {
        if let videoFramePreview = _videoFramePreview {
            return videoFramePreview
        } else {
            let qualityState = self.genericView.mediaPlayer.videoQualityState()
            if let qualityState = qualityState, !qualityState.available.isEmpty {
                if let minQuality = HLSVideoContent.minimizedHLSQuality(file: reference)?.file {
                    self._videoFramePreview = MediaPlayerFramePreview(postbox: account.postbox, fileReference: minQuality)
                } else {
                    _videoFramePreview = nil
                }
            } else {
                self._videoFramePreview = MediaPlayerFramePreview(postbox: account.postbox, fileReference: reference)
            }
        }
        return _videoFramePreview
    }
    
    
    func setMode(_ mode: PictureInPictureControlMode, animated: Bool) {
        genericView.setMode(mode, animated: animated)
        self.mode = mode
    }
    
    private var scrubbingFrame = Promise<MediaPlayerFramePreviewResult?>(nil)
    private var scrubbingFrames = false
    private var scrubbingFrameDisposable: Disposable?
    private let isProtected: Bool
    private let isControlsLimited: Bool
    private let message: Message?
    
    private let partDisposable = MetaDisposable()
    
    private let mediaPlaybackStateDisposable = MetaDisposable()
    
    private var endPlaybackId: Int?
    
    private var adContext: AdMessagesHistoryContext?
    private let adStateDisposable = MetaDisposable()
    private let nextAdDisposable = MetaDisposable()

    init(context: AccountContext, reference: FileMediaReference, message: Message?, fetchAutomatically: Bool = false, isProtected: Bool = false, isControlsLimited: Bool = false) {
        self.reference = reference
        self.account = context.account
        self.isProtected = isProtected
        self.isControlsLimited = isControlsLimited
        self.message = message
        self.context = context
        super.init()
        bar = .init(height: 0)
    }
    
    var status: Signal<MediaPlayerStatus, NoError> {
        return mediaPlayer.status
    }
    
    func play(_ startTime: TimeInterval? = nil) {
        mediaPlayer.play()
        self.isPaused = false
        if let startTime = startTime, startTime > 0 {
            mediaPlayer.seek(startTime)
        }
    }
    
    func setBaseRate(_ baseRate: Double) {
        enhancedInput?.endTemporarySpeed()
        playerSetRate(baseRate, persist: true)
    }
    
    func playOrPause() {
        self.isPaused = !self.isPaused
        mediaPlayer.togglePlayPause()
    }
    
    func pause() {
        self.isPaused = true
        mediaPlayer.pause()
    }
    
    func play() {
        self.isPaused = false
        self.play(nil)
    }
    
    
    func didEnter() {
        
    }
    
    func didExit() {
        
    }
    
    func isPlaying() -> Bool {
        return !self.isPaused
    }
    
    
    private func updateIdleTimer() {
        NSCursor.unhide()
        hideOnIdleDisposable.set((Signal<NoValue, NoError>.complete() |> delay(PlayerSettingsStore.shared.preferences.controlsHideDelay, queue: Queue.mainQueue())).start(completed: { [weak self] in
            guard let `self` = self else {return}
            let hide = !self.genericView.isInMenu && !self.genericView.insideControls && !contextMenuOnScreen()
            self.hideControls.set(hide)
            if !self.pictureInPicture, hide {
                NSCursor.hide()
            }
        }))
    }
    
    private func updateControlVisibility(_ isMouseUpOrDown: Bool = false) {
        
        
        if let rootView = genericView.superview?.superview {
            var hide = !genericView._mouseInside() && !rootView.isHidden && (NSEvent.pressedMouseButtons & (1 << 0)) == 0
            
           
            if !hide, (NSEvent.pressedMouseButtons & (1 << 0)) != 0 {
                hide = genericView.controlsStyle.isPip
            }

            
            if self.fullScreenWindow != nil && isMouseUpOrDown, !genericView.insideControls {
                hide = true
                if !self.isPaused {
                    if !contextMenuOnScreen() {
                        NSCursor.hide()
                    }
                }
            }
            if contextMenuOnScreen() {
                hide = false
            }
            hideControls.set(hide || forceHiddenControls)
        } else {
            hideControls.set(forceHiddenControls)
        }
    }
    
    
    
    private func setHandlersOn(window: Window) {
        
        updateIdleTimer()
        
        let account = self.account
        
        let mouseInsidePlayer = genericView.mediaPlayer._mouseInside()
        
        hideControls.set(!mouseInsidePlayer || forceHiddenControls)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            if let window = self?.genericView.window, let contentView = window.contentView {
                let point = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if contentView.hitTest(point) != nil {
                    self?.updateControlVisibility()
                }
            }
            self?.updateIdleTimer()
            return .rejected
        }, with: self, for: .mouseMoved, priority: .modal)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            if let window = self?.genericView.window, let contentView = window.contentView {
                let point = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if contentView.hitTest(point) != nil {
                    self?.updateControlVisibility()
                }
            }
            self?.updateIdleTimer()
            return .rejected
        }, with: self, for: .mouseExited, priority: .modal)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            self?.updateIdleTimer()
            
            return .rejected
        }, with: self, for: .leftMouseDragged, priority: .modal)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            if let window = self?.genericView.window, let contentView = window.contentView {
                let point = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if contentView.hitTest(point) != nil {
                    self?.updateControlVisibility()
                }
            }
            self?.updateIdleTimer()
            return .rejected
        }, with: self, for: .mouseEntered, priority: .modal)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            if self?.genericView.mediaPlayer._mouseInside() == true {
                self?.updateControlVisibility(true)
            }
            self?.updateIdleTimer()
            return .rejected
        }, with: self, for: .leftMouseDown, priority: .modal)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            guard let `self` = self else {return .rejected}
            if let window = self.genericView.window, let contentView = window.contentView {
                let point = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if contentView.hitTest(point) != nil {
                    self.updateControlVisibility(true)
                }
            }
            self.updateIdleTimer()
            return self.genericView.enhancedFinishControlDrag(with: event) ? .invoked : .rejected
        }, with: self, for: .leftMouseUp, priority: .modal)
        
//        self.updateControls = SwiftSignalKit.Timer(timeout: 2.0, repeat: true, completion: { [weak self] in
//            self?.updateControlVisibility()
//        }, queue: .mainQueue())
//
//        self.updateControls?.start()
        
    }
    
    private var assertionID: IOPMAssertionID = 0
    private var success: IOReturn?
    
    private func disableScreenSleep() -> Bool? {
        guard success == nil else { return nil }
        success = IOPMAssertionCreateWithName( kIOPMAssertionTypeNoDisplaySleep as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "Video Playing" as CFString,
                                               &assertionID )
        return success == kIOReturnSuccess
    }
    
    private func  enableScreenSleep() -> Bool {
        if success != nil {
            success = IOPMAssertionRelease(assertionID)
            success = nil
            return true
        }
        return false
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        enhancedInput?.activate()
      
        if let window = window {
            setHandlersOn(window: window)
        }
        playerShowControls(true)
        updateIdleTimer()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if enhancedPresentation == .gallery { enhancedInput?.deactivate() }
        hideOnIdleDisposable.set(nil)
        _ = enableScreenSleep()
        NSCursor.unhide()
        window?.removeAllHandlers(for: self)
        
    }
    
    var isPictureInPicture: Bool {
        return self.pictureInPicture
    }
    
    
    func hideControlsIfNeeded(_ forceHideControls: Bool = false) -> Bool {
        self.forceHiddenControls = forceHideControls
        if !controlsIsHidden {
            hideControls.set(true)
            return true
        }
        
        return false
    }
    
    func unhideControlsIfNeeded(_ forceUnhideControls: Bool = true) -> Bool {
        forceHiddenControls = !forceUnhideControls
        if controlsIsHidden {
            hideControls.set(false)
            return true
        }
        return false
    }
    
    private func runAdMessages(_ messages: [Message], _ startDelay: Int32, _ betweenDelay: Int32?) {
        
        let context = self.context
        
        var makeNext:((Message, Bool)->Void)? = nil
        
        let arguments = SVideoAdsArguments(context: context, removeAd: { [weak self] current, all, intime in
            guard let window = self?.window else {
                return
            }
            if !intime {
                makeNext?(current, true)
            } else {
                if context.isPremium {
                    if all {
                        _ = context.engine.accountData.updateAdMessagesEnabled(enabled: false).startStandalone()
                        self?.genericView.set(adMessage: nil, arguments: nil, animated: true)
                    }
                    showModalText(for: window, text: strings().chatDisableAdTooltip)
                } else {
                    prem(with: PremiumBoardingController(context: context, source: .no_ads, openFeatures: true), for: window)
                }
            }
        }, maybeNext: { current in
            makeNext?(current, true)
        }, markAsSeen: { [weak self] current in
            if let adAttribute = current.adAttribute {
                self?.adContext?.markAsSeen(opaqueId: adAttribute.opaqueId)
            }
        }, invoke: { [weak self] current in
            if let adAttribute = current.adAttribute {
                self?.adContext?.markAction(opaqueId: adAttribute.opaqueId, media: true, fullscreen: true)
                let link = inApp(for: adAttribute.url.nsstring, context: context, peerId: nil, openInfo: { peerId, toChat, messageId, initialAction in
                    getGalleryViewer()?.openInfo(peerId, toChat, messageId, initialAction)
                }, hashtag: nil, command: nil, applyProxy: nil, confirm: false)
                execute(inapp: link)
            }
        })
        
        makeNext = { [weak self, weak arguments] current, remove in
            guard let arguments else {
                return
            }
            let index = messages.firstIndex(where: { $0 == current })
            if let index, index < messages.count - 1 {
                if remove {
                    self?.genericView.set(adMessage: nil, arguments: nil, animated: true)
                    self?.updateControlVisibility()
                }
                if let betweenDelay {
                    self?.nextAdDisposable.set(delaySignal(Double(betweenDelay)).start(completed: {
                        self?.genericView.set(adMessage: messages[index + 1], arguments: arguments, animated: true)
                    }))
                }
            } else {
                self?.genericView.set(adMessage: nil, arguments: nil, animated: true)
                self?.nextAdDisposable.set(nil)
            }
        }
        
        
        if let first = messages.first {
            self.genericView.set(adMessage: first, arguments: arguments, animated: true)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        enhancedInput = PlayerInputController(target: self)
        enhancedCurrentRate = PlayerSettingsStore.shared.preferences.rememberSpeed ? FastSettings.playingVideoRate : 1
        mediaPlayer.setBaseRate(enhancedCurrentRate)
        genericView.enhancedAction = { [weak self] action in self?.enhancedInput?.perform(action) }
        genericView.enhancedIsFloating = { [weak self] in (self?.enhancedPresentation ?? .gallery) != .gallery }
        genericView.enhancedIsPinned = { enhancedFloatingIsPinned }
        genericView.enhancedMenuOpened = { [weak self] in self?.enhancedInput?.endTemporarySpeed() }
        genericView.enhancedRefreshSeekButtons()
        enhancedSettingsObserver = NotificationCenter.default.addObserver(forName: PlayerSettingsStore.didChange,
            object: nil, queue: .main) { [weak self] _ in self?.genericView.enhancedRefreshSeekButtons() }
        
        let account = self.account
        
        if isHLSVideo(file: reference.media) {
            let fetchSignal = HLSVideoContent.minimizedHLSQualityPreloadData(postbox: account.postbox, file: reference, userLocation: .other, prefixSeconds: 10, autofetchPlaylist: true, initialQuality: FastSettings.videoQuality)
            |> mapToSignal { fileAndRange -> Signal<Never, NoError> in
                guard let fileAndRange else {
                    return .complete()
                }
                return freeMediaFileResourceInteractiveFetched(postbox: account.postbox, userLocation: .other, fileReference: fileAndRange.0, resource: fileAndRange.0.media.resource, range: (fileAndRange.1, .default))
                |> ignoreValues
                |> `catch` { _ -> Signal<Never, NoError> in
                    return .complete()
                }
            }
            partDisposable.set(fetchSignal.start())
        } else {
            let preload = preloadVideoResource(postbox: account.postbox, userLocation: .other, userContentType: .init(file: reference.media), resourceReference: reference.resourceReference(reference.media.resource), duration: 3.0)
            partDisposable.set(preload.start())
        }
        
        if let message, let peer = message.peers[message.id.peerId], peer.isChannel {
            let adContext = context.engine.messages.adMessages(peerId: message.id.peerId, messageId: message.id)
            self.adContext = adContext
            
            var invoked: Bool = false
            
            adStateDisposable.set(combineLatest(queue:.mainQueue(), adContext.state, status).startStrict(next: { [weak self] values in
               
                let ( _, messages, startDelay, betweenDelay) = values.0
                let status = values.1
                
                if !messages.isEmpty, let startDelay, !invoked {
                    if Int32(status.timestamp) >= startDelay {
                        self?.runAdMessages(messages, startDelay, betweenDelay)
                        invoked = true
                    }
                }
            }))
        }


        
        genericView.layerContentsRedrawPolicy = .duringViewResize

        
        genericView.isControlsLimited = isControlsLimited
        
        
        genericView.isStreamable = reference.media.isStreamable
        hideControlsDisposable.set(hideControls.get().start(next: { [weak self] hide in
            self?.genericView.hideControls(hide, animated: true)
            self?.controlsIsHidden = hide
        }))
        
        
       
        
        let statusValue:Atomic<MediaPlayerStatus?> = Atomic(value: nil)
        let updateTemporaryStatus:(_ f: (MediaPlayerStatus?)->MediaPlayerStatus?) -> Void = { [weak self] f in
            self?.genericView.status = statusValue.modify(f)
        }
        
        let duration = Double(reference.media.duration ?? 0)
        // HLS/WKWebView startup is asynchronous. Use metadata immediately for
        // the timeline and menu without claiming any bytes are buffered.
        if genericView.status == nil {
            let initial = MediaPlayerStatus(generationTimestamp: 0, duration: duration,
                dimensions: reference.media.dimensions?.size ?? .zero, timestamp: 0,
                baseRate: enhancedCurrentRate, volume: FastSettings.volumeRate,
                seekId: 0, status: .buffering(initial: true, whilePlaying: false))
            _ = statusValue.swap(initial)
            genericView.status = initial
        }
        genericView.enhancedRefreshSeekButtons()
        genericView.updateLayout(size: genericView.bounds.size, transition: .immediate)
        
        statusDisposable.set((mediaPlayer.status |> deliverOnMainQueue).start(next: { [weak self] status in
            let status = status.withUpdatedDuration(status.duration != 0 ? status.duration : duration)
            switch status.status {
            case .playing:
                _ = self?.disableScreenSleep()
            case let .buffering(_, whilePlaying):
                if whilePlaying {
                    _ = self?.disableScreenSleep()
                } else {
                    _ = self?.enableScreenSleep()
                }
            case .paused:
                _ = self?.enableScreenSleep()
            }
            _ = statusValue.swap(status)
           
            self?.enhancedRawStatus = status
            let buffering: Bool
            if case .buffering = status.status { buffering = true } else { buffering = false }
            self?.enhancedInput?.observe(position: status.timestamp, generation: status.seekId, buffering: buffering)
            if let target = self?.enhancedInput?.pendingSeekPosition {
                self?.playerPreviewSeek(to: target)
            } else {
                self?.genericView.status = status
            }
            switch status.status {
            case .playing: self?.isPaused = false
            case .paused: self?.isPaused = true
            case let .buffering(_, whilePlaying): self?.isPaused = !whilePlaying
            }
        }))
        let size = reference.media.resource.size ?? 0
        
        let bufferingStatus = mediaPlayer.bufferingStatus |> deliverOnMainQueue
        
        bufferingDisposable.set(bufferingStatus.start(next: { [weak self] bufferingStatus in
            self?.genericView.bufferingStatus = bufferingStatus
        }))
        
        self.scrubbingFrameDisposable = (self.scrubbingFrame.get()
            |> deliverOnMainQueue).start(next: { [weak self] result in
                guard let `self` = self else {
                    return
                }
            let live = (NSEvent.pressedMouseButtons & (1 << 0)) != 0 && self.genericView.mouseDownIncontrols
                if let result = result {
                    self.genericView.showScrubblerPreviewIfNeeded(live: live)
                    self.genericView.setCurrentScrubblingState(result, live: live)
                } else {
                    self.genericView.hideScrubblerPreviewIfNeeded(live: live)
                    // empty image
                }
            })

        var paused: Bool? = nil
        
        genericView.interactions = SVideoInteractions(playOrPause: { [weak self] in
            self?.playOrPause()
        }, rewind: { [weak self] timestamp in
            self?.enhancedInput?.seek(to: timestamp)
        }, scrobbling: { [weak self] timecode in
            guard let `self` = self else { return }

            if let timecode = timecode, let videoFramePreview = self.videoFramePreview {
                if !self.scrubbingFrames {
                    self.scrubbingFrames = true
                    self.scrubbingFrame.set(videoFramePreview.generatedFrames
                        |> map(Optional.init))
                }
                videoFramePreview.generateFrame(at: timecode)
            } else {
                self.scrubbingFrame.set(.single(nil))
                self.videoFramePreview?.cancelPendingFrames()
                self.scrubbingFrames = false
            }
        }, volume: { [weak self] value in
            self?.mediaPlayer.setVolume(value)
            FastSettings.setVolumeRate(value)
            updateTemporaryStatus { status in
                return status?.withUpdatedVolume(value)
            }
        }, toggleFullScreen: { [weak self] in
            self?.toggleFullScreen()
        }, togglePictureInPicture: { [weak self] in
            self?.togglePictureInPicture()
        }, closePictureInPicture: {
            closePipVideo()
        }, setBaseRate: { [weak self] rate in
            self?.setBaseRate(rate)
        }, pause: { [weak self] in
            if self?.isPaused == false {
                self?.pause()
                paused = true
            }
        }, play: { [weak self] in
            if paused == true {
                self?.play()
                paused = nil
            }
        })
        
        if let duration = reference.media.duration, duration < 30 {
            endPlaybackId = mediaPlayer.addPlaybackCompleted { [weak self] in
                Queue.mainQueue().async {
                    self?.mediaPlayer.seek(0)
                    self?.mediaPlayer.play()
                    self?.updateIdleTimer()
                }
            }
        } else {
            endPlaybackId = mediaPlayer.addPlaybackCompleted { [weak self] in
                DispatchQueue.main.async {
                    if let duration = self?.mediaPlayer.duration, duration < 30 {
                        self?.mediaPlayer.seek(0)
                        self?.mediaPlayer.play()
                    }
                    self?.hideControls.set(false)
                    self?.updateIdleTimer()
                }
            }
        }
        
        
        if let message {
            let throttledSignal = self.mediaPlayer.status
            |> mapToThrottled { next -> Signal<MediaPlayerStatus, NoError> in
                return .single(next) |> then(.complete() |> delay(2.0, queue: Queue.concurrentDefaultQueue()))
            }
            
            self.mediaPlaybackStateDisposable.set(throttledSignal.startStrict(next: { status in
                if status.duration >= 10, case .playing = status.status {
                    let storedState = MediaPlaybackStoredState(timestamp: status.timestamp)
                    let _ = updateMediaPlaybackStoredStateInteractively(engine: TelegramEngine(account: account), messageId: message.id, state: storedState).startStandalone()
                }
            }))
        }
        


        
        
        readyOnce()
    }
    
    func togglePictureInPicture() {
        guard !isControlsLimited else { return }
        if enhancedPresentation != .gallery {
            enhancedChangeFloatingPresentation(enhancedPresentation == .mini ? .detached : .mini)
            return
        }
        if let function = togglePictureInPictureImpl {
            if fullScreenRestoreState != nil {
                toggleFullScreen()
            }
            self.pictureInPicture = true
            self.style = .pictureInPicture
            self.enhancedPresentation = enhancedInitialPresentation
            window?.removeAllHandlers(for: self)
            function(pictureInPicture, self)
            if let window = view.window?.contentView?.window as? Window {
                setHandlersOn(window: window)
            }
            
            genericView.set(isInPictureInPicture: enhancedPresentation == .mini)
        }
    }
    
    func togglePlayerOrPause() {
        playOrPause()
    }
    
    
    func rewindBackward() {
        enhancedInput?.perform(.seekBackward)
    }
    func rewindForward() {
        enhancedInput?.perform(.seekForward)
    }
    
    var isFullscreen: Bool {
        return self.fullScreenRestoreState != nil || (enhancedPresentation != .gallery && enhancedFloatingIsFullscreen)
    }
    
    func toggleFullScreen() {
        if enhancedPresentation != .gallery {
            enhancedToggleFloatingFullscreen()
            return
        }
        if PlayerSettingsStore.shared.preferences.enabled, fullScreenRestoreState == nil, togglePictureInPictureImpl != nil {
            enhancedInitialPresentation = .detached
            togglePictureInPicture()
            enhancedToggleFloatingFullscreen()
            return
        }
        if let screen = view.window?.screen ?? NSScreen.main {
            if let window = fullScreenWindow, let state = fullScreenRestoreState {
                
                var topInset: CGFloat = 0
                
                if #available(macOS 12.0, *) {
                    topInset = screen.safeAreaInsets.top
                }
                
                
                window.setFrame(NSMakeRect(screen.frame.minX + state.rect.minX, screen.frame.minY + screen.frame.height - state.rect.maxY - topInset, state.rect.width, state.rect.height), display: true, animate: true)
                window.orderOut(nil)
                view.frame = state.rect
                state.view.addSubview(view)
                
                genericView.set(isInFullScreen: false)
                mediaPlayer.setVideoLayerGravity(.resizeAspectFill)

                
                window.removeAllHandlers(for: self)
                if let window = self.window {
                    setHandlersOn(window: window)
                }
                
                self.fullScreenWindow = nil
                self.fullScreenRestoreState = nil
            } else {
                
                mediaPlayer.setVideoLayerGravity(.resizeAspect)

                
                fullScreenRestoreState = (rect: view.frame, view: view.superview!)
                fullScreenWindow = Window(contentRect: NSMakeRect(view.frame.minX, screen.frame.height - view.frame.maxY, view.frame.width, view.frame.height), styleMask: [.fullSizeContentView, .borderless], backing: .buffered, defer: true, screen: screen)
                
                setHandlersOn(window: fullScreenWindow!)
                window?.removeAllHandlers(for: self)
                
                
                fullScreenWindow?.isOpaque = true
                fullScreenWindow?.hasShadow = false
                fullScreenWindow?.level = .screenSaver
                self.view.frame = self.view.bounds
                fullScreenWindow?.contentView?.addSubview(self.view)
                fullScreenWindow?.orderFront(nil)
                genericView.set(isInFullScreen: true)
                fullScreenWindow?.becomeKey()
                fullScreenWindow?.setFrame(screen.frame, display: true, animate: true)
            }
        }
    }
    
    override func initializer() -> SVideoView {
        mediaPlayer = makePlayer(account: account, reference: reference)
        return SVideoView(frame: _frameRect, mediaPlayer: self.mediaPlayer)
    }
    
    deinit {
        enhancedInput?.deactivate()
        if let observer = enhancedSettingsObserver { NotificationCenter.default.removeObserver(observer) }
        statusDisposable.dispose()
        bufferingDisposable.dispose()
        hideOnIdleDisposable.dispose()
        hideControlsDisposable.dispose()
        mediaPlaybackStateDisposable.dispose()
        adStateDisposable.dispose()
        nextAdDisposable.dispose()
        partDisposable.dispose()
        if let endPlaybackId {
            mediaPlayer.removePlaybackCompleted(endPlaybackId)
        }
        updateControls?.invalidate()
        _ = IOPMAssertionRelease(assertionID)
    }
    
}


extension SVideoController: PlayerCommandTarget {
    var playerView: NSView { genericView }
    var playerPresentation: PlayerPresentation { enhancedPresentation }
    var playerInputAllowed: Bool {
        return !isControlsLimited && genericView.enhancedPlaybackControlsAllowed
    }
    var playerKeyboardAllowed: Bool {
        return playerInputAllowed && !genericView.isInMenu && !contextMenuOnScreen()
            && !((view.window as? Window).map { hasModals($0) } ?? false)
    }
    var playerSnapshot: PlayerSnapshot {
        let status = enhancedRawStatus ?? genericView.status
        var position = status?.timestamp ?? 0
        if let status = status, case .playing = status.status, status.generationTimestamp > 0 {
            position += max(0, CACurrentMediaTime() - status.generationTimestamp) * status.baseRate
            position = min(position, status.duration)
        }
        return PlayerSnapshot(position: position, duration: status?.duration ?? Double(reference.media.duration ?? 0),
                              volume: Double(genericView.status?.volume ?? FastSettings.volumeRate),
                              rate: enhancedCurrentRate, playing: !isPaused, seekGeneration: status?.seekId ?? 0)
    }
    func playerPreviewSeek(to timestamp: Double) {
        guard let status = enhancedRawStatus ?? genericView.status else { return }
        genericView.status = MediaPlayerStatus(generationTimestamp: 0, duration: status.duration,
            dimensions: status.dimensions, timestamp: timestamp, baseRate: enhancedCurrentRate,
            volume: status.volume, seekId: status.seekId, status: status.status)
    }
    func playerSeek(to timestamp: Double) {
        guard playerInputAllowed, timestamp.isFinite else { return }
        mediaPlayer.seek(max(0, min(timestamp, playerSnapshot.duration)))
    }
    func playerSetVolume(_ volume: Double) {
        guard volume.isFinite else { return }
        let value = Float(max(0, min(1, volume)))
        mediaPlayer.setVolume(value)
        FastSettings.setVolumeRate(value)
        genericView.status = genericView.status?.withUpdatedVolume(value)
    }
    func playerSetRate(_ rate: Double, persist: Bool) {
        guard rate.isFinite else { return }
        enhancedCurrentRate = max(0.25, min(2.5, rate))
        mediaPlayer.setBaseRate(enhancedCurrentRate)
        if persist && PlayerSettingsStore.shared.preferences.rememberSpeed {
            FastSettings.setPlayingVideoRate(enhancedCurrentRate)
        }
    }
    func playerCanHandleMouse(at point: NSPoint) -> Bool {
        return genericView.enhancedCanHandleMouse(at: point)
    }
    func playerShowControls(_ show: Bool) {
        if !show && (genericView.insideControls || genericView.isInMenu) { return }
        forceHiddenControls = false
        hideControls.set(!show)
    }
    func enhancedSetPresentation(_ presentation: PlayerPresentation) {
        enhancedInput?.activate()
        enhancedPresentation = presentation
        pictureInPicture = presentation != .gallery
        style = pictureInPicture ? .pictureInPicture : .regular
        genericView.setMode(presentation == .mini ? .pip : .normal, animated: false)
        genericView.set(isInPictureInPicture: presentation == .mini)
        genericView.set(isInFullScreen: false)
        mediaPlayer.setVideoLayerGravity(.resizeAspect)
        if let window = view.window as? Window { setHandlersOn(window: window) }
        if presentation == .gallery { enhancedInitialPresentation = .mini }
    }
    func playerPerform(_ action: PlayerAction) {
        switch action {
        case .playPause:
            if enhancedPresentation != .gallery { enhancedFloatingUserInteracted() }
            playOrPause()
        case .fullscreen: toggleFullScreen()
        case .pictureInPicture:
            enhancedInitialPresentation = .mini
            togglePictureInPicture()
        case .detach:
            if enhancedPresentation == .detached { exitPictureInPicture() }
            else if enhancedPresentation == .mini { enhancedChangeFloatingPresentation(.detached) }
            else { enhancedInitialPresentation = .detached; togglePictureInPicture() }
        case .pin:
            if enhancedPresentation == .gallery {
                enhancedInitialPresentation = .detached; togglePictureInPicture()
            }
            enhancedToggleFloatingPin()
        case .previous, .next:
            if enhancedPresentation == .gallery { getGalleryViewer()?.enhancedNavigate(forward: action == .next) }
            else { enhancedInput?.show(playerText("请先返回媒体浏览器", "Return to the gallery to browse media")) }
        case .escape:
            if isFullscreen { toggleFullScreen() }
            else if enhancedPresentation != .gallery { exitPictureInPicture() }
            else { closeGalleryViewer(true) }
        case .settings: showPlayerSettings(for: (view.window as? Window) ?? context.window)
        default: break
        }
    }
}
