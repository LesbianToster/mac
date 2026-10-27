import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos

// MARK: - Параметры стиля
struct Look {
    var blur = 6.0        // горизонтальное размытие (смаз плёнки)
    var bleed = 6.0       // расползание цвета (хроматика)
    var noise = 0.25      // зерно/шум
    var scan = 0.35       // строки развёртки
    var saturation = 1.2
    var contrast = 1.1
    var warmth = 0.0      // -1 холодно ... +1 тепло
    var vignette = 0.8
    var stamp = true      // надпись PLAY ▶ и дата

    static let presets: [(String, Look)] = [
        ("VHS", Look()),
        ("Camcorder 90s", Look(blur: 3, bleed: 3, noise: 0.12, scan: 0.15, saturation: 1.4, contrast: 1.15, warmth: 0.2, vignette: 0.5, stamp: true)),
        ("Старая лента", Look(blur: 10, bleed: 10, noise: 0.5, scan: 0.5, saturation: 0.8, contrast: 1.0, warmth: 0.4, vignette: 1.4, stamp: true)),
        ("Плёнка 80s", Look(blur: 1.5, bleed: 2, noise: 0.35, scan: 0, saturation: 1.1, contrast: 1.2, warmth: 0.5, vignette: 1.0, stamp: false)),
        ("Холодный VHS", Look(blur: 5, bleed: 7, noise: 0.3, scan: 0.3, saturation: 1.0, contrast: 1.1, warmth: -0.6, vignette: 0.9, stamp: true)),
    ]
}

// MARK: - Рендер эффекта
enum VHS {
    static let ctx = CIContext()
    static let df: DateFormatter = { let d = DateFormatter(); d.dateFormat = "MMM dd yyyy"; return d }()

    static func channel(_ img: CIImage, r: CGFloat, g: CGFloat, b: CGFloat, dx: CGFloat) -> CIImage {
        let m = CIFilter.colorMatrix()
        m.inputImage = img
        m.rVector = CIVector(x: r, y: 0, z: 0, w: 0)
        m.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
        m.bVector = CIVector(x: 0, y: 0, z: b, w: 0)
        m.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return m.outputImage!.transformed(by: CGAffineTransform(translationX: dx, y: 0))
    }

    static func render(_ input: CIImage, _ l: Look) -> UIImage? {
        let ext = input.extent
        let s = ext.width / 1000
        var img = input

        if l.blur > 0 {
            let f = CIFilter.motionBlur()
            f.inputImage = img.clampedToExtent(); f.radius = Float(l.blur * s); f.angle = 0
            img = f.outputImage!.cropped(to: ext)
        }
        if l.bleed > 0 {
            let d = CGFloat(l.bleed * s)
            let red = channel(img, r: 1, g: 0, b: 0, dx: d)
            let grn = channel(img, r: 0, g: 1, b: 0, dx: 0)
            let blu = channel(img, r: 0, g: 0, b: 1, dx: -d)
            let add1 = CIFilter.additionCompositing(); add1.inputImage = red; add1.backgroundImage = grn
            let add2 = CIFilter.additionCompositing(); add2.inputImage = blu; add2.backgroundImage = add1.outputImage!
            img = add2.outputImage!.cropped(to: ext).composited(over: img)
        }
        let cc = CIFilter.colorControls()
        cc.inputImage = img; cc.saturation = Float(l.saturation); cc.contrast = Float(l.contrast)
        img = cc.outputImage!

        let tt = CIFilter.temperatureAndTint()
        tt.inputImage = img
        tt.neutral = CIVector(x: 6500 + CGFloat(l.warmth) * 1500, y: 0)
        tt.targetNeutral = CIVector(x: 6500, y: 0)
        img = tt.outputImage!

        if l.noise > 0 {
            let n = CIFilter.randomGenerator().outputImage!
                .transformed(by: CGAffineTransform(scaleX: CGFloat(max(s, 0.5)), y: CGFloat(max(s, 0.5))))
            let m = CIFilter.colorMatrix()
            m.inputImage = n
            m.rVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
            m.gVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
            m.bVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
            m.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            m.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            let t = CIFilter.dissolveTransition()
            t.inputImage = img; t.targetImage = m.outputImage!.cropped(to: ext)
            t.time = Float(l.noise * 0.4)
            img = t.outputImage!.cropped(to: ext)
        }
        if l.scan > 0 {
            let st = CIFilter.stripesGenerator()
            st.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(l.scan))
            st.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
            st.width = Float(max(2 * s, 1)); st.sharpness = 0.6
            let lines = st.outputImage!.transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: ext)
            img = lines.composited(over: img)
        }
        if l.vignette > 0 {
            let v = CIFilter.vignette()
            v.inputImage = img; v.intensity = Float(l.vignette); v.radius = 2
            img = v.outputImage!
        }
        guard let cg = ctx.createCGImage(img, from: ext) else { return nil }
        let ui = UIImage(cgImage: cg)
        return l.stamp ? addStamp(ui) : ui
    }

    static func addStamp(_ img: UIImage) -> UIImage {
        let size = img.size
        let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            img.draw(at: .zero)
            let font = UIFont.monospacedSystemFont(ofSize: size.height * 0.035, weight: .bold)
            let a: [NSAttributedString.Key: Any] = [.font: font,
                .foregroundColor: UIColor(red: 1, green: 0.55, blue: 0.1, alpha: 0.95)]
            "PLAY ▶".draw(at: CGPoint(x: size.width * 0.05, y: size.height * 0.04), withAttributes: a)
            let txt = df.string(from: Date()).uppercased()
            let w = (txt as NSString).size(withAttributes: a).width
            txt.draw(at: CGPoint(x: size.width - w - size.width * 0.05, y: size.height * 0.91), withAttributes: a)
        }
    }
}

