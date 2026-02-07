//
//  TVLoginView.swift
//  AudioShelfTV
//
//  Created by Claude on 2026-02-04.
//

import SwiftUI

struct TVLoginView: View {
    @Binding var isLoggedIn: Bool
    @State private var viewModel = LoginViewModel()

    var body: some View {
        VStack(spacing: 40) {
            // App branding
            VStack(spacing: 16) {
                Image(systemName: "headphones.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("AudioShelf")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Connect to your Audiobookshelf server")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // Login form
            VStack(spacing: 24) {
                TextField("Server URL (e.g. https://audio.example.com)", text: $viewModel.serverURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()

                TextField("Username", text: $viewModel.username)
                    .textContentType(.username)
                    .autocorrectionDisabled()

                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                Button {
                    Task {
                        await viewModel.login()
                        if AudioBookshelfAPI.shared.isLoggedIn {
                            isLoggedIn = true
                        }
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign In")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(viewModel.isLoading || viewModel.serverURL.isEmpty || viewModel.username.isEmpty || viewModel.password.isEmpty)
            }
            .frame(maxWidth: 500)
        }
        .padding(60)
    }
}
