// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Foundation
import Testing

@testable import ContextCore

@Suite("JSON Schema Format Validator")
struct JSONSchemaFormatValidatorTests {
  let validator = JSONSchemaFormatValidator()
  let contentValidator = JSONSchemaContentValidator()
  
  // MARK: - Email Format Tests
  
  @Test("Email format validation")
  func emailFormat() {
    #expect(validator.validate("test@example.com", format: "email"))
    #expect(validator.validate("user.name+tag@example.co.uk", format: "email"))
    #expect(!validator.validate("invalid-email", format: "email"))
    #expect(!validator.validate("@example.com", format: "email"))
    #expect(!validator.validate("test@", format: "email"))
    #expect(!validator.validate("test@.com", format: "email"))
  }
  
  @Test("IDN email format validation")
  func idnEmailFormat() {
    #expect(validator.validate("test@example.com", format: "idn-email"))
    #expect(validator.validate("用户@例子.中国", format: "idn-email"))
    #expect(validator.validate("test@münchen.de", format: "idn-email"))
    #expect(!validator.validate("@example.com", format: "idn-email"))
    #expect(!validator.validate("test@", format: "idn-email"))
  }
  
  // MARK: - URI/IRI Format Tests
  
  @Test("URI format validation")
  func uriFormat() {
    #expect(validator.validate("https://example.com", format: "uri"))
    #expect(validator.validate("http://example.com/path?query=1", format: "uri"))
    #expect(validator.validate("ftp://ftp.example.com", format: "uri"))
    #expect(validator.validate("mailto:test@example.com", format: "uri"))
    #expect(!validator.validate("not a uri", format: "uri"))
    #expect(!validator.validate("//example.com", format: "uri")) // Missing scheme
  }
  
  @Test("URI reference format validation")
  func uriReferenceFormat() {
    #expect(validator.validate("https://example.com", format: "uri-reference"))
    #expect(validator.validate("/path/to/resource", format: "uri-reference"))
    #expect(validator.validate("../relative/path", format: "uri-reference"))
    #expect(validator.validate("#fragment", format: "uri-reference"))
    #expect(validator.validate("?query=value", format: "uri-reference"))
  }
  
  @Test("IRI format validation")
  func iriFormat() {
    // Valid IRIs
    #expect(validator.validate("https://example.com", format: "iri"))
    #expect(validator.validate("https://例え.jp", format: "iri"))
    #expect(validator.validate("https://münchen.de/straße", format: "iri"))
    #expect(validator.validate("http://用户@例子.中国:8080/路径?查询=1#片段", format: "iri"))
    #expect(validator.validate("ftp://файл.рф/документы", format: "iri"))
    
    // Invalid IRIs
    #expect(!validator.validate("", format: "iri"))  // Empty
    #expect(!validator.validate("has spaces", format: "iri"))  // Contains spaces
    #expect(!validator.validate("https://example.com\npath", format: "iri"))  // Contains newline
    #expect(!validator.validate("example.com", format: "iri"))  // Missing scheme
    #expect(!validator.validate("https://<example>.com", format: "iri"))  // Invalid character <
    #expect(!validator.validate("https://example.com\"path", format: "iri"))  // Invalid character "
    #expect(!validator.validate("https://example.com{path}", format: "iri"))  // Invalid characters {}
    #expect(!validator.validate("https://example.com|path", format: "iri"))  // Invalid character |
    #expect(!validator.validate("https://example.com\\path", format: "iri"))  // Invalid character \
    #expect(!validator.validate("https://example.com^path", format: "iri"))  // Invalid character ^
    #expect(!validator.validate("https://example.com`path", format: "iri"))  // Invalid character `
  }
  
  @Test("IRI reference format validation")
  func iriReferenceFormat() {
    // Valid IRI references (absolute and relative)
    #expect(validator.validate("https://example.com", format: "iri-reference"))
    #expect(validator.validate("/путь/к/ресурсу", format: "iri-reference"))
    #expect(validator.validate("../相対/パス", format: "iri-reference"))
    #expect(validator.validate("#фрагмент", format: "iri-reference"))
    #expect(validator.validate("?запрос=значение", format: "iri-reference"))
    
    // Invalid IRI references
    #expect(!validator.validate("", format: "iri-reference"))  // Empty
    #expect(!validator.validate("path with spaces", format: "iri-reference"))  // Contains spaces
    #expect(!validator.validate("path\nwith\nnewlines", format: "iri-reference"))  // Contains newlines
    #expect(!validator.validate("path<with>brackets", format: "iri-reference"))  // Invalid characters
  }
  
  @Test("URI template format validation")
  func uriTemplateFormat() {
    #expect(validator.validate("https://example.com/users/{id}", format: "uri-template"))
    #expect(validator.validate("/path/{foo}/to/{bar}", format: "uri-template"))
    #expect(validator.validate("https://api.com/{?query,limit}", format: "uri-template"))
    #expect(!validator.validate("https://example.com/users/{", format: "uri-template"))
    #expect(!validator.validate("https://example.com/users/}", format: "uri-template"))
  }
  
  // MARK: - Date/Time Format Tests
  
