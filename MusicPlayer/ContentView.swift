//
//  ContentView.swift
//  MusicPlayer
//
//  Created by John Seong on 8/5/25.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.presentationMode) var mode: Binding<PresentationMode>

       var body: some View {
           VStack(spacing: 0) {

           }
           .appBar(title: "John Seong") {
               self.mode.wrappedValue.dismiss()
           }
       }
}

extension View {
    /// CommonAppBar
    public func appBar(title: String, backButtonAction: @escaping() -> Void) -> some View {

        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .navigationBarItems(leading: Button(action: {
                backButtonAction()
            }) {
                Image("ic-back") // set backbutton image here
                    .renderingMode(.template)
                    .foregroundColor(.blue)
            })
    }
}

#Preview {
    ContentView()
}
