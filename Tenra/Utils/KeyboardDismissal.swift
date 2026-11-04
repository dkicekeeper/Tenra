//
//  KeyboardDismissal.swift
//  Tenra
//
//  The keyboard goes away when the person taps anywhere off a text field, on every screen
//  and sheet (the owner's request, 2026-10-31). One tap recognizer on each window, installed
//  as the window becomes key (AppDelegate): it sees every tap without taking it from the view
//  under it (`cancelsTouchesInView = false`, recognized alongside the others), and ends
//  editing in the window, unless the tap
//
//  - lands in a text field or text view (to move the caret or pick a word), or
//  - lands in a zone that keeps the keyboard (`.keepsKeyboardOnTap()`): an amount whose
//    display is a button that focuses a hidden field, the assistant's composer with its send
//    button. A tap there would hide the keyboard the view is about to use.
//
//  - moves the focus to another field (a button that focuses one): the keyboard is the new
//    field's then. The decision waits 0.1 s for the tap's own action and the focus change it
//    makes, and ends editing only when the field that had the keyboard as the tap began still
//    has it.
//
//  A button tapped while typing does its job and the keyboard goes, as in iOS's own forms.
//

import SwiftUI
import UIKit

@MainActor
final class KeyboardDismissal: NSObject, UIGestureRecognizerDelegate {

    static let shared = KeyboardDismissal()

    private static let recognizerName = "tenra.keyboardDismissal"

    /// The zones that keep the keyboard, in window coordinates (`.global`).
    private var keepZones: [UUID: CGRect] = [:]
    private var observer: NSObjectProtocol?
    /// The text input that had the keyboard when the tap began.
    private weak var editingAtTouch: UIResponder?

    /// Installs the recognizer on every window that becomes key, and on those already there.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { notification in
            guard let window = notification.object as? UIWindow else { return }
            MainActor.assumeIsolated { KeyboardDismissal.shared.install(on: window) }
        }
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach(install(on:))
        }
    }

    private func install(on window: UIWindow) {
        guard !(window.gestureRecognizers ?? []).contains(where: { $0.name == Self.recognizerName }) else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.name = Self.recognizerName
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
    }

    func setKeepZone(_ id: UUID, frame: CGRect?) {
        keepZones[id] = frame
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let window = recognizer.view as? UIWindow,
              let editing = editingAtTouch else { return }
        let point = recognizer.location(in: window)
        guard !keepZones.values.contains(where: { $0.contains(point) }) else { return }
        // After the tapped view's own action and the focus change it makes (SwiftUI moves the
        // first responder on its next update): a button that focused another field keeps it.
        Task { @MainActor [weak window, weak editing] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let window, let editing, editing.isFirstResponder else { return }
            window.endEditing(true)
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Nothing to hide without a field that has the keyboard.
        editingAtTouch = UIResponder.tenraFirstResponder
        guard editingAtTouch != nil else { return false }
        // A tap in a text input moves its caret or picks a word: the keyboard stays.
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        return true
    }
}

private extension UIResponder {
    private static weak var found: UIResponder?

    /// The first responder of the app, if any: the field that has the keyboard.
    static var tenraFirstResponder: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(tenraReportFirstResponder), to: nil, from: nil, for: nil)
        return found
    }

    @objc func tenraReportFirstResponder() {
        UIResponder.found = self
    }
}

private struct KeepsKeyboardOnTap: ViewModifier {
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                KeyboardDismissal.shared.setKeepZone(id, frame: frame)
            }
            .onDisappear { KeyboardDismissal.shared.setKeepZone(id, frame: nil) }
    }
}

extension View {
    /// A tap on this view leaves the keyboard up (`KeyboardDismissal`): a control that focuses a
    /// field itself, or sits next to the field it sends.
    func keepsKeyboardOnTap() -> some View {
        modifier(KeepsKeyboardOnTap())
    }
}
