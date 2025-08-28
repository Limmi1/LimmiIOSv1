//
//  StringContent.swift
//  Limmi
//
//  Created by ALP on 14.05.2025.
//

import Foundation

extension String {
    func chunkedUUID() -> String {
        guard self.count == 32 else { return self }
        return "\(self.prefix(8))-\(self.dropFirst(8).prefix(4))-\(self.dropFirst(12).prefix(4))-\(self.dropFirst(16).prefix(4))-\(self.dropFirst(20))"
    }
}

