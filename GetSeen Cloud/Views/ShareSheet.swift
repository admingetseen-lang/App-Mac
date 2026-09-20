//
//  ShareSheet.swift
//  GetSeen Cloud
//
//  iOS/iPadOS: System-Share-Sheet (Sichern in Dateien, AirDrop, andere Apps).
//

#if os(iOS)
import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) { }
}
#endif
