//
//  ContentView.swift
//  VideoFilterTest
//
//  Created by Yuki Kuwashima on 2024/05/22.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import AVKit

struct ContentView: View {

    @State var newURL: URL?

    let r: CIFilter = {
        let f = CIFilter.colorMonochrome()
        f.setDefaults()
        return f
    }()

    var body: some View {
        VStack {
            if let newURL {
                VideoPlayer(player: .init(url: newURL))
            }
        }
        .padding()
        .onAppear {
            let filter = VideoFilter()
            filter.ciFilterVideo(
                videoURL: Bundle.main.url(forResource: "test", withExtension: "mp4")!,
                ciFilter: r
            ) { err, filteredVideoURL in
                newURL = filteredVideoURL
            }
        }
    }
}
