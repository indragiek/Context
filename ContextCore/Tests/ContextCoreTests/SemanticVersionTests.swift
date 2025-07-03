// Copyright © 2025 Indragie Karunaratne. All rights reserved.

import Testing
@testable import ContextCore

@Suite struct SemanticVersionTests {
  
  // MARK: - Parsing Tests
  
  @Test func testBasicVersionParsing() {
    let v1 = SemanticVersion(string: "1.2.3")
    #expect(v1?.major == 1)
    #expect(v1?.minor == 2)
    #expect(v1?.patch == 3)
    #expect(v1?.prerelease.isEmpty == true)
    #expect(v1?.buildMetadata.isEmpty == true)
    
    let v2 = SemanticVersion(string: "0.0.0")
    #expect(v2?.major == 0)
    #expect(v2?.minor == 0)
    #expect(v2?.patch == 0)
    
    let v3 = SemanticVersion(string: "10.20.30")
    #expect(v3?.major == 10)
    #expect(v3?.minor == 20)
    #expect(v3?.patch == 30)
  }
  
  @Test func testVersionWithMissingComponents() {
    let v1 = SemanticVersion(string: "1")
    #expect(v1?.major == 1)
    #expect(v1?.minor == 0)
    #expect(v1?.patch == 0)
    
    let v2 = SemanticVersion(string: "1.2")
    #expect(v2?.major == 1)
    #expect(v2?.minor == 2)
    #expect(v2?.patch == 0)
  }
  
  @Test func testPrereleaseVersionParsing() {
    let v1 = SemanticVersion(string: "1.0.0-alpha")
    #expect(v1?.prerelease == ["alpha"])
    
    let v2 = SemanticVersion(string: "1.0.0-alpha.1")
    #expect(v2?.prerelease == ["alpha", "1"])
    
    let v3 = SemanticVersion(string: "1.0.0-0.3.7")
    #expect(v3?.prerelease == ["0", "3", "7"])
    
    let v4 = SemanticVersion(string: "1.0.0-x.7.z.92")
    #expect(v4?.prerelease == ["x", "7", "z", "92"])
    
    let v5 = SemanticVersion(string: "1.0.0-x-y-z.--")
    #expect(v5?.prerelease == ["x-y-z", "--"])
  }
  
  @Test func testBuildMetadataParsing() {
    let v1 = SemanticVersion(string: "1.0.0+20130313144700")
    #expect(v1?.buildMetadata == ["20130313144700"])
    
    let v2 = SemanticVersion(string: "1.0.0+exp.sha.5114f85")
    #expect(v2?.buildMetadata == ["exp", "sha", "5114f85"])
    
    let v3 = SemanticVersion(string: "1.0.0-beta+exp.sha.5114f85")
    #expect(v3?.prerelease == ["beta"])
    #expect(v3?.buildMetadata == ["exp", "sha", "5114f85"])
  }
  
  @Test func testInvalidVersions() {
    // Leading zeros not allowed
    #expect(SemanticVersion(string: "01.2.3") == nil)
    #expect(SemanticVersion(string: "1.02.3") == nil)
    #expect(SemanticVersion(string: "1.2.03") == nil)
    
    // But zero itself is fine
    #expect(SemanticVersion(string: "0.0.0") != nil)
    
    // Empty identifiers not allowed
    #expect(SemanticVersion(string: "1.0.0-") == nil)
    #expect(SemanticVersion(string: "1.0.0+") == nil)
    #expect(SemanticVersion(string: "1.0.0-.") == nil)
    
    // Invalid characters
    #expect(SemanticVersion(string: "1.0.0-alpha@beta") == nil)
    #expect(SemanticVersion(string: "1.0.0+build!123") == nil)
    
    // Too many version components
    #expect(SemanticVersion(string: "1.2.3.4") == nil)
    
    // Non-numeric version components
    #expect(SemanticVersion(string: "a.b.c") == nil)
    #expect(SemanticVersion(string: "1.a.0") == nil)
  }
  
  @Test func testLeadingZerosInPrerelease() {
    // Numeric identifiers in pre-release must not have leading zeros
    #expect(SemanticVersion(string: "1.0.0-01") == nil)
    #expect(SemanticVersion(string: "1.0.0-alpha.01") == nil)
    
    // But alphanumeric identifiers can have leading zeros
    #expect(SemanticVersion(string: "1.0.0-0alpha") != nil)
    #expect(SemanticVersion(string: "1.0.0-alpha.0beta") != nil)
  }
  
  // MARK: - Comparison Tests
  
  @Test func testBasicComparison() {
    let v1 = SemanticVersion(string: "1.0.0")!
    let v2 = SemanticVersion(string: "2.0.0")!
    let v3 = SemanticVersion(string: "2.1.0")!
    let v4 = SemanticVersion(string: "2.1.1")!
    
    #expect(v1 < v2)
    #expect(v2 < v3)
    #expect(v3 < v4)
    #expect(v1 < v4)
    
    // Test equality
    let v5 = SemanticVersion(string: "1.0.0")!
    #expect(v1 == v5)
    #expect(!(v1 < v5))
    #expect(!(v1 > v5))
  }
  
