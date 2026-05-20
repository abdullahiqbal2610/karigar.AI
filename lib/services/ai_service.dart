import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class AiService {
  // Analyzes the prompt (and optional image) and suggests booking options
  static Future<Map<String, dynamic>> parseServiceRequest(String prompt, {String? base64Image}) async {
    try {
      final messages = [];

      // Construct payload according to OpenRouter vision standards
      if (base64Image != null && base64Image.isNotEmpty) {
        messages.add({
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$base64Image'
              }
            }
          ]
        });
      } else {
        messages.add({
          'role': 'user',
          'content': prompt
        });
      }

      final response = await http.post(
        Uri.parse(AppConstants.openRouterUrl),
        headers: {
          'Authorization': 'Bearer ${AppConstants.openRouterApiKey}',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://karigar.app', 
          'X-Title': 'Karigar',
        },
        body: jsonEncode({
          'model': AppConstants.openRouterModel,
          'messages': [
            {
              'role': 'system',
              'content': 'You are an agentic assistant for a service booking app. Analyze the user request and return ONLY a valid JSON object with the following keys: "profession_needed" (string, e.g., Plumber, Electrician), "estimated_cost" (number), "urgency" (string: Low, Medium, or High), "summary" (string: a concise 1-sentence summary of the task).'
            },
            ...messages
          ],
          'response_format': { 'type': 'json_object' } // Enforce JSON response if model supports it
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'];
        
        // Clean up markdown code blocks if the model wrapped the JSON
        String cleanJson = content;
        if (cleanJson.contains('```json')) {
          cleanJson = cleanJson.split('```json')[1].split('```')[0].trim();
        } else if (cleanJson.contains('```')) {
          cleanJson = cleanJson.split('```')[1].split('```')[0].trim();
        }
        
        return jsonDecode(cleanJson);
      } else {
        throw Exception('API Error: ${response.statusCode} - ${response.body}');
      }
      
    } catch (e) {
      debugPrint('AI Service Error: $e');
      // Fallback
      return {
        'profession_needed': 'General Service',
        'estimated_cost': 50.0,
        'urgency': 'Medium',
        'summary': prompt,
      };
    }
  }
}
