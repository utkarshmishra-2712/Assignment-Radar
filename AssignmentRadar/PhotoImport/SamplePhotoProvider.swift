//
//  SamplePhotoProvider.swift
//  AssignmentRadar
//
//  Generates a crisp sample syllabus/noticeboard image for testing Vision OCR
//  directly in the iOS Simulator without requiring a physical camera.
//

import UIKit

final class SamplePhotoProvider {

    /// Generates a realistic high-resolution university assignment noticeboard image.
    static func makeSampleSyllabusImage() -> UIImage {
        let size = CGSize(width: 1000, height: 750)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let cgContext = context.cgContext

            // 1. Background fill
            let bgRect = CGRect(origin: .zero, size: size)
            cgContext.setFillColor(UIColor(red: 0.95, green: 0.97, blue: 0.96, alpha: 1.0).cgColor)
            cgContext.fill(bgRect)

            // 2. White Card Board
            let cardRect = CGRect(x: 40, y: 40, width: 920, height: 670)
            let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 24)
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.setShadow(offset: CGSize(width: 0, height: 6), blur: 16, color: UIColor.black.withAlphaComponent(0.08).cgColor)
            path.fill()

            // Reset shadow
            cgContext.setShadow(offset: .zero, blur: 0, color: nil)

            // Accent header strip
            let headerStrip = CGRect(x: 40, y: 40, width: 920, height: 12)
            let headerPath = UIBezierPath(roundedRect: headerStrip, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 24, height: 24))
            cgContext.setFillColor(UIColor(red: 0.18, green: 0.44, blue: 0.42, alpha: 1.0).cgColor) // Teal primary
            headerPath.fill()

            // 3. Text Attributes
            let courseAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .bold),
                .foregroundColor: UIColor(red: 0.07, green: 0.19, blue: 0.18, alpha: 1.0)
            ]

            let subheaderAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: UIColor(red: 0.42, green: 0.50, blue: 0.49, alpha: 1.0)
            ]

            let itemTitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor(red: 0.10, green: 0.22, blue: 0.20, alpha: 1.0)
            ]

            let itemDateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: UIColor(red: 0.92, green: 0.38, blue: 0.26, alpha: 1.0) // Coral accent
            ]

            // 4. Draw Header
            let titleString = "CS301: Advanced Software Systems"
            (titleString as NSString).draw(at: CGPoint(x: 80, y: 80), withAttributes: courseAttrs)

            let subheader = "Fall Term — Upcoming Assignment Deadlines"
            (subheader as NSString).draw(at: CGPoint(x: 80, y: 130), withAttributes: subheaderAttrs)

            // Divider line
            cgContext.setStrokeColor(UIColor(red: 0.88, green: 0.92, blue: 0.91, alpha: 1.0).cgColor)
            cgContext.setLineWidth(2)
            cgContext.move(to: CGPoint(x: 80, y: 175))
            cgContext.addLine(to: CGPoint(x: 920, y: 175))
            cgContext.strokePath()

            // 5. Draw Deliverables
            let items: [(title: String, due: String, yOffset: CGFloat)] = [
                (
                    title: "1. Problem Set 4: Distributed Systems Architecture",
                    due: "Due: October 30, 2026 at 11:59 PM",
                    yOffset: 210
                ),
                (
                    title: "2. Midterm Database Schema Implementation",
                    due: "Due: November 15, 2026 at 5:00 PM",
                    yOffset: 340
                ),
                (
                    title: "3. Final Capstone Project Report",
                    due: "Due: December 08, 2026 at 11:59 PM",
                    yOffset: 470
                )
            ]

            for item in items {
                // Card for item
                let itemCard = CGRect(x: 80, y: item.yOffset, width: 840, height: 100)
                let itemPath = UIBezierPath(roundedRect: itemCard, cornerRadius: 14)
                cgContext.setFillColor(UIColor(red: 0.97, green: 0.98, blue: 0.98, alpha: 1.0).cgColor)
                itemPath.fill()

                // Draw Text
                (item.title as NSString).draw(at: CGPoint(x: 105, y: item.yOffset + 18), withAttributes: itemTitleAttrs)
                (item.due as NSString).draw(at: CGPoint(x: 105, y: item.yOffset + 56), withAttributes: itemDateAttrs)
            }

            // Footer note
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .regular),
                .foregroundColor: UIColor(red: 0.55, green: 0.62, blue: 0.61, alpha: 1.0)
            ]
            let footer = "Please submit all deliverables directly to Moodle before the stated cutoff."
            (footer as NSString).draw(at: CGPoint(x: 80, y: 625), withAttributes: footerAttrs)
        }
    }
}
