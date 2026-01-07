//
//  LoginView.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI

struct LoginView: View {
    @State private var viewModel = LoginViewModel()
    @Binding var isLoggedIn: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "headphones.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)
                    .padding(.bottom, 20)

                Text("AudioShelf")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Connect to your AudioBookshelf server")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 30)

                VStack(spacing: 16) {
                    TextField("Server URL", text: $viewModel.serverURL)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)

                    TextField("Username", text: $viewModel.username)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.username)
                        .autocapitalization(.none)

                    SecureField("Password", text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                }
                .padding(.horizontal)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
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
                        Text("Login")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
                .padding(.horizontal)
                .padding(.top, 10)

                Spacer()
            }
            .padding()
        }
    }
}

#Preview {
    LoginView(isLoggedIn: .constant(false))
}
