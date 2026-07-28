import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

Future<bool> downloadInvoice(
  BuildContext context,
  GlobalKey key,
  String bookingCode,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final boundaryContext = key.currentContext;
    if (boundaryContext == null) {
      messenger?.showSnackBar(
        const SnackBar(content: Text("Invoice is not ready yet")),
      );
      return false;
    }

    final renderObject = boundaryContext.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      messenger?.showSnackBar(
        const SnackBar(content: Text("Unable to capture invoice")),
      );
      return false;
    }

    if (renderObject.debugNeedsPaint) {
      await Future.delayed(const Duration(milliseconds: 120));
    }

    final ui.Image image = await renderObject.toImage(pixelRatio: 3.0);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      messenger?.showSnackBar(
        const SnackBar(content: Text("Failed to generate invoice image")),
      );
      return false;
    }

    final Uint8List pngBytes = byteData.buffer.asUint8List();

    final pdf = pw.Document();
    final pdfImage = pw.MemoryImage(pngBytes);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pdfContext) {
          return pw.Center(
            child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
          );
        },
      ),
    );

    final safeCode =
        bookingCode.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_').trim();
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/Invoice_$safeCode.pdf');
    await file.writeAsBytes(await pdf.save(), flush: true);

    await Share.shareXFiles([XFile(file.path)], text: "Booking Invoice");
    return true;
  } catch (e) {
    debugPrint("Invoice Download Error: $e");
    messenger?.showSnackBar(
      const SnackBar(content: Text("Unable to download invoice right now")),
    );
    return false;
  }
}
