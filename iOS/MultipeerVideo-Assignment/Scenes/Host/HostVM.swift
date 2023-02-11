//
//  HostVM.swift
//  MultipeerVideo-Assignment
//
//  Created by cleanmac on 16/01/23.
//

import Foundation
import Combine
import MultipeerConnectivity
import AVKit

enum RecordingState: String {
    case notRecording
    case isRecording
    case finishedRecording
}

final class HostVM: NSObject, ObservableObject {
    private let serviceType = "video-peer"
    private let peerId = MCPeerID(displayName: UIDevice.current.name)
    private let peerBrowser: MCNearbyServiceBrowser
    private let peerSession: MCSession
    private let peerBrowserVc: MCBrowserViewController
    
    private weak var viewController: HostVC?
    
    let fileUrl = FileManager.default.urls(for: .documentDirectory,
                                           in: .userDomainMask)[0]
        .appendingPathComponent("output.mov")
    
    @Published private(set) var connectedPeers: [MCPeerID] = []
    @Published private(set) var recordingState: RecordingState = .notRecording
    
    init(viewController: HostVC) {
        peerSession = MCSession(peer: peerId,
                                securityIdentity: nil,
                                encryptionPreference: .none)
        peerBrowser = MCNearbyServiceBrowser(peer: peerId,
                                             serviceType: serviceType)
        peerBrowserVc = MCBrowserViewController(serviceType: serviceType,
                                                session: peerSession)
        
        self.viewController = viewController
        
        super.init()
        
        peerSession.delegate = self
        peerBrowser.delegate = self
        peerBrowserVc.delegate = self
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
    
    private func getVideoResolutionAndSize() -> (CGSize?, String?) {
        guard let videoAsset = AVURLAsset(url: fileUrl).tracks(withMediaType: .video).first,
              let videoData = try? Data(contentsOf: fileUrl)
        else {
            return (nil, nil)
        }
        
        let dimensions = videoAsset.naturalSize.applying(videoAsset.preferredTransform)
        let dimensionSize = CGSize(width: abs(dimensions.width), height: abs(dimensions.height))
        let videoSize = ByteCountFormatter().string(fromByteCount: Int64(videoData.count))
        return (dimensionSize, videoSize)
    }
    
    func showVideoResolutionAlert() {
        let size = getVideoResolutionAndSize()
        let message = (size.0 == nil && size.1 == nil) ? "Video not found" : "Width: \(size.0!.width)\nHeight: \(size.0!.height)\nSize: \(size.1!)"
        
        let alert = UIAlertController(title: "Video resolution",
                                      message: message,
                                      preferredStyle: .alert)
        let action = UIAlertAction(title: "OK", style: .cancel)
        alert.addAction(action)
        viewController?.present(alert, animated: true)
    }
    
    func showPeerBrowserModal() {
        viewController?.present(peerBrowserVc, animated: true)
    }
    
    func showVideoPlayer(from url: URL ) {
        DispatchQueue.main.async { [unowned self] in
            let player = AVPlayer(url: url)
            let vc = AVPlayerViewController()
            vc.player = player
            self.viewController?.present(vc, animated: true) {
                player.play()
            }
        }
    }
    
    private func setPreviewVideo(from stream: InputStream) {
        let bufferSize = 32768
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        DispatchQueue.global(qos: .background).async { [unowned self] in
            let numberBytes = stream.read(&buffer, maxLength: bufferSize)
            let data = Data(referencing: NSData(bytes: &buffer, length: numberBytes))
            if let imageData = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.viewController?.previewCameraView.layer.contents = imageData.cgImage
                }
            }
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
            showVideoPlayer(from: fileUrl)
            changeRecordingState()
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func session(_ session: MCSession,
                 didReceive stream: InputStream,
                 withName streamName: String,
                 fromPeer peerID: MCPeerID) {
        stream.delegate = self
        stream.schedule(in: RunLoop.main, forMode: .default)
        stream.open()
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
        browserViewController.dismiss(animated: true)
    }
    
    func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        browserViewController.dismiss(animated: true)
    }
}

extension HostVM: StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            setPreviewVideo(from: aStream as! InputStream)
        case .hasSpaceAvailable:
            break
        default:
            break
        }
    }
}
