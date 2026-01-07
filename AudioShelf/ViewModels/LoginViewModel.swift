//
//  LoginViewModel.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import Foundation

@Observable
class LoginViewModel {
    var serverURL: String = ""
    var username: String = ""
    var password: String = ""
    var isLoading = false
    var errorMessage: String?

    private let api = AudioBookshelfAPI.shared

    func login() async {
        guard !serverURL.isEmpty, !username.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            _ = try await api.login(serverURL: serverURL, username: username, password: password)
            isLoading = false
        } catch APIError.unauthorized {
            isLoading = false
            errorMessage = "Invalid username or password"
        } catch APIError.invalidURL {
            isLoading = false
            errorMessage = "Invalid server URL"
        } catch {
            isLoading = false
            errorMessage = "Connection failed: \(error.localizedDescription)"
        }
    }
}
