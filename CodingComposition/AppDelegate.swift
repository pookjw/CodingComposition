//
//  AppDelegate.swift
//  CodingComposition
//
//  Created by Jinwoo Kim on 12/16/23.
//

import Cocoa

@main
struct CodingComposition {
    static func main() {
        let application: NSApplication = .shared
        let delegate: AppDelegate = .init()
        application.delegate = delegate
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let window: NSWindow = .init(
            contentRect: .init(x: .zero, y: .zero, width: 1280.0, height: 720.0),
            styleMask: [.closable, .resizable, .titled],
            backing: .buffered,
            defer: true
        )
        
        let viewController: ViewController = .init()
        
        window.contentViewController = viewController
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(self)
    }
}
