//
//  ViewController.swift
//  FileDownloaderTest
//
//  Created by Sanggeon Park on 13.06.19.
//  Copyright © 2019 Sanggeon Park. All rights reserved.
//

import UIKit
import AVKit
import AVFoundation

class ViewController: UIViewController {
    var viewModels = [DownloadViewModel(with: "Video 1", remotePath: "http://bit.ly/2WHqcG2"),
                      DownloadViewModel(with: "Video 2", remotePath: "http://bit.ly/2WHqcG2")]

    var downloader: Downloader!
    
    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        downloader = Downloader()
        downloader.delegate = self
        
        downloader.allDownloads { [unowned self] (downloadedModels) in
            guard let downloadedModels = downloadedModels else {
                return
            }
            for i in 0..<self.viewModels.count {
                let savedModel = downloadedModels.first(where: { $0.identifier == self.viewModels[i].identifier })
                if savedModel != nil {
                    self.viewModels[i].downloadStatus = .DOWNLOADED
                    self.viewModels[i].progress = 100
                }
            }
        }
    }
    
    func playVideo(path: String) {
        let player = AVPlayer(url: URL(fileURLWithPath: path))
        let playerController = AVPlayerViewController()
        playerController.player = player
        self.present(playerController, animated: true) {
            player.play()
        }
    }
}

extension ViewController: DownloaderDelegate {
    func didUpdateDownloadStatus(for identifier: String, progress: Float, status: DownloadStatus, error: Error?) {
        for i in 0..<viewModels.count {
            if viewModels[i].identifier == identifier {
                viewModels[i].downloadStatus = status
                viewModels[i].progress = progress
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
                break
            }
        }
        if error != nil {
            let alertVC = UIAlertController(title: "Alert", message: "Oops, smth went wrong during downloading", preferredStyle: .alert)
            alertVC.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
            self.present(alertVC, animated: true, completion: nil)
        }
    }
    
    func didUpdateProgress(for identifier: String, progress: Int) {
        for i in 0..<viewModels.count {
            if viewModels[i].identifier == identifier {
                viewModels[i].progress = Float(progress)
                DispatchQueue.main.async {
                    self.tableView.reloadRows(at: [IndexPath(row: i, section: 0)], with: .none)
                }
                break
            }
        }
    }
}

extension ViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModels.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)
        cell.textLabel?.text = viewModels[indexPath.row].identifier
        let status = viewModels[indexPath.row].downloadStatus
        switch status {
        case .DOWNLOADING:
            #warning("UPDATE DOWNLOADING PROGRESS")
            cell.detailTextLabel?.text = String(format: "%.0f", viewModels[indexPath.row].progress) + "%"
        default:
            cell.detailTextLabel?.text = viewModels[indexPath.row].downloadStatus.rawValue
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let status = viewModels[indexPath.row].downloadStatus
        switch status {
        case .NONE,
             .PAUSED:
            #warning("RESUME DOWNLOAD")
            downloader.resumeDownload(for: viewModels[indexPath.row].identifier, remotePath: viewModels[indexPath.row].remoteFilePath)
            {
                [weak self] (model, error) in
                if let model = model, error == nil {
                    self?.viewModels[indexPath.row].downloadStatus = model.status
                    DispatchQueue.main.async {
                        tableView.reloadData()
                    }
                }
            }
            break
        case .DOWNLOADING:
            #warning("PAUSE DOWNLOAD")
            downloader.pauseDownload(for: viewModels[indexPath.row].identifier) {
                [weak self] (model, error) in
                if let model = model, error == nil {
                    self?.viewModels[indexPath.row].downloadStatus = model.status
                    DispatchQueue.main.async {
                        tableView.reloadData()
                    }
                }
            }
            break
        case .DOWNLOADED:
            #warning("PLAY DOWNLOADED VIDEO")
            downloader.downloadData(for: viewModels[indexPath.row].identifier) {
                [weak self] (model) in
                guard let model = model,
                    let path = model.localFilePath else {
                        return
                }
                DispatchQueue.main.async {
                    //Documents Directory changes every time we launch the app
                    if let newDocumentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first,
                        let fileIdentifierName = path.components(separatedBy: "/").last
                    {
                        let newPath = newDocumentDirectory + "/" + fileIdentifierName
                        self?.playVideo(path: newPath)
                    }
                }
            }
            break
        default:
            break
        }

        tableView.deselectRow(at: indexPath, animated: false)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool
    {
        return true
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            #warning("REMOVE ONLY DOWNLOAD & REFRESH ROW")
            if viewModels[indexPath.row].downloadStatus != .DOWNLOADED {
                return
            }
            downloader.removeDownload(for: viewModels[indexPath.row].identifier) {
                [weak self] (error) in
                if let error = error {
                    print(error)
                    return
                }
                self?.viewModels.remove(at: indexPath.row)
                self?.tableView.deleteRows(at: [indexPath], with: .automatic)
            }
           
        }
    }
}

