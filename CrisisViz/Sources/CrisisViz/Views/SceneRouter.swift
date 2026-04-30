import SwiftUI

/// Routes the current scene address to the appropriate chapter renderer.
/// Receives the already-computed `localTime` so chapters are pure renderers.
///
/// `inspection` is consumed by Ch02 only (vertex inspection); other chapters
/// ignore it. We default it so the testbed can still call `SceneRouter` without
/// constructing one explicitly when not capturing inspection frames.
struct SceneRouter: View {
    let address: SceneAddress
    let localTime: Double
    let engine: SceneEngine
    let dm: DataManager
    var inspection: InspectionState? = nil

    var body: some View {
        switch address.chapter {
        case 0:
            Ch01_Problem(sceneIndex: address.scene, localTime: localTime, engine: engine, dm: dm)
        case 1:
            Ch02_Graph(
                sceneIndex: address.scene,
                localTime: localTime,
                engine: engine,
                dm: dm,
                inspection: inspection ?? InspectionState()
            )
        case 2:
            Ch03_Partition(sceneIndex: address.scene, localTime: localTime, engine: engine, dm: dm)
        case 3:
            Ch04_Rounds(sceneIndex: address.scene, localTime: localTime, engine: engine, dm: dm)
        case 4:
            Ch05_Voting(sceneIndex: address.scene, localTime: localTime, engine: engine, dm: dm)
        case 5:
            Ch06_Leader(sceneIndex: address.scene, localTime: localTime, engine: engine, dm: dm)
        case 6:
            Ch07_Order(sceneIndex: address.scene, localTime: localTime, engine: engine, dm: dm)
        case 7:
            Ch08_DA_Problem(sceneIndex: address.scene, localTime: localTime, engine: engine, dm: dm)
        case 8:
            Ch09_DA_Design(sceneIndex: address.scene, localTime: localTime, engine: engine, dm: dm)
        case 9:
            Ch10_Byzantine(sceneIndex: address.scene, localTime: localTime, engine: engine, dm: dm)
        default:
            Text("Unknown chapter")
                .foregroundStyle(.secondary)
        }
    }
}
