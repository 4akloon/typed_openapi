// Copyright (c) 2013, the Dart project authors.
// Copyright (c) 2006, Kirill Simonov.
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:source_span/source_span.dart';

/// Receives a warning the YAML spec asks an implementation to give, such as
/// for an unknown directive.
///
/// typed_openapi: package:yaml prints these through a global callback; the
/// copy hands them to the [Parser]'s owner instead.
typedef YamlWarningHandler = void Function(String message, FileSpan span);

/// Whether [codeUnit] is a UTF-16 high surrogate.
bool isHighSurrogate(int codeUnit) => codeUnit >>> 10 == 0x36;

/// Whether [codeUnit] is a UTF-16 low surrogate.
bool isLowSurrogate(int codeUnit) => codeUnit >>> 10 == 0x37;
