import XCTest
@testable import tesults

final class tesultsTests: XCTestCase {
    let targetForTest = "<REPLACE_WITH_TARGET_TOKEN_FOR_TESTING>"
    let localTargetForTest = "<REPLACE_WITH_LOCAL_TARGET_TOKEN_FOR_TESTING>"
    
    func dataGeneration (target: String, includeFiles: Bool, excludeTarget: Bool = false, excludeResults: Bool = false, excludeCases: Bool = false, includeInvalidCase: Bool = false, includeBuildCase: Bool = false) -> Dictionary<String,Any> {
        var data = Dictionary<String, Any>()
        
        var cases : [Dictionary<String, Any>] = []
        
        var testCase1 = Dictionary<String, Any>()
        testCase1["suite"] = "Suite A"
        testCase1["name"] = "Test Case 1"
        testCase1["desc"] = "Test Case 1 description"
        testCase1["result"] = "pass"
        testCase1["reason"] = "Failure reason"
        testCase1["params"] = ["Param 1" : "Param 1 Value", "Param 2" : "Param 2 Value"]
        if (includeFiles) {
            testCase1["files"] = ["/Users/admin/Library/Mobile Documents/com~apple~CloudDocs/Ajeet/Documents/tr/test-files/logs/log1.txt",
            "/Users/admin/Library/Mobile Documents/com~apple~CloudDocs/Ajeet/Documents/tr/test-files/logs/log2.txt",
          "/Users/admin/Library/Mobile Documents/com~apple~CloudDocs/Ajeet/Documents/tr/test-files/images/bali/bali-best/bali18.jpg"]
        }
        testCase1["steps"] = [
            [
                "name":"Step 1",
                "result":"pass"
            ],
            [
                "name":"Step 2",
                "result":"pass"
            ]
        ]
        
        testCase1["start"] = Date().timeIntervalSince1970*1000
        testCase1["end"] = (Date().timeIntervalSince1970 + 100) * 1000
        // Commenting out because start and stop supplied testCase1["duration"] = 100
        testCase1["_Custom Field"] = "Custom Field Value"
        cases.append(testCase1)
        
        if (includeInvalidCase) {
            var testCaseInvalid = Dictionary<String, Any>()
            testCaseInvalid["name"] = "Invalid test case"
            testCaseInvalid["suite"] = "Invalid"
            cases.append(testCaseInvalid)
        }
        
        if (includeBuildCase) {
            var buildCase = Dictionary<String, Any>()
            buildCase["name"] = "1.0.0"
            buildCase["desc"] = "Build case description"
            buildCase["suite"] = "[build]"
            buildCase["result"] = "pass"
            cases.append(buildCase)
        }
        
        if (excludeTarget != true) {
            data["target"] = target
        }
        if (excludeResults != true) {
            if (excludeCases != true) {
                data["results"] = ["cases" : cases]
            } else {
                data["results"] = ["someOtherKey": true]
            }
        }
        
        return data
    }
    
    func resultsUpload (data: Dictionary<String, Any>, successExpected: Bool) async {
        print("Tesults results upload...")
        let resultsResponse = await Tesults().results(data: data)
        print("Success: \(resultsResponse.success)")
        print("Message: \(resultsResponse.message)")
        print("Warnings: \(resultsResponse.warnings.count)")
        print("Errors: \(resultsResponse.errors.count)")
        XCTAssertEqual(resultsResponse.success, successExpected)
    }
    
    func testResultsUploadIncludingFiles () async throws {
        let data = dataGeneration(target: targetForTest, includeFiles: true)
        await resultsUpload(data: data, successExpected: true)
    }
    
    func testResultsUploadNotIncludingFiles () async throws {
        let data = dataGeneration(target: targetForTest, includeFiles: false)
        await resultsUpload(data: data, successExpected: true)
    }
    
    func testResultsUploadNoTarget () async throws {
        let data = dataGeneration(target: targetForTest, includeFiles: false, excludeTarget: true)
        await resultsUpload(data: data, successExpected: false)
    }
    
    func testResultsUploadNoResults () async throws {
        let data = dataGeneration(target: targetForTest, includeFiles: false, excludeResults: true)
        await resultsUpload(data: data, successExpected: false)
    }
    
    func testResultsUploadNoCases () async throws {
        let data = dataGeneration(target: targetForTest, includeFiles: false, excludeCases: true)
        await resultsUpload(data: data, successExpected: false)
    }
    
    func testResultsUploadWithOneInvalidCase () async throws {
        let data = dataGeneration(target: targetForTest, includeFiles: false, includeInvalidCase: true)
        await resultsUpload(data: data, successExpected: false)
    }
    
    func testResultsUploadWithBuildCase () async throws {
        let data = dataGeneration(target: targetForTest, includeFiles: false, includeBuildCase: true)
        await resultsUpload(data: data, successExpected: true)
    }
    
    func testResultsUploadInvalidTarget () async throws {
        let data = dataGeneration(target: "bad_token", includeFiles: false)
        await resultsUpload(data: data, successExpected: false)
    }
    
    func testRefreshCredentials () async throws {
        // Manual test
    }
    
    func testCorrectNumberOfFilesOutput () async throws {
        // Manual test
    }
    
    func testCorrectNumberOfBytesOutput () async throws {
        // Manual test
    }
    
    func testServerErrorHandling () async throws {
        // Manual step -> set endpoint to throw error
        let data = dataGeneration(target: localTargetForTest, includeFiles: false)
        await resultsUpload(data: data, successExpected: false)
    }
}
