//
//  PDFLayout.swift
//  TPPDF
//
//  Created by Philip Niedertscheider on 31/10/2017.
//

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/**
 Contains all relevant layout informations of a pdf document
 */
class PDFLayout: CustomStringConvertible {
    /**
     TODO: documentation
     */
    var heights = PDFLayoutHeights()

    /**
     TODO: documentation
     */
    var indentation = PDFLayoutIndentations()

    /**
     TODO: documentation
     */
    var margin: EdgeInsets = .zero

    // MARK: - INTERNAL FUNCS

    /**
     TODO: documentation
     */
    func getContentOffset(in container: PDFContainer) -> CGFloat {
        if container.isHeader {
            return heights.header[container]!
        } else if container.isFooter {
            return heights.footer[container]!
        }
        return heights.content
    }

    /**
     TODO: documentation
     */
    func setContentOffset(in container: PDFContainer, to value: CGFloat) {
        if container.isHeader {
            heights.header[container] = value
        } else if container.isFooter {
            heights.footer[container] = value
        } else {
            heights.content = value
        }
    }

    /**
     TODO: documentation
     */
    func reset() {
        heights = PDFLayoutHeights()
        indentation = PDFLayoutIndentations()
        margin = .zero
    }
}
