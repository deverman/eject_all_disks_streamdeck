import Foundation
import Testing
@testable import EjectAllDisksPlugin

@Suite("Monitor resource lifecycle")
@MainActor
struct MonitorResourceTests {
    @Test("Final stop releases every observer and fallback timer")
    func stopReleasesResources() {
        let monitor = DiskCountMonitor()
        let ingress = EventIngress(activeActions: ActiveActionRegistry())

        monitor.start(epoch: 1, ingress: ingress)
        #expect(monitor.observerCount == 4)
        #expect(monitor.hasFallbackTimer)

        monitor.stop(epoch: 2)
        #expect(monitor.observerCount == 0)
        #expect(!monitor.hasFallbackTimer)
    }

    @Test("Old start and stop epochs cannot invert current ownership")
    func epochInversion() {
        let monitor = DiskCountMonitor()
        let ingress = EventIngress(activeActions: ActiveActionRegistry())

        monitor.start(epoch: 10, ingress: ingress)
        monitor.stop(epoch: 11)
        monitor.start(epoch: 9, ingress: ingress)
        #expect(monitor.observerCount == 0)
        #expect(!monitor.hasFallbackTimer)

        monitor.start(epoch: 12, ingress: ingress)
        monitor.stop(epoch: 11)
        #expect(monitor.observerCount == 4)
        #expect(monitor.hasFallbackTimer)

        monitor.stop(epoch: 13)
    }
}

@Suite("Renderer admission")
struct RendererAdmissionTests {
    @Test("Older revisions and inactive tokens are rejected")
    func staleRevision() {
        let registry = ActiveActionRegistry()
        let instanceID = ActionInstanceID()
        registry.activate(context: "context", instanceID: instanceID)
        var gate = RenderRevisionGate(activeActions: registry)
        let presentation = KeyPresentation(title: "Checking…", image: .normal, feedback: nil)
        let newer = RenderRequest(
            context: "context",
            instanceID: instanceID,
            revision: 2,
            presentation: presentation
        )
        let older = RenderRequest(
            context: "context",
            instanceID: instanceID,
            revision: 1,
            presentation: presentation
        )

        let acceptedNewer = gate.begin(newer)
        #expect(acceptedNewer)
        #expect(gate.isCurrent(newer))
        let acceptedOlder = gate.begin(older)
        #expect(!acceptedOlder)

        registry.deactivate(context: "context", instanceID: instanceID)
        #expect(!gate.isCurrent(newer))
    }

    @Test("Context reuse rejects the old instance token")
    func contextReuse() {
        let registry = ActiveActionRegistry()
        let oldID = ActionInstanceID()
        let newID = ActionInstanceID()
        registry.activate(context: "context", instanceID: oldID)
        registry.activate(context: "context", instanceID: newID)
        var gate = RenderRevisionGate(activeActions: registry)
        let presentation = KeyPresentation(title: nil, image: .normal, feedback: nil)

        let acceptedOldInstance = gate.begin(RenderRequest(
            context: "context",
            instanceID: oldID,
            revision: 1,
            presentation: presentation
        ))
        let acceptedNewInstance = gate.begin(RenderRequest(
            context: "context",
            instanceID: newID,
            revision: 1,
            presentation: presentation
        ))
        #expect(!acceptedOldInstance)
        #expect(acceptedNewInstance)
    }

    @Test("Releasing an instance removes its revision entry")
    func releasePrunesRevisionEntries() {
        let registry = ActiveActionRegistry()
        let instanceID = ActionInstanceID()
        registry.activate(context: "context", instanceID: instanceID)
        var gate = RenderRevisionGate(activeActions: registry)
        let accepted = gate.begin(RenderRequest(
            context: "context",
            instanceID: instanceID,
            revision: 1,
            presentation: KeyPresentation(title: nil, image: .normal, feedback: nil)
        ))
        #expect(accepted)
        #expect(gate.trackedInstanceCount == 1)

        registry.deactivate(context: "context", instanceID: instanceID)
        gate.release(instanceID)
        #expect(gate.trackedInstanceCount == 0)
    }
}
