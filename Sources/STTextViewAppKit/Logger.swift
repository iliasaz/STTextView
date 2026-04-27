//  Created by Marcin Krzyzanowski
//  https://github.com/krzyzanowskim/STTextView/blob/main/LICENSE.md

import Foundation
import OSLog

let logger = Logger(subsystem: "best.swift.sttextview", category: "STTextView")

// Dedicated logger for diagnosing the Cmd-End → Cmd-Home viewport-collapse
// issue. Filter in Console.app or `log stream` with:
//   subsystem:best.swift.sttextview category:CmdHome
// All sites use `.notice` so they show up without enabling debug streaming.
let cmdHomeLogger = Logger(subsystem: "best.swift.sttextview", category: "CmdHome")
