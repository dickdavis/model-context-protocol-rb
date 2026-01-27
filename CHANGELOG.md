## [Unreleased]

- Implement list changed notifications for prompts, resources, and tools (Streamable HTTP transport only).
- Add `ssl_params` configuration option for Redis connections to support hosted Redis providers with self-signed certificates.

## [0.6.0] - 2026-01-26

- Implement server logging capability for internal server diagnostics.
- Add informational and debug logging in streamable HTTP transport.
- (Fix) Ensure stream monitor thread shuts down quickly.
- (Fix) Ensure streams are closed when the server shuts down.
- (Fix) Fix stream handling in streamable HTTP transport.
- (Fix) Ensure empty options don't break the registry.
- (Fix) Ensure progressable timer tasks do not run indefinitely.
- (Breaking) Update connection pool dependency; requires updating other gems that depend on connection_pool.

## [0.5.1] - 2025-09-23

- (Fix) Ensure streams are properly closed when clients disconnect.

## [0.5.0] - 2025-09-22

- Make streamable HTTP transport thread-safe by using Redis to manage state.
- Implement Redis connection pooling with robust management and configuration.
- Automatically upgrade connection to SSE to send notifications.
- Add support for cancellations and progress notifications via `cancellable` and `progressable` blocks in prompts, resources, and tools.

## [0.4.0] - 2025-09-07

- Implement pagination support.
- Add support for server title and instructions.
- Implement resource annotations.
- Implement content responses and helper methods for easily serializing text, image, audio, embedded resource, and resource link content blocks.
- (Breaking) Simplify the ergonomics of `respond_with`.
- (Breaking) Rename `with_metadata` to `define`; this avoids confusion with the distinct concept of metadata in MCP.
- (Breaking) Nest argument declarations within `define` (formerly `with_metadata`).
- Allow prompts, resources, and tools to declare the `title` field.
- Implement default completion functionality.
- Implement structured content support for tools (with `output_schema` declaration and validation).
- Implement a prompt builder DSL for easily building a message history for a prompt; supports use of new content block helpers.
- Implement support for protocol negotiation.
- Finalize the initial working version of the streamable HTTP transport.

## [0.3.4] - 2025-09-02

- (Fix) Fixes broken arguments usage in prompts and tools.

## [0.3.3] - 2025-09-02

- (Breaking) Added logging support.
  - Requires updating the `enable_log` configuration option to `logging_enabled`.
- Added experimental Streamable HTTP transport.
- (Breaking) Renamed params to arguments in prompts, resources, and tools.
  - Requires updating all references to `params` in prompts, resources, and tools to `arguments` with symbolized keys.
- Improved ergonomics of completions and resource templates.
- Added support for providing context to prompts, resources, and tools.

## [0.3.2] - 2025-05-10

- Added resource template support.
- Added completion support for prompts and resources.
- Improved metadata definition for prompts, resources, and tools using simple DSL.

## [0.3.1] - 2025-04-04

- Added support for environment variables to MCP servers (thanks @hmk):
  - `require_environment_variable` method to specify required environment variables
  - `set_environment_variable` method to programmatically set environment variables
  - Environment variables accessible within tool/prompt/resource handlers
- Added `respond_with` helper methods to simplify response creation:
  - For tools: text, image, resource, and error responses
  - For prompts: formatted message responses
  - For resources: text and binary responses
- Improved development tooling:
  - Generated executable now loads all test classes
  - Fixed test support classes for better compatibility with MCP inspector
  - Organized test tools, prompts, and resources in dedicated directories

## [0.3.0] - 2025-03-11

- (Breaking) Replaced router initialization in favor of registry initialization during server configuration. The server now relies on the registry for auto-discovery of prompts, resources, and tools; this requires the use of SDK-provided builders to facilitate.
- (Breaking) Implemented the use of `Data` objects across the implementation. As a result, responses from custom handlers must now respond with an object that responds to `serialized`.
- Refactored the implementation to maintain separation of concerns and improve testability/maintainability.
- Improved test coverage.
- Improved development tooling.

## [0.2.0] - 2025-01-13

- Added a basic, synchronous server implementation that routes requests to custom handlers.

## [0.1.0] - 2025-01-10

- Initial release

[Unreleased]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.3.4...v0.4.0
[0.3.4]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/dickdavis/model-context-protocol-rb/releases/tag/v0.1.0
