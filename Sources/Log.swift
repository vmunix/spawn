import Logging

/// Shared logger for the spawn CLI. Default level is `.warning` (silent).
/// Commands set `logger.logLevel = .debug` when `--verbose` is passed.
/// Mutation happens only at startup before concurrent work begins.
nonisolated(unsafe) var logger: Logger = {
    LoggingSystem.bootstrap(StreamLogHandler.standardError)
    var log = Logger(label: "spawn")
    log.logLevel = .warning
    return log
}()
