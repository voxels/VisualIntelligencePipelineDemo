import Foundation

public enum DiverBundle {
    public static var module: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: DiverKitMarker.self)
        #endif
    }
}

private class DiverKitMarker {}
