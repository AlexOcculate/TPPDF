//
//  PDFTableObject.swift
//  TPPDF
//
//  Created by Philip Niedertscheider on 12/08/2017.
//

// swiftlint:disable function_body_length function_parameter_count line_length

typealias PDFTableCalculatedCell = (cell: PDFTableCell, style: PDFTableCellStyle, frames: (cell: CGRect, content: CGRect))

/**
 TODO: Documentation
 */
internal class PDFTableObject: PDFRenderObject {

    /**
     Table to calculate and draw
     */
    internal var table: PDFTable

    /**
     Initializer

     - parameter: Table to calculate and draw
     */
    internal init(table: PDFTable) {
        self.table = table
    }

    /**
     TODO: Documentation
     */
    internal var styleIndexOffset: Int = 0

    /**
     - throws: `PDFError` if table validation fails. See `PDFTableValidator.validateTableData(::)` for details
     */
    override internal func calculate(generator: PDFGenerator, container: PDFContainer) throws -> [PDFLocatedRenderObject] {
        try PDFTableValidator.validateTable(table: table)

        var availableSize = PDFCalculations.calculateAvailableFrame(for: generator, in: container)
        var tableOrigin = PDFCalculations.calculateElementPosition(for: generator, in: container, with: availableSize)

        let mergeNodes = PDFTableMergeUtil.calculateMerged(table: table)
        var verticalOrigins = [tableOrigin.y] + mergeNodes.indices.map { _ in tableOrigin.y }
        var cellItems: [[PDFTableCalculatedCell]] = []

        for (rowIdx, row) in mergeNodes.enumerated() {
            var frames: [PDFTableCalculatedCell] = []
            for node in row {
                let columns = node.position.column...(node.position.column + node.moreColumnsSpan)
                let originX = table.widths[..<node.position.column].reduce(0, +) * availableSize.width
                let origin = CGPoint(x: tableOrigin.x + originX,
                                     y: verticalOrigins[node.position.row])
                let availableWidth = table.widths[columns].reduce(0, +) * availableSize.width
                let style = getStyle(for: node, in: table, at: rowIdx)
                let frame = calculate(generator: generator,
                                      container: container,
                                      cell: node.cell,
                                      style: style,
                                      origin: origin,
                                      width: availableWidth)
                let bottomIndex = node.position.row + node.moreRowsSpan + 1
                verticalOrigins[bottomIndex] = max(verticalOrigins[bottomIndex], frame.frames.cell.maxY)

                frames.append(frame)
            }
            cellItems.append(frames)
        }

        for (rowIdx, row) in mergeNodes.enumerated() {
            for (colIdx, node) in row.enumerated() {
                let bottomIndex = node.position.row + node.moreRowsSpan + 1
                var frame = cellItems[rowIdx][colIdx]
                let diffY = verticalOrigins[bottomIndex] - frame.frames.cell.maxY
                frame.frames.cell.size.height += diffY
                cellItems[rowIdx][colIdx] = reposition(cell: frame)
            }
        }

        // Create render objects
        let renderObjects = try createRenderObjects(generator: generator,
                                                    container: container,
                                                    cellItems: cellItems,
                                                    pageBreakIndicies: [])
        let finalOffset = PDFCalculations.calculateContentOffset(for: generator, of: renderObjects.offset, in: container)
        try PDFOffsetObject(offset: finalOffset).calculate(generator: generator, container: container)

        return renderObjects.objects
    }

    internal func getStyle(for node: PDFTableNode, in table: PDFTable, at rowIdx: Int) -> PDFTableCellStyle {
        getStyle(for: node.cell,
                 tableStyle: table.style,
                 isHeader: rowIdx < table.style.columnHeaderCount,
                 isFooter: rowIdx >= table.cells.count - table.style.footerCount,
                 rowHeaderCount: table.style.rowHeaderCount,
                 isAlternatingRow: rowIdx % 2 == 1,
                 colIdx: node.position.column)
    }

    /**
     TODO: Documentation
     */
    internal func calculateFrames(row: [PDFTableCell],
                                  rowIdx: Int,
                                  availableSize: CGSize,
                                  origin: CGPoint,
                                  tableHeight: Int,
                                  styles: [PDFTableCellStyle],
                                  generator: PDFGenerator,
                                  container: PDFContainer) -> [(cell: PDFTableCell, style: PDFTableCellStyle, frames: (cell: CGRect, content: CGRect))] {
        var frames: [(cell: PDFTableCell, style: PDFTableCellStyle, frames: (cell: CGRect, content: CGRect))] = []
        var newOrigin = origin

        // Calcuate X, Y position and size
        for (colIdx, cell) in row.enumerated() {
            let columnWidth = table.widths[colIdx] * availableSize.width

            let frame = calculate(generator: generator,
                                  container: container,
                                  cell: cell,
                                  style: styles[colIdx],
                                  origin: newOrigin,
                                  width: columnWidth)

            frames.append(frame)

            newOrigin.x += columnWidth
        }
        return frames
    }

