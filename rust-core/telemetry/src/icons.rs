//! Normalizes process icons for remote clients: every icon becomes a square 128 px PNG
//! identified by the SHA-256 of its bytes.
//!
//! Sources are untrusted files from the host's icon themes. PNG sources larger than 512 px
//! are dropped; SVG sources are rendered into a fixed 128 px canvas with external references
//! disabled, so their cost does not grow with the declared size. SVGZ, XPM and anything else
//! is unsupported; the client then shows the letter fallback.
use image::{ImageFormat, ImageReader, Limits, RgbaImage, imageops::FilterType};
use sha2::{Digest, Sha256};
use std::io::Cursor;

/// Edge of a normalized icon.
pub const TARGET_PX: u32 = 128;
/// Largest PNG source edge.
pub const MAX_SOURCE_PX: u32 = 512;
/// Largest source file read.
pub const MAX_SOURCE_BYTES: usize = 1024 * 1024;
/// Largest normalized icon.
pub const MAX_ICON_BYTES: usize = 256 * 1024;

const PNG_SIGNATURE: &[u8] = b"\x89PNG\r\n\x1a\n";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum IconError {
    /// Over a size bound.
    TooLarge,
    /// Not a PNG or SVG.
    Unsupported,
    /// Could not be decoded.
    Malformed,
}

/// Lowercase hexadecimal SHA-256.
pub fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn looks_like_svg(bytes: &[u8]) -> bool {
    let head = &bytes[..bytes.len().min(1024)];
    let text = String::from_utf8_lossy(head);
    let trimmed = text.trim_start_matches('\u{feff}').trim_start();
    trimmed.starts_with("<?xml") || trimmed.starts_with("<svg") || trimmed.contains("<svg")
}

/// Normalizes icon source bytes to a 128 px PNG.
///
/// # Errors
/// The source is too large, not a PNG or SVG, or malformed.
pub fn normalize(bytes: &[u8]) -> Result<Vec<u8>, IconError> {
    if bytes.len() > MAX_SOURCE_BYTES {
        return Err(IconError::TooLarge);
    }
    let canvas = if bytes.starts_with(PNG_SIGNATURE) {
        normalize_png(bytes)?
    } else if bytes.starts_with(&[0x1f, 0x8b]) {
        // SVGZ would decompress without our byte budget.
        return Err(IconError::Unsupported);
    } else if looks_like_svg(bytes) {
        render_svg(bytes)?
    } else {
        return Err(IconError::Unsupported);
    };
    let mut encoded = Vec::new();
    canvas
        .write_to(&mut Cursor::new(&mut encoded), ImageFormat::Png)
        .map_err(|_| IconError::Malformed)?;
    if encoded.len() > MAX_ICON_BYTES {
        return Err(IconError::TooLarge);
    }
    Ok(encoded)
}

fn normalize_png(bytes: &[u8]) -> Result<RgbaImage, IconError> {
    let mut reader = ImageReader::with_format(Cursor::new(bytes), ImageFormat::Png);
    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_SOURCE_PX);
    limits.max_image_height = Some(MAX_SOURCE_PX);
    limits.max_alloc = Some(u64::from(MAX_SOURCE_PX * MAX_SOURCE_PX) * 16);
    reader.limits(limits);
    let image = reader.decode().map_err(|error| match error {
        image::ImageError::Limits(_) => IconError::TooLarge,
        _ => IconError::Malformed,
    })?;
    let (width, height) = (image.width(), image.height());
    if width == 0 || height == 0 {
        return Err(IconError::Malformed);
    }
    let rgba = image.to_rgba8();
    if width == TARGET_PX && height == TARGET_PX {
        return Ok(rgba);
    }
    let scale = f64::from(TARGET_PX) / f64::from(width.max(height));
    let scaled_width = ((f64::from(width) * scale).round() as u32).clamp(1, TARGET_PX);
    let scaled_height = ((f64::from(height) * scale).round() as u32).clamp(1, TARGET_PX);
    let resized = image::imageops::resize(&rgba, scaled_width, scaled_height, FilterType::Lanczos3);
    let mut canvas = RgbaImage::new(TARGET_PX, TARGET_PX);
    image::imageops::overlay(
        &mut canvas,
        &resized,
        i64::from((TARGET_PX - scaled_width) / 2),
        i64::from((TARGET_PX - scaled_height) / 2),
    );
    Ok(canvas)
}

