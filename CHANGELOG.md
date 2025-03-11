## [Unreleased]

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

[Unreleased]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/dickdavis/model-context-protocol-rb/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/dickdavis/model-context-protocol-rb/releases/tag/v0.1.0
