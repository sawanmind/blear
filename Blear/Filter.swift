//
//  Filter.swift
//  Blear
//
//  Created by Sawan Kumar on 26/06/19.
//  Copyright © 2019 Sindre Sorhus. All rights reserved.
//

import Foundation
import UIKit
import CoreImage


// MARK: Filter Category enum

enum FilterCategory : String, CaseIterable {
    
    case CIColorInvert
    case CIColorMonochrome
    case CIColorPosterize
    case CIFalseColor
    case CIMaskToAlpha
    case CIMaximumComponent
    case CIMinimumComponent
    case CIPhotoEffectChrome
    case CIPhotoEffectFade
    case CIPhotoEffectInstant
    case CIPhotoEffectMono
    case CIPhotoEffectNoir
    case CIPhotoEffectProcess
    case CIPhotoEffectTonal
    case CIPhotoEffectTransfer
    case CISepiaTone
    case CIVignette
    case CIVignetteEffect
    case CILinearToSRGBToneCurve
    case CITemperatureAndTint
    
    
}

