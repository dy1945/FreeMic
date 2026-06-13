import SwiftUI
import Foundation
import AppKit

/// Menu-bar glyph: a broadcast headset (headphones + boom mic), matching the
/// app icon. Embedded as a template PNG so macOS tints it for light/dark menu
/// bars — no resource bundle needed for the SPM executable.
private let menuBarIcon: NSImage = {
    let base64 = "iVBORw0KGgoAAAANSUhEUgAAADYAAAA2CAYAAACMRWrdAAAAAXNSR0IArs4c6QAAADhlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAAqACAAQAAAABAAAANqADAAQAAAABAAAANgAAAADQiwyeAAADvklEQVRoBe2ZyWsUQRTGM+4rXuISUSdxQcQFPHhwARHv4sE/Q4MLHoWcvOtFEUQiHgX1JogkYkQERUQDHoQMKASUuMSIGy6/j0w5PT1dXdUz1ZlE+oOPqnlV9b33qnuqq6s7OgoUM1DMQJ4zUMpTHO1ZsAeW4TL4B36GlSp/Uc4YdBLpMXgbfoFKJokT2O/Ao3AFnLbQlbkMv8OkRNJsGqOx3XDaYC6RnIHfYFrwPm1fq1qzKduKLrwPQZ+gs/R5gObKdmWmW28kh6TMBEh7fbPJlZocqNl8BMsp48dpuwHvwmH4FgpaKLbCg/Aw1GppQ4WGPXDU1iGkfQ5iD6GZ2Xj5ibaTcBF0YTEdTkOtkHEd81u3pf7HuaMPD8ZpvLxPWzfMijIDBmFcz/zuoy1X6J63rX43adPVbBbzGXgLmmSipR4HG5sV9hl31eJ4ALsCaxWamHswmpSp97cqbhu/moYfCU61RVprG9SEvcyYj9AkZMqf2HJ5BGhBME6i5QnsodGLYNSHqZ8K7Uh6SbfIGPaFOThbgOZ7aBIypWIIinmoabtjHJjyUlAv9WLaOxo/ptTC5bX067XCB5vopFmMQw/fvDCYIKwFanOCvcHkm1h3w8hJw3OLPYT5mUVkncVeZ/ZNbGndqNoPs02qWcLV3lmk0rZg/4b4Jmbrp3s/L7SkbQs4Hqz2f0lYnmQMZNObeBL03AyG7SiZlSlaXsFeCualJiTNfhj1Zeo7at1ar2kHboTj5fnW5RsUpBn3Y34rliBYg4rrHGNXEE+TItIySSSVepYpplT4/McOoaAHdBqOpDVmbHNp6VmmmFLhk5hzdvDg0yc1kEijj5azj09iPn1Cnir5aDljcnaIzOSMqhaJzajLRbA+V0xvsy58cHXI0O6j5YzJJ7EBj6AGPfr4dvHR8onJy59OoJIelrI9hj4rmZejqpY0bf4USzAsQek6jDvTq3oeByzSlHbcn2JQLMGxE8VeqIOdfcHVGwXPYjLJnWtstluyHnA+RUqcKoxEHFUidWc1a2IuQW119kO9cWtPZ6i9pqmrlN8X8ALUBtuGbZGG15H6lFZ3420CmlvHpxyif9kS5RbsWtal8xt2QW+EvGLH8aqvJ1mwl84VqPONYfgG6grqyh+A5q1CK+EobAuSzgF9rpqrT4VsdLzeNvTg+RV0Barz/3GoK3QNPoFJX3B0W1+EnTAzSplHpA/Qrb0B6oGtWypO81GDpjponM4LV0HdfmPwJdSHiALFDBQzUMxAMQPFDBQz8L/MwF9GaH02QfQijgAAAABJRU5ErkJggg=="
    let data = Data(base64Encoded: base64)!
    let img = NSImage(data: data)!
    img.size = NSSize(width: 18, height: 18)
    img.isTemplate = true
    return img
}()

@main
struct FreeMicApp: App {
    @StateObject private var audio: AudioManager

    init() {
        let manager = AudioManager()
        // Headless debug path: print device state and exit without showing UI.
        if CommandLine.arguments.contains("--list") {
            manager.printDebug()
            exit(0)
        }
        _audio = StateObject(wrappedValue: manager)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(audio: audio)
        } label: {
            Image(nsImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
