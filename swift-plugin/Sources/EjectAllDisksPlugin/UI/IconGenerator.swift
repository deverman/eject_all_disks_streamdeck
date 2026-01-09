//
//  IconGenerator.swift
//  EjectAllDisksPlugin
//
//  Generates SVG icons for the Stream Deck button states.
//  Ported from the TypeScript implementation.
//

import Foundation

/// Generates SVG icons for the Eject All Disks action button
public enum IconGenerator {

    // MARK: - Color Constants

    /// Colors used for icon states
    enum Colors {
        /// Normal eject icon color (orange)
        static let normal = "#FF9F0A"
        /// Ejecting/in-progress color (yellow)
        static let ejecting = "#FFCC00"
        /// Success color (green)
        static let success = "#34C759"
        /// Error color (red)
        static let error = "#FF3B30"
        /// Badge background color (red)
        static let badge = "#FF3B30"
        /// Background circle color
        static let background = "#222222"
        /// Stroke color
        static let stroke = "#000000"
        /// Text color
        static let text = "#FFFFFF"
    }

    // MARK: - SVG Generation

    /// Creates the normal eject icon SVG with optional disk count badge
    /// - Parameter count: Number of ejectable disks (0 hides the badge)
    /// - Returns: SVG string encoded as a data URI
    public static func createNormalSvg(count: Int = 0) -> String {
        let badgeMarkup = count > 0 ? """
              <g>
                <circle cx="110" cy="34" r="20" fill="\(Colors.badge)" stroke="\(Colors.stroke)" stroke-width="2"/>
                <text x="110" y="42" text-anchor="middle" font-family="Arial, sans-serif" font-size="24" font-weight="bold" fill="\(Colors.text)">\(count)</text>
              </g>
        """ : ""

        let svg = """
        <svg width="144" height="144" viewBox="0 0 144 144" xmlns="http://www.w3.org/2000/svg">
          <!-- Dark background circle for better text contrast -->
          <circle cx="72" cy="72" r="65" fill="\(Colors.background)" opacity="0.6"/>
          <g fill="\(Colors.normal)">
            <!-- Triangle shape pointing upward -->
            <path d="M72 36L112 90H32L72 36Z" stroke="\(Colors.stroke)" stroke-width="2"/>
            <!-- Horizontal line beneath the triangle -->
            <rect x="32" y="100" width="80" height="10" rx="2" stroke="\(Colors.stroke)" stroke-width="2"/>
          </g>
          <!-- Disk count badge -->
          \(badgeMarkup)
        </svg>
        """

        return encodeAsDataUri(svg)
    }

    /// Creates the ejecting icon SVG with animation
    /// - Returns: SVG string encoded as a data URI
    public static func createEjectingSvg() -> String {
        let svg = """
        <svg width="144" height="144" viewBox="0 0 144 144" xmlns="http://www.w3.org/2000/svg">
          <!-- Dark background circle for better text contrast -->
          <circle cx="72" cy="72" r="65" fill="\(Colors.background)" opacity="0.7"/>
          <g fill="\(Colors.ejecting)">
            <!-- Triangle shape pointing upward with animation effect -->
            <path d="M72 36L112 90H32L72 36Z" stroke="\(Colors.stroke)" stroke-width="2">
              <animate attributeName="opacity" values="0.7;1;0.7" dur="1s" repeatCount="indefinite" />
            </path>
            <!-- Horizontal line beneath the triangle -->
            <rect x="32" y="100" width="80" height="10" rx="2" stroke="\(Colors.stroke)" stroke-width="2"/>
          </g>
        </svg>
        """

        return encodeAsDataUri(svg)
    }

    /// Creates the success icon SVG with checkmark
    /// - Returns: SVG string encoded as a data URI
    public static func createSuccessSvg() -> String {
        let svg = """
        <svg width="144" height="144" viewBox="0 0 144 144" xmlns="http://www.w3.org/2000/svg">
          <!-- Dark background circle for better text contrast -->
          <circle cx="72" cy="72" r="65" fill="\(Colors.background)" opacity="0.7"/>
          <g fill="\(Colors.success)">
            <!-- Triangle shape pointing upward -->
            <path d="M72 36L112 90H32L72 36Z" stroke="\(Colors.stroke)" stroke-width="2"/>
            <!-- Horizontal line beneath the triangle -->
            <rect x="32" y="100" width="80" height="10" rx="2" stroke="\(Colors.stroke)" stroke-width="2"/>
            <!-- Checkmark -->
            <path d="M52 72L67 87L92 57" stroke="\(Colors.text)" stroke-width="6" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
          </g>
        </svg>
        """

        return encodeAsDataUri(svg)
    }

    /// Creates the error icon SVG with X mark
    /// - Returns: SVG string encoded as a data URI
    public static func createErrorSvg() -> String {
        let svg = """
        <svg width="144" height="144" viewBox="0 0 144 144" xmlns="http://www.w3.org/2000/svg">
          <!-- Dark background circle for better text contrast -->
          <circle cx="72" cy="72" r="65" fill="\(Colors.background)" opacity="0.8"/>
          <g fill="\(Colors.error)">
            <!-- Triangle shape pointing upward -->
            <path d="M72 36L112 90H32L72 36Z" stroke="\(Colors.stroke)" stroke-width="2"/>
            <!-- Horizontal line beneath the triangle -->
            <rect x="32" y="100" width="80" height="10" rx="2" stroke="\(Colors.stroke)" stroke-width="2"/>
            <!-- X mark -->
            <path d="M60 60L84 84M84 60L60 84" stroke="\(Colors.text)" stroke-width="6" stroke-linecap="round"/>
          </g>
        </svg>
        """

        return encodeAsDataUri(svg)
    }

    // MARK: - Utility

    /// Encodes an SVG string as a data URI for use with setImage
    /// - Parameter svg: Raw SVG string
    /// - Returns: Data URI encoded string
    private static func encodeAsDataUri(_ svg: String) -> String {
        let encoded = svg.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? svg
        return "data:image/svg+xml,\(encoded)"
    }

    /// Creates a raw SVG string without data URI encoding (for testing)
    /// - Parameter count: Number of ejectable disks
    /// - Returns: Raw SVG string
    public static func createNormalSvgRaw(count: Int = 0) -> String {
        let badgeMarkup = count > 0 ? """
              <g>
                <circle cx="110" cy="34" r="20" fill="\(Colors.badge)" stroke="\(Colors.stroke)" stroke-width="2"/>
                <text x="110" y="42" text-anchor="middle" font-family="Arial, sans-serif" font-size="24" font-weight="bold" fill="\(Colors.text)">\(count)</text>
              </g>
        """ : ""

        return """
        <svg width="144" height="144" viewBox="0 0 144 144" xmlns="http://www.w3.org/2000/svg">
          <!-- Dark background circle for better text contrast -->
          <circle cx="72" cy="72" r="65" fill="\(Colors.background)" opacity="0.6"/>
          <g fill="\(Colors.normal)">
            <!-- Triangle shape pointing upward -->
            <path d="M72 36L112 90H32L72 36Z" stroke="\(Colors.stroke)" stroke-width="2"/>
            <!-- Horizontal line beneath the triangle -->
            <rect x="32" y="100" width="80" height="10" rx="2" stroke="\(Colors.stroke)" stroke-width="2"/>
          </g>
          <!-- Disk count badge -->
          \(badgeMarkup)
        </svg>
        """
    }
}
