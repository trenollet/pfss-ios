import ARKit
import Combine
import SceneKit
import SwiftUI
import simd

@MainActor
final class ARAreaMeasurementSession: NSObject, ObservableObject, ARSCNViewDelegate, ARSessionDelegate {
    @Published private(set) var points: [SIMD3<Float>] = []
    @Published private(set) var legLengthsFeet: [Double] = []
    @Published private(set) var guidance = "Move the phone slowly so PFSS can find the surface."
    @Published private(set) var isTrackingReady = false
    @Published var errorMessage = ""

    weak var sceneView: ARSCNView?
    private var measurementNodes: [SCNNode] = []

    static var supportsLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    func attach(to sceneView: ARSCNView) {
        self.sceneView = sceneView
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        if Self.supportsLiDAR {
            configuration.sceneReconstruction = .mesh
        }
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func addPoint() {
        guard let sceneView else { return }
        let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        let queryTypes: [(ARRaycastQuery.Target, ARRaycastQuery.TargetAlignment)] = [
            (.existingPlaneGeometry, .any),
            (.estimatedPlane, .any)
        ]

        var position: SIMD3<Float>?
        for (target, alignment) in queryTypes {
            guard let query = sceneView.raycastQuery(from: center, allowing: target, alignment: alignment) else {
                continue
            }
            if let result = sceneView.session.raycast(query).first {
                let column = result.worldTransform.columns.3
                position = SIMD3(column.x, column.y, column.z)
                break
            }
        }

        guard let position else {
            errorMessage = "PFSS cannot find a surface at the crosshair yet. Move slowly and aim at a well-lit surface."
            return
        }

        errorMessage = ""
        if let previous = points.last {
            legLengthsFeet.append(Double(simd_distance(previous, position)) * 3.280839895)
        }
        points.append(position)
        addMarker(at: position)
        if points.count > 1 {
            addLine(from: points[points.count - 2], to: position)
        }
        guidance = points.count < 3
            ? "Add the next corner. Three points complete two rectangle legs."
            : "Finish as a rectangle, or continue adding corners for an irregular area."
    }

    func undoLastPoint() {
        guard !points.isEmpty else { return }
        points.removeLast()
        if !legLengthsFeet.isEmpty { legLengthsFeet.removeLast() }
        rebuildNodes()
        errorMessage = ""
    }

    func reset() {
        points.removeAll()
        legLengthsFeet.removeAll()
        measurementNodes.forEach { $0.removeFromParentNode() }
        measurementNodes.removeAll()
        guidance = "Aim the crosshair at the first corner and tap Add Point."
        errorMessage = ""
    }

    func rectangleArea() -> Double? {
        guard let area = ARAreaGeometry.rectangleAreaSquareFeet(points: points) else {
            errorMessage = "A rectangle needs a starting corner and two measured legs."
            return nil
        }
        return area
    }

    func polygonArea() -> Double? {
        guard let area = ARAreaGeometry.polygonAreaSquareFeet(points: points) else {
            errorMessage = "An irregular area needs at least three corners on the same surface."
            return nil
        }
        return area
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let update: (String, Bool)
        switch camera.trackingState {
        case .normal:
            update = ("Tracking ready. Aim the crosshair at a corner and tap Add Point.", true)
        case .notAvailable:
            update = ("Camera measurement is unavailable on this device.", false)
        case .limited(let reason):
            switch reason {
            case .initializing:
                update = ("Move the phone slowly while PFSS maps the surface.", false)
            case .excessiveMotion:
                update = ("Slow down so the measurement stays accurate.", false)
            case .insufficientFeatures:
                update = ("Aim at a brighter surface with more visible detail.", false)
            case .relocalizing:
                update = ("Return the camera to the measured area.", false)
            @unknown default:
                update = ("Move the phone slowly to improve tracking.", false)
            }
        }
        Task { @MainActor in
            guidance = update.0
            isTrackingReady = update.1
        }
    }

    private func addMarker(at position: SIMD3<Float>) {
        guard let sceneView else { return }
        let sphere = SCNSphere(radius: 0.012)
        sphere.firstMaterial?.diffuse.contents = UIColor.systemOrange
        let node = SCNNode(geometry: sphere)
        node.simdPosition = position
        sceneView.scene.rootNode.addChildNode(node)
        measurementNodes.append(node)
    }

    private func addLine(from start: SIMD3<Float>, to end: SIMD3<Float>) {
        guard let sceneView else { return }
        let vector = end - start
        let distance = simd_length(vector)
        guard distance > 0 else { return }

        let cylinder = SCNCylinder(radius: 0.004, height: CGFloat(distance))
        cylinder.firstMaterial?.diffuse.contents = UIColor.systemOrange
        let node = SCNNode(geometry: cylinder)
        node.simdPosition = (start + end) / 2
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(vector))
        sceneView.scene.rootNode.addChildNode(node)
        measurementNodes.append(node)
    }

    private func rebuildNodes() {
        measurementNodes.forEach { $0.removeFromParentNode() }
        measurementNodes.removeAll()
        for point in points { addMarker(at: point) }
        guard points.count > 1 else { return }
        for index in 1..<points.count {
            addLine(from: points[index - 1], to: points[index])
        }
    }
}

private struct ARAreaCameraRepresentable: UIViewRepresentable {
    @ObservedObject var measurement: ARAreaMeasurementSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        measurement.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct ARAreaMeasurementView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var measurement = ARAreaMeasurementSession()
    let onUseArea: (Double) -> Void

    var body: some View {
        ZStack {
            ARAreaCameraRepresentable(measurement: measurement)
                .ignoresSafeArea()

            Image(systemName: "plus")
                .font(.system(size: 30, weight: .thin))
                .foregroundStyle(.white)
                .shadow(radius: 2)

            VStack(spacing: 12) {
                statusPanel
                Spacer()
                controls
            }
            .padding()
        }
        .navigationTitle("Measure Area")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(ARAreaMeasurementSession.supportsLiDAR ? "LiDAR Measurement" : "Camera Measurement", systemImage: "viewfinder")
                    .fontWeight(.semibold)
                Spacer()
                Text("\(measurement.points.count) points")
            }
            Text(measurement.guidance)
                .font(.caption)
            if let last = measurement.legLengthsFeet.last {
                Text("Last leg: \(last.formatted(.number.precision(.fractionLength(1...2)))) ft")
                    .font(.caption.bold())
            }
            if !measurement.errorMessage.isEmpty {
                Text(measurement.errorMessage)
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button {
                measurement.addPoint()
            } label: {
                Label("Add Point", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!measurement.isTrackingReady)

            HStack {
                Button("Undo", systemImage: "arrow.uturn.backward") { measurement.undoLastPoint() }
                    .disabled(measurement.points.isEmpty)
                Button("Start Over", systemImage: "arrow.counterclockwise") { measurement.reset() }
                    .disabled(measurement.points.isEmpty)
            }
            .buttonStyle(.bordered)

            HStack {
                Button("Finish Rectangle") {
                    if let area = measurement.rectangleArea() { finish(with: area) }
                }
                .disabled(measurement.points.count < 3)

                Button("Finish Shape") {
                    if let area = measurement.polygonArea() { finish(with: area) }
                }
                .disabled(measurement.points.count < 3)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func finish(with area: Double) {
        onUseArea(area)
        dismiss()
    }
}
