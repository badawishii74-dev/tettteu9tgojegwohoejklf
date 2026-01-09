import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';



import '../services/file_service.dart';
import '../services/sms_service.dart';
import '../services/log_service.dart';
import '../services/export_service.dart';
import '../models/sms_row.dart';
import '../widgets/stat_card.dart';
import '../widgets/config_panel.dart';
import '../widgets/message_preview_dialog.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Services
  final FileService _fileService = FileService();
  final ExportService _exportService = ExportService();
  late SmsService _smsService;
  late LogService _logService;
  
  // Template State
  String _selectedTemplateType = 'Certificates'; // or 'Security'
 final String _certificatesTemplate =
    "*** ادارة التجنيد والتعبئة ***\n"
    " لقد قمت بسداد رسوم الشهادة برجاء ارسال صورة شخصية وصورة البطاقه لطباعة الشهاده على رقم الوتساب\n"
    " 01094258960";

  final String _securityTemplate =
    "*** ادارة التجنيد والتعبئة ***\n"
    " لقد تم قبول التصديق الامني الخاص بكم يمكنك تسجيل تصريح سفر من الموقع الالكتروني \n"
    "علما بأن مدة تصريح السفر 15 يوم من تاريخ الدفع";

  // State
  List<SmsRow> _rows = [];
  bool _isLoadingFile = false;
  bool _isSending = false;
  
  // Stats
  int _total = 0;
  int _sent = 0;
  int _failed = 0;
  int _currentIndex = 0;

  // Scroll Controller
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _logService = LogService();
    _smsService = SmsService(_logService);
    _messageController.text = _certificatesTemplate;
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.sms,
      Permission.phone, // READ_PHONE_STATE
      Permission.storage, // Storage
    ].request();

    if (statuses[Permission.sms] != PermissionStatus.granted) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('SMS permission is required / إذن الرسائل مطلوب')),
         );
      }
    }
  }

  Future<void> _pickFile() async {
    setState(() => _isLoadingFile = true);
    
    try {
      FilePickerResult? result = await _fileService.pickFile();
      if (result != null) {
        String path = result.files.single.path!;
        List<SmsRow> rows = await _fileService.parseFile(path);
        
        setState(() {
          _rows = rows;
          _total = rows.length;
          _sent = 0;
          _failed = 0;
          _currentIndex = 0;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File loaded: $_total rows / تم تحميل الملف')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoadingFile = false);
    }
  }

  void _updateConfig(int batch, int delay, int pause) {
    _smsService.batchSize = batch;
    _smsService.delaySeconds = delay;
    _smsService.pauseAfterBatchSeconds = pause;
  }

  void _clearFile() {
    setState(() {
      _rows = [];
      _total = 0;
      _sent = 0;
      _failed = 0;
      _currentIndex = 0;
    });
  }

  Future<void> _startSending() async {
    if (_rows.isEmpty) return;
    if (_isSending) return;
    
    // Check permissions again
    if (!await Permission.sms.isGranted) {
       await _requestPermissions();
       if (!await Permission.sms.isGranted) return;
    }

    if (_rows.length > 100) {
      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Confirm / تأكيد'),
          content: Text('You are about to send ${_rows.length} messages. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Start')),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() {
      _isSending = true;
    });

    // Validate Template
    String template = _messageController.text;
    if (template.trim().isEmpty) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter a message template / أدخل نص الرسالة'), backgroundColor: Colors.red),
        );
        return;
    }

    // Pre-calculate messages
    for (var row in _rows) {
        // Don't overwrite if sent? Or allow re-send?
        // Logic: if sent, skip in sending loop, but helpful to update object for consistency
        row.setFinalMessage(row.getFormattedMessage(template));
    }

    await _smsService.sendBatch(
      _rows,
      onRowUpdate: (index, row) {
        if (mounted) setState(() {});
        // Auto scroll
        if (index > 5) {
            // _scrollController.jumpTo(...) // Optional, might be annoying if user scrolls
        }
      },
      onProgress: (sent, failed) {
        if (mounted) {
           setState(() {
             _sent = sent;
             _failed = failed;
             _currentIndex = sent + failed; // Approximation
           });
        }
      },
    );

    if (mounted) {
      setState(() => _isSending = false);
      
      // Check failures
      List<SmsRow> failed = _rows.where((r) => r.status == AppSmsStatus.failed).toList();
      if (failed.isNotEmpty) {
          String path = await _exportService.createFailedSheet(failed);
           // Show Dialog
          showDialog(
            context: context,
            builder: (c) => AlertDialog(
                title: const Text("Sending Finished / تم الانتهاء"),
                content: Text("Process finished with ${failed.length} failures.\nFailed sheet created at:\n$path"),
                actions: [
                    TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK")),
                    // In a real app, "Download" might invoke Share or Open File intent.
                    // For now, we just show path.
                ],
            )
          );
      } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Finished Successfully / تم الانتهاء بنجاح')),
          );
      }
    }
  }

  void _stopSending() {
    _smsService.stop();
    setState(() => _isSending = false);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stopped / تم الإيقاف')),
      );
  }

  Future<void> _exportLog() async {
    String path = await _logService.getLogPath();
     if (mounted) {
        showDialog(context: context, builder: (c) => AlertDialog(
            title: const Text("Log Path"),
            content: Text(path),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK"))],
        ));
     }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Bulk Sender'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context, 
              applicationName: 'SMS Sender',
              children: const [Text('Use responsibly. App must handle SMS limits.')]
            ),
          ),
          IconButton(onPressed: _exportLog, icon: const Icon(Icons.history))
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Stats Row
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(child: StatCard(label: "Total / الكلي", value: "$_total", icon: Icons.list)),
                  Expanded(child: StatCard(label: "Sent / تم", value: "$_sent", color: Colors.green, icon: Icons.check)),
                  Expanded(child: StatCard(label: "Failed / فشل", value: "$_failed", color: Colors.red, icon: Icons.error)),
                ],
              ),
            ),
          ),
          
          // Controls
          SliverToBoxAdapter(
            child: ConfigPanel(onConfigChanged: _updateConfig, isRunning: _isSending),
          ),
          
          // Message Template & Configuration
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                      // Template Selector
                      DropdownButtonFormField<String>(
                          value: _selectedTemplateType,
                          decoration: const InputDecoration(
                              labelText: "Type / نوع الرسالة",
                              border: OutlineInputBorder()
                          ),
                          items: const [
                              DropdownMenuItem(value: 'Certificates', child: Text("Certificates / شهادات")),
                              DropdownMenuItem(value: 'Security', child: Text("Security Confirmation / التصديق الأمني")),
                              DropdownMenuItem(value: 'Custom', child: Text("Custom / مخصص")),
                          ],
                          onChanged: (val) {
                              if (val == null) return;
                              setState(() {
                                  _selectedTemplateType = val;
                                  if (val == 'Certificates') {
                                      _messageController.text = _certificatesTemplate;
                                  } else if (val == 'Security') {
                                      _messageController.text = _securityTemplate;
                                  } else {
                                      _messageController.clear();
                                  }
                              });
                          }
                      ),
                      const SizedBox(height: 8),
                      // TextField
                      TextField(
                          controller: _messageController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                              labelText: "Message Template / نص الرسالة",
                              border: OutlineInputBorder(),
                              helperText: "Vars: \${Name}, \${country}, \${tasdek_from}, \${tasdek_to}, \${service}",
                          ),
                          onChanged: (v) {
                              if (mounted) setState(() {}); 
                          },
                      ),
                  ],
              ),
            ),
          ),
          
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: _rows.isEmpty 
                        ? ElevatedButton.icon(
                          onPressed: _isSending ? null : _pickFile,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Load File / اختر ملف'),
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                        )
                        : ElevatedButton.icon(
                          onPressed: _isSending ? null : _clearFile,
                          icon: const Icon(Icons.delete, color: Colors.white),
                          label: const Text('Clear File / حذف الملف', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.red,
                          ),
                        ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSending ? _stopSending : _startSending,
                      icon: Icon(_isSending ? Icons.stop : Icons.send),
                      label: Text(_isSending ? 'Stop / إيقاف' : 'Start / ابدأ'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _isSending ? Colors.red.shade100 : Theme.of(context).colorScheme.primaryContainer,
                          padding: const EdgeInsets.symmetric(vertical: 16)
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_isSending)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: LinearProgressIndicator(
                  value: _total > 0 ? (_sent + _failed) / _total : 0,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: Divider()),
          
          // List
          _rows.isEmpty
              ? const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text("Load a CSV/XLSX file to start\nحمل ملف للبدء", textAlign: TextAlign.center)),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final row = _rows[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getStatusColor(row.status),
                          child: Text("${row.index}", style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                        title: Text(row.number),
                        subtitle: Text(row.getFormattedMessage(_messageController.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: row.status == AppSmsStatus.failed 
                            ? Tooltip(message: row.error ?? "Error", child: const Icon(Icons.info, color: Colors.red))
                            : const Icon(Icons.chevron_right),
                        onTap: () async {
                             await showDialog(
                                context: context, 
                                builder: (c) => MessagePreviewDialog(
                                    row: row, 
                                    template: _messageController.text,
                                    smsService: _smsService
                                )
                             );
                             setState(() {}); // Refresh status
                        },
                      );
                    },
                    childCount: _rows.length,
                  ),
                ),
        ],
      ),
    );
  }

  Color _getStatusColor(AppSmsStatus status) {
    if (status == AppSmsStatus.sent) return Colors.green;
    if (status == AppSmsStatus.failed) return Colors.red;
    if (status == AppSmsStatus.sending) return Colors.blue;
    return Colors.grey;
  }
}
