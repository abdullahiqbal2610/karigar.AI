import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../services/ai_service.dart';
import '../../services/database_provider.dart';
import '../../services/auth_provider.dart';
import '../../models/appointment_model.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

class ReceiverDashboard extends StatefulWidget {
  const ReceiverDashboard({super.key});

  @override
  State<ReceiverDashboard> createState() => _ReceiverDashboardState();
}

class _ReceiverDashboardState extends State<ReceiverDashboard> {
  final TextEditingController _promptController = TextEditingController();
  bool _isAnalyzing = false;
  Map<String, dynamic>? _analysisResult;

  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isListening = false;

  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  String? _base64Image;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    await _speechToText.initialize();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speechToText.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speechToText.listen(
          onResult: (val) => setState(() {
            _promptController.text = val.recognizedWords;
          }),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speechToText.stop();
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
    }
  }

  Future<void> _analyzePrompt() async {
    if (_promptController.text.trim().isEmpty && _selectedImage == null) return;

    setState(() {
      _isAnalyzing = true;
      _analysisResult = null;
    });

    if (_selectedImage != null) {
      final bytes = await _selectedImage!.readAsBytes();
      _base64Image = base64Encode(bytes);
    } else {
      _base64Image = null;
    }

    final result = await AiService.parseServiceRequest(
      _promptController.text.isEmpty ? "What's wrong in this picture?" : _promptController.text, 
      base64Image: _base64Image,
    );

    setState(() {
      _isAnalyzing = false;
      _analysisResult = result;
    });
  }

  void _showBookingForm() {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null || _analysisResult == null) return;

    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = TimeOfDay.now();
    String urgency = _analysisResult!['urgency'] ?? 'Medium';
    TextEditingController locationController = TextEditingController(text: user.area ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24, right: 24, top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Confirm Booking Details', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 16),
                    Text('Profession: ${_analysisResult!['profession_needed']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Est. Cost: \$${_analysisResult!['estimated_cost']}', style: const TextStyle(color: AppTheme.successColor, fontWeight: FontWeight.bold)),
                    const Divider(height: 32),
                    
                    // Date Picker
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date'),
                      subtitle: Text(DateFormat('MMM d, yyyy').format(selectedDate)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date != null) setModalState(() => selectedDate = date);
                      },
                    ),
                    
                    // Time Picker
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Time'),
                      subtitle: Text(selectedTime.format(context)),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (time != null) setModalState(() => selectedTime = time);
                      },
                    ),

                    // Urgency
                    DropdownButtonFormField<String>(
                      value: urgency,
                      decoration: const InputDecoration(labelText: 'Urgency'),
                      items: ['Low', 'Medium', 'High'].map((u) {
                        return DropdownMenuItem(value: u, child: Text(u));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => urgency = val);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Area
                    TextFormField(
                      controller: locationController,
                      decoration: const InputDecoration(labelText: 'Service Address/Area'),
                    ),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final combinedDateTime = DateTime(
                            selectedDate.year, selectedDate.month, selectedDate.day,
                            selectedTime.hour, selectedTime.minute,
                          );

                          final appointment = AppointmentModel(
                            id: const Uuid().v4(),
                            receiverId: user.id,
                            status: AppointmentStatus.pending,
                            description: '${_analysisResult!['summary']} [Urgency: $urgency]',
                            scheduledAt: combinedDateTime,
                            location: locationController.text.trim().isEmpty ? 'Current Location' : locationController.text.trim(),
                            cost: (_analysisResult!['estimated_cost'] as num).toDouble(),
                          );

                          await context.read<DatabaseProvider>().createAppointment(appointment);

                          if (context.mounted) {
                            Navigator.pop(context); // close modal
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Service request sent to professionals!')),
                            );
                            _promptController.clear();
                            setState(() {
                              _analysisResult = null;
                              _selectedImage = null;
                            });
                          }
                        },
                        child: const Text('Confirm & Request'),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Service'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.p24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'What do you need help with?',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Describe your problem, or upload a photo/audio.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              
              // Image Preview
              if (_selectedImage != null) ...[
                Stack(
                  children: [
                    Container(
                      height: 120,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.grey.shade200,
                      ),
                      child: const Center(child: Icon(Icons.image, size: 50, color: Colors.grey)), // Placeholder for web. In real app, Image.file or Image.network
                    ),
                    Positioned(
                      top: 8, right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        onPressed: () => setState(() => _selectedImage = null),
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Prompt Input
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _promptController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: _isListening ? 'Listening...' : 'e.g., The sink in my kitchen is leaking badly...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.camera_alt, color: AppTheme.textSecondary),
                        onPressed: _pickImage, 
                      ),
                      IconButton(
                        icon: Icon(_isListening ? Icons.mic : Icons.mic_none, color: _isListening ? AppTheme.errorColor : AppTheme.textSecondary),
                        onPressed: _listen, 
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: _isAnalyzing ? null : _analyzePrompt,
                    icon: _isAnalyzing 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                    label: const Text('Analyze'),
                  ),
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Analysis Result
              if (_analysisResult != null) _buildResultCard(),
              
              if (_analysisResult == null && !_isAnalyzing) ...[
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 32),
                Text('Or book manually', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                _buildManualCategoryGrid(),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    return Card(
      elevation: 4,
      shadowColor: AppTheme.accentColor.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.accentColor.withOpacity(0.5), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.successColor),
                const SizedBox(width: 8),
                Text('Analysis Complete', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppTheme.successColor)),
              ],
            ),
            const SizedBox(height: 16),
            Text('We found the right professional for you:', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildResultRow('Profession', _analysisResult!['profession_needed']),
                  const Divider(height: 24),
                  _buildResultRow('Est. Cost', '\$${_analysisResult!['estimated_cost']}'),
                  const Divider(height: 24),
                  _buildResultRow('Urgency', '${_analysisResult!['urgency'] ?? 'Medium'}'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _showBookingForm,
                child: const Text('Select Time & Request'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildManualCategoryGrid() {
    final categories = [
      {'icon': Icons.plumbing, 'name': 'Plumber'},
      {'icon': Icons.electrical_services, 'name': 'Electrician'},
      {'icon': Icons.cleaning_services, 'name': 'Cleaning'},
      {'icon': Icons.handyman, 'name': 'Handyman'},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.5,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        return InkWell(
          onTap: () {
            _promptController.text = 'I need a ${categories[index]['name']}';
            _analyzePrompt();
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(categories[index]['icon'] as IconData, color: AppTheme.accentColor, size: 32),
                const SizedBox(height: 8),
                Text(categories[index]['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      },
    );
  }
}
