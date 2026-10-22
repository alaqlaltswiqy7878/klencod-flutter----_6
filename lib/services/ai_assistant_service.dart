import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../config/local_api_key.dart' as local;
import 'settings_store.dart';

class AiAssistantException implements Exception {
  final String message;
  const AiAssistantException(this.message);
  @override String toString() => message;
}

class AiAssistantService {
  static const String model = 'gemini-2.5-flash';
  static const Duration timeout = Duration(seconds: 35);
  // مفتاح اختياري يُحقن وقت البناء: --dart-define=GEMINI_API_KEY=...
  static const String _buildKey = String.fromEnvironment('GEMINI_API_KEY');

  /// يحذف أي محارف مخفية (RTL/مسافات/أسطر) تدخل عند اللصق من الهاتف.
  static String sanitizeKey(String raw) => raw.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '');

  // المصدر الأول: GitHub Secret عبر dart-define. المصدر الثاني: ملف local_api_key.dart.
  static String get _embeddedKey {
    final fromBuild = sanitizeKey(_buildKey);
    return fromBuild.isNotEmpty ? fromBuild : sanitizeKey(local.geminiApiKey);
  }

  static String get _activeKey {
    final saved = sanitizeKey(SettingsStore.geminiApiKey);
    return saved.isNotEmpty ? saved : _embeddedKey;
  }

  static bool get hasBuildKey => _embeddedKey.isNotEmpty;
  static bool get isConfigured => _activeKey.isNotEmpty;

  static Future<String> send({required List<Map<String, String>> messages, String? systemInstruction, String? apiKey}) async {
    final key = apiKey != null ? sanitizeKey(apiKey) : _activeKey;
    if (key.isEmpty) throw const AiAssistantException('لم يتم إعداد مفتاح Gemini. افتح إعداد اتصال نيكو أولًا.');
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    final contents = messages.map((m) => {'role': m['role'] == 'assistant' ? 'model' : 'user', 'parts': [{'text': m['text'] ?? ''}]}).toList();
    final body = <String, dynamic>{'contents': contents};
    if (systemInstruction != null && systemInstruction.trim().isNotEmpty) body['systemInstruction'] = {'parts': [{'text': systemInstruction}]};
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set('x-goog-api-key', key);
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(timeout);
      final raw = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) throw AiAssistantException(_messageForStatus(response.statusCode, raw));
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;
      final content = candidates != null && candidates.isNotEmpty ? (candidates.first as Map)['content'] : null;
      final parts = content is Map ? content['parts'] as List? : null;
      final first = parts?.isNotEmpty == true ? parts!.first : null;
      final text = first is Map && first['text'] is String ? first['text'] as String : null;
      if (text == null || text.trim().isEmpty) throw const AiAssistantException('وصل رد فارغ من نيكو. تحقق من النموذج ثم حاول مرة أخرى.');
      return text.trim();
    } on SocketException { throw const AiAssistantException('لا يوجد اتصال بالإنترنت. تحقق من اتصالك ثم حاول مرة أخرى.'); }
    on HttpException { throw const AiAssistantException('تعذر الاتصال بخدمة نيكو.'); }
    on TimeoutException { throw const AiAssistantException('انتهت مهلة الاتصال. حاول مرة أخرى.'); }
    on AiAssistantException { rethrow; }
    on HandshakeException catch (e) { throw AiAssistantException('فشل الاتصال الآمن (TLS): ${e.message}'); }
    catch (e) { throw AiAssistantException('خطأ غير متوقع: ${e.runtimeType} - $e'); }
    finally { client.close(force: true); }
  }

  static Future<bool> testConnection({String? apiKey}) async {
    await send(apiKey: apiKey, messages: const [{'role': 'user', 'text': 'أجب بكلمة واحدة فقط: جاهز'}]);
    return true;
  }

  static String _apiDetail(String raw) {
    try {
      final m = (jsonDecode(raw) as Map)['error'];
      if (m is Map && m['message'] is String) return ' [${m['message']}]';
    } catch (_) {}
    return '';
  }

  static String _messageForStatus(int status, String raw) {
    final d = _apiDetail(raw);
    return '${_baseMessage(status)}$d';
  }

  static String _baseMessage(int status) {
    if (status == 400) return 'رفض Gemini الطلب. تحقق من صيغة المفتاح أو إعدادات النموذج.';
    if (status == 401 || status == 403) return 'مفتاح Gemini غير صالح أو غير مصرح باستخدام Gemini API.';
    if (status == 404) return 'نموذج Gemini المحدد غير متاح لهذا المفتاح أو لم يعد متاحًا.';
    if (status == 429) return 'تم تجاوز الحد المجاني أو عدد الطلبات. حاول لاحقًا.';
    if (status >= 500) return 'خدمة Gemini تواجه مشكلة مؤقتة. حاول لاحقًا.';
    return 'تعذر الوصول إلى نيكو حاليًا (رمز الخدمة $status).';
  }
}
