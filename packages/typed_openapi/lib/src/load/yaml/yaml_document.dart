// Copyright (c) 2014, the Dart project authors.
// Copyright (c) 2006, Kirill Simonov.
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

/// A directive indicating which version of YAML a document was written to.
class VersionDirective {
  /// The major version number.
  final int major;

  /// The minor version number.
  final int minor;

  VersionDirective(this.major, this.minor);

  @override
  String toString() => '%YAML $major.$minor';
}

/// A directive describing a custom tag handle.
class TagDirective {
  /// The handle for use in the document.
  final String handle;

  /// The prefix that the handle maps to.
  final String prefix;

  TagDirective(this.handle, this.prefix);

  @override
  String toString() => '%TAG $handle $prefix';
}
