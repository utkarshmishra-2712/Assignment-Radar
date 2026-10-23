//
//  Item.swift
//  AssignmentRadar
//
//  Created by KIET3 on 23/10/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
