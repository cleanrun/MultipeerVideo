//
//  HostVM.swift
//  MultipeerVideo-Mac
//
//  Created by cleanmac on 11/02/23.
//

import Foundation
import Combine
import MultipeerConnectivity

enum RecordingState: String {
    case notRecording
    case isRecording
    case finishedRecording
}

final class HostVM: NSObject, ObservableObject {
    private let serviceType = "video-peer"
    private let peerId = MCPeerID(displayName: ProcessInfo.processInfo.userName)
    private let peerBrowser: MCNearbyServiceBrowser
    private let peerSession: MCSession
    private let peerBrowserVc: MCBrowserViewController
    
    private weak var viewController: HostVC?
    
    let fileUrl = FileManager.default.urls(for: .documentDirectory,
                                           in: .userDomainMask)[0]
        .appendingPathComponent("output.mov")
    
    @Published private(set) var connectedPeers = [MCPeerID]()
    @Published private(set) var recordingState: RecordingState = .notRecording
    
    init(viewController: HostVC) {
        peerSession = MCSession(peer: peerId,
                                securityIdentity: nil,
                                encryptionPreference: .none)
        peerBrowser = MCNearbyServiceBrowser(peer: peerId,
                                             serviceType: serviceType)
        peerBrowserVc = MCBrowserViewController(serviceType: serviceType,
                                                session: peerSession)
        peerBrowserVc.maximumNumberOfPeers = 1
        
        self.viewController = viewController
        
        super.init()
        
        peerSession.delegate = self
        peerBrowser.delegate = self
        peerBrowserVc.delegate = self
    }
    
    func disconnectPeer() {
        peerSession.disconnect()
        connectedPeers.removeAll()
    }
    
    func changeRecordingState() {
        do {
            if recordingState == .notRecording {
                recordingState = .isRecording
            } else if recordingState == .isRecording {
                recordingState = .finishedRecording
            } else {
                recordingState = .notRecording
            }
            
            try peerSession.send(recordingState.rawValue.data(using: .utf8)!,
                                 toPeers: connectedPeers,
                                 with: .reliable)
        } catch {
            print(error.localizedDescription)
            recordingState = .notRecording
        }
    }
    
    func showPeerBrowsermodal() {
        viewController?.presentAsSheet(peerBrowserVc)
    }
    
    func showVideoPlayer() {
        DispatchQueue.main.async { [unowned self] in
            let videoPlayerWindow = VideoPlayerWC(from: fileUrl)
            videoPlayerWindow.showWindow(viewController)
        }
    }
    
    
}

extension HostVM: MCSessionDelegate {
    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        connectedPeers = session.connectedPeers
    }
    
    func session(_ session: MCSession,
                 didReceive data: Data,
                 fromPeer peerID: MCPeerID) {
        try? FileManager.default.removeItem(at: fileUrl)
        do {
            try data.write(to: fileUrl)
            showVideoPlayer()
            changeRecordingState()
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func session(_ session: MCSession,
                 didReceive stream: InputStream,
                 withName streamName: String,
                 fromPeer peerID: MCPeerID) {
        // FIXME: Implement stream handler
    }
    
    func session(_ session: MCSession,
                 didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 with progress: Progress) {
        
    }
    
    func session(_ session: MCSession,
                 didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 at localURL: URL?,
                 withError error: Error?) {
        
    }
    
}

extension HostVM: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String : String]?) {
        
    }
    
    func browser(_ browser: MCNearbyServiceBrowser,
                 lostPeer peerID: MCPeerID) {
        
    }
    
    
}

extension HostVM: MCBrowserViewControllerDelegate {
    func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        viewController?.dismiss(browserViewController)
    }
    
    func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        viewController?.dismiss(browserViewController)
    }
}
