struct HandsFreeLockCoordinator {
    private(set) var sessionLocked = false
    private(set) var pendingLock = false

    mutating func beginSession() {
        sessionLocked = false
        pendingLock = false
    }

    mutating func requestLock(
        activationMode: ActivationMode,
        dictationState: DictationController.State
    ) -> Bool {
        guard activationMode == .hold, !sessionLocked else { return false }
        sessionLocked = true
        if dictationState == .recording {
            pendingLock = false
            return true
        }
        pendingLock = true
        return false
    }

    mutating func recordingDidStart() -> Bool {
        guard pendingLock else { return false }
        pendingLock = false
        return true
    }

    func shouldEndOnRelease(activationMode: ActivationMode) -> Bool {
        activationMode == .hold && !sessionLocked
    }

    mutating func endSession() {
        sessionLocked = false
        pendingLock = false
    }
}