    internal func calculate(generator: PDFGenerator,
                            container: PDFContainer,
                            cell: PDFTableCell,
                            style: PDFTableCellStyle,
                            origin: CGPoint,
                            width: CGFloat) -> PDFTableCalculatedCell {
        var frame = (
            cell: cell,
            style: style,
            frames: (
                cell: CGRect(
                    origin: origin + table.margin,
                    size: CGSize(
                        width: width - 2 * table.margin,
                        height: 0
                    )
                ),
                content: CGRect(
                    origin: origin + table.margin + table.padding,
                    size: CGSize(
                        width: width - 2 * (table.margin + table.padding),
                        height: 0
                    )
                )
            )
        )
        guard let content = cell.content else {
            return frame
        }

        var result = CGRect.zero

        if content.isAttributedString || content.isString {
            let text: NSAttributedString! = {
                if let attributedString = content.attributedStringValue {
                    return attributedString
                } else if let text = content.stringValue {
                    return createAttributedCellText(text: text, cellStyle: style, alignment: cell.alignment)
                } else {
                    return nil
                }
            }()
            if text != nil {
                result = PDFCalculations
                    .calculateCellFrame(generator: generator,
                                        container: container,
                                        position: (origin: frame.frames.content.origin, width: frame.frames.content.width),
                                        text: text,
                                        alignment: cell.alignment)
            }
        } else if let image = content.imageValue {
            result = PDFCalculations
                .calculateCellFrame(generator: generator,
                                    origin: frame.frames.content.origin,
                                    width: frame.frames.content.width,
                                    image: image)
        }

        frame.frames.content.size = result.size
        frame.frames.cell.size.height = result.height + 2 * table.padding

        return frame
    }
    /**
     TODO: Documentation
     */
    internal func reposition(cell: PDFTableCalculatedCell) -> PDFTableCalculatedCell {
        var result = cell
        let alignment = cell.cell.alignment
        let frame = cell.frames

        result.frames.content.origin.x = {
            if alignment.isLeft {
                return frame.content.minX
            } else if alignment.isRight {
                return frame.content.minX + frame.cell.width - 2 * table.padding - frame.content.width
            } else {
                return frame.content.minX + (frame.cell.width - 2 * table.padding - frame.content.width) / 2
            }
        }()

        result.frames.content.origin.y = {
            if alignment.isTop {
                return frame.content.minY
            } else if alignment.isBottom {
                return frame.content.minY + frame.cell.height - 2 * table.padding - frame.content.height
            } else { 
                return frame.content.minY + (frame.cell.height - 2 * table.padding - frame.content.height) / 2
            }
        }()

        return result
    }

    /**
     TODO: Documentation
     */
    internal func createAttributedCellText(text: String, cellStyle: PDFTableCellStyle, alignment: PDFTableCellAlignment) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = {
            if alignment.isLeft {
                return NSTextAlignment.left
            } else if alignment.isRight {
                return NSTextAlignment.right
            } else {
                return NSTextAlignment.center
            }
        }()

        let attributes: [NSAttributedString.Key: AnyObject] = [
            NSAttributedString.Key.foregroundColor: cellStyle.colors.text,
            NSAttributedString.Key.font: cellStyle.font,
            NSAttributedString.Key.paragraphStyle: paragraph
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }

    /**
     TODO: Documentation
     */
    internal func createRenderObjects(generator: PDFGenerator,
                                      container: PDFContainer,
                                      cellItems: [[(cell: PDFTableCell, style: PDFTableCellStyle, frames: (cell: CGRect, content: CGRect))]],
                                      pageBreakIndicies: [Int]) throws -> (objects: [PDFLocatedRenderObject], offset: CGFloat) {
        var result: [PDFRenderObject?] = []

        var pageStart: CGPoint! = nil
        var pageEnd: CGPoint = CGPoint.zero

        for (rowIdx, row) in cellItems.enumerated() {
            for item in row {
                let cellFrame = item.frames.cell
                let contentFrame = item.frames.content

                if pageStart == nil {
                    pageStart = cellFrame.origin - CGPoint(x: table.margin, y: table.margin)
                }
                pageEnd = CGPoint(x: cellFrame.maxX, y: cellFrame.maxY) + CGPoint(x: table.margin, y: table.margin)

                // Background
                result.append(createCellBackgroundObject(cellStyle: item.style,
                                                         frame: cellFrame))

                // Content
                result.append(createCellContentObject(content: item.cell.content,
                                                      cellStyle: item.style,
                                                      alignment: item.cell.alignment,
                                                      frame: contentFrame))

                // Grid
                result += createCellOutlineObjects(borders: item.style.borders, cellFrame: cellFrame) as [PDFRenderObject?]
            }

            if pageBreakIndicies.contains(rowIdx) || rowIdx == cellItems.count - 1 {
                let tableOutlineObject = PDFRectangleObject(lineStyle: table.style.outline, size: CGSize.zero)
                tableOutlineObject.frame = CGRect(
                    x: pageStart.x,
                    y: pageStart.y,
                    width: pageEnd.x - pageStart.x,
                    height: pageEnd.y - pageStart.y
                )
                result.append(tableOutlineObject)
            }

            // Page break
            if pageBreakIndicies.contains(rowIdx) {
                result.append(PDFPageBreakObject())

                pageStart = nil
            }
        }

        let compactObjects = result.compactMap { (obj) -> PDFLocatedRenderObject? in
            if let obj = obj {
                return (container, obj)
            } else {
                return nil
            }
        }
        return (objects: compactObjects, offset: pageEnd.y)
    }

