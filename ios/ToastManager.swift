import SwiftUI
import Combine
import UIKit

@objc public class ToastManager: NSObject {
    private var overlayWindow: PassThroughWindow?
    private var hostingController: CustomHostingView?
    private var autoDismissTimer: Timer?
    private var dismissCancellable: AnyCancellable?
    private var tapCancellable: AnyCancellable?
    private var actionCancellable: AnyCancellable?
    // Guards against double-firing onDismiss when a programmatic dismiss
    // also trips the Combine subscription on `isPresented`.
    private var isDismissing = false
    // Deferred so the status bar doesn't flash back in mid-collapse, and
    // cancellable so a queued toast keeps it hidden across the handoff.
    private var statusBarRestoreWorkItem: DispatchWorkItem?
    private var imageLoadTask: URLSessionDataTask?

    @objc public var onDismiss: (() -> Void)?
    @objc public var onPress: (() -> Void)?
    @objc public var onActionPress: (() -> Void)?

    @objc public func show(
        icon: String,
        iconUri: String,
        title: String,
        message: String,
        duration: Int,
        autoDismiss: Bool,
        enableSwipeDismiss: Bool,
        useDynamicIsland: Bool,
        accentColor: UIColor?,
        strokeColor: UIColor?,
        disableBackdropSampling: Bool,
        actionLabel: String
    ) {
        // A new window, or one hidden since the last toast, lays the collapsed
        // pill out first so the open animation has a starting frame.
        let needsLayoutPass = overlayWindow?.isHidden ?? true
        ensureOverlayWindow()

        guard let overlayWindow else { return }
        overlayWindow.isHidden = false

        let (primary, secondary) = iconColors(for: icon)
        let accent = accentColor.map { Color($0) }
        let stroke = strokeColor.map { Color($0) }

        let toast = Toast(
            symbol: icon,
            symbolFont: .system(size: 35),
            symbolForegroundStyle: (primary, accent ?? secondary),
            title: title,
            message: message,
            customIcon: nil,
            accentOverride: accent,
            strokeOverride: stroke,
            disableBackdropSampling: disableBackdropSampling,
            actionLabel: actionLabel.isEmpty ? nil : actionLabel
        )

        overlayWindow.toast = toast
        overlayWindow.useDynamicIsland = useDynamicIsland
        overlayWindow.wasTapped = false
        overlayWindow.actionTapped = false
        isDismissing = false

        loadCustomIconIfNeeded(uri: iconUri)

        let present = { [weak self] in
            guard let self, let overlayWindow = self.overlayWindow else { return }
            overlayWindow.isPresented = true
            if !disableBackdropSampling {
                overlayWindow.startBackdropSampling()
            }
            self.cancelStatusBarRestore()
            self.setStatusBarHidden(true)
            overlayWindow.makeKey()

            self.cancelTimer()
            if autoDismiss && duration > 0 {
                let interval = TimeInterval(duration) / 1000.0
                self.autoDismissTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.dismiss()
                    }
                }
            }
        }

        if needsLayoutPass {
            DispatchQueue.main.async(execute: present)
        } else {
            present()
        }
    }

    @objc public func update(
        icon: String,
        iconUri: String,
        title: String,
        message: String,
        duration: Int,
        autoDismiss: Bool,
        accentColor: UIColor?,
        strokeColor: UIColor?,
        disableBackdropSampling: Bool,
        actionLabel: String
    ) {
        guard let overlayWindow, overlayWindow.isPresented else { return }

        let (primary, secondary) = iconColors(for: icon)
        let accent = accentColor.map { Color($0) }
        let stroke = strokeColor.map { Color($0) }

        // Carry the resolved customIcon forward; loadCustomIconIfNeeded
        // swaps it if the URI changed.
        let previous = overlayWindow.toast
        overlayWindow.toast = Toast(
            symbol: icon,
            symbolFont: .system(size: 35),
            symbolForegroundStyle: (primary, accent ?? secondary),
            title: title,
            message: message,
            customIcon: previous?.customIcon,
            accentOverride: accent,
            strokeOverride: stroke,
            disableBackdropSampling: disableBackdropSampling,
            actionLabel: actionLabel.isEmpty ? nil : actionLabel
        )

        loadCustomIconIfNeeded(uri: iconUri)

        if disableBackdropSampling {
            overlayWindow.stopBackdropSampling()
        } else if overlayWindow.isPresented {
            overlayWindow.startBackdropSampling()
        }

        cancelTimer()
        if autoDismiss && duration > 0 {
            let interval = TimeInterval(duration) / 1000.0
            autoDismissTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.dismiss()
                }
            }
        }
    }

    @objc public func dismiss() {
        cancelTimer()

        guard let overlayWindow, overlayWindow.isPresented, !isDismissing else { return }
        isDismissing = true

        overlayWindow.isPresented = false
        overlayWindow.stopBackdropSampling()
        imageLoadTask?.cancel()
        imageLoadTask = nil
        scheduleStatusBarRestore()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.onDismiss?()
        }
    }

    // MARK: - Overlay Window

    private func ensureOverlayWindow() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        if let existing = windowScene.windows.first(where: { $0.tag == 1009 }) as? PassThroughWindow {
            overlayWindow = existing
            hostingController = existing.rootViewController as? CustomHostingView
        } else {
            let window = PassThroughWindow(windowScene: windowScene)
            window.backgroundColor = .clear
            window.isHidden = false
            window.isUserInteractionEnabled = true
            window.tag = 1009

            let hosting = CustomHostingView(
                rootView: PrettyToastView(window: window)
            )
            hosting.view.backgroundColor = .clear
            window.rootViewController = hosting

            overlayWindow = window
            hostingController = hosting
        }

        observeDismiss()
        observeTap()
        observeAction()
    }

    // Catches swipe-dismissals that flip `isPresented` from outside dismiss().
    private func observeDismiss() {
        guard let overlayWindow else { return }

        dismissCancellable = overlayWindow.$isPresented
            .dropFirst()
            .filter { !$0 }
            .sink { [weak self] _ in
                guard let self, !self.isDismissing else { return }
                self.isDismissing = true
                self.cancelTimer()
                self.overlayWindow?.stopBackdropSampling()
                self.scheduleStatusBarRestore()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.onDismiss?()
                }
            }
    }

    private func observeTap() {
        guard let overlayWindow else { return }

        tapCancellable = overlayWindow.$wasTapped
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else { return }
                self.overlayWindow?.wasTapped = false
                self.onPress?()
            }
    }

    private func observeAction() {
        guard let overlayWindow else { return }

        actionCancellable = overlayWindow.$actionTapped
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else { return }
                self.overlayWindow?.actionTapped = false
                self.onActionPress?()
            }
    }

    // MARK: - Helpers

    private func loadCustomIconIfNeeded(uri: String) {
        imageLoadTask?.cancel()
        imageLoadTask = nil

        if uri.isEmpty {
            overlayWindow?.toast?.customIcon = nil
            return
        }

        // file:// URIs load synchronously; remote URLs fall through below.
        if let url = URL(string: uri),
           url.isFileURL,
           let image = UIImage(contentsOfFile: url.path) {
            overlayWindow?.toast?.customIcon = image
            // Reassign the whole struct so @Published fires.
            if var t = overlayWindow?.toast {
                t.customIcon = image
                overlayWindow?.toast = t
            }
            return
        }

        guard let url = URL(string: uri) else { return }

        imageLoadTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                if var t = self.overlayWindow?.toast {
                    t.customIcon = image
                    self.overlayWindow?.toast = t
                }
            }
        }
        imageLoadTask?.resume()
    }

    private func restoreKeyWindow() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.tag != 1009 && !$0.isHidden }?
            .makeKey()
    }

    private func cancelTimer() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
    }

    // 0.5s ≈ collapse animation (0.35s) + JS round-trip slack so a follow-up
    // show() can cancel this and keep the status bar hidden. Key-window
    // handoff is bundled in to prevent the status bar from fading in
    // behind the shrinking pill.
    private func scheduleStatusBarRestore() {
        statusBarRestoreWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.setStatusBarHidden(false)
            self.restoreKeyWindow()
            // A visible full-screen window above the app's owns the status bar:
            // iOS asks its controller, so the app's own screens could no longer
            // hide or restyle the bar after the first toast. Hide it between
            // toasts.
            self.overlayWindow?.isHidden = true
        }
        statusBarRestoreWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func cancelStatusBarRestore() {
        statusBarRestoreWorkItem?.cancel()
        statusBarRestoreWorkItem = nil
    }

    // iPadOS keeps its status bar visible so the toast does not change the
    // larger tablet navigation chrome. iPhone still hides it while the pill
    // is presented.
    private var shouldManageStatusBar: Bool {
        UIDevice.current.userInterfaceIdiom != .pad
    }

    // Requires UIViewControllerBasedStatusBarAppearance=YES. Apps linked
    // against the iOS 27 SDK no longer get UIApplication's app-wide status
    // bar API on iOS 27, so the overlay's controller is the only way in.
    private func setStatusBarHidden(_ hidden: Bool) {
        guard shouldManageStatusBar else { return }
        hostingController?.isStatusBarHidden = hidden
    }

    deinit {
        // deinit may run off-main; Timer/UIWindow teardown must happen on
        // main, so hop over before breaking the retain cycle.
        let window = overlayWindow
        let dismissCancel = dismissCancellable
        let tapCancel = tapCancellable
        let actionCancel = actionCancellable
        let timer = autoDismissTimer
        let workItem = statusBarRestoreWorkItem
        let loadTask = imageLoadTask
        DispatchQueue.main.async {
            timer?.invalidate()
            workItem?.cancel()
            dismissCancel?.cancel()
            tapCancel?.cancel()
            actionCancel?.cancel()
            loadTask?.cancel()
            window?.stopBackdropSampling()
            // Break the window ↔ hosting controller ↔ PrettyToastView cycle
            // so the window can actually deallocate.
            window?.rootViewController = nil
            window?.isHidden = true
        }
    }

    private func iconColors(for symbol: String) -> (Color, Color) {
        if symbol.contains("checkmark") {
            return (.white, .green)
        } else if symbol.contains("xmark") {
            return (.white, .red)
        } else if symbol.contains("exclamation") {
            return (.white, .orange)
        } else if symbol.contains("info") {
            return (.white, .blue)
        } else if symbol.contains("heart") {
            return (.white, .pink)
        } else if symbol.contains("arrow") {
            return (.white, .blue)
        } else {
            return (.white, .gray)
        }
    }
}
