//
//  Extension.swift
//  Limmi
//
//  Created by ALP on 18.05.2025.
//
import SwiftUI


@ViewBuilder
func textSub(_ txt: String) -> some View {
    HStack {
        Text(txt)
            .font(.custom("Helvetica", size: 24))
            .fontWeight(.regular) // Closest to 400

        Spacer()
    }
    .padding(25)
}

func textSubCreate(_ txt: String) -> some View {
    HStack {
        Text(txt)
            .font(.custom("Helvetica", size: 24))
            .fontWeight(.regular) // Closest to 400

    }
  
}

func txtBeacon(_ txt: String) -> some View {
    HStack {
        Text(txt)
            .font(.custom("Helvetica", size: 24))
            .fontWeight(.regular) // Closest to 400
        Spacer()
    }
    .padding(.horizontal, 30)
}

