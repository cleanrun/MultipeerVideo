//
//  H264Encoder.swift
//  MultipeerVideo-Assignment
//
//  Created by cleanmac on 04/03/23.
//

import Foundation
import VideoToolbox
import CoreMedia

enum FrameType: UInt {
    case spspps
    case iframe
    case pframe
}

protocol H264EncoderDelegate: AnyObject {
    func didReceiveData(_ data: Data, frameType: FrameType)
    func didReceiveSpsppsData(_ sps: Data, pps: Data)
}

final class H264Encoder {
    var delegate: H264EncoderDelegate?
    
    private var session: VTCompressionSession?
    private let callback: (CMSampleBuffer) -> Void
    private var width: Int32
    private var height: Int32
    private var fps: Int32 = 10
    private var frameCount: Int64
    private var shouldUnpack: Bool
    private var bufferArray = [CMSampleBuffer]()
    
    private let outputCallback: VTCompressionOutputCallback = { refCon, sourceFrameRefCon, status, infoFlags, sampleBuffer in
        guard let refCon, status == noErr, let sampleBuffer else {
            print("Encoder output callback sample buffer Nil, status: \(status)")
            return
        }
        
        if (!CMSampleBufferDataIsReady(sampleBuffer)) {
            print("Sample buffer isn't ready")
            return
        }
        
        let encoder: H264Encoder = Unmanaged<H264Encoder>.fromOpaque(refCon).takeRetainedValue()
        if encoder.shouldUnpack {
            var isKeyFrame: Bool = false
            
            guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) else {
                print("Attachments array is nil")
                return
            }
            
            if CFArrayGetCount(attachmentsArray) > 0 {
                let cfDict = CFArrayGetValueAtIndex(attachmentsArray, 0)
                let dictRef = unsafeBitCast(cfDict, to: CFDictionary.self)
                let value = CFDictionaryGetValue(dictRef, unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self))
                if value == nil {
                    isKeyFrame = true
                }
            }
            
            if isKeyFrame {
                var description = CMSampleBufferGetFormatDescription(sampleBuffer)!
                
                // Getting the SPS
                var sparamSetCount: size_t = 0
                var sparamSetSize: size_t = 0
                var sparamSetPointer: UnsafePointer<UInt8>?
                var sstatusCode: OSStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: 0, parameterSetPointerOut: &sparamSetPointer, parameterSetSizeOut: &sparamSetSize, parameterSetCountOut: &sparamSetCount, nalUnitHeaderLengthOut: nil)
                
                if sstatusCode == noErr {
                    
                    // Getting the PPS
                    var pparamSetCount: size_t = 0
                    var pparamSetSize: size_t = 0
                    var pparamSetPointer: UnsafePointer<UInt8>?
                    var pstatusCode: OSStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: 0, parameterSetPointerOut: &pparamSetPointer, parameterSetSizeOut: &pparamSetSize, parameterSetCountOut: &pparamSetCount, nalUnitHeaderLengthOut: nil)
                    
