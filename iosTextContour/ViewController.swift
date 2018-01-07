//
//  ViewController.swift
//  iosTextContour
//
//  Created by Rob Mayoff on 1/7/18.
//  Copyright © 2018 Rob Mayoff. All rights reserved.
//

import UIKit

class ViewController: UIViewController, UITextViewDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        highlightLayer.backgroundColor = nil
        highlightLayer.fillColor = #colorLiteral(red: 0.4745098054, green: 0.8392156959, blue: 0.9764705896, alpha: 1)
        highlightLayer.strokeColor = nil
        view.layer.insertSublayer(highlightLayer, at: 0)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        highlightLayer.frame = view.bounds

        // Just doing setHighlightPath() here directly has a problem: the text view hasn't been laid out yet, because it is not a direct subview of self.view. I can't set the highlight path until the text view has been laid out.
        DispatchQueue.main.async {
            self.setHighlightPath()
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        setHighlightPath()
    }

    @IBAction private func layoutParameterDidChange() {
        setHighlightPath()
    }

    @IBOutlet private var textView: UITextView!
    @IBOutlet private var insetSlider: UISlider!
    @IBOutlet private var radiusSlider: UISlider!
    private var highlightLayer = CAShapeLayer()

    private func setHighlightPath() {
        let textLayer = textView.layer
        let textContainerInset = textView.textContainerInset
        let uiInset = CGFloat(insetSlider.value)
        let radius = CGFloat(radiusSlider.value)
        let highlightLayer = self.highlightLayer
        let layout = textView.layoutManager
        let range = NSMakeRange(0, layout.numberOfGlyphs)
        var rects = [CGRect]()
        layout.enumerateLineFragments(forGlyphRange: range) { (_, usedRect, _, _, _) in
            if usedRect.width > 0 && usedRect.height > 0 {
                var rect = usedRect
                rect.origin.x += textContainerInset.left
                rect.origin.y += textContainerInset.top
                rect = highlightLayer.convert(rect, from: textLayer)
                rect = rect.insetBy(dx: uiInset, dy: uiInset)
                rects.append(rect)
            }
        }
        highlightLayer.path = CGPath.makeUnion(of: rects, cornerRadius: radius)
    }

}

