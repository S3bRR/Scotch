import Foundation
import AppKit

public struct ColorQuad {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8
}

public enum BitmapCompression: UInt32 {
    case rgb = 0x0000
    case rle8 = 0x0001
    case rle4 = 0x0002
    case bitfields = 0x0003
    case jpeg = 0x0004
    case png = 0x0005
    case alphaBitfields = 0x0006
    case cmyk = 0x000B
    case cmykRle8 = 0x000C
    case cmykRle4 = 0x000D
}

public enum BitmapOriginDirection {
    case bottomLeft
    case upperLeft
}

public enum ColorFormat: UInt16 {
    case unknown = 0
    case indexed1 = 1
    case indexed2 = 2
    case indexed4 = 4
    case indexed8 = 8
    case sampled16 = 16
    case sampled24 = 24
    case sampled32 = 32
}

public struct BitmapInfoHeader: Hashable {
    public let size: UInt32
    public let width: Int32
    public let height: Int32
    public let planes: UInt16
    public let bitCount: UInt16
    public let compression: BitmapCompression
    public let sizeImage: UInt32
    public let xPelsPerMeter: Int32
    public let yPelsPerMeter: Int32
    public let clrUsed: UInt32
    public let clrImportant: UInt32

    public let originDirection: BitmapOriginDirection
    public let colorFormat: ColorFormat

    init(handle: FileHandle, offset: UInt64) {
        var offset = offset
        self.size = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        self.width = handle.extract(Int32.self, offset: offset) ?? 0
        offset += 4
        self.height = handle.extract(Int32.self, offset: offset) ?? 0
        offset += 4
        self.planes = handle.extract(UInt16.self, offset: offset) ?? 0
        offset += 2
        self.bitCount = handle.extract(UInt16.self, offset: offset) ?? 0
        offset += 2
        self.compression = BitmapCompression(rawValue: handle.extract(UInt32.self, offset: offset) ?? 0) ?? .rgb
        offset += 4
        self.sizeImage = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        self.xPelsPerMeter = handle.extract(Int32.self, offset: offset) ?? 0
        offset += 4
        self.yPelsPerMeter = handle.extract(Int32.self, offset: offset) ?? 0
        offset += 4
        self.clrUsed = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        self.clrImportant = handle.extract(UInt32.self, offset: offset) ?? 0

        self.originDirection = self.height < 0 ? .upperLeft : .bottomLeft
        self.colorFormat = ColorFormat(rawValue: bitCount) ?? .unknown
    }