    /**
     TODO: Documentation
     */
    internal func createCellBackgroundObject(cellStyle: PDFTableCellStyle, frame: CGRect) -> PDFRenderObject {
        let object = PDFRectangleObject(lineStyle: .none, size: .zero, fillColor: cellStyle.colors.fill)
        object.frame = frame
        return object
    }

    /**
     TODO: Documentation
     */
    internal func createCellContentObject(content: PDFTableContent?,
                                          cellStyle: PDFTableCellStyle,
                                          alignment: PDFTableCellAlignment, frame: CGRect) -> PDFRenderObject? {
        if content == nil {
            return nil
        }
        var contentObject: PDFRenderObject?

        if let contentImage = content?.imageValue {
            contentObject = PDFImageObject(image: PDFImage(image: contentImage, options: [.none]))
        } else {
            var attributedString: NSAttributedString?
            if let contentText = content?.stringValue {
                attributedString = createAttributedCellText(text: contentText, cellStyle: cellStyle, alignment: alignment)
            } else if let contentText = content?.attributedStringValue {
                attributedString = contentText
            }

            if let string = attributedString {
                let textObject = PDFAttributedTextObject(attributedText: PDFAttributedText(text: string))
                textObject.attributedString = string
                contentObject = textObject
            }
        }
        contentObject?.frame = frame

        return contentObject
    }

    /**
     TODO: Documentation
     */
    internal func createCellOutlineObjects(borders: PDFTableCellBorders, cellFrame: CGRect) -> [PDFLineObject] {
        return [
            PDFLineObject(style: borders.top,
                          startPoint: CGPoint(x: cellFrame.minX, y: cellFrame.minY),
                          endPoint: CGPoint(x: cellFrame.maxX, y: cellFrame.minY)),
            PDFLineObject(style: borders.bottom,
                          startPoint: CGPoint(x: cellFrame.minX, y: cellFrame.maxY),
                          endPoint: CGPoint(x: cellFrame.maxX, y: cellFrame.maxY)),
            PDFLineObject(style: borders.right,
                          startPoint: CGPoint(x: cellFrame.maxX, y: cellFrame.minY),
                          endPoint: CGPoint(x: cellFrame.maxX, y: cellFrame.maxY)),
            PDFLineObject(style: borders.left,
                          startPoint: CGPoint(x: cellFrame.minX, y: cellFrame.minY),
                          endPoint: CGPoint(x: cellFrame.minX, y: cellFrame.maxY))
        ]
    }

    /**
     TODO: Documentation
     */
    internal func stylesForRow(tableStyle: PDFTableStyle,
                               isHeader: Bool,
                               isFooter: Bool,
                               rowHeaderCount: Int,
                               isAlternatingRow: Bool,
                               cells: [PDFTableCell]) -> [PDFTableCellStyle] {
        return cells.enumerated().map({ arg in
            getStyle(for: arg.element,
                     tableStyle: tableStyle,
                     isHeader: isHeader,
                     isFooter: isFooter,
                     rowHeaderCount: rowHeaderCount,
                     isAlternatingRow: isAlternatingRow,
                     colIdx: arg.offset)
        })
    }

    /**
     TODO: Documentation
     */
    internal func getStyle(for cell: PDFTableCell,
                           tableStyle: PDFTableStyle,
                           isHeader: Bool,
                           isFooter: Bool,
                           rowHeaderCount: Int,
                           isAlternatingRow: Bool,
                           colIdx: Int) -> PDFTableCellStyle {
        if let cellStyle = cell.style {
            return cellStyle
        } else if isHeader {
            return tableStyle.columnHeaderStyle
        } else if isFooter {
            return tableStyle.footerStyle
        } else if colIdx < rowHeaderCount {
            return tableStyle.rowHeaderStyle
        } else if isAlternatingRow {
            return tableStyle.alternatingContentStyle ?? tableStyle.contentStyle
        }
        return tableStyle.contentStyle
    }

    /**
     Creates a new `PDFTableObject` with the same properties
     */
    override internal var copy: PDFRenderObject {
        return PDFTableObject(table: table.copy)
    }
}
