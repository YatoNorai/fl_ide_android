import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_agent.dart';

// ── Available models per provider ─────────────────────────────────────────────

const kGeminiModels = [
  'gemini-2.5-pro',
  'gemini-2.5-flash',
  'gemini-2.5-flash-lite',
  'gemini-2.0-flash',
  'gemini-2.0-flash-lite',
  'gemini-1.5-pro',
  'gemini-1.5-flash',
];

const kGptModels = [
  'gpt-4.1',
  'gpt-4.1-mini',
  'gpt-4.1-nano',
  'gpt-4o',
  'gpt-4o-mini',
  'o3',
  'o4-mini',
  'o3-mini',
];

const kClaudeModels = [
  'claude-opus-4-6',
  'claude-sonnet-4-6',
  'claude-haiku-4-5-20251001',
  'claude-3-7-sonnet-20250219',
  'claude-3-5-haiku-20241022',
];

const kDeepSeekModels = [
  'deepseek-chat',
  'deepseek-reasoner',
  'deepseek-r1',
];

class AiProvider extends ChangeNotifier {
  // ── SharedPreferences keys ────────────────────────────────────────────────
  static const _kGeminiKey      = 'ai_gemini_key';
  static const _kGptKey         = 'ai_gpt_key';
  static const _kClaudeKey      = 'ai_claude_key';
  static const _kDeepSeekKey    = 'ai_deepseek_key';
  static const _kGeminiModel    = 'ai_gemini_model';
  static const _kGptModel       = 'ai_gpt_model';
  static const _kClaudeModel    = 'ai_claude_model';
  static const _kDeepSeekModel  = 'ai_deepseek_model';
  static const _kAgents         = 'ai_agents';

  // ── API keys ──────────────────────────────────────────────────────────────
  String _geminiKey   = '';
  String _gptKey      = '';
  String _claudeKey   = '';
  String _deepSeekKey = '';

  String get geminiKey   => _geminiKey;
  String get gptKey      => _gptKey;
  String get claudeKey   => _claudeKey;
  String get deepSeekKey => _deepSeekKey;

  // ── Selected models ───────────────────────────────────────────────────────
  String _geminiModel   = kGeminiModels.first;
  String _gptModel      = kGptModels.first;
  String _claudeModel   = kClaudeModels.first;
  String _deepSeekModel = kDeepSeekModels.first;

  String get geminiModel   => _geminiModel;
  String get gptModel      => _gptModel;
  String get claudeModel   => _claudeModel;
  String get deepSeekModel => _deepSeekModel;

  // ── Agents ────────────────────────────────────────────────────────────────
  List<AiAgent> _agents = List<AiAgent>.from(kDefaultAgents);

  List<AiAgent> get agents => List.unmodifiable(_agents);

  AiProvider() {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _geminiKey   = p.getString(_kGeminiKey)   ?? '';
    _gptKey      = p.getString(_kGptKey)      ?? '';
    _claudeKey   = p.getString(_kClaudeKey)   ?? '';
    _deepSeekKey = p.getString(_kDeepSeekKey) ?? '';

    _geminiModel   = p.getString(_kGeminiModel)   ?? kGeminiModels.first;
    _gptModel      = p.getString(_kGptModel)      ?? kGptModels.first;
    _claudeModel   = p.getString(_kClaudeModel)   ?? kClaudeModels.first;
    _deepSeekModel = p.getString(_kDeepSeekModel) ?? kDeepSeekModels.first;

    final raw = p.getString(_kAgents);
    if (raw != null && raw.isNotEmpty) {
      try {
        _agents = AiAgent.decodeList(raw);
        // Ensure all default agents are present (merge by id).
        for (final def in kDefaultAgents) {
          if (!_agents.any((a) => a.id == def.id)) {
            _agents.insert(kDefaultAgents.indexOf(def), def);
          }
        }
      } catch (_) {
        _agents = List<AiAgent>.from(kDefaultAgents);
      }
    }
    notifyListeners();
  }

  Future<void> _saveAgents() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAgents, AiAgent.encodeList(_agents));
  }

  // ── API key setters ───────────────────────────────────────────────────────
  Future<void> setGeminiKey(String v) async {
    _geminiKey = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kGeminiKey, v);
    notifyListeners();
  }

  Future<void> setGptKey(String v) async {
    _gptKey = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kGptKey, v);
    notifyListeners();
  }

  Future<void> setClaudeKey(String v) async {
    _claudeKey = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kClaudeKey, v);
    notifyListeners();
  }

  Future<void> setDeepSeekKey(String v) async {
    _deepSeekKey = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDeepSeekKey, v);
    notifyListeners();
  }

  // ── Model setters ─────────────────────────────────────────────────────────
  Future<void> setGeminiModel(String v) async {
    _geminiModel = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kGeminiModel, v);
    notifyListeners();
  }

  Future<void> setGptModel(String v) async {
    _gptModel = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kGptModel, v);
    notifyListeners();
  }

  Future<void> setClaudeModel(String v) async {
    _claudeModel = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kClaudeModel, v);
    notifyListeners();
  }

  Future<void> setDeepSeekModel(String v) async {
    _deepSeekModel = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDeepSeekModel, v);
    notifyListeners();
  }

  // ── Agent CRUD ────────────────────────────────────────────────────────────
  Future<void> addAgent(AiAgent agent) async {
    _agents.add(agent);
    await _saveAgents();
    notifyListeners();
  }

  /// Updates an existing agent by id. Default agents can be edited but not removed.
  Future<void> updateAgent(AiAgent updated) async {
    final idx = _agents.indexWhere((a) => a.id == updated.id);
    if (idx == -1) return;
    _agents[idx] = updated;
    await _saveAgents();
    notifyListeners();
  }

  /// Deletes an agent. Only non-default agents may be deleted.
  Future<void> deleteAgent(String id) async {
    _agents.removeWhere((a) => a.id == id && !a.isDefault);
    await _saveAgents();
    notifyListeners();
  }
}
