import Foundation
import XCTest
import ClientRuntime
import AWSClientRuntime
import AWSS3

public struct Tesults {
    
    func refreshCredentials (credentialsRequest: CredentialsRequest) async -> CredentialsResponse {
        let url = URL(string: "https://www.tesults.com/permitupload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var jsonData : Data? = nil
        
        do {
            let creds = ["target": credentialsRequest.target, "key": credentialsRequest.key]
            jsonData = try JSONSerialization.data(withJSONObject: creds, options: [.prettyPrinted])
            
        } catch {
            return CredentialsResponse(success: false, message: "Failed to encode data", upload: nil)
        }
        var credentialsResponse: CredentialsResponse? = nil
        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: jsonData!)
            guard let response = response as? HTTPURLResponse,
                (200...299).contains(response.statusCode) else {
                do {
                    let response: ErrorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)
                    let errorResponseData: ErrorResponseData = response.error
                    print("Ch0: \(response.error.code)")
                    credentialsResponse = CredentialsResponse(success: false, message: errorResponseData.message, upload: nil)
                    return credentialsResponse!
                } catch {
                    credentialsResponse = CredentialsResponse(success: false, message: "Unsuccessful refreshing credentials", upload: nil)
                    return credentialsResponse!
                }
            }
            do {
                let response: Response = try JSONDecoder().decode(Response.self, from: data)
                let responseData: ResponseData = response.data
                if (responseData.code == 200) {
                    if (responseData.upload != nil) {
                        return CredentialsResponse(success: true, message: responseData.message, upload: responseData.upload)
                    } else {
                        credentialsResponse = CredentialsResponse(success: false, message: responseData.message, upload: nil)
                    }
                } else {
                    credentialsResponse = CredentialsResponse(success: false, message: "Unexpected error", upload: nil)
                }
            } catch {
                credentialsResponse = CredentialsResponse(success: false, message: "Failure to decode refresh credentails response.", upload: nil)
            }
        } catch {
            credentialsResponse = CredentialsResponse(success: false, message: "Error: \(error)", upload: nil)
        }
        if (credentialsResponse == nil) {
            credentialsResponse = CredentialsResponse(success: false, message: "Unexpected empty response.", upload: nil)
        }
        return credentialsResponse!
    }
    
    func s3Create (auth: Auth) -> S3Client? {
        let credentials = AWSCredentials(
            accessKey:auth.AccessKeyId,
            secret: auth.SecretAccessKey,
            expirationTimeout: auth.Expiration,
            sessionToken: auth.SessionToken
        )
        do {
            let credentialsProvider = try AWSCredentialsProvider.fromStatic(credentials)
            let s3ClientConfiguration = try S3Client.S3ClientConfiguration(region: "us-east-1",credentialsProvider: credentialsProvider, endpointResolver: nil,  signingRegion: nil)
            let s3Client = S3Client(config: s3ClientConfiguration)
            return s3Client
        }
        catch {
            return nil
        }
    }
    
    struct FilesUploadResult {
        let message: String
        let warnings: [String]
        
        init (message: String, warnings: [String]) {
            self.message = message
            self.warnings = warnings
        }
    }
    
    let expireBuffer = 30; // 30 seconds
    let maxActiveUploads = 10; // Upload at most 10 files simulataneously to avoid hogging the client machine.
    
    func filesUpload (files: inout [CaseFile], key: String, auth: Auth, target : String, warnings: inout [String], uploading: inout Int, filesUploaded: inout Int, bytesUploaded: inout UInt64) async ->  FilesUploadResult {
        if (files.count > 0) {
            while (uploading >= maxActiveUploads) {
                // Wait if already at max active uploads.
            }
            let expiration = auth.Expiration
            // Check if new credentials required.
            let now = Date().timeIntervalSince1970
            if (Int(now) + expireBuffer > expiration) { // Check within 30 seconds
            //of expiry.
                // Refresh credentials
                let credentialsRequest = CredentialsRequest(target: target, key: key)
                let credentials = await refreshCredentials(credentialsRequest:credentialsRequest)
                if (credentials.success != true) {
                    warnings.append(credentials.message)
                    let result = FilesUploadResult(message: credentials.message, warnings: warnings)
                    return result
                } else {
                    // Successful response, check if upload permitted.
                    if (credentials.upload!.permit != true) {
                        // Must stop due to failure to be permitted new credentials.
                        warnings.append(credentials.upload!.message)
                        let result = FilesUploadResult(message: credentials.upload!.message, warnings: warnings)
                        return result
                    } else {
                        return await filesUpload(files: &files, key: key, auth: credentials.upload!.auth, target: target, warnings: &warnings, uploading: &uploading, filesUploaded: &filesUploaded, bytesUploaded: &bytesUploaded)
                    }
                }
            } else {
                // Load new file for upload
                let caseFile = files.removeFirst()
                if (FileManager().fileExists(atPath: caseFile.file)) {
                    do {
                        uploading += 1
                        let attributes = try FileManager.default.attributesOfItem(atPath: caseFile.file)
                        if let size = attributes[FileAttributeKey.size] as? UInt64 {
                            let name = URL(fileURLWithPath: caseFile.file).lastPathComponent
                            let uploadPath = "\(key)/\(caseFile.num)/\(name)"
                            let fileUrl = URL(fileURLWithPath: caseFile.file)
                            let fileData = try Data(contentsOf: fileUrl)
                            let dataStream = ByteStream.from(data: fileData)
                            let input = PutObjectInput(
                                body: dataStream,
                                bucket: "tesults-results",
                                key: uploadPath
                            )
                            if let s3 = s3Create(auth: auth) {
                                _ = try await s3.putObject(input: input)
                                bytesUploaded += size
                                filesUploaded += 1
                                uploading = uploading - 1
                                return await filesUpload(files: &files, key: key, auth: auth, target: target, warnings: &warnings, uploading: &uploading, filesUploaded: &filesUploaded, bytesUploaded: &bytesUploaded)
                            } else {
                                uploading = uploading - 1
                                warnings.append("Unable to upload file: \(caseFile.file) (1)")
                                return await filesUpload(files: &files, key: key, auth: auth, target: target, warnings: &warnings, uploading: &uploading, filesUploaded: &filesUploaded, bytesUploaded: &bytesUploaded)
                            }
                        } else {
                            uploading = uploading - 1
                            warnings.append("Unable to upload file: \(caseFile.file) (2)")
                            return await filesUpload(files: &files, key: key, auth: auth, target: target, warnings: &warnings, uploading: &uploading, filesUploaded: &filesUploaded, bytesUploaded: &bytesUploaded)
                        }
                    } catch {
                        uploading -= 1
                        warnings.append("Unable to upload file: \(caseFile.file) (3)")
                        return await filesUpload(files: &files, key: key, auth: auth, target: target, warnings: &warnings, uploading: &uploading, filesUploaded: &filesUploaded, bytesUploaded: &bytesUploaded)
                    }
                } else {
                    warnings.append("File not found: \(caseFile.file)")
                    return await filesUpload(files: &files, key: key, auth: auth, target: target, warnings: &warnings, uploading: &uploading, filesUploaded: &filesUploaded, bytesUploaded: &bytesUploaded)
                }
            }
        } else {
            while (uploading != 0) {
                // Wait for uploads to complete.
            }
            let message = "\(filesUploaded) files uploaded. \(bytesUploaded) bytes uploaded."
            let result = FilesUploadResult(message: message, warnings: warnings)
            return result
        }
    }
    
    struct CaseFile {
        let num: Int
        let file: String
        
        init (num: Int, file: String) {
            self.num = num
            self.file = file
        }
    }
    
    func filesInTestCases (data: Dictionary<String, Any?>) -> [CaseFile] {
        var files : [CaseFile] = []
        var num = 0
        if let results = data["results"] {
            if let cases = (results as! Dictionary<String, Any?>)["cases"] {
                for c in (cases as! [Dictionary<String, Any?>]) {
                    if let caseFiles = c["files"] {
                        for f in (caseFiles as! [String]) {
                            let caseFile = CaseFile(num: num, file: f)
                            files.append(caseFile)
                        }
                    }
                    num += 1
                }
            }
        }
        return files
    }
    
    public struct ResultsResponse {
        let success: Bool
        let message: String
        let warnings: [String]
        let errors: [String]
        
        init (success: Bool, message: String, warnings: [String], errors: [String]){
            self.success = success
            self.message = message
            self.warnings = warnings
            self.errors = errors
        }
    }
    
    struct ErrorResponse: Decodable {
        let error: ErrorResponseData
    }
    
    struct ErrorResponseData: Decodable {
        let code: Int
        let message: String
    }
    
    struct Response: Decodable {
        let data: ResponseData
    }
    
    struct ResponseData : Decodable {
        let code: Int
        let message: String
        let upload: Upload?
    }
    
    struct Upload : Decodable {
        let permit: Bool
        let message: String
        let auth: Auth
        let key: String
    }
    
    struct Auth : Decodable {
        let AccessKeyId: String
        let Expiration: UInt64
        let SecretAccessKey: String
        let SessionToken: String
    }
    
    struct CredentialsRequest: Encodable {
        let target: String
        let key: String
        
        init (target: String, key: String) {
            self.target = target
            self.key = key
        }
    }
     
    struct CredentialsResponse {
        let success: Bool
        let message: String
        let upload: Upload?
    }
    
    public func results (data: Dictionary<String, Any?>) async -> ResultsResponse  {
        if (data["target"] == nil) {
            return ResultsResponse(success: false, message: "The target property is required", warnings: [], errors: [])
        }
        if (data["results"] == nil) {
            return ResultsResponse(success: false, message: "The results property is required", warnings: [], errors: [])
        }
        
        let url = URL(string: "https://www.tesults.com/results")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var jsonData : Data? = nil
        
        do {
            jsonData = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted])
        } catch {
            return ResultsResponse(success: false, message: "Tesults error. Unable to encode results data.", warnings: [], errors: [])
        }
        var resultsResponse: ResultsResponse? = nil
        do {
            let (dataBody, response) = try await URLSession.shared.upload(for: request, from: jsonData!)
            guard let response = response as? HTTPURLResponse,
                (200...299).contains(response.statusCode) else {
                do {
                    let response: ErrorResponse = try JSONDecoder().decode(ErrorResponse.self, from: dataBody)
                    let errorResponseData: ErrorResponseData = response.error
                    resultsResponse = ResultsResponse(success: false, message: errorResponseData.message, warnings: [], errors: [])
                    return resultsResponse!
                } catch {
                    resultsResponse = ResultsResponse(success: false, message: "Tesults unsuccessful response", warnings: [], errors: [])
                    return resultsResponse!
                }
            }
            do {
                let response: Response = try JSONDecoder().decode(Response.self, from: dataBody)
                let responseData: ResponseData = response.data
                if (responseData.code == 200) {
                    if (responseData.upload != nil) {
                        if (responseData.upload!.permit) {
                            var files = filesInTestCases(data: data)
                            var warnings: [String] = [];
                            var uploading = 0;
                            var filesUploaded = 0;
                            var bytesUploaded: UInt64 = 0;
                            let filesUploadResult = await filesUpload(files: &files, key: responseData.upload!.key, auth: responseData.upload!.auth, target: data["target"] as! String, warnings: &warnings, uploading: &uploading, filesUploaded: &filesUploaded, bytesUploaded: &bytesUploaded)
                            resultsResponse = ResultsResponse(success: true, message: "Success \(filesUploadResult.message)", warnings: filesUploadResult.warnings, errors: [])
                        } else {
                            resultsResponse = ResultsResponse(success: true, message: "Success \(responseData.upload!.message)", warnings: [], errors: [])
                        }
                    } else {
                        resultsResponse = ResultsResponse(success: true, message: "Success", warnings: [], errors: [])
                    }
                } else {
                    resultsResponse = ResultsResponse(success: false, message: "Unexpected error", warnings: [], errors: [])
                }
            } catch {
                resultsResponse = ResultsResponse(success: false, message: "Tesults failure to decode response and results upload may have failed.", warnings: [], errors: [])
            }
        } catch {
            resultsResponse = ResultsResponse(success: false, message: "Tesults error: \(error)", warnings: [], errors: [])
        }
        if (resultsResponse == nil) {
            resultsResponse = ResultsResponse(success: false, message: "Tesults unexpected empty response.", warnings: [], errors: [])
        }
        return resultsResponse!
    }
    
    public init () {}
}
