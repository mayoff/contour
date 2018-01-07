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
            self?.cachedUnionPath = nil
            self?.needsDisplay = true
        })
        observers.append(UserDefaults.standard.observe(\UserDefaults.cornerRadius) { [weak self] (_, _) in
            self?.cachedUnionPath = nil
            self?.needsDisplay = true
        })
    }

    private static let defaultRectsJson = "[[[65,26],[80,197]],[[37,145],[271,43]],[[230,67],[94,137]],[[119,48],[140,57]]]"

    var rects: [CGRect] = {
        let data = RectsView.defaultRectsJson.data(using: .utf8)!
        let decoder = JSONDecoder()
        return try! decoder.decode([CGRect].self, from: data)
    }() {
        didSet {
            cachedUnionPath = nil
            needsDisplay = true
        }
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

    override func draw(_ dirtyRect: NSRect) {
        NSLog("draw!")

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
                    print(size)
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
        didSet {
            cachedUnionPath = nil
            needsDisplay = true
        }
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

private func swapped<A, B>(_ pair: (A, B)) -> (B, A) { return (pair.1, pair.0) }

private struct Segment {
    var y0: Int
    var y1: Int
    var insertions = 0
    var status  = Status.empty
    var leftChildIndex: Int?
    var rightChildIndex: Int?

    var mid: Int { return (y0 + y1) / 2 }

    init(y0: Int, y1: Int) {
        self.y0 = y0
        self.y1 = y1
    }

    enum Status {
        case empty
        case partial
        case full
    }
}

private struct /*Vertical*/Side: Comparable {
    var x: Int
    var edge: Edge
    var y0: Int
    var y1: Int

    enum Edge: Int {
        case left = 0
        case right = 1
    }

    static func ==(lhs: Side, rhs: Side) -> Bool {
        return lhs.x == rhs.x && lhs.edge == rhs.edge && lhs.y0 == rhs.y0 && lhs.y1 == rhs.y1
    }

    static func <(lhs: Side, rhs: Side) -> Bool {
        if lhs.x < rhs.x { return true }
        if lhs.x > rhs.x { return false }
        if lhs.edge.rawValue < rhs.edge.rawValue { return true }
        if lhs.edge.rawValue > rhs.edge.rawValue { return false }
        if lhs.y0 < rhs.y0 { return true }
        if lhs.y0 > rhs.y0 { return false }
        return lhs.y1 < rhs.y1
    }
}

extension CGPath {
    static func makeUnion(of rects: [CGRect], cornerRadius: CGFloat) -> CGPath {
        guard rects.count > 0 && false else {
            let path = CGMutablePath()
            for rect in rects {
                path.addRoundedRect(in: rect, cornerWidth: min(cornerRadius, rect.size.width / 2), cornerHeight: min(cornerRadius, rect.size.height / 2))
            }
            return path.copy()!
        }

        let xs = Array(Set(rects.map({ $0.minX })).union(rects.map({ $0.maxX }))).sorted()
        let indexOfX = [CGFloat:Int](uniqueKeysWithValues: xs.enumerated().map(swapped))
        let ys = Array(Set(rects.map({ $0.minY })).union(rects.map({ $0.maxY }))).sorted()
        let indexOfY = [CGFloat:Int](uniqueKeysWithValues: ys.enumerated().map(swapped))

        var segments = [Segment]()
        segments.reserveCapacity(2 * ys.count)

        func makeSegment(y0: Int, y1: Int) -> Int {
            let index = segments.count
            segments.append(Segment(y0: y0, y1: y1))
            if y1 - y0 > 1 {
                let mid = (y0 + y1) / 2
                segments[index].leftChildIndex = makeSegment(y0: y0, y1: mid)
                segments[index].rightChildIndex = makeSegment(y0: mid, y1: y1)
            }
            return index
        }

        _ = makeSegment(y0: 0, y1: ys.count - 1)

        func makeSide(edge: Side.Edge, rect: CGRect) -> Side {
            let x: Int
            switch edge {
            case .left: x = indexOfX[rect.minX]!
            case .right: x = indexOfX[rect.maxX]!
            }
            return Side(x: x, edge: edge, y0: indexOfY[rect.minY]!, y1: indexOfY[rect.maxY]!)
        }

        var stack = [Int]() // An array to be taken by twos, as y0 and y1 of currently-included segments.

        func compl(_ i: Int) {
            let segment = segments[i]
            switch segment.status {
            case .empty:
                if let top = stack.last, segment.y0 == top {
                    // segment.y0 == prior segment.y1, so merge.
                    stack[stack.count] = segment.y1
                } else {
                    stack.append(segment.y0)
                    stack.append(segment.y1)
                }
            case .partial:
                // Note that only branch nodes can be .partial, so these force-unwraps are safe.
                compl(segment.leftChildIndex!)
                compl(segment.rightChildIndex!)
            case .full: break
            }
        }

        func uncachedStatus(of segment: Segment) -> Segment.Status {
            if segment.insertions > 0 { return .full }
            if let l = segment.leftChildIndex, let r = segment.rightChildIndex {
                return segments[l].status == .empty && segments[r].status == .empty ? .empty : .partial
            }
            return .empty
        }

        func insert(_ side: Side, intoSegmentAtIndex i: Int) {
            var segment = segments[i]
            if side.y0 <= segment.y0 && segment.y1 <= side.y1 {
                compl(i)
                segment.insertions += 1
            } else {
                if let l = segment.leftChildIndex, side.y0 < segment.mid { insert(side, intoSegmentAtIndex: l) }
                if let r = segment.rightChildIndex, segment.mid < side.y1 { insert(side, intoSegmentAtIndex: r) }
            }

            segment.status = uncachedStatus(of: segment)
            segments[i] = segment
        }

        func remove(_ side: Side, fromSegmentAtIndex i: Int) {
            var segment = segments[i]

            if side.y0 <= segment.y0 && segment.y1 <= side.y1 {
                segment.insertions -= 1
                compl(i)
            } else {
                if let l = segment.leftChildIndex, side.y0 < segment.mid { remove(side, fromSegmentAtIndex: l) }
                if let r = segment.rightChildIndex, segment.mid < side.y1 { remove(side, fromSegmentAtIndex: r) }
            }

            segment.status = uncachedStatus(of: segment)
            segments[i] = segment
        }

        var contourSides = [Side]()

        func contributeContourSidesFromStack(x: Int, edge: Side.Edge) {
            for i in stride(from: 0, to: stack.count, by: 2) {
                contourSides.append(Side(x: x, edge: edge, y0: stack[i], y1: stack[i+1]))
            }
            stack.removeAll(keepingCapacity: true)
        }

        let sides = (rects.map({ makeSide(edge: .left, rect: $0) }) + rects.map({ makeSide(edge: .right, rect: $0)})).sorted()
        // First side is guaranteed to be a left side.
        insert(sides[0], intoSegmentAtIndex: 0)
        var priorX = sides[0].x
        var priorEdge = Side.Edge.left
        for side in sides.dropFirst() {
            if side.x != priorX || side.edge != priorEdge {
                contributeContourSidesFromStack(x: priorX, edge: priorEdge)
                priorX = side.x
                priorEdge = side.edge
            }
            switch priorEdge {
            case .left: insert(side, intoSegmentAtIndex: 0)
            case .right: remove(side, fromSegmentAtIndex: 0)
            }
        }
        contributeContourSidesFromStack(x: priorX, edge: priorEdge)

        return CGPath(rect: .zero, transform: nil)
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
