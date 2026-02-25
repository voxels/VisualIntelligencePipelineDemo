import XCTest
@testable import DiverKit

final class EdgeModelProvisionerTests: XCTestCase {
#if os(macOS)
    func testValidateProvisioningKeys() async {
        let provisioner = EdgeModelProvisioner.shared
        let validationStatus = await provisioner.validateProvisioning()
        
        // Ensure all component status tracking keys are present
        XCTAssertNotNil(validationStatus["models_directory_exists"], "Models root should be validated")
        XCTAssertNotNil(validationStatus["shared_venv_python"], "Shared Portable Python path should be validated")
        XCTAssertNotNil(validationStatus["shared_venv_mlx_lm"], "mlx_lm path should be validated")
        XCTAssertNotNil(validationStatus["sam_2.1_coreml"], "SAM CoreML should be validated")
        XCTAssertNotNil(validationStatus["clara_7b_mlx"], "CLaRa MLX root should be validated")
        XCTAssertNotNil(validationStatus["ml_sharp_script"], "enhance script should be validated")
        XCTAssertNotNil(validationStatus["ml_sharp_venv"], "ml-sharp venv should be validated")
    }
    
    // Test the standalone fetch explicitly without mutating the real shared DB if possible,
    // though the system architecture of Provisioner works asynchronously with the real data stores.
#endif
}