    func renderBitmap(handle: FileHandle, offset: UInt64, dataEnd: UInt64) -> NSImage? {
        guard width > 0,
              height > 0,
              height % 2 == 0,
              width <= 4096,
              height / 2 <= 4096,
              planes == 1,
              compression == .rgb else {
            return nil
        }

        let pixelWidth = Int(width)
        let pixelHeight = Int(height / 2)
        let bitsPerPixel = Int(bitCount)
        guard let bytesPerPixel = bytesPerPixel(for: colorFormat) else {
            return nil
        }

        var offset = offset
        guard let colorTable = buildColorTable(offset: &offset, handle: handle, dataEnd: dataEnd) else {
            return nil
        }

        var pixels: [ColorQuad] = []
        pixels.reserveCapacity(pixelWidth * pixelHeight)

        let rowStride = ((pixelWidth * bitsPerPixel + 31) / 32) * 4
        let pixelDataStart = offset

        for rowIndex in 0..<pixelHeight {
            var pixelRow: [ColorQuad] = []
            pixelRow.reserveCapacity(pixelWidth)
            let rowOffset = pixelDataStart + UInt64(rowIndex * rowStride)
            var cursor = rowOffset

            for _ in 0..<pixelWidth {
                guard cursor + UInt64(bytesPerPixel) <= dataEnd else {
                    return nil
                }
                switch colorFormat {
                case .indexed1, .indexed2, .indexed4:
                    return nil
                case .indexed8:
                    let index = Int(handle.extract(UInt8.self, offset: cursor) ?? 0)
                    if index >= colorTable.count {
                        pixelRow.append(ColorQuad(red: 0, green: 0, blue: 0, alpha: 0))
                    } else {
                        pixelRow.append(colorTable[Int(index)])
                    }
                    cursor += 1
                case .sampled16:
                    let sample = handle.extract(UInt16.self, offset: cursor) ?? 0
                    let red = sample & 0x001F
                    let green = (sample & 0x03E0) >> 5
                    let blue = (sample & 0x7C00) >> 10
                    pixelRow.append(ColorQuad(red: UInt8(red << 3), green: UInt8(green << 3), blue: UInt8(blue << 3), alpha: 255))
                    cursor += 2
                case .sampled24:
                    let blue = handle.extract(UInt8.self, offset: cursor) ?? 0
                    cursor += 1
                    let green = handle.extract(UInt8.self, offset: cursor) ?? 0
                    cursor += 1
                    let red = handle.extract(UInt8.self, offset: cursor) ?? 0
                    cursor += 1
                    pixelRow.append(ColorQuad(red: red, green: green, blue: blue, alpha: 255))
                case .sampled32:
                    let blue = handle.extract(UInt8.self, offset: cursor) ?? 0
                    cursor += 1
                    let green = handle.extract(UInt8.self, offset: cursor) ?? 0
                    cursor += 1
                    let red = handle.extract(UInt8.self, offset: cursor) ?? 0
                    cursor += 1
                    let alpha = handle.extract(UInt8.self, offset: cursor) ?? 0
                    cursor += 1
                    pixelRow.append(ColorQuad(red: red, green: green, blue: blue, alpha: alpha))
                case .unknown:
                    return nil
                }
            }

            if originDirection == .upperLeft {
                pixels.append(contentsOf: pixelRow)
            } else {
                pixels.insert(contentsOf: pixelRow, at: 0)
            }
        }

        return constructImage(pixels: pixels, width: pixelWidth, height: pixelHeight)
    }

    private func bytesPerPixel(for format: ColorFormat) -> Int? {
        switch format {
        case .indexed8:
            1
        case .sampled16:
            2
        case .sampled24:
            3
        case .sampled32:
            4
        case .indexed1, .indexed2, .indexed4, .unknown:
            nil
        }
    }

    private func buildColorTable(offset: inout UInt64, handle: FileHandle, dataEnd: UInt64) -> [ColorQuad]? {
        var colorTable: [ColorQuad] = []
        let colorCount: UInt32

        if clrUsed > 0 {
            colorCount = clrUsed
        } else if colorFormat == .indexed8 {
            colorCount = 256
        } else {
            colorCount = 0
        }

        guard colorCount <= 256 else {
            return nil
        }

        for _ in 0..<colorCount {
            guard offset + 4 <= dataEnd else {
                return nil
            }
            let blue = handle.extract(UInt8.self, offset: offset) ?? 0
            offset += 1
            let green = handle.extract(UInt8.self, offset: offset) ?? 0
            offset += 1
            let red = handle.extract(UInt8.self, offset: offset) ?? 0
            offset += 2

            colorTable.append(
                ColorQuad(
                    red: red,
                    green: green,
                    blue: blue,
                    alpha: (Int(red) + Int(green) + Int(blue) == 0) ? 0 : 255
                )
            )
        }

        return colorTable
    }

    private func constructImage(pixels: [ColorQuad], width: Int, height: Int) -> NSImage? {
        guard !pixels.isEmpty else { return nil }

        var pixels = pixels
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        let quadStride = MemoryLayout<ColorQuad>.stride
        let byteCount = pixels.count * quadStride

        guard pixels.count == width * height else {
            return nil
        }

        guard let providerRef = CGDataProvider(data: Data(bytes: &pixels, count: byteCount) as CFData) else {
            return nil
        }

        guard let cgImg = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * quadStride,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: providerRef,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return NSImage(cgImage: cgImg, size: .zero)
    }
}
