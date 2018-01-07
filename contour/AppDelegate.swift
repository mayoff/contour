//
//  AppDelegate.swift
//  contour
//
//  Created by Rob Mayoff on 1/7/18.
//  Copyright © 2018 Rob Mayoff. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!
    @IBOutlet var rectsView: RectsView!

    @IBAction func resetButtonWasClicked(_ sender: Any) {
        rectsView.rects = []
    }

    @IBAction func redrawButtonWasClicked(_ sender: Any) {
        rectsView.markUnionPathDirty()
    }

    @IBAction func copySourceCodeButtonWasClicked(_ sender: Any) {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(rectsView.rects)
        let string = String(data: data, encoding: .utf8)!
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

class RectsView: NSView {

    required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)

        wantsLayer = true
        layer!.backgroundColor = NSColor.white.cgColor

        observers.append(UserDefaults.standard.observe(\UserDefaults.rectInset) { [weak self] (_, _) in
            self?.markUnionPathDirty()
        })
        observers.append(UserDefaults.standard.observe(\UserDefaults.cornerRadius) { [weak self] (_, _) in
            self?.markUnionPathDirty()
        })
    }

    private static let defaultRectsJson = "[[[65,26],[80,197]],[[37,145],[271,43]],[[230,67],[94,137]],[[119,48],[140,57]]]"
//    private static let defaultRectsJson = "[[[17,60],[49,53]],[[40,39],[51,48]]]"

    var rects: [CGRect] = {
        let data = RectsView.defaultRectsJson.data(using: .utf8)!
        let decoder = JSONDecoder()
        return try! decoder.decode([CGRect].self, from: data)
    }() {
        didSet { markUnionPathDirty() }
    }

    var fillColor: NSColor = NSColor.selectedTextBackgroundColor {
        didSet { needsDisplay = true }
    }

    var strokeColor: NSColor = .black {
        didSet { needsDisplay = true }
    }

    var unionPath: CGPath {
        if let cached = cachedUnionPath { return cached }
        let rects: [CGRect]
        if let rectBeingDragged = rectBeingDragged {
            rects = self.rects + [rectBeingDragged.standardized]
        } else {
            rects = self.rects
        }
        let inset = UserDefaults.standard.rectInset
        let path = CGPath.makeUnion(of: rects.map({ $0.insetBy(dx: inset, dy: inset) }), cornerRadius: UserDefaults.standard.cornerRadius)
        cachedUnionPath = path
        return path
    }

    func markUnionPathDirty() {
        cachedUnionPath = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        fillColor.set()
        let gc = NSGraphicsContext.current!.cgContext
        gc.addPath(unionPath)
        gc.fillPath()

        strokeColor.set()
        let lineWidth: CGFloat = 1
        gc.setLineWidth(lineWidth)
        rects.forEach { gc.stroke($0.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)) }
        if let rect = rectBeingDragged {
            gc.stroke(rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let origin = event.location(in: self)?.rounded else { return }
        var size: CGSize = .zero
        rectBeingDragged = CGRect(origin: origin, size: size)

        window!.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTrackingRunLoopMode) { (event, outStop) in
            guard let event = event else { outStop.pointee = true; return }
            switch event.type {
            case .leftMouseDragged:
                if let corner = event.location(in: self)?.rounded {
                    size = corner - origin
                    rectBeingDragged = CGRect(origin: origin, size: size)
                }
            case .leftMouseUp:
                if let corner = event.location(in: self)?.rounded {
                    size = corner - origin
                    rectBeingDragged = CGRect(origin: origin, size: size)
                }
                outStop.pointee = true
            default: break
            }
        }

        if abs(size.width) >= 1 && abs(size.height) >= 1 {
            rects.append(CGRect(origin: origin, size: size).standardized)
        }
        rectBeingDragged = nil
    }

    private var observers: [NSKeyValueObservation] = []
    private var cachedUnionPath: CGPath?

    // not standardized, so origin is always the location of the mouseDown
    private var rectBeingDragged: CGRect? = nil {
        didSet { markUnionPathDirty() }
    }

    private func moveCornerOfLatestRect(to corner: CGPoint) {
        let origin = rects[rects.count - 1].origin
        rects[rects.count - 1].size = CGSize(width: corner.x - origin.x, height: corner.y - origin.y)
    }

    private func finalizeLatestRect() {
        let rect = rects[rects.count - 1]
        if rect.size.width == 0 || rect.size.height == 0 {
            rects.removeLast()
        } else {
            rects[rects.count - 1] = rect.standardized
        }
    }

}

extension NSEvent {

    /// Return my location in the geometry of `view`, if possible. If I can't convert my location to `view`'s geometry, I return nil.
    func location(in view: NSView) -> CGPoint? {
        guard let myWindow = self.window, let viewWindow = view.window else { return nil }
        var location = locationInWindow
        // location is in myWindow
        if myWindow != viewWindow {
            var rect = CGRect(origin: location, size: .zero)
            rect = myWindow.convertToScreen(rect)
            rect = viewWindow.convertFromScreen(rect)
            location = rect.origin
        }
        // location is in viewWindow
        return view.convert(location, from: nil)
    }

}

private extension CGPoint {
    var rounded: CGPoint {
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}

private func -(_ lhs: CGPoint, _ rhs: CGPoint) -> CGSize {
    return CGSize(width: lhs.x - rhs.x, height: lhs.y - rhs.y)
}

private extension UserDefaults {
    @objc var rectInset: CGFloat {
        return CGFloat(self.double(forKey: "rectInset"))
    }

    @objc var cornerRadius: CGFloat {
        return CGFloat(self.double(forKey: "cornerRadius"))
    }
}