// MARK: - Камера
final class Cam: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    @Published var preview: UIImage?
    @Published var saved = false
    @Published var look = Look() { didSet { _look = look } }
    private var _look = Look()

    @Published var lens = 1 { didSet { let l = lens; q.async { self.configure(l) } } }  // 0=0.5x, 1=1x, 2=селфи
    @Published var auto = true { didSet { apply() } }
    @Published var iso = 100.0 { didSet { apply() } }
    @Published var shutterX = 0.5 { didSet { apply() } }   // 0 = 1/4096 ... 1 = 1/4 c
    @Published var focus = 0.5 { didSet { apply() } }      // 0 = близко, 1 = бесконечность
    @Published var kelvin = 5000.0 { didSet { apply() } }
    @Published var ev = 0.0 { didSet { apply() } }
    @Published var zoom = 1.0 { didSet { apply() } }

    let session = AVCaptureSession()
    private let photoOut = AVCapturePhotoOutput()
    private let videoOut = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private let q = DispatchQueue(label: "cam.session")

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { return }
            self.q.async { self.configure(1); self.session.startRunning() }
        }
    }

    private func configure(_ lens: Int) {
        let type: AVCaptureDevice.DeviceType = lens == 0 ? .builtInUltraWideCamera : .builtInWideAngleCamera
        let pos: AVCaptureDevice.Position = lens == 2 ? .front : .back
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.inputs.forEach { session.removeInput($0) }
        guard let d = AVCaptureDevice.default(type, for: .video, position: pos),
              let inp = try? AVCaptureDeviceInput(device: d), session.canAddInput(inp) else {
            session.commitConfiguration(); return
        }
        session.addInput(inp); device = d
        if session.outputs.isEmpty {
            videoOut.setSampleBufferDelegate(self, queue: DispatchQueue(label: "cam.frames"))
            videoOut.alwaysDiscardsLateVideoFrames = true
            session.addOutput(videoOut); session.addOutput(photoOut)
        }
        videoOut.connection(with: .video)?.videoOrientation = .portrait
        session.commitConfiguration()
        DispatchQueue.main.async { self.zoom = 1 }
    }

    func apply() {
        let (a, i, sx, f, k, e, z) = (auto, iso, shutterX, focus, kelvin, ev, zoom)
        q.async {
            guard let d = self.device else { return }
            do { try d.lockForConfiguration() } catch { return }
            defer { d.unlockForConfiguration() }
            if a {
                if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
                if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
                if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { d.whiteBalanceMode = .continuousAutoWhiteBalance }
                d.setExposureTargetBias(Float(e), completionHandler: nil)
            } else {
                let fmt = d.activeFormat
                var secs = 1.0 / pow(2.0, 12 - 10 * sx)
                secs = min(max(secs, CMTimeGetSeconds(fmt.minExposureDuration)), CMTimeGetSeconds(fmt.maxExposureDuration))
                let isoV = min(max(Float(i), fmt.minISO), fmt.maxISO)
                d.setExposureModeCustom(duration: CMTimeMakeWithSeconds(secs, preferredTimescale: 1_000_000), iso: isoV, completionHandler: nil)
                if d.isLockingFocusWithCustomLensPositionSupported {
                    d.setFocusModeLocked(lensPosition: Float(f), completionHandler: nil)
                }
                var g = d.deviceWhiteBalanceGains(for: .init(temperature: Float(k), tint: 0))
                let mx = d.maxWhiteBalanceGain
                g.redGain = min(max(g.redGain, 1), mx); g.greenGain = min(max(g.greenGain, 1), mx); g.blueGain = min(max(g.blueGain, 1), mx)
                d.setWhiteBalanceModeLocked(with: g, completionHandler: nil)
            }
            d.videoZoomFactor = min(max(z, d.minAvailableVideoZoomFactor), min(d.maxAvailableVideoZoomFactor, 10))
        }
    }

    func shoot() { photoOut.capturePhoto(with: AVCapturePhotoSettings(), delegate: self) }

    func photoOutput(_ o: AVCapturePhotoOutput, didFinishProcessingPhoto p: AVCapturePhoto, error: Error?) {
        guard let data = p.fileDataRepresentation(),
              let ci = CIImage(data: data, options: [.applyOrientationProperty: true]),
              let ui = VHS.render(ci, _look) else { return }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: ui)
        }) { ok, _ in
            DispatchQueue.main.async {
                self.saved = ok
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.saved = false }
            }
        }
    }

    func captureOutput(_ o: AVCaptureOutput, didOutput sb: CMSampleBuffer, from c: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let ci = CIImage(cvPixelBuffer: pb).transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        if let ui = VHS.render(ci, _look) { DispatchQueue.main.async { self.preview = ui } }
    }
}

