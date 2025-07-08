## Unreleased

* Update OAuth callback URL scheme to app.contextmcp (#9)
* Support MCP Pagination (#10))
* Support MCP Roots (#11)
* Handle pings sent by server to client (#12)
* Handle "Connection: keep-alive" HTTP header (#17)
* Fix numerous bugs in the OAuth authentication flow (#7, #24)
* Handle requests where `params` is not specified (#25)

## Version 1.0.6 (106)

* Implement support for Anthropic dxt (Desktop Extension) format (#4)
* Fix servers not appearing in sidebar after importing servers (#8)
* Fix broken OAuth token refresh and remove HTTPS requirement for OAuth (#7)

## Version 1.0.5 (105)
* Implement missing SQLite uuid() function ([cb33360](https://github.com/indragiek/Context/commit/cb33360a73b5a2a5d661f330439341f226d13731))

## Version 1.0.4 (104)
* Fix crash due to partial initialization of StdioTransport ([ec0e988](https://github.com/indragiek/Context/commit/ec0e9886be179cc3bb00eb56d0e95d7f2d2d8ad7))
* Fix broken handling of legacy SSE transport ([4bac2d6](https://github.com/indragiek/Context/commit/4bac2d6405270ac7cb1f9b9d95204156db8f6410))
* Build a universal binary for Intel and Apple Silicon ([0528f8e](https://github.com/indragiek/Context/commit/0528f8e36b2ae5372b062d69d6299bc28661469b))
* Use shared browser session for OAuth ([ec26845](https://github.com/indragiek/Context/commit/ec26845e34f6044e5d8000793bc4fa4f5a2abaf5))
* Allow HTTP connections for OAuth on localhost ([f57c01f](https://github.com/indragiek/Context/commit/f57c01f0ba7744c6911efcaedc07e5aead5d9863))
* Use stats.store for Sparkle analytics ([c67fca3](https://github.com/indragiek/Context/commit/c67fca33a8bc1e1458ad55c89de646d0a4221779))
* Fix $PATH resolution to use shell $PATH ([ff896cf](https://github.com/indragiek/Context/commit/ff896cf595159eae7a34717bc59e8a80039d9054))

## Version 1.0.3 (103)

- Fix Import Servers modal not appearing when opening it from the Welcome modal

## Version 1.0.2 (102)

- Fix bug where authentication modal wouldn't appear after adding a server
- Animate the connection state icon

## Version 1.0.1 (101)

- Initial public version
