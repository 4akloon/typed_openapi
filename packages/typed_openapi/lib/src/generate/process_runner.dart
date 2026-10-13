import 'dart:io';

/// Starts a process and waits for it: `chmod` and `kill`, which a test
/// replaces to make them fail.
typedef ProcessRunner =
    ProcessResult Function(String executable, List<String> arguments);
