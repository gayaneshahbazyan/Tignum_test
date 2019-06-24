//
//  Downloader.swift
//  FileDownloaderTest
//
//  Created by Sanggeon Park on 13.06.19.
//  Copyright © 2019 Sanggeon Park. All rights reserved.
//

import Foundation
import UIKit

public protocol DownloaderDelegate: class {
    func didUpdateDownloadStatus(for identifier: String, progress: Float, status: DownloadStatus, error: Error?)
    func didUpdateProgress(for identifier: String, progress: Int)
}

extension DownloaderDelegate {
    func didUpdateDownloadStatus(for identifier: String, progress: Float, status: DownloadStatus, error: Error?) {
        // Optional Function
    }
}

#warning("DO NOT USER ANY STATIC VARIABLES AND FUNCTIONS")
open class Downloader: NSObject {
    weak var delegate: DownloaderDelegate?
    
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.Tignum.config")
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration,
                          delegate: self, delegateQueue: nil)
    }()
    
    private var sessionTaksDict: [String: URLSessionDownloadTask] = [:]
    private var downloadModelsInProcess: [DownloadModel] = []
    private var downloadedModels: [DownloadModel]! {
        didSet {
            self.saveDownloadedModels(downloadedModels)
        }
    }
    var shouldSaveDownloadedModel: Bool!
    
    public init(with delegate: DownloaderDelegate? = nil, shouldSaveDownloadedModel: Bool = true) {
        super.init()
        
        self.shouldSaveDownloadedModel = shouldSaveDownloadedModel
        self.downloadedModels = self.getSavedDownloadedModels() ?? []
        
        NotificationCenter.default.addObserver(self, selector: #selector(cancelTasks), name: UIApplication.willTerminateNotification, object: nil)

    }
    
    @objc
    private func cancelTasks() {
        for dict in sessionTaksDict {
            dict.value.cancel()
        }
    }

    public func allDownloads(_ completion: @escaping ([DownloadModel]?) -> Void) {
        let allStartedDownloads : [DownloadModel] = downloadModelsInProcess + downloadedModels
        completion(allStartedDownloads)
    }

    public func resumeDownload(for identifier: String, remotePath: String,
                        _ completion: @escaping (_ data: DownloadModel?, _ error: Error?) -> Void) {
        
        if let task = sessionTaksDict.first(where: { $0.key == identifier })?.value {
            task.resume()
            let downloadModel = DownloadModel(identifier: identifier, status: .DOWNLOADING, progress: 0, remoteFilePath: remotePath, localFilePath: "")
            completion(downloadModel, nil)
        } else {
            if let url = URL(string: remotePath) {
                let task = session.downloadTask(with: url)
                sessionTaksDict[identifier] = task
                task.resume()
                
                let downloadModel = DownloadModel(identifier: identifier, status: .DOWNLOADING, progress: 0, remoteFilePath: remotePath, localFilePath: "")
                downloadModelsInProcess.append(downloadModel)
                
                completion(downloadModel, nil)
            } else {
                completion(nil, NSError(domain: "DOWNLOADER", code: -1, userInfo: nil))
            }
        }
    }

    public func pauseDownload(for identifier: String, _ completion: @escaping (_ data: DownloadModel?, _ error: Error?) -> Void) {
        if let task = sessionTaksDict.first(where: { $0.key == identifier })?.value {
            for i in 0..<downloadModelsInProcess.count {
                if identifier == downloadModelsInProcess[i].identifier {
                    task.suspend()
                    let tmpDownloadModel = DownloadModel(identifier: identifier, status: .PAUSED, progress: downloadModelsInProcess[i].progress, remoteFilePath: downloadModelsInProcess[i].remoteFilePath, localFilePath: "")
                    downloadModelsInProcess[i] = tmpDownloadModel
                    completion(tmpDownloadModel, nil)
                    return
                }
            }

        }
        completion(nil, NSError(domain: "Model doesn't exist", code: -1, userInfo: nil))
    }

    public func removeDownload(for identifier: String, _ completion: @escaping (_ error: Error?) -> Void) {
        
        var modelToBeRemoved: DownloadModel?
        for i in 0..<downloadedModels.count {
            if downloadedModels[i].identifier == identifier {
                modelToBeRemoved = downloadedModels[i]
                downloadedModels.remove(at: i)
            }
        }
        
        if let path = modelToBeRemoved?.localFilePath,
            let newDocumentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first,
            let fileIdentifierName = path.components(separatedBy: "/").last
        {
            do {
                let newPath = newDocumentDirectory + "/" + fileIdentifierName
                try FileManager.default.removeItem(atPath: newPath)
                completion(nil)
                return
            }
            catch {
                print ("The file could not be removed")
                completion(NSError(domain: "DOWNLOADER", code: -1, userInfo: nil))
            }
        }
        completion(NSError(domain: "DOWNLOADER", code: -1, userInfo: nil))
    }

    public func downloadData(for identifier: String, _ completion: @escaping (_ data: DownloadModel?) -> Void) {
        let model = downloadedModels.first(where: { $0.identifier == identifier })
        completion(model ?? nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension Downloader: URLSessionDelegate, URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {

        if let identifier = getIdentifierFor(sessionTask: downloadTask) {
            sessionTaksDict.removeValue(forKey: identifier)
            
            let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            var destinationUrl = documentsDirectoryURL.appendingPathComponent(identifier)
            destinationUrl.appendPathExtension("mp4")
            
            var downloadedModel: DownloadModel?
            for i in 0..<downloadModelsInProcess.count {
                if downloadModelsInProcess[i].identifier == identifier {
                    downloadedModel = downloadModelsInProcess[i]
                    downloadModelsInProcess.remove(at: i)
                    break
                }
            }
            
            do {
                try? FileManager.default.removeItem(at: destinationUrl)
                try FileManager.default.copyItem(at: location, to: destinationUrl)
                let model = DownloadModel(identifier: identifier, status: .DOWNLOADED, progress: 100, remoteFilePath: downloadedModel?.remoteFilePath ?? "", localFilePath: destinationUrl.path)
                downloadedModels.append(model)

                delegate?.didUpdateDownloadStatus(for: identifier, progress: 100, status: .DOWNLOADED, error: nil)
            } catch {
                try? FileManager.default.removeItem(at: location)
                delegate?.didUpdateDownloadStatus(for: identifier, progress: 0, status: .NONE, error: NSError(domain: "FileManager error", code: -1, userInfo: nil))
            }
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let identifier = getIdentifierFor(sessionTask: downloadTask), totalBytesExpectedToWrite > 0 {
            let prc = Int(( Double(totalBytesWritten) * 1.0 )/Double(totalBytesExpectedToWrite) * 100)
            print(prc)
            delegate?.didUpdateProgress(for: identifier, progress: prc)
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, let identifier = getIdentifierFor(sessionTask: task) {
            delegate?.didUpdateDownloadStatus(for: identifier, progress: 0, status: .NONE, error: error)
            sessionTaksDict.removeValue(forKey: identifier)
            print(error)
        }
    }
}

extension Downloader {
    func getIdentifierFor(sessionTask: URLSessionTask) -> String? {
        for dict in sessionTaksDict {
            if dict.value == sessionTask {
                return dict.key
            }
        }
        return nil
    }
}

extension Downloader {
    func saveDownloadedModels(_ downloadedModels: [DownloadModel]) {
        if shouldSaveDownloadedModel, let encoded = try? JSONEncoder().encode(downloadedModels) {
            UserDefaults.standard.set(encoded, forKey: "DownloadedModels")
        }
    }
    
    func getSavedDownloadedModels() -> [DownloadModel]? {
        if let savedDownloadedModels =  UserDefaults.standard.object(forKey: "DownloadedModels") as? Data {
            if let savedModels = try? JSONDecoder().decode([DownloadModel].self, from: savedDownloadedModels) {
                return savedModels
            }
        }
        return nil
    }
}

