# Testing Guide

This document provides comprehensive information about testing ClipboardManager.

## Table of Contents

- [Overview](#overview)
- [Running Tests](#running-tests)
- [Test Structure](#test-structure)
- [Writing Tests](#writing-tests)
- [Continuous Integration](#continuous-integration)
- [Code Coverage](#code-coverage)
- [Best Practices](#best-practices)

## Overview

ClipboardManager has a comprehensive test suite that covers:

- **Database Operations** - CRUD, encryption, FTS search
- **State Management** - AppState coordination and reactive updates
- **Data Models** - ClipboardEntry utilities and validation
- **Concurrency** - Actor isolation and thread safety
- **Performance** - Benchmarks for critical operations

**Test Statistics:**
- 75+ unit tests
- ~90% code coverage (excluding UI)
- Average test execution: <5 seconds

## Running Tests

### Basic Commands

```bash
# Run all tests
swift test

# Run with verbose output
swift test -v

# Run specific test suite
swift test --filter ClipboardDatabaseTests

# Run specific test method
swift test --filter ClipboardDatabaseTests.testSaveAndRetrieveTextClip

# List all tests without running
swift test --list-tests
```

### With Code Coverage

```bash
# Enable code coverage
swift test --enable-code-coverage

# Generate detailed coverage report
xcrun llvm-cov show \
  .build/debug/ClipboardManagerPackageTests.xctest/Contents/MacOS/ClipboardManagerPackageTests \
  -instr-profile .build/debug/codecov/default.profdata \
  -format=html -output-dir=coverage/

# Open coverage report in browser
open coverage/index.html
```

### Using Xcode

```bash
# Open in Xcode
xed .

# In Xcode:
# 1. Select the test file in the navigator
# 2. Click the diamond icon next to a test to run it
# 3. Use Cmd+U to run all tests
# 4. View coverage: Editor → Show Code Coverage
```

## Test Structure

```
Tests/ClipboardManagerTests/
├── ClipboardDatabaseTests.swift   # 40+ tests for database operations
├── AppStateTests.swift            # 20+ tests for state management
└── ClipboardEntryTests.swift      # 15+ tests for data models
```

### ClipboardDatabaseTests

Tests for database operations and encryption:

- **Basic Operations** - Save, retrieve, update, delete
- **Encryption** - AES-256-GCM encryption/decryption
- **Pin/Unpin** - Pin management and ordering
- **Search** - Full-text search with FTS5
- **Cleanup** - Retention policies and bulk deletion
- **Performance** - Benchmarks for critical operations
- **Concurrency** - Thread-safe actor operations
- **Edge Cases** - Empty strings, large content, unicode

### AppStateTests

Tests for state management:

- **Initialization** - AppState setup and configuration
- **Load Operations** - Fetching clips with limits
- **Pin Management** - Toggle pin and ordering updates
- **Delete Operations** - Single and bulk deletions
- **Clipboard Copy** - Copying clips to system clipboard
- **Reactive Updates** - Published property changes

### ClipboardEntryTests

Tests for data models:

- **Preview Text** - Truncation, newline handling
- **Hashable** - Equality and set operations
- **Unicode** - Special characters and emojis
- **Edge Cases** - Empty content, whitespace

## Writing Tests

### Test Naming Convention

Use descriptive names that follow this pattern:
```
test<Feature>_<Condition>_<ExpectedResult>
```

Examples:
```swift
func testSaveClip_WithValidContent_StoresEncrypted()
func testTogglePin_WhenUnpinned_SetsToTrue()
func testSearch_WithSpecialChars_ReturnsResults()
```

### Test Structure

Follow the AAA pattern:
- **Arrange** - Set up test data
- **Act** - Execute the code under test
- **Assert** - Verify the results

```swift
func testSaveAndRetrieveTextClip() async throws {
    // Arrange
    let testContent = "Test clip content"

    // Act
    await database.saveClip(testContent)
    let clips = await database.getRecentClips(limit: 10)

    // Assert
    XCTAssertEqual(clips.first?.content, testContent)
}
```

### Testing Actors

ClipboardDatabase is an actor, so use `async/await`:

```swift
func testConcurrentOperations() async throws {
    // Use Task groups for concurrent operations
    await withTaskGroup(of: Void.self) { group in
        for i in 1...10 {
            group.addTask {
                await self.database.saveClip("Clip \(i)")
            }
        }
    }

    let count = await database.getTotalClipsCount()
    XCTAssertGreaterThanOrEqual(count, 10)
}
```

### Testing UI (MainActor)

AppState is `@MainActor`, so tests must run on main actor:

```swift
@MainActor
func testLoadClips() async throws {
    await database.saveClip("Test")

    appState.loadClips()
    try await Task.sleep(nanoseconds: 200_000_000)

    XCTAssertGreaterThan(appState.clips.count, 0)
}
```

### Setup and Teardown

Clean up test data to avoid pollution:

```swift
override func setUp() async throws {
    try await super.setUp()
    database = ClipboardDatabase()
    try await Task.sleep(nanoseconds: 100_000_000)
    XCTAssertTrue(database.isInitialized)
}

override func tearDown() async throws {
    // Clean up test data
    _ = await database.clearAllHistory(keepPinned: false)
    try await super.tearDown()
}
```

### Performance Tests

Use `measure` for performance benchmarks:

```swift
func testPerformanceSaveClip() {
    measure {
        let expectation = self.expectation(description: "Save")
        Task {
            await database.saveClip("Performance test")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }
}
```

## Continuous Integration

GitHub Actions automatically runs tests on every push and PR.

### CI Pipeline

1. **Test** - Run all unit tests
2. **Lint** - SwiftLint code quality checks
3. **Build** - Release build verification
4. **Coverage** - Upload to Codecov

### Workflow Configuration

See `.github/workflows/tests.yml` for full configuration.

**Key features:**
- Runs on macOS 13 (minimum supported version)
- Uses Xcode 15.0
- Generates code coverage reports
- Uploads artifacts for debugging

### Viewing CI Results

1. Go to the GitHub repository
2. Click "Actions" tab
3. Select a workflow run
4. View test results and logs

### Code Coverage Badge

Add to README.md:
```markdown
[![codecov](https://codecov.io/gh/username/ClipboardManager/branch/main/graph/badge.svg)](https://codecov.io/gh/username/ClipboardManager)
```

## Code Coverage

### Coverage Goals

- **Target**: 80%+ overall coverage
- **Critical paths**: 95%+ (encryption, database)
- **UI code**: 60%+ (harder to test, acceptable)

### Viewing Coverage Locally

```bash
# Generate coverage
swift test --enable-code-coverage

# View in Xcode (after opening project)
# 1. Run tests with coverage (Cmd+U)
# 2. View coverage: Editor → Show Code Coverage
# 3. See line-by-line coverage in editor gutter

# Generate HTML report
xcrun llvm-cov show \
  .build/debug/ClipboardManagerPackageTests.xctest/Contents/MacOS/ClipboardManagerPackageTests \
  -instr-profile .build/debug/codecov/default.profdata \
  -format=html -output-dir=coverage/

open coverage/index.html
```

### Coverage Tips

**To improve coverage:**
1. Test error paths, not just happy paths
2. Test edge cases (empty, nil, large values)
3. Test concurrency scenarios
4. Add integration tests for complex workflows

**What to skip:**
- UI rendering code (SwiftUI views)
- Simple getters/setters
- External library code

## Best Practices

### Do's ✅

- **Write tests first** (TDD approach)
- **Test one thing per test** (single responsibility)
- **Use descriptive names** (self-documenting)
- **Clean up test data** (avoid pollution)
- **Test edge cases** (empty, nil, large, unicode)
- **Test error paths** (not just happy paths)
- **Use async/await** (for actor testing)
- **Mock external dependencies** (when needed)

### Don'ts ❌

- **Don't test implementation details** (test behavior)
- **Don't use sleep for synchronization** (use proper async)
- **Don't share state between tests** (isolate tests)
- **Don't test private methods** (test public API)
- **Don't ignore flaky tests** (fix or remove)
- **Don't commit failing tests** (CI should always pass)

### Example: Good vs Bad Test

**Bad:**
```swift
func test1() {
    database.saveClip("test")
    XCTAssertTrue(database.clips.count > 0)  // Testing internal state
}
```

**Good:**
```swift
func testSaveClip_WithValidContent_AppearsInRecentClips() async throws {
    let content = "Test clipboard content"

    await database.saveClip(content)

    let clips = await database.getRecentClips(limit: 10)
    XCTAssertEqual(clips.first?.content, content)
}
```

## Troubleshooting

### Tests Failing Locally

**Keychain Access Issues:**
```
Error: Failed to save encryption key to keychain
```
Solution: Grant Xcode keychain access in System Settings

**Database Permission Issues:**
```
Error: Unable to open database
```
Solution: Check file permissions, delete test database

**Timing Issues:**
```
Error: Clip not found after save
```
Solution: Increase sleep duration or use proper async waiting

### CI Failures

**SwiftLint Failures:**
- Run `swiftlint` locally before pushing
- Fix all warnings and errors

**Test Timeouts:**
- Tests should complete in <5 seconds
- Check for infinite loops or blocking operations

**Flaky Tests:**
- Avoid hard-coded sleep durations
- Use expectations for async operations
- Ensure proper test isolation

## Contributing

When adding new features:

1. **Write tests first** - Define expected behavior
2. **Implement feature** - Make tests pass
3. **Refactor** - Improve code while keeping tests green
4. **Document** - Update this guide if adding new patterns

### Test PR Checklist

- [ ] All tests pass locally (`swift test`)
- [ ] SwiftLint passes (`swiftlint`)
- [ ] Code coverage maintained or improved
- [ ] New features have test coverage
- [ ] Tests follow naming conventions
- [ ] Documentation updated if needed

## Resources

- [XCTest Documentation](https://developer.apple.com/documentation/xctest)
- [Swift Testing (new in Swift 6)](https://github.com/apple/swift-testing)
- [SwiftLint Rules](https://realm.github.io/SwiftLint/rule-directory.html)
- [Codecov Documentation](https://docs.codecov.com/)

---

**Questions?** Open an issue on GitHub or contact the maintainer.
