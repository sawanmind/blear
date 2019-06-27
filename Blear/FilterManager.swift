//
//  FilterManager.swift
//  Blear
//
//  Created by Sawan Kumar on 26/06/19.
//  Copyright © 2019 Sindre Sorhus. All rights reserved.
//

import Foundation
import UIKit
import CoreImage
import OpenGLES
// MARK: Filter State
enum FilterState {
    case new, filtered, failed
}
// MARK: Image Model
class ImageModel {
    var state = FilterState.new
    var image : UIImage?
    
    init(image:UIImage) {
        self.image = image
    }
}
// MARK: Pending Operations
class PendingOperations {
    lazy var filtrationsInProgress: [Int: Operation] = [:]
    lazy var filtrationQueue: OperationQueue = {
        var queue = OperationQueue()
        queue.name = "Image_Filtration_queue"
        return queue
    }()
}


// MARK: FilterManager Operations
class FilterManager: Operation {
    let photoRecord: ImageModel
    var filterCategory : FilterCategory
    var context: CIContext?
    
    init(_ photoRecord: ImageModel, filterCategory : FilterCategory) {
        self.photoRecord = photoRecord
        self.filterCategory = filterCategory
        super.init()
        switchToGPU()
    }
    
    override func main () {
        if isCancelled {
            return
        }
        
        if let image = photoRecord.image,
            let filteredImage = applyFilter(filterCategory, image) {
            photoRecord.image = filteredImage
            photoRecord.state = .filtered
        }
    }

    fileprivate func switchToGPU() {
        let openGLContext = EAGLContext(api: .openGLES3)
        let _context = CIContext(eaglContext: openGLContext!)
        context = _context
    }
    
    // MARK: Applying filter
    func applyFilter(_ type:FilterCategory, _ image: UIImage) -> UIImage? {
        
        guard let data = image.pngData(),
        let coreImage = CIImage(data: data) else { return nil }
        
        if isCancelled {
            return nil
        }
        
        
        let filter = CIFilter(name:type.rawValue)
        filter?.setValue(coreImage, forKey: kCIInputImageKey)
        
        if type == .CISepiaTone {
             filter?.setValue(0.8, forKey: "inputIntensity")
        } else if type == .CIVignette {
            filter?.setValue(0.8, forKey: "inputIntensity")
        } else if type == .CIVignetteEffect {
            filter?.setValue(0.8, forKey: "inputIntensity")
        }
        
        if self.isCancelled {
            return nil
        }
        
        guard
            let outputImage = filter?.outputImage,
            let outImage = context?.createCGImage(outputImage, from: outputImage.extent)
            else {
                return nil
        }
        
        return UIImage(cgImage: outImage)
    }

}

