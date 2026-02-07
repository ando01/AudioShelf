//
//  SettingsView.swift
//  AudioShelf
//
//  Created by Claude on 2026-02-07.
//

import SwiftUI

struct SettingsView: View {
    @Binding var isLoggedIn: Bool
    @State private var showLogoutConfirmation = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                // Account Section
                Section {
                    if let serverURL = AudioBookshelfAPI.shared.serverURL {
                        HStack {
                            Text("Server")
                            Spacer()
                            Text(serverURL)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Button(role: .destructive) {
                        showLogoutConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Logout")
                        }
                    }
                } header: {
                    Text("Account")
                }

                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("AudioShelf")
                        Spacer()
                        Text("for Audiobookshelf")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Are you sure you want to logout?",
                isPresented: $showLogoutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Logout", role: .destructive) {
                    AudioBookshelfAPI.shared.logout()
                    isLoggedIn = false
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

#Preview {
    SettingsView(isLoggedIn: .constant(true))
}
