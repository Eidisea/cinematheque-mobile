import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Downloads [csv] as [filename]. A UTF-8 byte order mark goes first so Excel shows ₱ and
/// accented names correctly, as on the website.
void downloadCsv(String filename, String csv) {
  final bytes = utf8.encode('﻿$csv');
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'text/csv;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body!.append(link);
  link.click();
  link.remove();
  web.URL.revokeObjectURL(url);
}
