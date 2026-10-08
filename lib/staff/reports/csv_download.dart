// Saves a CSV file in the browser (the staff app is Flutter Web). Elsewhere it is unsupported.
export 'csv_download_stub.dart' if (dart.library.js_interop) 'csv_download_web.dart';
