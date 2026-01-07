//
//  User.swift
//  AudioShelf
//
//  Created by Claude on 2026-01-07.
//

import Foundation

struct LoginResponse: Codable {
    let user: User
}

struct User: Codable {
    let id: String
    let username: String
    let token: String
}