                    if pstatusCode == noErr {
                        var sps = NSData(bytes: sparamSetPointer, length: sparamSetSize)
                        var pps = NSData(bytes: pparamSetPointer, length: pparamSetSize)
                        encoder.delegate?.didReceiveSpsppsData(sps as Data, pps: pps as Data)
                    }
                }
                
                var dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)!
                var length: size_t = 0
                var totalLength: size_t = 0
                var bufferDataPointer: UnsafeMutablePointer<Int8>?
                var statusCodePointer = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: &totalLength, dataPointerOut: &bufferDataPointer)
                if statusCodePointer == noErr {
                    var bufferOffset: size_t = 0
                    let AVCCHeaderLength: Int = 4
                    while bufferOffset < totalLength - AVCCHeaderLength {
                        
                        // Read the NAL unit length
                        var NALUnitLength: UInt32 = 0
                        memcpy(&NALUnitLength, bufferDataPointer! + bufferOffset, AVCCHeaderLength)
                        
                        // Big-Endian to Little-Endian
                        NALUnitLength = CFSwapInt32BigToHost(NALUnitLength)
                        
                        var data = NSData(bytes: (bufferDataPointer! + bufferOffset + AVCCHeaderLength), length: Int(Int32(NALUnitLength)))
                        var frameType: FrameType = .pframe
                        var dataBytes = Data(bytes: data.bytes, count: data.length)
                        if (dataBytes[0] & 0x1F) == 5 {
                            frameType = .iframe
                        }
                        
                        encoder.delegate?.didReceiveData(data as Data, frameType: frameType)
                        
                        // Move to the next NAL unit in the block buffer
                        bufferOffset += AVCCHeaderLength + size_t(NALUnitLength)
                    }
                }
            }
        }
        
        encoder.processSample(sampleBuffer)
    }
    
    init(width: Int32, height: Int32, fps: Int32, callback: @escaping (CMSampleBuffer) -> Void) {
        self.callback = callback
        self.width = width
        self.height = height
        self.fps = fps
        self.frameCount = 0
        self.shouldUnpack = true
    }
    
    deinit {
        print("H264Encoder deinit")
    }
    
    private func processSample(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferGetDataBuffer(sampleBuffer) != nil else {
            print("\(#function): Encoder outputCallback dataBuffer is nil")
            return
        }
        
        callback(sampleBuffer)
    }
    
    private func copySampleBuffer(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer), let formatDescriptionRef = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            print("\(#function): block buffer or format description reference is nil")
            return nil
        }
        
        let copiedSampleBuffer = UnsafeMutablePointer<CMSampleBuffer?>.allocate(capacity: 1)
        let copiedDataBuffer = UnsafeMutablePointer<CMBlockBuffer?>.allocate(capacity: 1)
        
        let (data, length) = H264Encoder.getData(from: blockBuffer)
        print("\(#function): Retained data", data)
        
        let nsData = NSMutableData(data: data)
        CMBlockBufferCreateEmpty(allocator: nil, capacity: 0, flags: kCMBlockBufferAlwaysCopyDataFlag, blockBufferOut: copiedDataBuffer)
        CMBlockBufferAppendMemoryBlock(copiedDataBuffer.pointee!, memoryBlock: nsData.mutableBytes, length: length, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: length, flags: kCMBlockBufferAlwaysCopyDataFlag)
        
        let (timingInfo, timingInfoCount) = H264Encoder.getTimingArray(from: sampleBuffer)
        let (sizeArray, sizeArrayCount) = H264Encoder.getSizeArray(from: sampleBuffer)
        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        
        let retainedDataBuffer = Unmanaged.passRetained(copiedDataBuffer.pointee!)
        CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                             dataBuffer: retainedDataBuffer.takeUnretainedValue(),
                             dataReady: true,
                             makeDataReadyCallback: nil,
                             refcon: nil,
                             formatDescription: formatDescriptionRef,
                             sampleCount: sampleCount,
                             sampleTimingEntryCount: timingInfoCount,
                             sampleTimingArray: timingInfo,
                             sampleSizeEntryCount: sizeArrayCount,
                             sampleSizeArray: sizeArray,
                             sampleBufferOut: copiedSampleBuffer)
        timingInfo.deallocate()
        sizeArray.deallocate()
        H264Encoder.copyAttachments(from: sampleBuffer, to: copiedSampleBuffer.pointee!)
        return copiedSampleBuffer.pointee!
    }
    
    func prepareToEncodeFrames() {
        let encoderSpecifications = [ kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true as CFBoolean ] as CFDictionary
        let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
                                                width: self.width,
                                                height: self.height,
                                                codecType: kCMVideoCodecType_H264,
                                                encoderSpecification: encoderSpecifications,
                                                imageBufferAttributes: nil,
                                                compressedDataAllocator: nil,
                                                outputCallback: outputCallback,
                                                refcon: Unmanaged.passUnretained(self).toOpaque(),
                                                compressionSessionOut: &session)
        print("\(#function): H264 init status \(status == noErr) \(status)")
        
        guard let session else {
            print("\(#function): Session is nil")
            return
        }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &self.fps))
        VTCompressionSessionPrepareToEncodeFrames(session)
    }
    
    func encodeBySampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        encodeByPixelBuffer(imageBuffer)
    }
    
    func encodeByPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        frameCount += 1
        let imageBuffer = pixelBuffer
        let presentationTimeStamp = CMTimeMake(value: frameCount, timescale: 1000)
        var _: OSStatus = VTCompressionSessionEncodeFrame(session!,
                                                          imageBuffer: imageBuffer,
                                                          presentationTimeStamp: presentationTimeStamp,
                                                          duration: .invalid,
                                                          frameProperties: nil,
                                                          sourceFrameRefcon: nil,
                                                          infoFlagsOut: nil)
    }
    
    func encode(_ sampleBuffer: CMSampleBuffer) {
        guard let session, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("\(#function): Encode failed, session or image buffer might be nil")
            return
        }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let _ = VTCompressionSessionEncodeFrame(session,
                                                imageBuffer: imageBuffer,
                                                presentationTimeStamp: timestamp,
                                                duration: .invalid,
                                                frameProperties: nil,
                                                sourceFrameRefcon: nil,
                                                infoFlagsOut: nil)
    }
    
    func stop() {
        guard let session else {
            print("\(#function): Session is nil")
            return
        }
        VTCompressionSessionInvalidate(session)
        frameCount = 0
        self.session = nil
    }
}

