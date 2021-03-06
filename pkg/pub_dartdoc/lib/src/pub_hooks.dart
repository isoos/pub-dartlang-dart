// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io' as io;

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/memory_file_system.dart';
// ignore: implementation_imports
import 'package:analyzer/src/generated/sdk.dart';
// ignore: implementation_imports
import 'package:analyzer/src/generated/source.dart';
import 'package:dartdoc/dartdoc.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

const _maxFileCount = 10000;
const _maxTotalLengthBytes = 10 * 1024 * 1024;

/// Creates an overlay file system with binary file support on top
/// of the input sources.
///
/// TODO: Use a propr overlay in-memory filesystem with binary support,
///       instead of overriding file writes in the output path.
class PubResourceProvider implements ResourceProvider {
  final ResourceProvider _defaultProvider;
  final _memoryResourceProvider = MemoryResourceProvider();
  bool _isSdkDocs = false;
  String _outputPath;
  int _fileCount = 0;
  int _totalLengthBytes = 0;

  PubResourceProvider(this._defaultProvider);

  /// Writes in-memory files to disk.
  void writeFilesToDiskSync() {
    void storeFolder(Folder rs) {
      for (final c in rs.getChildren()) {
        if (c is Folder) {
          storeFolder(c);
        } else if (c is File) {
          final file = io.File(c.path);
          file.parent.createSync(recursive: true);
          file.writeAsBytes(c.readAsBytesSync());
        }
      }
    }

    storeFolder(_memoryResourceProvider.getFolder(_outputPath));
  }

  /// Checks if we have reached any file write limit before storing the bytes.
  void _aboutToWriteBytes(int length) {
    _fileCount++;
    _totalLengthBytes += length;
    if (_isSdkDocs) {
      // do not throw on too output large file
      return;
    }
    if (_fileCount > _maxFileCount) {
      throw AssertionError(
          'Reached $_maxFileCount files in the output directory.');
    }
    if (_totalLengthBytes > _maxTotalLengthBytes) {
      throw AssertionError(
          'Reached $_maxTotalLengthBytes bytes in the output directory.');
    }
  }

  void setConfig({
    @required String output,
    @required bool isSdkDocs,
  }) {
    _outputPath = output;
    _isSdkDocs = isSdkDocs;
  }

  bool _isOutput(String path) {
    return _outputPath != null &&
        (path == _outputPath || p.isWithin(_outputPath, path));
  }

  ResourceProvider _rp(String path) =>
      _isOutput(path) ? _memoryResourceProvider : _defaultProvider;

  @override
  File getFile(String path) => _File(this, _rp(path).getFile(path));

  @override
  Folder getFolder(String path) => _rp(path).getFolder(path);

  @override
  Future<List<int>> getModificationTimes(List<Source> sources) async {
    return _defaultProvider.getModificationTimes(sources);
  }

  @override
  Resource getResource(String path) => _rp(path).getResource(path);

  @override
  Folder getStateLocation(String pluginId) {
    return _defaultProvider.getStateLocation(pluginId);
  }

  @override
  p.Context get pathContext => _defaultProvider.pathContext;
}

class _File implements File {
  final PubResourceProvider _provider;
  final File _delegate;
  _File(this._provider, this._delegate);

  @override
  Stream<WatchEvent> get changes => _delegate.changes;

  @override
  File copyTo(Folder parentFolder) => _delegate.copyTo(parentFolder);

  @override
  Source createSource([Uri uri]) => _delegate.createSource(uri);

  @override
  void delete() => _delegate.delete();

  @override
  bool get exists => _delegate.exists;

  @override
  bool isOrContains(String path) => _delegate.isOrContains(path);

  @override
  int get lengthSync => _delegate.lengthSync;

  @override
  int get modificationStamp => _delegate.modificationStamp;

  @override
  Folder get parent => _delegate.parent2;

  @override
  Folder get parent2 => _delegate.parent2;

  @override
  String get path => _delegate.path;

  @override
  ResourceProvider get provider => _delegate.provider;

  @override
  List<int> readAsBytesSync() => _delegate.readAsBytesSync();

  @override
  String readAsStringSync() => _delegate.readAsStringSync();

  @override
  File renameSync(String newPath) => _delegate.renameSync(newPath);

  @override
  Resource resolveSymbolicLinksSync() => _delegate.resolveSymbolicLinksSync();

  @override
  String get shortName => _delegate.shortName;

  @override
  Uri toUri() => _delegate.toUri();

  @override
  void writeAsBytesSync(List<int> bytes) {
    if (_provider._isSdkDocs && path.endsWith('.html')) {
      // do not write file for SDK docs
    }
    _provider._aboutToWriteBytes(bytes.length);
    _delegate.writeAsBytesSync(bytes);
  }

  @override
  void writeAsStringSync(String content) {
    writeAsBytesSync(utf8.encode(content));
  }
}

/// Allows the override of [resourceProvider].
class PubPackageMetaProvider implements PackageMetaProvider {
  final PackageMetaProvider _delegate;
  final ResourceProvider _resourceProvider;

  PubPackageMetaProvider(this._delegate, this._resourceProvider);

  @override
  DartSdk get defaultSdk => _delegate.defaultSdk;

  @override
  Folder get defaultSdkDir => _delegate.defaultSdkDir;

  @override
  PackageMeta fromDir(Folder dir) => _delegate.fromDir(dir);

  @override
  PackageMeta fromElement(LibraryElement library, String s) =>
      _delegate.fromElement(library, s);

  @override
  PackageMeta fromFilename(String s) => _delegate.fromFilename(s);

  @override
  ResourceProvider get resourceProvider => _resourceProvider;
}
