/*
 * Copyright (C) 2022 Romain Guy
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import CoreGraphics
import CoreText
import Foundation

import Cocoa
import Quartz

import Carbon

var pathStyle: String
var fontColor: CGColor
var fontName: CFString
var fontSize: CGFloat
var text: String

var keynoteMode: Bool = false

func toCGColor(_ color: UInt32) -> CGColor {
    return CGColor(
        srgbRed: Double((color >> 16) & 0xFF) / 255.0,
        green: Double((color >> 8) & 0xFF) / 255.0,
        blue: Double(color & 0xFF) / 255.0,
        alpha: 1.0)
}

if CommandLine.arguments.count < 6 {
    if CommandLine.arguments.count < 3 {
        print("elegant-underline [style] [color] [font name] [size in points] [text]")
        print("   style: jagged, elegant")
        print("   color: sRGB color in hex format FF00FF")
        exit(1)
    }
    let script: NSAppleScript = {
        let script = NSAppleScript(source: """
            tell application "Keynote"
                activate
                
                if not (exists front document) then error number -128
                if playing is true then tell the front document to stop
                
                tell the front document
                    set thisSlide to current slide
                    set thisTextItem to text item 1 of thisSlide
                    tell thisTextItem
                        set thisText to its object text
                        set thisSize to the size of its object text
                        set thisFont to the font of its object text
                    end tell
                end tell
            end tell

            thisSize & thisFont & thisText
            """
        )!
        let success = script.compileAndReturnError(nil)
        assert(success)
        return script
    }()

    pathStyle = CommandLine.arguments[1]
    fontColor = toCGColor(UInt32(CommandLine.arguments[2], radix: 16)!)

    var error: NSDictionary? = nil
    if let result = script.executeAndReturnError(&error) as NSAppleEventDescriptor? {
        fontSize = CGFloat((result.atIndex(1)?.doubleValue)!)
        fontName = (result.atIndex(2)?.stringValue)! as CFString
        text = (result.atIndex(3)?.stringValue)!
    } else {
        print("Open Keynote and present one text item on the current slide or use standalone mode:")
        print("elegant-underline [style] [color] [font name] [size in points] [text]")
        print("   style: jagged, elegant")
        print("   color: sRGB color in hex format FF00FF")
        exit(1)
    }

    keynoteMode = true
} else {
    pathStyle = CommandLine.arguments[1]
    fontColor = toCGColor(UInt32(CommandLine.arguments[2], radix: 16)!)
    fontName = CommandLine.arguments[3] as CFString
    fontSize = CGFloat(Float(CommandLine.arguments[4]) ?? Float(72.0))
    text = CommandLine.arguments[5]
}

let font = CTFontCreateWithName(fontName, fontSize, nil)
let attributes = [kCTFontAttributeName : font] as CFDictionary
let attributedText = CFAttributedStringCreate(kCFAllocatorDefault, text as NSString, attributes)

let line = CTLineCreateWithAttributedString(attributedText!)
let runs = CTLineGetGlyphRuns(line)
let runCount = CFArrayGetCount(runs)

var glyphs = Array(repeating: CGGlyph(), count: 1)
var positions = Array(repeating: CGPoint(), count: 1)

let pathBuilder = CGMutablePath()
for i in 0..<runCount {
    let run: CTRun = unsafeBitCast(CFArrayGetValueAtIndex(runs, i), to: CTRun.self)
    let glyphCount = CTRunGetGlyphCount(run)

    for j in 0..<glyphCount {
        let range = CFRangeMake(j, 1)
        CTRunGetGlyphs(run, range, &glyphs)
        CTRunGetPositions(run, range, &positions)

        let letter = CTFontCreatePathForGlyph(font, glyphs[0], nil)
        let transform = CGAffineTransform(translationX: positions[0].x, y: positions[0].y)

        if letter != nil {
            pathBuilder.addPath(letter!, transform: transform)
        }
    }
}

var path = pathBuilder.copy()!
var boundingBox = path.boundingBox

let fontUnderlinePosition = CTFontGetUnderlinePosition(font)
let fontUnderlineThickness = CTFontGetUnderlineThickness(font)

switch pathStyle {
case "jagged":
    var x = boundingBox.minX
    let y = fontUnderlinePosition - fontUnderlineThickness / 2.0
    let end = x + boundingBox.width

    let jagged = CGMutablePath()
    jagged.move(to: CGPoint(x: x, y: y))
    while x < end {
        x += fontUnderlineThickness
        jagged.addLine(to: CGPoint(x: x, y: fontUnderlinePosition + fontUnderlineThickness / 2.0))
        x += fontUnderlineThickness
        if (x < end) {
            jagged.addLine(to: CGPoint(x: x, y: fontUnderlinePosition - fontUnderlineThickness / 2.0))
        }
    }

    path = jagged.copy(
        strokingWithWidth: fontUnderlineThickness / 2.0,
        lineCap: CGLineCap.butt,
        lineJoin: CGLineJoin.miter,
        miterLimit: CGFloat(10.0)
    )
    boundingBox = path.boundingBox
case "elegant":
    let underlineBounds = CGRect(
        x: boundingBox.minX,
        y: fontUnderlinePosition,
        width: boundingBox.width,
        height: fontUnderlineThickness
    )
    let underlinePath = CGPath(rect: underlineBounds, transform: nil)

    let clipBounds = CGRect(
        x: boundingBox.minX,
        y: boundingBox.minY,
        width: boundingBox.width,
        height: fontUnderlinePosition
    )
    let clipPath = CGPath(rect: clipBounds, transform: nil)

    // TODO: Finish when macOS 13.0 is available
    // step 1: subtract clipPath from textPath
    // step 2: get a filled path for the stroke of step 1
    // step 3: subtract the stroked text path from underlinePath
default:
    break
}

var outUrl: URL

if keynoteMode {
    outUrl = try FileManager.default.url(
        for: .itemReplacementDirectory,
        in: .userDomainMask,
        appropriateFor: URL(fileURLWithPath: "./"),
        create: true
    ).appendingPathComponent("elegant-underline.pdf", isDirectory: false)
} else {
    outUrl = URL(fileURLWithPath: "./elegant-underline.pdf")
}

print("Result in", outUrl)

var mediaBox = CGRect(
    x: CGFloat(0.0),
    y: CGFloat(0.0),
    width: boundingBox.width,
    height: boundingBox.height
)

let gc = CGContext(outUrl as CFURL, mediaBox: &mediaBox, nil)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: gc, flipped: false)

gc.beginPDFPage(nil)
gc.translateBy(x: -boundingBox.minX, y: -boundingBox.minY)
gc.beginPath()
gc.addPath(path)
if pathStyle == "jagged" {
    gc.setFillColor(fontColor)
}
gc.fillPath()
gc.endPDFPage()
gc.closePDF()

NSGraphicsContext.current = nil

let script: NSAppleScript = {
    let script = NSAppleScript(source: """
        on positionPDF(path, insertPosition)
            tell application "Keynote"
                activate
                tell the front document
                    tell the current slide
                        set thisTextItem to its text item 1
                        set thisImage to (POSIX file path) as alias
                        set thisTextPosition to the position of thisTextItem
                        set thisImagePosition to {item 1 of thisTextPosition, (item 2 of thisTextPosition) + (height of thisTextItem) + insertPosition}
                        set thisImage to make new image with properties {file:thisImage, position:thisImagePosition}
                    end tell
                end tell
            end tell
        end positionPDF
        """
    )!
    let success = script.compileAndReturnError(nil)
    assert(success)
    return script
}()

let parameters = NSAppleEventDescriptor.list()
parameters.insert(NSAppleEventDescriptor(string: outUrl.path), at: 1)
// TODO: Use fontUnderlinePosition
parameters.insert(NSAppleEventDescriptor(double: -CTFontGetDescent(font)), at: 2)

let event = NSAppleEventDescriptor(
    eventClass: AEEventClass(kASAppleScriptSuite),
    eventID: AEEventID(kASSubroutineEvent),
    targetDescriptor: nil,
    returnID: AEReturnID(kAutoGenerateReturnID),
    transactionID: AETransactionID(kAnyTransactionID)
)
event.setDescriptor(NSAppleEventDescriptor(string: "positionPDF"), forKeyword: AEKeyword(keyASSubroutineName))
event.setDescriptor(parameters, forKeyword: AEKeyword(keyDirectObject))

var error: NSDictionary? = nil
let _ = script.executeAppleEvent(event, error: &error) as NSAppleEventDescriptor?