extension H264Encoder {
    static func getData(from buffer: CMBlockBuffer) -> (Data, Int) {
        var totalLength = Int()
        var length = Int()
        var dataPointer: UnsafeMutablePointer<Int8>?
        let _ = CMBlockBufferGetDataPointer(buffer, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        return (Data(bytes: dataPointer!, count: length), length)
    }
    
    static func copyAttachments(from sampleBuffer: CMSampleBuffer, to output: CMSampleBuffer) {
        attachments(from: sampleBuffer)
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) else {
            print("\(#function): attachments array is nil")
            return
        }
        let newAttachments = CMSampleBufferGetSampleAttachmentsArray(output, createIfNecessary: true)!
        let numValues = CFArrayGetCount(attachmentsArray)
        for i in 0..<numValues
        {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachmentsArray, i), to: CFDictionary.self)
            let newDict = unsafeBitCast(CFArrayGetValueAtIndex(newAttachments, i), to: CFMutableDictionary.self)
            
            let dictCount = CFDictionaryGetCount(dict)
            let keys = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: dictCount)
            let values = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: dictCount)
            
            CFDictionaryGetKeysAndValues(dict, keys, values)
            
            for j in 0..<dictCount {
                CFDictionarySetValue(newDict, keys[j], values[j])
            }
            let key = Unmanaged.passRetained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque()
            let value = Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            CFDictionaryAddValue(newDict, key, value)
            keys.deallocate()
            values.deallocate()
        }
    }
    
    static func attachments(from sampleBuffer: CMSampleBuffer) {
        let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)!
        let numValues = CFArrayGetCount(attachmentsArray)
        
        for i in 0..<numValues {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachmentsArray, i), to: CFDictionary.self) as NSDictionary
            let _ = dict.allKeys as! [CFString]
            let _ = dict.allValues as! [CFBoolean]
        }
    }
    
    static func getTimingArray(from sampleBuffer: CMSampleBuffer) -> (pointer: UnsafeMutablePointer<CMSampleTimingInfo>, count: CMItemCount) {
        var entriesCount: CMItemCount = 0
        _ = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &entriesCount)
        let timingArray = UnsafeMutablePointer<CMSampleTimingInfo>.allocate(capacity: entriesCount)
        _ = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: entriesCount, arrayToFill: timingArray, entriesNeededOut: &entriesCount)
        return (timingArray, entriesCount)
    }
    
    static func getSizeArray(from sampleBuffer: CMSampleBuffer) -> (pointer: UnsafeMutablePointer<Int>, count: CMItemCount) {
        var entriesCount: CMItemCount = 0
        _ = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &entriesCount)
        let sizeArray = UnsafeMutablePointer<Int>.allocate(capacity: entriesCount)
        _ = CMSampleBufferGetSampleSizeArray(sampleBuffer, entryCount: entriesCount, arrayToFill: sizeArray, entriesNeededOut: &entriesCount)
        return (sizeArray, entriesCount)
    }
}
