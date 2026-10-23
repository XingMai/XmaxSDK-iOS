//
//  XmaxConfiguration.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// The credentials, service environment, and logging options for an Xmax client.
public struct XmaxConfiguration: Equatable, Sendable {

    /// The API key used to access Xmax services.
    public let apiKey: String

    /// The service environment and log detail language: Chinese for China, English for global.
    ///
    /// The most recently created client determines the log language for all clients.
    public let environment: XmaxEnvironment

    /// The enabled log categories. An empty set disables logging.
    public let loggerOptions: XmaxLoggerOption

    /// Creates a client configuration.
    public init(
        apiKey: String,
        environment: XmaxEnvironment = .china,
        loggerOptions: XmaxLoggerOption = []
    ) {
        let resolvedApiKey = apiKey.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.apiKey = resolvedApiKey
        self.environment = environment
        self.loggerOptions = loggerOptions
    }

    /// Verifies that the API key is not empty.
    ///
    /// - Throws: An `XmaxError` if the API key is empty.
    public func validate() throws {
        guard !apiKey.isEmpty else {
            throw XmaxError(
                code: .invalidAPIKey,
                message: "API key cannot be empty"
            )
        }
    }
}