  @Test func testPrereleaseComparison() {
    // Pre-release versions have lower precedence than normal versions
    let v1 = SemanticVersion(string: "1.0.0")!
    let v2 = SemanticVersion(string: "1.0.0-alpha")!
    #expect(v2 < v1)
    
    // Compare pre-release versions
    let alpha = SemanticVersion(string: "1.0.0-alpha")!
    let alpha1 = SemanticVersion(string: "1.0.0-alpha.1")!
    let alphaBeta = SemanticVersion(string: "1.0.0-alpha.beta")!
    let beta = SemanticVersion(string: "1.0.0-beta")!
    let beta2 = SemanticVersion(string: "1.0.0-beta.2")!
    let beta11 = SemanticVersion(string: "1.0.0-beta.11")!
    let rc1 = SemanticVersion(string: "1.0.0-rc.1")!
    
    #expect(alpha < alpha1)
    #expect(alpha1 < alphaBeta)
    #expect(alphaBeta < beta)
    #expect(beta < beta2)
    #expect(beta2 < beta11)
    #expect(beta11 < rc1)
    #expect(rc1 < v1)
  }
  
  @Test func testNumericVsAlphanumericPrerelease() {
    // Numeric identifiers always have lower precedence than non-numeric
    let v1 = SemanticVersion(string: "1.0.0-1")!
    let v2 = SemanticVersion(string: "1.0.0-alpha")!
    #expect(v1 < v2)
    
    let v3 = SemanticVersion(string: "1.0.0-alpha.1")!
    let v4 = SemanticVersion(string: "1.0.0-alpha.beta")!
    #expect(v3 < v4) // 1 < "beta" because numeric < alphanumeric
  }
  
  @Test func testBuildMetadataIgnoredInComparison() {
    let v1 = SemanticVersion(string: "1.0.0+build1")!
    let v2 = SemanticVersion(string: "1.0.0+build2")!
    #expect(v1 == v2)
    
    let v3 = SemanticVersion(string: "1.0.0-alpha+build1")!
    let v4 = SemanticVersion(string: "1.0.0-alpha+build2")!
    #expect(v3 == v4)
  }
  
  // MARK: - Version String Tests
  
  @Test func testVersionStringGeneration() {
    let v1 = SemanticVersion(major: 1, minor: 2, patch: 3)
    #expect(v1.versionString == "1.2.3")
    
    let v2 = SemanticVersion(major: 1, minor: 0, patch: 0, prerelease: ["alpha", "1"])
    #expect(v2.versionString == "1.0.0-alpha.1")
    
    let v3 = SemanticVersion(major: 1, minor: 0, patch: 0, buildMetadata: ["20130313144700"])
    #expect(v3.versionString == "1.0.0+20130313144700")
    
    let v4 = SemanticVersion(
      major: 1, minor: 0, patch: 0,
      prerelease: ["beta"],
      buildMetadata: ["exp", "sha", "5114f85"]
    )
    #expect(v4.versionString == "1.0.0-beta+exp.sha.5114f85")
  }
  
  // MARK: - Requirement Satisfaction Tests
  
  @Test func testBasicRequirements() {
    let v = SemanticVersion(string: "1.2.3")!
    
    #expect(v.satisfies(">=1.0.0"))
    #expect(v.satisfies(">=1.2.3"))
    #expect(!v.satisfies(">=2.0.0"))
    
    #expect(v.satisfies(">1.0.0"))
    #expect(!v.satisfies(">1.2.3"))
    
    #expect(v.satisfies("<=2.0.0"))
    #expect(v.satisfies("<=1.2.3"))
    #expect(!v.satisfies("<=1.0.0"))
    
    #expect(v.satisfies("<2.0.0"))
    #expect(!v.satisfies("<1.2.3"))
    
    #expect(v.satisfies("==1.2.3"))
    #expect(!v.satisfies("==1.2.4"))
  }
  
  @Test func testCompoundRequirements() {
    let v = SemanticVersion(string: "1.5.0")!
    
    // AND conditions (space-separated)
    #expect(v.satisfies(">=1.0.0 <2.0.0"))
    #expect(!v.satisfies(">=1.0.0 <1.4.0"))
    
    // OR conditions
    #expect(v.satisfies(">=2.0.0 || ==1.5.0"))
    #expect(v.satisfies("<1.0.0 || >1.4.0"))
    #expect(!v.satisfies("<1.0.0 || >2.0.0"))
  }
  
  @Test func testPessimisticOperator() {
    let v1 = SemanticVersion(string: "1.4.5")!
    
    // ~> 1.4.2 means >= 1.4.2 and < 1.5.0
    #expect(v1.satisfies("~> 1.4.2"))
    #expect(!v1.satisfies("~> 1.5.0"))
    
    // ~> 1.4 means >= 1.4.0 and < 2.0.0
    #expect(v1.satisfies("~> 1.4"))
    #expect(!v1.satisfies("~> 2.0"))
    
    let v2 = SemanticVersion(string: "2.1.0")!
    #expect(v2.satisfies("~> 2.0"))
    #expect(!v2.satisfies("~> 1.9"))
  }
  
  @Test func testRealWorldVersionRequirements() {
    // Test node version requirement from the original issue
    let nodeVersion = SemanticVersion(string: "20.9.0")!
    #expect(nodeVersion.satisfies(">=16.0.0"))
    
    // Test Python version requirements
    let pythonVersion = SemanticVersion(string: "3.9.5")!
    #expect(pythonVersion.satisfies(">=3.8.0"))
    #expect(pythonVersion.satisfies(">=3.8.0 <4"))
    #expect(!pythonVersion.satisfies(">=3.10.0"))
  }
  
  @Test func testPrereleaseRequirements() {
    let v1 = SemanticVersion(string: "1.0.0-alpha.1")!
    let v2 = SemanticVersion(string: "1.0.0")!
    
    #expect(v1.satisfies(">=1.0.0-alpha"))
    #expect(!v1.satisfies(">=1.0.0"))
    #expect(v2.satisfies(">=1.0.0-alpha"))
    #expect(v2.satisfies(">=1.0.0"))
  }
}