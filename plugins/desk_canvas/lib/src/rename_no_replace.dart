// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef _RenameNative = Int32 Function(
  Int32,
  Pointer<Uint8>,
  Int32,
  Pointer<Uint8>,
  Uint32,
);
typedef _RenameDart = int Function(
  int,
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  int,
);

/// Linux atomic rename with RENAME_NOREPLACE: no existence-check race and no shell.
void renameNoReplace(String source, String target) {
  final libc = DynamicLibrary.open('libc.so.6');
  final rename = libc.lookupFunction<_RenameNative, _RenameDart>('renameat2');
  final errno = libc
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        '__errno_location',
      );
  final malloc = libc
      .lookupFunction<
        Pointer<Uint8> Function(IntPtr),
        Pointer<Uint8> Function(int)
      >('malloc');
  final free = libc
      .lookupFunction<
        Void Function(Pointer<Uint8>),
        void Function(Pointer<Uint8>)
      >('free');
  Pointer<Uint8> string(String value) {
    if (value.contains('\u0000')) {
      throw const FormatException('Invalid filename');
    }
    final bytes = utf8.encode(value);
    final pointer = malloc(bytes.length + 1);
    if (pointer == nullptr) throw StateError('Cannot allocate filename');
    pointer.asTypedList(bytes.length + 1)
      ..setRange(0, bytes.length, bytes)
      ..[bytes.length] = 0;
    return pointer;
  }

  final from = string(source);
  Pointer<Uint8> to = nullptr;
  try {
    to = string(target);
    if (rename(-100, from, -100, to, 1) != 0) {
      final code = errno().value;
      throw FileSystemException(
        code == 17 ? '该名称已经存在' : '无法重命名（系统错误 $code）',
        source,
        OSError('renameat2 failed', code),
      );
    }
  } finally {
    free(from);
    if (to != nullptr) free(to);
  }
}