  @Test("Date format validation")
  func dateFormat() {
    #expect(validator.validate("2025-01-15", format: "date"))
    #expect(validator.validate("1999-12-31", format: "date"))
    #expect(validator.validate("2024-02-29", format: "date")) // Leap year
    #expect(!validator.validate("2025-13-01", format: "date")) // Invalid month
    #expect(!validator.validate("2025-01-32", format: "date")) // Invalid day
    #expect(!validator.validate("2023-02-29", format: "date")) // Not a leap year
    #expect(!validator.validate("2025-1-15", format: "date")) // Missing leading zero
    #expect(!validator.validate("2025/01/15", format: "date")) // Wrong separator
  }
  
  @Test("Time format validation")
  func timeFormat() {
    #expect(validator.validate("14:30:00", format: "time"))
    #expect(validator.validate("23:59:59", format: "time"))
    #expect(validator.validate("00:00:00", format: "time"))
    #expect(validator.validate("14:30:00.123", format: "time")) // With fractional seconds
    #expect(validator.validate("14:30:00Z", format: "time")) // With timezone
    #expect(validator.validate("14:30:00+05:30", format: "time")) // With offset
    #expect(!validator.validate("24:00:00", format: "time")) // Invalid hour
    #expect(!validator.validate("14:60:00", format: "time")) // Invalid minute
    #expect(!validator.validate("14:30:60", format: "time")) // Invalid second
  }
  
  @Test("Date-time format validation")
  func dateTimeFormat() {
    #expect(validator.validate("2025-01-15T14:30:00Z", format: "date-time"))
    #expect(validator.validate("2025-01-15T14:30:00.123Z", format: "date-time"))
    #expect(validator.validate("2025-01-15T14:30:00+05:30", format: "date-time"))
    #expect(validator.validate("2025-01-15T14:30:00-08:00", format: "date-time"))
    #expect(!validator.validate("2025-01-15 14:30:00", format: "date-time")) // Missing T
    #expect(!validator.validate("2025-01-15T14:30:00", format: "date-time")) // Missing timezone
  }
  
  @Test("Duration format validation")
  func durationFormat() {
    #expect(validator.validate("P1Y2M3DT4H5M6S", format: "duration"))
    #expect(validator.validate("PT1H", format: "duration"))
    #expect(validator.validate("P1M", format: "duration"))
    #expect(validator.validate("PT0.5S", format: "duration"))
    #expect(!validator.validate("P", format: "duration")) // Empty duration
    #expect(!validator.validate("PT", format: "duration")) // Empty time duration
    #expect(!validator.validate("1H", format: "duration")) // Missing P prefix
  }
  
  // MARK: - Network Format Tests
  
  @Test("Hostname format validation")
  func hostnameFormat() {
    #expect(validator.validate("example.com", format: "hostname"))
    #expect(validator.validate("sub.example.com", format: "hostname"))
    #expect(validator.validate("localhost", format: "hostname"))
    #expect(validator.validate("xn--e1afmkfd.xn--p1ai", format: "hostname")) // Punycode
    #expect(!validator.validate("-example.com", format: "hostname")) // Starts with hyphen
    #expect(!validator.validate("example.com-", format: "hostname")) // Ends with hyphen
    #expect(!validator.validate("ex ample.com", format: "hostname")) // Contains space
    #expect(!validator.validate("", format: "hostname"))
  }
  
  @Test("IDN hostname format validation")
  func idnHostnameFormat() {
    #expect(validator.validate("example.com", format: "idn-hostname"))
    #expect(validator.validate("münchen.de", format: "idn-hostname"))
    #expect(validator.validate("例え.jp", format: "idn-hostname"))
    #expect(!validator.validate("", format: "idn-hostname"))
    #expect(!validator.validate("-example.com", format: "idn-hostname"))
  }
  
  @Test("IPv4 format validation")
  func ipv4Format() {
    #expect(validator.validate("192.168.1.1", format: "ipv4"))
    #expect(validator.validate("0.0.0.0", format: "ipv4"))
    #expect(validator.validate("255.255.255.255", format: "ipv4"))
    #expect(!validator.validate("256.1.1.1", format: "ipv4")) // Out of range
    #expect(!validator.validate("192.168.1", format: "ipv4")) // Missing octet
    #expect(!validator.validate("192.168.1.1.1", format: "ipv4")) // Too many octets
    #expect(!validator.validate("192.168.01.1", format: "ipv4")) // Leading zero
  }
  
  @Test("IPv6 format validation")
  func ipv6Format() {
    #expect(validator.validate("2001:db8::8a2e:370:7334", format: "ipv6"))
    #expect(validator.validate("::1", format: "ipv6")) // Loopback
    #expect(validator.validate("::", format: "ipv6")) // All zeros
    #expect(validator.validate("2001:db8:85a3::8a2e:370:7334", format: "ipv6"))
    #expect(validator.validate("fe80::1%lo0", format: "ipv6")) // With zone
    #expect(!validator.validate("02001:db8::1", format: "ipv6")) // Too many digits
    #expect(!validator.validate("2001:db8::8a2e::7334", format: "ipv6")) // Double ::
    #expect(!validator.validate("gggg::1", format: "ipv6")) // Invalid hex
  }
  
