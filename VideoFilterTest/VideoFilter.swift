//
//  VideoFilter.swift
//  VideoFilterTest
//
//  Created by Yuki Kuwashima on 2024/05/22.
//

import AVFoundation
import UIKit
import SwiftUI

class VideoFilter {

    let ciContext = CIContext()

    public func ciFilterVideo(videoURL:URL, ciFilter: CIFilter, _ completion: ((_ err: NSError?, _ filteredVideoURL: URL?) -> Void)?) {
           applyProcessingOnVideo(videoURL: videoURL, { ciImage in
               ciFilter.setValue(ciImage, forKey: kCIInputImageKey)
               let outCIImage = ciFilter.outputImage
               return outCIImage
           } , { err, processedVideoURL in
               guard err == nil else { print(err?.localizedDescription as Any); return }
               completion?(err,processedVideoURL)
           })
       }

       public func applyProcessingOnVideo(videoURL:URL, _ processingFunction: @escaping ((CIImage) -> CIImage?), _ completion: ((_ err: NSError?, _ processedVideoURL: URL?) -> Void)?) {
           var frame:Int = 0
           var isFrameRotated = false
           let asset = AVURLAsset(url: videoURL)
           let duration = asset.duration.value
           let frameRate = asset.preferredRate
           let totalFrame = frameRate * Float(duration)
           let err: NSError = NSError.init(domain: "SemanticImage", code: 999, userInfo: [NSLocalizedDescriptionKey: "Video Processing Failed"])
           guard let writingDestinationUrl: URL  = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("\(Date())" + ".mp4") else { print("nil"); return}

           // setup

           guard let reader: AVAssetReader = try? AVAssetReader.init(asset: asset) else {
               completion?(err, nil)
               return
           }
           guard let writer: AVAssetWriter = try? AVAssetWriter(outputURL: writingDestinationUrl, fileType: AVFileType.mov) else {
               completion?(err, nil)
               return
           }

           // setup finish closure

           var audioFinished: Bool = false
           var videoFinished: Bool = false
           let writtingFinished: (() -> Void) = {
               if audioFinished == true && videoFinished == true {
                   writer.finishWriting {
                       completion?(nil, writingDestinationUrl)
                   }
                   reader.cancelReading()
               }
           }

           // prepare video reader

           let readerVideoOutput: AVAssetReaderTrackOutput = AVAssetReaderTrackOutput(
               track: asset.tracks(withMediaType: AVMediaType.video)[0],
               outputSettings: [
                   kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
               ]
           )

           reader.add(readerVideoOutput)

           // prepare audio reader

           var readerAudioOutput: AVAssetReaderTrackOutput!
           if asset.tracks(withMediaType: AVMediaType.audio).count <= 0 {
               audioFinished = true
           } else {
               readerAudioOutput = AVAssetReaderTrackOutput.init(
                   track: asset.tracks(withMediaType: AVMediaType.audio)[0],
                   outputSettings: [
                       AVSampleRateKey: 44100,
                       AVFormatIDKey:   kAudioFormatLinearPCM,
                   ]
               )
               if reader.canAdd(readerAudioOutput) {
                   reader.add(readerAudioOutput)
               } else {
                   print("Cannot add audio output reader")
                   audioFinished = true
               }
           }

           // prepare video input

           let transform = asset.tracks(withMediaType: AVMediaType.video)[0].preferredTransform
           let radians = atan2(transform.b, transform.a)
           let degrees = (radians * 180.0) / .pi

           var writerVideoInput: AVAssetWriterInput
           switch degrees {
           case 90:
               let rotateTransform = CGAffineTransform(rotationAngle: 0)
               writerVideoInput = AVAssetWriterInput.init(
                   mediaType: AVMediaType.video,
                   outputSettings: [
                       AVVideoCodecKey:                 AVVideoCodecType.h264,
                       AVVideoWidthKey:                 asset.tracks(withMediaType: AVMediaType.video)[0].naturalSize.height,
                       AVVideoHeightKey:                asset.tracks(withMediaType: AVMediaType.video)[0].naturalSize.width,
                       AVVideoCompressionPropertiesKey: [
                           AVVideoAverageBitRateKey: asset.tracks(withMediaType: AVMediaType.video)[0].estimatedDataRate,
                       ],
                   ]
               )
               writerVideoInput.expectsMediaDataInRealTime = false

               isFrameRotated = true
               writerVideoInput.transform = rotateTransform
           default:
               writerVideoInput = AVAssetWriterInput.init(
                   mediaType: AVMediaType.video,
                   outputSettings: [
                       AVVideoCodecKey:                 AVVideoCodecType.h264,
                       AVVideoWidthKey:                 asset.tracks(withMediaType: AVMediaType.video)[0].naturalSize.width,
                       AVVideoHeightKey:                asset.tracks(withMediaType: AVMediaType.video)[0].naturalSize.height,
                       AVVideoCompressionPropertiesKey: [
                           AVVideoAverageBitRateKey: asset.tracks(withMediaType: AVMediaType.video)[0].estimatedDataRate,
                       ],
                   ]
               )
               writerVideoInput.expectsMediaDataInRealTime = false
               isFrameRotated = false
               writerVideoInput.transform = asset.tracks(withMediaType: AVMediaType.video)[0].preferredTransform
           }
           let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerVideoInput, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])

           writer.add(writerVideoInput)


           // prepare writer input for audio

           var writerAudioInput: AVAssetWriterInput! = nil
           if asset.tracks(withMediaType: AVMediaType.audio).count > 0 {
               let formatDesc: [Any] = asset.tracks(withMediaType: AVMediaType.audio)[0].formatDescriptions
               var channels: UInt32 = 1
               var sampleRate: Float64 = 44100.000000
               for i in 0 ..< formatDesc.count {
                   guard let bobTheDesc: UnsafePointer<AudioStreamBasicDescription> = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc[i] as! CMAudioFormatDescription) else {
                       continue
                   }
                   channels = bobTheDesc.pointee.mChannelsPerFrame
                   sampleRate = bobTheDesc.pointee.mSampleRate
                   break
               }
               writerAudioInput = AVAssetWriterInput.init(
                   mediaType: AVMediaType.audio,
                   outputSettings: [
                       AVFormatIDKey:         kAudioFormatMPEG4AAC,
                       AVNumberOfChannelsKey: channels,
                       AVSampleRateKey:       sampleRate,
                       AVEncoderBitRateKey:   128000,
                   ]
               )
               writerAudioInput.expectsMediaDataInRealTime = true
               writer.add(writerAudioInput)
           }


           // write

           let videoQueue = DispatchQueue.init(label: "videoQueue")
           let audioQueue = DispatchQueue.init(label: "audioQueue")
           writer.startWriting()
           reader.startReading()
           writer.startSession(atSourceTime: CMTime.zero)

           // write video

           writerVideoInput.requestMediaDataWhenReady(on: videoQueue) {
               while writerVideoInput.isReadyForMoreMediaData {
                   autoreleasepool {
                       if let buffer = readerVideoOutput.copyNextSampleBuffer(),let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) {
                           frame += 1
                           var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                           if isFrameRotated {
                               ciImage = ciImage.oriented(CGImagePropertyOrientation.right)
                           }
                           guard let outCIImage = processingFunction(ciImage) else { print("Video Processing Failed") ; return }

                           let presentationTime = CMSampleBufferGetOutputPresentationTimeStamp(buffer)
                           var pixelBufferOut: CVPixelBuffer?
                           CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferAdaptor.pixelBufferPool!, &pixelBufferOut)

                           self.ciContext.render(outCIImage, to: pixelBufferOut!)
                           pixelBufferAdaptor.append(pixelBufferOut!, withPresentationTime: presentationTime)

   //                        if frame % 100 == 0 {
   //                            print("\(frame) / \(totalFrame) frames were processed..")
   //                        }
                       } else {
                           writerVideoInput.markAsFinished()
                           DispatchQueue.main.async {
                               videoFinished = true
                               writtingFinished()
                           }
                       }
                   }
               }
           }
           if writerAudioInput != nil {
               writerAudioInput.requestMediaDataWhenReady(on: audioQueue) {
                   while writerAudioInput.isReadyForMoreMediaData {
                       autoreleasepool {
                           let buffer = readerAudioOutput.copyNextSampleBuffer()
                           if buffer != nil {
                               writerAudioInput.append(buffer!)
                           } else {
                               writerAudioInput.markAsFinished()
                               DispatchQueue.main.async {
                                   audioFinished = true
                                   writtingFinished()
                               }
                           }
                       }
                   }
               }
           }
       }
}
