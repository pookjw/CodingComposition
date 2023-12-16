//
//  ViewController.swift
//  CodingComposition
//
//  Created by Jinwoo Kim on 12/16/23.
//

import Cocoa
import AVKit
import UniformTypeIdentifiers

@MainActor
final class ViewController: NSViewController {
    private var task: Task<Void, Never>?
    
    deinit {
        task?.cancel()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        task = .init { [unowned self] in
            do {
                let resourcesURL: URL = try await self.resourcesURL()
                try Task.checkCancellation()
                try await self.copySampleVideos(to: resourcesURL)
                try Task.checkCancellation()
                let composition: AVComposition = try await self.composition(resourcesURL: resourcesURL)
                try Task.checkCancellation()
                let playerView: AVPlayerView = self.playerView()
                
                let playerItem: AVPlayerItem = .init(asset: composition)
                let player: AVPlayer = .init(playerItem: playerItem)
                playerView.player = player
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }
    
    private nonisolated func resourcesURL() async throws -> URL {
//        UserDefaults.standard.removeObject(forKey: "bookmarkData")
        
        var bookmarkDataIsStale: Bool = false
        
        if
            let bookmarkData: Data = UserDefaults
                .standard
                .data(forKey: "bookmarkData"),
            let bookmarkURL: URL = try! .init(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &bookmarkDataIsStale
            ),
            !bookmarkDataIsStale
        {
            return bookmarkURL
        } else {
            var observation: NSKeyValueObservation?
            var continuation: CheckedContinuation<URL, Error>?
            let onCancel: () -> Void = {
                observation?.invalidate()
                continuation?.resume(with: .failure(CancellationError()))
            }
            
            return try await withTaskCancellationHandler {
                let view: NSView = await MainActor.run { self.view }
                
                let result: URL = try await withCheckedThrowingContinuation { _continuation in
                    continuation = _continuation
                    
                    observation = view.observe(\.window, options: [.initial, .new]) { [weak self] view, changes in
                        if (changes.newValue ?? nil) != nil {
                            Task { @MainActor [weak self] in
                                guard
                                    view.window != nil,
                                    let self
                                else {
                                    _continuation.resume(with: .failure(CancellationError()))
                                    return
                                }
                                
                                let result: URL = self
                                    .requestUserSelectedURL()
                                
                                do {
                                    let bookmarkData: Data = try result.bookmarkData(
                                        options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil
                                    )
                                    
                                    UserDefaults.standard.setValue(bookmarkData, forKey: "bookmarkData")
                                    
                                    _continuation.resume(with: .success(result))
                                } catch {
                                    _continuation.resume(with: .failure(error))
                                }
                            }
                        }
                    }
                }
                
                observation?.invalidate()
                return result
            } onCancel: {
                onCancel()
            }
        }
    }
    
    private func requestUserSelectedURL() -> URL {
        let openPanel: NSOpenPanel = .init()
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Resources will be copied here."
        
        let response: NSApplication.ModalResponse = openPanel.runModal()
        
        guard
            response == .OK,
            let url: URL = openPanel.url
        else {
            return requestUserSelectedURL()
        }
        
        return url
    }
    
    private nonisolated func copySampleVideos(to url: URL) async throws {
        assert(url.startAccessingSecurityScopedResource())
        
        do {
            let sampleVideoURLs: [URL] = Bundle.main.urls(forResourcesWithExtension: UTType.mpeg4Movie.preferredFilenameExtension, subdirectory: nil)!
            
            for sampleVideoURL in sampleVideoURLs {
                try Task.checkCancellation()
                
                let destinationURL: URL = url.appending(component: sampleVideoURL.lastPathComponent, directoryHint: .notDirectory)
                
                guard !FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) else {
                    continue
                }
                
                try FileManager.default.copyItem(at: sampleVideoURL, to: destinationURL)
            }
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw error
        }
    }
    
    private nonisolated func composition(resourcesURL: URL) async throws -> AVComposition {
//        UserDefaults.standard.removeObject(forKey: "composition")
        
        if let data: Data = UserDefaults.standard.data(forKey: "composition") {
            let composition: AVComposition = try NSKeyedUnarchiver.unarchivedObject(ofClass: AVComposition.self, from: data)!
            return composition
        }
        
        let mutableComposition: AVMutableComposition = .init()
        mutableComposition.naturalSize = .init(width: 1280.0, height: 720.0)
        
        let mainVideoTrack: AVMutableCompositionTrack = mutableComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        
        assert(resourcesURL.startAccessingSecurityScopedResource())
        do {
            let urls: [URL] = try FileManager.default.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil)
            
            for url in urls {
                let avAsset: AVAsset = .init(url: url)
                let tracks: [AVAssetTrack] = try await avAsset.load(.tracks)
                
                for track in tracks {
                    let timeRange: CMTimeRange = try await track.load(.timeRange)
                    
                    switch track.mediaType {
                    case .video:
                        try mainVideoTrack.insertTimeRange(timeRange, of: track, at: mainVideoTrack.timeRange.duration)
                    default:
                        break
                    }
                }
            }
        } catch {
            resourcesURL.stopAccessingSecurityScopedResource()
            throw error
        }
        
        let composition: AVComposition = mutableComposition.copy() as! AVComposition
        let data: Data = try NSKeyedArchiver.archivedData(withRootObject: composition, requiringSecureCoding: false)
        UserDefaults.standard.setValue(data, forKey: "composition")
        
        return composition
    }
    
    private func playerView() -> AVPlayerView {
        let playerView: AVPlayerView = .init(frame: view.bounds)
        playerView.autoresizingMask = [.width, .height]
        view.addSubview(playerView)
        return playerView
    }
}