  // MARK: - Other Format Tests
  
  @Test("UUID format validation")
  func uuidFormat() {
    #expect(validator.validate("550e8400-e29b-41d4-a716-446655440000", format: "uuid"))
    #expect(validator.validate("550E8400-E29B-41D4-A716-446655440000", format: "uuid")) // Uppercase
    #expect(!validator.validate("550e8400-e29b-41d4-a716-44665544000", format: "uuid")) // Too short
    #expect(!validator.validate("550e8400-e29b-41d4-a716-4466554400000", format: "uuid")) // Too long
    #expect(!validator.validate("550e8400-e29b-61d4-a716-446655440000", format: "uuid")) // Invalid version
    #expect(!validator.validate("550e8400e29b41d4a716446655440000", format: "uuid")) // No hyphens
  }
  
  @Test("Regex format validation")
  func regexFormat() {
    #expect(validator.validate("^[a-z]+$", format: "regex"))
    #expect(validator.validate("\\d{3}-\\d{3}-\\d{4}", format: "regex"))
    #expect(validator.validate(".*", format: "regex"))
    #expect(!validator.validate("[", format: "regex")) // Unclosed bracket
    #expect(!validator.validate("(?<", format: "regex")) // Invalid group
  }
  
  @Test("JSON pointer format validation")
  func jsonPointerFormat() {
    #expect(validator.validate("", format: "json-pointer")) // Root
    #expect(validator.validate("/foo", format: "json-pointer"))
    #expect(validator.validate("/foo/0", format: "json-pointer"))
    #expect(validator.validate("/foo/bar", format: "json-pointer"))
    #expect(validator.validate("/foo~0bar", format: "json-pointer")) // Escaped ~
    #expect(validator.validate("/foo~1bar", format: "json-pointer")) // Escaped /
    #expect(!validator.validate("foo", format: "json-pointer")) // Missing leading /
    #expect(!validator.validate("/foo~2", format: "json-pointer")) // Invalid escape
  }
  
  @Test("Relative JSON pointer format validation")
  func relativeJsonPointerFormat() {
    #expect(validator.validate("0", format: "relative-json-pointer"))
    #expect(validator.validate("1", format: "relative-json-pointer"))
    #expect(validator.validate("0#", format: "relative-json-pointer"))
    #expect(validator.validate("1/foo", format: "relative-json-pointer"))
    #expect(validator.validate("2/foo/bar", format: "relative-json-pointer"))
    #expect(!validator.validate("-1", format: "relative-json-pointer")) // Negative
    #expect(!validator.validate("01", format: "relative-json-pointer")) // Leading zero
    #expect(!validator.validate("/foo", format: "relative-json-pointer")) // Missing number
  }
  
  // MARK: - Content Validation Tests
  
  @Test("JSON content validation")
  func jsonContentValidation() {
    #expect(contentValidator.validateMediaType("{\"foo\": \"bar\"}", mediaType: "application/json"))
    #expect(contentValidator.validateMediaType("[1, 2, 3]", mediaType: "application/json"))
    #expect(contentValidator.validateMediaType("\"string\"", mediaType: "application/json"))
    #expect(contentValidator.validateMediaType("123", mediaType: "application/json"))
    #expect(contentValidator.validateMediaType("true", mediaType: "application/json"))
    #expect(contentValidator.validateMediaType("null", mediaType: "application/json"))
    #expect(!contentValidator.validateMediaType("{invalid json}", mediaType: "application/json"))
    #expect(!contentValidator.validateMediaType("", mediaType: "application/json"))
  }
  
  @Test("Base64 encoded content validation")
  func base64EncodedContent() {
    // Valid base64 encoded JSON
    let validBase64 = "eyJmb28iOiAiYmFyIn0=" // {"foo": "bar"}
    #expect(contentValidator.validateEncodedContent(validBase64, mediaType: "application/json", encoding: "base64"))
    
    // Invalid base64
    #expect(!contentValidator.validateEncodedContent("not-base64!", mediaType: "application/json", encoding: "base64"))
    
    // Valid base64 but invalid JSON
    let invalidJsonBase64 = "aW52YWxpZCBqc29u" // "invalid json"
    #expect(!contentValidator.validateEncodedContent(invalidJsonBase64, mediaType: "application/json", encoding: "base64"))
  }
  
  @Test("Base64URL encoded content validation")
  func base64URLEncodedContent() {
    // Valid base64url encoded JSON (no padding, - instead of +, _ instead of /)
    let validBase64URL = "eyJmb28iOiAiYmFyIn0" // {"foo": "bar"} without padding
    #expect(contentValidator.validateEncodedContent(validBase64URL, mediaType: "application/json", encoding: "base64url"))
    
    // With URL-safe characters
    let withUrlChars = "eyJ0ZXN0IjogIitfLz0ifQ" // {"test": "+_/="}
    #expect(contentValidator.validateEncodedContent(withUrlChars, mediaType: "application/json", encoding: "base64url"))
  }
}