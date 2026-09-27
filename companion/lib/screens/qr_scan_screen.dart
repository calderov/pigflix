import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// A pairing QR code (rendered by the web frontend's "Pair remote control"
/// dialog, see `frontend/lib/screens/movie_grid_screen.dart`) encodes the
/// server address and pairing code as a `pigflix://pair?host=...&code=...`
/// URI. Returns null if [data] isn't one.
({String host, String code})? parsePairingQrData(String data) {
  final uri = Uri.tryParse(data);
  if (uri == null || uri.scheme != 'pigflix' || uri.host != 'pair') {
    return null;
  }
  final host = uri.queryParameters['host'];
  final code = uri.queryParameters['code'];
  if (host == null || host.isEmpty || code == null || code.isEmpty) {
    return null;
  }
  return (host: host, code: code);
}

/// Full-screen camera scanner for the pairing QR code. Pops with a
/// `(host, code)` record on the first successfully-parsed detection;
/// anything else detected (an unrelated QR code, a parse failure) is
/// ignored and scanning continues.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final result = parsePairingQrData(raw);
      if (result != null) {
        _handled = true;
        Navigator.of(context).pop(result);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR code')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Point the camera at the QR code shown in the '
                '"Pair remote control" dialog on Pigflix',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  shadows: const [Shadow(blurRadius: 8)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
