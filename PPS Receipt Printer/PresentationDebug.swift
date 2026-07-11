//
//  PresentationDebug.swift
//  PPS Receipt Printer
//
//  Created by Timothy Renollet on 7/11/26.
//

import Foundation

enum PresentationDebug {
    static var isEnabled = true

    static func log(
        _ event: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        guard isEnabled else { return }

        let timestamp = Date().formatted(
            .dateTime
                .hour()
                .minute()
                .second()
                .secondFraction(.fractional(3))
        )

        print(
            """
            🧭 PRESENTATION DEBUG
            Time: \(timestamp)
            Event: \(event)
            File: \(file)
            Function: \(function)
            Line: \(line)
            ─────────────────────────────
            """
        )
    }

    static func state(
        _ name: String,
        value: Bool,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(
            "\(name) changed to \(value)",
            file: file,
            function: function,
            line: line
        )
    }

    static func item(
        _ name: String,
        isPresent: Bool,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(
            "\(name) is \(isPresent ? "present" : "nil")",
            file: file,
            function: function,
            line: line
        )
    }
}
