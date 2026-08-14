import Contracts
import CoreGraphics

/// Cut a normalised region out of a page image.
///
/// `Region` is upper-left origin (I12) and so is `CGImage.cropping(to:)`, which
/// is the whole point of converting once at Boundary A — this function needs
/// no flip, and neither does anything else downstream.
///
/// Returns nil when the region falls outside the image.
public func crop(_ image: CGImage, to region: Region) -> CGImage? {
    let rect = CGRect(x: region.x * Double(image.width),
                      y: region.y * Double(image.height),
                      width: region.width * Double(image.width),
                      height: region.height * Double(image.height)).integral
    guard rect.width >= 1, rect.height >= 1 else { return nil }
    return image.cropping(to: rect)
}
