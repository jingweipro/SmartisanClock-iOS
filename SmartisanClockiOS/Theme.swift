import AVFoundation
import CoreText
import SwiftUI
import UIKit

enum ClockTheme {
    static let background = Color(red: 250 / 255, green: 250 / 255, blue: 250 / 255)
    static let pageGray = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
    static let red = Color(red: 212 / 255, green: 77 / 255, blue: 68 / 255)
    static let alarmRed = Color(red: 213 / 255, green: 84 / 255, blue: 75 / 255)
    static let rulerRed = Color(red: 230 / 255, green: 63 / 255, blue: 60 / 255)
    static let title = Color.black.opacity(0.60)
    static let primaryText = Color.black.opacity(0.70)
    static let secondaryText = Color.black.opacity(0.40)
    static let hintText = Color.black.opacity(0.30)
    static let divider = Color.black.opacity(0.06)
    static let switchBlue = Color(red: 80 / 255, green: 121 / 255, blue: 217 / 255)
}

enum SmartisanAssets {
    private static let imageCache = NSCache<NSString, UIImage>()
    private static var fontsRegistered = false

    static func image(_ name: String, scale: CGFloat = 3) -> UIImage {
        let cacheKey = "\(name)@\(scale)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) { return cached }
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        let base = parts.first ?? name
        let ext = parts.count > 1 ? parts[1] : "png"
        guard let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "SmartisanAssets"),
              let data = try? Data(contentsOf: url),
              let loaded = UIImage(data: data, scale: scale) else {
            return UIImage()
        }
        imageCache.setObject(loaded, forKey: cacheKey)
        return loaded
    }

    static func url(_ name: String) -> URL? {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard let base = parts.first else { return nil }
        return Bundle.main.url(
            forResource: base,
            withExtension: parts.count > 1 ? parts[1] : nil,
            subdirectory: "SmartisanAssets"
        )
    }

    static func registerFonts() {
        guard !fontsRegistered else { return }
        fontsRegistered = true
        ["smartisan_clock.ttf", "smartisan_clock_bold.ttf", "smartisan_clock_light.otf"].forEach {
            guard let url = url($0) else { return }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func font(_ style: SmartisanFontStyle, size: CGFloat) -> Font {
        Font.custom(style.postScriptName, size: size)
    }
}

enum SmartisanFontStyle {
    case regular, bold, light

    var postScriptName: String {
        switch self {
        case .regular: "SmartisanClock-Regular"
        case .bold: "SmartisanClock-Bold"
        case .light: "SmartisanClock-Light"
        }
    }
}

@MainActor
final class SmartisanSoundEffects {
    static let shared = SmartisanSoundEffects()
    private var players: [String: AVAudioPlayer] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    func play(_ name: String, volume: Float = 1) {
        guard let player = player(named: name) else { return }
        player.stop()
        player.currentTime = 0
        player.numberOfLoops = 0
        player.volume = volume
        player.play()
    }

    func setLoop(_ name: String, playing: Bool, volume: Float = 1) {
        guard let player = player(named: name) else { return }
        if playing {
            if player.isPlaying { return }
            player.numberOfLoops = -1
            player.volume = volume
            player.currentTime = 0
            player.play()
        } else {
            player.stop()
            player.currentTime = 0
        }
    }

    private func player(named name: String) -> AVAudioPlayer? {
        if let existing = players[name] { return existing }
        guard let url = SmartisanAssets.url("\(name).wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[name] = player
        return player
    }
}

enum SmartisanHaptics {
    static func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
    }

    static func confirm() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.75)
    }
}

struct SmartisanTitleBar: View {
    let title: String
    var leading: SmartisanBarAction?
    var trailing: SmartisanBarAction?

    var body: some View {
        ZStack {
            ClockTheme.background
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(ClockTheme.title)

            if let leading {
                SmartisanImageButton(action: leading, size: 36)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 6)
            }
            if let trailing {
                SmartisanImageButton(action: trailing, size: 36)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 6)
            }
        }
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ClockTheme.divider).frame(height: 0.67)
        }
    }
}

struct SmartisanBarAction {
    let image: String
    var pressedImage: String?
    var disabledImage: String?
    var enabled = true
    let accessibilityLabel: String
    let action: () -> Void
}

struct SmartisanImageButton: View {
    let action: SmartisanBarAction
    var size: CGFloat

    var body: some View {
        Button(action: action.action) { Color.clear }
            .buttonStyle(SmartisanBitmapButtonStyle(
                normal: action.image,
                pressed: action.pressedImage,
                disabled: action.disabledImage,
                size: size,
                enabled: action.enabled
            ))
            .frame(width: size, height: size)
            .disabled(!action.enabled)
            .accessibilityLabel(action.accessibilityLabel)
    }
}

struct SmartisanBitmapButtonStyle: ButtonStyle {
    let normal: String
    var pressed: String?
    var disabled: String?
    let size: CGFloat
    var enabled = true
    var scale: CGFloat = 3
    var pressedOffset: CGSize = .zero

    func makeBody(configuration: Configuration) -> some View {
        let name = !enabled ? (disabled ?? normal) : (configuration.isPressed ? (pressed ?? normal) : normal)
        return Image(uiImage: SmartisanAssets.image(name, scale: scale))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .offset(configuration.isPressed ? pressedOffset : .zero)
            .opacity(enabled ? 1 : 0.5)
    }
}

struct SmartisanDivider: View {
    var width: CGFloat = 80
    var body: some View { Rectangle().fill(ClockTheme.divider).frame(width: width, height: 0.67) }
}
