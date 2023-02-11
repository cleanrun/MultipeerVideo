//
//  VideoPlayerWC.swift
//  MultipeerVideo-Mac
//
//  Created by cleanmac on 11/02/23.
//

import Cocoa
import AVKit

final class VideoPlayerWC: NSWindowController {

    @IBOutlet weak var playerView: AVPlayerView!
    
    private var player: AVPlayer!
    private var fileUrl: URL!
    
    override var windowNibName: String! {
        return "VideoPlayerWC"
    }
    
    init(from url: URL) {
        self.fileUrl = url
        self.player = AVPlayer(url: fileUrl)
        super.init(window: nil)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        playerView.player = player
        player.play()
    }
}