fn render_svg(bytes: &[u8]) -> Result<RgbaImage, IconError> {
    let options = resvg::usvg::Options {
        image_href_resolver: resvg::usvg::ImageHrefResolver {
            resolve_data: Box::new(|_, _, _| None),
            resolve_string: Box::new(|_, _| None),
        },
        ..Default::default()
    };
    let tree = resvg::usvg::Tree::from_data(bytes, &options).map_err(|_| IconError::Malformed)?;
    let size = tree.size();
    let (width, height) = (size.width(), size.height());
    if !(width.is_finite() && height.is_finite()) || width <= 0.0 || height <= 0.0 {
        return Err(IconError::Malformed);
    }
    let scale = TARGET_PX as f32 / width.max(height);
    let offset_x = (TARGET_PX as f32 - width * scale) / 2.0;
    let offset_y = (TARGET_PX as f32 - height * scale) / 2.0;
    let mut pixmap =
        resvg::tiny_skia::Pixmap::new(TARGET_PX, TARGET_PX).ok_or(IconError::Malformed)?;
    resvg::render(
        &tree,
        resvg::tiny_skia::Transform::from_row(scale, 0.0, 0.0, scale, offset_x, offset_y),
        &mut pixmap.as_mut(),
    );
    RgbaImage::from_raw(TARGET_PX, TARGET_PX, pixmap.take_demultiplied())
        .ok_or(IconError::Malformed)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn png(width: u32, height: u32) -> Vec<u8> {
        let image = RgbaImage::from_pixel(width, height, image::Rgba([200, 30, 30, 255]));
        let mut bytes = Vec::new();
        image
            .write_to(&mut Cursor::new(&mut bytes), ImageFormat::Png)
            .unwrap();
        bytes
    }

    fn dimensions(bytes: &[u8]) -> (u32, u32) {
        let image = image::load_from_memory_with_format(bytes, ImageFormat::Png).unwrap();
        (image.width(), image.height())
    }

    #[test]
    fn png_sources_become_128_px_squares() {
        assert_eq!(dimensions(&normalize(&png(128, 128)).unwrap()), (128, 128));
        assert_eq!(dimensions(&normalize(&png(48, 48)).unwrap()), (128, 128));
        assert_eq!(dimensions(&normalize(&png(512, 256)).unwrap()), (128, 128));
    }

    #[test]
    fn png_sources_over_512_px_are_dropped() {
        assert_eq!(normalize(&png(513, 16)), Err(IconError::TooLarge));
    }

    #[test]
    fn svg_sources_are_rasterized() {
        let svg = br##"<svg xmlns="http://www.w3.org/2000/svg" width="4096" height="2048" viewBox="0 0 2 1"><rect width="2" height="1" fill="#09f"/></svg>"##;
        let png = normalize(svg).unwrap();
        assert_eq!(dimensions(&png), (128, 128));
        let image = image::load_from_memory(&png).unwrap().to_rgba8();
        assert_eq!(image.get_pixel(64, 64)[3], 255, "content is centered");
        assert_eq!(
            image.get_pixel(64, 2)[3],
            0,
            "letterboxed outside the aspect ratio"
        );
    }

    #[test]
    fn external_references_are_not_loaded() {
        let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="16" height="16"><image width="16" height="16" xlink:href="file:///etc/passwd"/></svg>"#;
        let png = normalize(svg).unwrap();
        let image = image::load_from_memory(&png).unwrap().to_rgba8();
        assert!(image.pixels().all(|pixel| pixel[3] == 0));
    }

    #[test]
    fn other_formats_are_unsupported() {
        assert_eq!(
            normalize(b"/* XPM */ static char *x[] = {};"),
            Err(IconError::Unsupported)
        );
        assert_eq!(normalize(&[0x1f, 0x8b, 0, 0]), Err(IconError::Unsupported));
        assert_eq!(
            normalize(b"\x89PNG\r\n\x1a\nbroken"),
            Err(IconError::Malformed)
        );
        assert_eq!(
            normalize(&vec![b' '; MAX_SOURCE_BYTES + 1]),
            Err(IconError::TooLarge)
        );
    }

    #[test]
    fn hashes_are_stable() {
        let first = normalize(&png(48, 48)).unwrap();
        let second = normalize(&png(48, 48)).unwrap();
        assert_eq!(sha256_hex(&first), sha256_hex(&second));
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }
}
