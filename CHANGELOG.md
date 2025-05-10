## [Unreleased]

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

[Unreleased]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.3.2...HEAD
[0.3.1]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/dickdavis/model-context-protocol-rb/releases/tag/v0.1.0