// MARK: - Интерфейс
struct Row: View {
    let t: String; @Binding var v: Double; let r: ClosedRange<Double>
    var body: some View {
        HStack {
            Text(t).font(.caption).frame(width: 100, alignment: .leading)
            Slider(value: $v, in: r)
        }.foregroundColor(.white)
    }
}

struct ContentView: View {
    @StateObject var cam = Cam()
    @State var tab = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 6) {
                Group {
                    if let p = cam.preview { Image(uiImage: p).resizable().scaledToFit() } else { Color.black }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { if cam.saved { Text("Сохранено ✓").padding(8).background(.black.opacity(0.7)).foregroundColor(.white).cornerRadius(8) } }

                Picker("", selection: $tab) {
                    Text("Стиль").tag(0); Text("Камера").tag(1)
                }.pickerStyle(.segmented).padding(.horizontal)

                ScrollView { VStack(spacing: 4) { tab == 0 ? AnyView(lookPanel) : AnyView(camPanel) } }
                    .frame(height: 190).padding(.horizontal)

                Button(action: cam.shoot) {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 70, height: 70)
                        .overlay(Circle().fill(.white).padding(8))
                }.padding(.bottom, 8)
            }
        }.onAppear { cam.start() }
    }

    var lookPanel: some View {
        VStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(Look.presets.enumerated()), id: \.offset) { _, p in
                        Button(p.0) { cam.look = p.1 }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.white.opacity(0.2)).foregroundColor(.white).cornerRadius(8)
                    }
                }
            }
            Row(t: "Смаз", v: $cam.look.blur, r: 0...20)
            Row(t: "Цвет. сдвиг", v: $cam.look.bleed, r: 0...20)
            Row(t: "Шум", v: $cam.look.noise, r: 0...1)
            Row(t: "Строки", v: $cam.look.scan, r: 0...1)
            Row(t: "Насыщенность", v: $cam.look.saturation, r: 0...2)
            Row(t: "Контраст", v: $cam.look.contrast, r: 0.5...1.5)
            Row(t: "Тепло", v: $cam.look.warmth, r: -1...1)
            Row(t: "Виньетка", v: $cam.look.vignette, r: 0...2)
            Toggle("PLAY ▶ и дата", isOn: $cam.look.stamp).foregroundColor(.white)
        }
    }

    var camPanel: some View {
        VStack(spacing: 4) {
            Picker("", selection: $cam.lens) {
                Text("0.5×").tag(0); Text("1×").tag(1); Text("Селфи").tag(2)
            }.pickerStyle(.segmented)
            Row(t: "Зум", v: $cam.zoom, r: 1...6)
            Toggle("Авто экспозиция/фокус/WB", isOn: $cam.auto).foregroundColor(.white)
            if cam.auto {
                Row(t: "Экспокоррекция", v: $cam.ev, r: -3...3)
            } else {
                Row(t: "ISO", v: $cam.iso, r: 25...1600)
                Row(t: "Выдержка", v: $cam.shutterX, r: 0...1)
                Row(t: "Фокус", v: $cam.focus, r: 0...1)
                Row(t: "Баланс бел. K", v: $cam.kelvin, r: 2500...8000)
            }
        }
    }
}

@main
struct VHSCamApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
