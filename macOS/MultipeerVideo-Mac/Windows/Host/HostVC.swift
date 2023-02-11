//
//  HostVC.swift
//  MultipeerVideo-Mac
//
//  Created by cleanmac on 11/02/23.
//

import Cocoa
import Combine

final class HostVC: NSViewController {
    
    @IBOutlet weak var connectionStatusLabel: NSTextField!
    @IBOutlet weak var connectButton: NSButton!
    @IBOutlet weak var seeVideoButton: NSButton!
    @IBOutlet weak var recordButton: NSButton!
    @IBOutlet weak var cameraPreviewView: NSView!
    
    private var viewModel: HostVM!
    private var disposables = Set<AnyCancellable>()
    
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel = HostVM(viewController: self)
        setupBindings()
    }
    
    private func setupBindings() {
        viewModel
            .$connectedPeers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard !value.isEmpty else {
                    self?.connectionStatusLabel.isHidden = true
                    self?.recordButton.isHidden = true
                    self?.connectButton.title = "Connect"
                    return
                }
                
                let peers = String(describing: value.map { $0.displayName })
                self?.connectionStatusLabel.isHidden = false
                self?.connectionStatusLabel.stringValue = "Connected to: \(peers)"
                self?.recordButton.isHidden = false
                self?.connectButton.title = "Disconnect"
            }.store(in: &disposables)
        
        viewModel
            .$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.recordButton.title = value == .isRecording ? "Stop Recording" : "Start Recording"
            }.store(in: &disposables)
    }
    
    @IBAction private func buttonActions(_ sender: NSButton) {
        if sender == connectButton {
            if viewModel.connectedPeers.isEmpty {
                viewModel.showPeerBrowsermodal()
            } else {
                viewModel.disconnectPeer()
            }
        } else if sender == recordButton {
            if viewModel.recordingState != .finishedRecording {
                viewModel.changeRecordingState()
            }
        } else if sender == seeVideoButton {
            viewModel.showVideoPlayer()
        }
    }

}
