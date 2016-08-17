/*
*     Copyright 2016 IBM Corp.
*     Licensed under the Apache License, Version 2.0 (the "License");
*     you may not use this file except in compliance with the License.
*     You may obtain a copy of the License at
*     http://www.apache.org/licenses/LICENSE-2.0
*     Unless required by applicable law or agreed to in writing, software
*     distributed under the License is distributed on an "AS IS" BASIS,
*     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
*     See the License for the specific language governing permissions and
*     limitations under the License.
*/


/**
    A custom wrapper of NSURLSession that incorporates analytics and security from Bluemix Mobile Services.
*/
public struct BMSUrlSession {

    /// The network session
    public let urlSession: NSURLSession
    
    static let logger = Logger.logger(forName: Logger.bmsLoggerPrefix + "urlSession")
    
    
    public init(configuration: NSURLSessionConfiguration = .defaultSessionConfiguration(),
               delegate: NSURLSessionDelegate? = nil,
               delegateQueue: NSOperationQueue? = nil) {
        
        var bmsDelegate: NSURLSessionDelegate? = nil
        if delegate != nil {
            bmsDelegate = BMSUrlSessionDelegate(parentDelegate: delegate!)
        }
        urlSession = NSURLSession(configuration: configuration, delegate: bmsDelegate, delegateQueue: delegateQueue)
    }
    
    
    // Inject BMSSecurity and BMSAnalytics into the request object by adding headers
    internal func prepareRequest(request: NSURLRequest) -> NSURLRequest {
        
        let bmsRequest = request.mutableCopy() as! NSMutableURLRequest
        
        // Security
        let authManager = BMSClient.sharedInstance.authorizationManager
        if let authHeader: String = authManager.cachedAuthorizationHeader {
            bmsRequest.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        
        // Analytics
        bmsRequest.setValue(NSUUID().UUIDString, forHTTPHeaderField: "x-wl-analytics-tracking-id")
        if let requestMetadata = BaseRequest.requestAnalyticsData {
            bmsRequest.setValue(requestMetadata, forHTTPHeaderField: "x-mfp-analytics-metadata")
        }
        
        return bmsRequest
    }
    
    
    // If we receive a challenge response from an MCA-protected backend, then we should use AuthorizationManager to handle the challenge.
    internal static func isAuthorizationManagerRequired(response: NSURLResponse?) -> Bool {
        
        let authManager = BMSClient.sharedInstance.authorizationManager
        
        if let response = response as? NSHTTPURLResponse,
            let wwwAuthHeader = response.allHeaderFields["WWW-Authenticate"] as? String
            where authManager.isAuthorizationRequired(forStatusCode: response.statusCode, httpResponseAuthorizationHeader: wwwAuthHeader) {
            
            return true
        }
        return false
    }
    
    
    // Handle the challenge with AuthorizationManager from BMSSecurity
    internal static func handleAuthorizationChallenge(urlSession: NSURLSession, request: NSMutableURLRequest, handleFailure: () -> Void) {
        
        let authManager = BMSClient.sharedInstance.authorizationManager
        let authCallback: BmsCompletionHandler = {(response: Response?, error:NSError?) in
            
            if error == nil && response?.statusCode >= 200 && response?.statusCode < 300 {
                
                // Resend the original request with the "Authorization" header
                
                let authManager = BMSClient.sharedInstance.authorizationManager
                if let authHeader: String = authManager.cachedAuthorizationHeader {
                    request.setValue(authHeader, forHTTPHeaderField: "Authorization")
                }
                
                urlSession.dataTaskWithRequest(request).resume()
            }
            else {
                BMSUrlSession.logger.error("Authorization process failed. \nError: \(error). \nResponse: \(response).")
                handleFailure()
            }
        }
        authManager.obtainAuthorization(completionHandler: authCallback)
    }
}



// MARK: Data tasks

extension BMSUrlSession {
    
    public func dataTaskWithURL(url: NSURL) -> NSURLSessionDataTask {

        return self.dataTaskWithRequest(NSURLRequest(URL: url))
    }

    public func dataTaskWithURL(url: NSURL, completionHandler: BMSDataTaskCompletionHandler) -> NSURLSessionDataTask {

        return self.dataTaskWithRequest(NSURLRequest(URL: url), completionHandler: completionHandler)
    }
    
    public func dataTaskWithRequest(request: NSURLRequest) -> NSURLSessionDataTask {
        
        let bmsRequest = prepareRequest(request)
        
        return urlSession.dataTaskWithRequest(bmsRequest)
    }
    
    public func dataTaskWithRequest(request: NSURLRequest, completionHandler: BMSDataTaskCompletionHandler) -> NSURLSessionDataTask {
        
        let bmsRequest = prepareRequest(request)
        let bmsCompletionHandler = BMSUrlSessionCompletionHandler.from(completionHandler, urlSession: urlSession, request: request)
        
        return urlSession.dataTaskWithRequest(bmsRequest, completionHandler: bmsCompletionHandler)
    }
}



// MARK: Upload tasks

extension BMSUrlSession {

    public func uploadTaskWithRequest(request: NSURLRequest, fromData bodyData: NSData) -> NSURLSessionUploadTask {

        let bmsRequest = prepareRequest(request)
        
        return urlSession.uploadTaskWithRequest(bmsRequest, fromData: bodyData)
    }

    public func uploadTaskWithRequest(request: NSURLRequest, fromData bodyData: NSData?, completionHandler: BMSDataTaskCompletionHandler) -> NSURLSessionUploadTask {
        
        let bmsRequest = prepareRequest(request)
        
        return urlSession.uploadTaskWithRequest(bmsRequest, fromData: bodyData, completionHandler: completionHandler)
    }

    public func uploadTaskWithRequest(request: NSURLRequest, fromFile fileURL: NSURL) -> NSURLSessionUploadTask {

        let bmsRequest = prepareRequest(request)
        
        return urlSession.uploadTaskWithRequest(bmsRequest, fromFile: fileURL)
    }

    public func uploadTaskWithRequest(request: NSURLRequest, fromFile fileURL: NSURL, completionHandler: BMSDataTaskCompletionHandler) -> NSURLSessionUploadTask {

        let bmsRequest = prepareRequest(request)
        
        return urlSession.uploadTaskWithRequest(bmsRequest, fromFile: fileURL, completionHandler: completionHandler)
    }
}