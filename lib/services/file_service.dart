import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:csv/csv.dart';
import '../models/sms_row.dart';

class FileService {
  Future<FilePickerResult?> pickFile() async {
    return await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv', 'txt'],
    );
  }

  Future<List<SmsRow>> parseFile(String path) async {
    final extension = path.split('.').last.toLowerCase();
    
    if (extension == 'xlsx') {
      return _parseExcel(path);
    } else if (extension == 'csv' || extension == 'txt') {
      return _parseCsv(path);
    } else {
      throw Exception('Unsupported file format: $extension');
    }
  }

  Future<List<SmsRow>> _parseExcel(String path) async {
    final bytes = File(path).readAsBytesSync();
    
    // SpreadsheetDecoder detects format automatically usually, but we know it's xlsx
    var decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);
    
    final List<SmsRow> rows = [];
    if (decoder.tables.isEmpty) return rows;

    // Use first sheet
    final table = decoder.tables.values.first;

    // Header Mapping
    Map<String, int> headerMap = {};
    bool isHeaderParsed = false;
    int rowIndex = 0;

    for (var row in table.rows) {
        if (row.isEmpty) continue;
        
        // Simple heuristic: First row is header
        if (!isHeaderParsed) {
             for (int i = 0; i < row.length; i++) {
                 String val = row[i]?.toString().toLowerCase().trim() ?? '';
                 if (val.contains('number') || val.contains('phone') || val == 'mobile') headerMap['number'] = i;
                 if (val == 'name') headerMap['name'] = i;
                 if (val == 'service') headerMap['service'] = i;
                 if (val == 'location') headerMap['location'] = i;
                 if (val == 'country') headerMap['country'] = i;
                 if (val.contains('tasdek') && val.contains('from')) headerMap['tasdek_from'] = i;
                 if (val.contains('tasdek') && val.contains('to')) headerMap['tasdek_to'] = i;
             }
             isHeaderParsed = true;
             
             if (headerMap.isNotEmpty) continue; 
             
             // Fallback default mapping
             headerMap = {'number': 0, 'name': 1, 'service': 2, 'location': 3, 'country': 4, 'tasdek_from': 5, 'tasdek_to': 6};
        }
        
        // Parse using map
        String number = _getValue(row, headerMap['number']);
        String name = _getValue(row, headerMap['name']);
        String service = _getValue(row, headerMap['service']);
        String location = _getValue(row, headerMap['location']);
        String country = _getValue(row, headerMap['country']);
        String tasdekFrom = _getValue(row, headerMap['tasdek_from']);
        String tasdekTo = _getValue(row, headerMap['tasdek_to']);

        if (number.isEmpty) continue;

        rows.add(SmsRow(
            index: rowIndex + 1,
            number: _cleanNumber(number),
            name: name,
            service: service,
            location: location,
            country: country,
            tasdekFrom: tasdekFrom,
            tasdekTo: tasdekTo,
        ));
        rowIndex++;
    }
    return rows;
  }
  
  String _getValue(List<dynamic> row, int? index) {
      if (index == null || index < 0 || index >= row.length) return '';
      return row[index]?.toString() ?? '';
  }

  Future<List<SmsRow>> _parseCsv(String path) async {
    final file = File(path);
    final input = file.openRead();
    final fields = await input.transform(utf8.decoder).transform(const CsvToListConverter()).toList();

    final List<SmsRow> rows = [];
    int rowIndex = 0;
    
    Map<String, int> headerMap = {};
    bool isHeaderParsed = false;

    for (var row in fields) {
        if (row.isEmpty) continue;

        if (!isHeaderParsed) {
             for (int i = 0; i < row.length; i++) {
                 String val = row[i].toString().toLowerCase().trim();
                 if (val.contains('number') || val.contains('phone') || val.contains('mobile') || val.contains('رقم التيلفون')) headerMap['number'] = i;
                 if (val == 'name') headerMap['name'] = i;
                 if (val == 'service') headerMap['service'] = i;
                 if (val == 'location') headerMap['location'] = i;
                 if (val == 'country') headerMap['country'] = i;
                 if (val.contains('tasdek') && val.contains('from')) headerMap['tasdek_from'] = i;
                 if (val.contains('tasdek') && val.contains('to')) headerMap['tasdek_to'] = i;
             }
             isHeaderParsed = true;
             if (headerMap.isNotEmpty) continue;
             
             headerMap = {'number': 0, 'name': 1, 'service': 2, 'location': 3, 'country': 4, 'tasdek_from': 5, 'tasdek_to': 6};
        }

        String number = _getCsvValue(row, headerMap['number']);
        String name = _getCsvValue(row, headerMap['name']);
        String service = _getCsvValue(row, headerMap['service']);
        String location = _getCsvValue(row, headerMap['location']);
        String country = _getCsvValue(row, headerMap['country']);
        String tasdekFrom = _getCsvValue(row, headerMap['tasdek_from']);
        String tasdekTo = _getCsvValue(row, headerMap['tasdek_to']);

        if (number.isEmpty) continue;

        rows.add(SmsRow(
            index: rowIndex + 1,
            number: _cleanNumber(number),
            name: name,
            service: service,
            location: location,
            country: country,
            tasdekFrom: tasdekFrom,
            tasdekTo: tasdekTo,
        ));
        rowIndex++;
    }
    return rows;
  }
  
  String _getCsvValue(List<dynamic> row, int? index) {
       if (index == null || index < 0 || index >= row.length) return '';
       return row[index].toString();
  }

  String _cleanNumber(String input) {
    return input.replaceAll(RegExp(r'[^0-9+]'), '');
  }
}
