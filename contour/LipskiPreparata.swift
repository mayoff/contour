//
//  LipskiPreparata.swift
//  contour
//
//  Created by Rob Mayoff on 1/7/18.
//  Copyright © 2018 Rob Mayoff. All rights reserved.
//

import CoreGraphics

extension CGPath {
    static func makeUnion(of rects: [CGRect], cornerRadius: CGFloat) -> CGPath {
        let phase2 = AlgorithmPhase2()
        _ = AlgorithmPhase1(rects: rects, phase2: phase2)
        return phase2.makePath(cornerRadius: cornerRadius)
    }
}

fileprivate func swapped<A, B>(_ pair: (A, B)) -> (B, A) { return (pair.1, pair.0) }

fileprivate class AlgorithmPhase1 {

    init(rects: [CGRect], phase2: AlgorithmPhase2) {
        self.phase2 = phase2
        xs = Array(Set(rects.map({ $0.origin.x})).union(rects.map({ $0.origin.x + $0.size.width }))).sorted()
        indexOfX = [CGFloat:Int](uniqueKeysWithValues: xs.enumerated().map(swapped))
        ys = Array(Set(rects.map({ $0.origin.y})).union(rects.map({ $0.origin.y + $0.size.height }))).sorted()
        indexOfY = [CGFloat:Int](uniqueKeysWithValues: ys.enumerated().map(swapped))
        segments.reserveCapacity(2 * ys.count)
        _ = makeSegment(y0: 0, y1: ys.count - 1)

        let sides = (rects.map({ makeSide(edge: .left, rect: $0) }) + rects.map({ makeSide(edge: .right, rect: $0)})).sorted()
        var priorX = 0
        var priorEdge = Side.Edge.left
        for side in sides {
            if side.x != priorX || side.edge != priorEdge {
                convertStackToPhase2Sides(atX: priorX)
                priorX = side.x
                priorEdge = side.edge
            }
            switch priorEdge {
            case .left:
                pushEmptySegmentsOfSegmentTree(atIndex: 0, thatOverlap: side)
                adjustInsertionCountsOfSegmentTree(atIndex: 0, by: 1, for: side)
            case .right:
                adjustInsertionCountsOfSegmentTree(atIndex: 0, by: -1, for: side)
                pushEmptySegmentsOfSegmentTree(atIndex: 0, thatOverlap: side)
            }
        }
        convertStackToPhase2Sides(atX: priorX)

    }

    private let phase2: AlgorithmPhase2
    private let xs: [CGFloat]
    private let indexOfX: [CGFloat: Int]
    private let ys: [CGFloat]
    private let indexOfY: [CGFloat: Int]
    private var segments: [Segment] = []
    private var stack: [Int] = []

    private struct Segment {
        var y0: Int
        var y1: Int
        var insertions = 0
        var status  = Status.empty
        var leftChildIndex: Int?
        var rightChildIndex: Int?

        var mid: Int { return (y0 + y1 + 1) / 2 }

        func withChildrenThatOverlap(_ side: Side, do body: (_ childIndex: Int) -> ()) {
            if side.y0 < mid, let l = leftChildIndex { body(l) }
            if mid < side.y1, let r = rightChildIndex { body(r) }
        }

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

        func fullyContains(_ segment: Segment) -> Bool {
            return y0 <= segment.y0 && segment.y1 <= y1
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

    private func makeSegment(y0: Int, y1: Int) -> Int {
        let index = segments.count
        let segment: Segment = Segment(y0: y0, y1: y1)
        segments.append(segment)
        if y1 - y0 > 1 {
            let mid = segment.mid
            segments[index].leftChildIndex = makeSegment(y0: y0, y1: mid)
            segments[index].rightChildIndex = makeSegment(y0: mid, y1: y1)
        }
        return index
    }

    private func adjustInsertionCountsOfSegmentTree(atIndex i: Int, by delta: Int, for side: Side) {
        var segment = segments[i]
        if side.fullyContains(segment) {
            segment.insertions += delta
        } else {
            segment.withChildrenThatOverlap(side) { adjustInsertionCountsOfSegmentTree(atIndex: $0, by: delta, for: side) }
        }

        segment.status = uncachedStatus(of: segment)
        segments[i] = segment
    }

    private func uncachedStatus(of segment: Segment) -> Segment.Status {
        if segment.insertions > 0 { return .full }
        if let l = segment.leftChildIndex, let r = segment.rightChildIndex {
            return segments[l].status == .empty && segments[r].status == .empty ? .empty : .partial
        }
        return .empty
    }

    private func pushEmptySegmentsOfSegmentTree(atIndex i: Int, thatOverlap side: Side) {
        let segment = segments[i]
        switch segment.status {
        case .empty where side.fullyContains(segment):
            if let top = stack.last, segment.y0 == top {
                // segment.y0 == prior segment.y1, so merge.
                stack[stack.count - 1] = segment.y1
            } else {
                stack.append(segment.y0)
                stack.append(segment.y1)
            }
        case .partial, .empty:
            segment.withChildrenThatOverlap(side) { pushEmptySegmentsOfSegmentTree(atIndex: $0, thatOverlap: side) }
        case .full: break
        }
    }

    private func makeSide(edge: Side.Edge, rect: CGRect) -> Side {
        let x: Int
        switch edge {
        case .left: x = indexOfX[rect.minX]!
        case .right: x = indexOfX[rect.maxX]!
        }
        return Side(x: x, edge: edge, y0: indexOfY[rect.minY]!, y1: indexOfY[rect.maxY]!)
    }

    private func convertStackToPhase2Sides(atX x: Int) {
        guard stack.count > 0 else { return }
        let gx = xs[x]
        for i in stride(from: 0, to: stack.count, by: 2) {
            phase2.addVerticalSide(x: gx, y0: ys[stack[i]], y1: ys[stack[i+1]])
        }
        stack.removeAll(keepingCapacity: true)
    }

}

fileprivate class AlgorithmPhase2 {

    init() { }

    func addVerticalSide(x: CGFloat, y0: CGFloat, y1: CGFloat) {
        verticalSides.append(VerticalSide(x: x, y0: y0, y1: y1))
    }

    func makePath(cornerRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for side in verticalSides {
            let rect = CGRect(x: side.x, y: side.y0, width: 0, height: side.y1 - side.y0).insetBy(dx: -2, dy: 0)
            path.addRect(rect)
        }
        return path.copy()!
    }

    private var verticalSides: [VerticalSide] = []

    private struct VerticalSide {
        var x: CGFloat
        var y0: CGFloat
        var y1: CGFloat
    }

}
