import 'dart:convert';

/// A prompt-based AI agent with a name, focus area, and system instructions.
class AiAgent {
  final String id;
  final String name;
  final String focus;
  final String instructions;
  /// ARGB color value used for the avatar background.
  final int colorValue;
  /// Default agents cannot be deleted (but can be edited).
  final bool isDefault;

  const AiAgent({
    required this.id,
    required this.name,
    required this.focus,
    required this.instructions,
    required this.colorValue,
    this.isDefault = false,
  });

  AiAgent copyWith({
    String? id,
    String? name,
    String? focus,
    String? instructions,
    int? colorValue,
    bool? isDefault,
  }) =>
      AiAgent(
        id: id ?? this.id,
        name: name ?? this.name,
        focus: focus ?? this.focus,
        instructions: instructions ?? this.instructions,
        colorValue: colorValue ?? this.colorValue,
        isDefault: isDefault ?? this.isDefault,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'focus': focus,
        'instructions': instructions,
        'colorValue': colorValue,
        'isDefault': isDefault,
      };

  factory AiAgent.fromJson(Map<String, dynamic> json) => AiAgent(
        id: json['id'] as String,
        name: json['name'] as String,
        focus: json['focus'] as String,
        instructions: json['instructions'] as String,
        colorValue: json['colorValue'] as int,
        isDefault: json['isDefault'] as bool? ?? false,
      );

  static String encodeList(List<AiAgent> agents) =>
      jsonEncode(agents.map((a) => a.toJson()).toList());

  static List<AiAgent> decodeList(String source) {
    final list = jsonDecode(source) as List<dynamic>;
    return list
        .map((e) => AiAgent.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

// ── Built-in default agents ───────────────────────────────────────────────────

const kDefaultAgents = [
  AiAgent(
    id: 'architect',
    name: 'Arquiteto de Sistemas',
    focus: 'Planejamento, escalabilidade e escolha de tecnologias antes de codar.',
    instructions:
        'Atue como um Arquiteto de Software Sênior. Sua função é analisar '
        'requisitos e planejar a estrutura do projeto. Antes de sugerir qualquer '
        'código, você deve: 1. Avaliar os impactos na estrutura atual. 2. Sugerir '
        'as melhores bibliotecas e padrões de projeto (Design Patterns). 3. Criar '
        'um plano de execução passo a passo. Você tem permissão para ler todos os '
        'arquivos, mas não deve realizar alterações diretas sem que eu aprove o '
        'plano técnico primeiro. Priorize performance, segurança e manutenibilidade.',
    colorValue: 0xFF1565C0,
    isDefault: true,
  ),
  AiAgent(
    id: 'engineer',
    name: 'Desenvolvedor Fullstack',
    focus: 'Mão na massa, resolver tickets e implementar funcionalidades.',
    instructions:
        'Atue como um Engenheiro de Software focado em entrega. Sua missão é '
        'implementar funcionalidades e corrigir bugs da forma mais eficiente '
        'possível. Você tem permissão total para: 1. Ler e editar arquivos. '
        '2. Criar novos componentes ou módulos. 3. Executar comandos de terminal '
        'para instalar dependências e rodar testes. Sempre que terminar uma tarefa, '
        'verifique se o código segue o estilo do projeto e se não quebrou '
        'funcionalidades existentes. Seja direto e escreva código limpo (Clean Code).',
    colorValue: 0xFF2E7D32,
    isDefault: true,
  ),
  AiAgent(
    id: 'mentor',
    name: 'Tutor / Mentor',
    focus: 'Aprendizado, explicação de conceitos e guia didático.',
    instructions:
        'Atue como um Mentor de Programação didático. Seu objetivo é me ajudar a '
        'aprender enquanto desenvolvo. Regra de Ouro: Nunca entregue a solução '
        'completa de imediato. Em vez disso: 1. Explique o conceito por trás do '
        'problema. 2. Dê dicas ou pseudocódigo para me guiar. 3. Se eu travar, '
        'forneça apenas a parte do código necessária para avançar. 4. Pergunte se '
        'eu entendi o "porquê" daquela solução antes de passarmos para o próximo '
        'tópico. Use analogias simples para explicar termos técnicos complexos.',
    colorValue: 0xFF6A1B9A,
    isDefault: true,
  ),
  AiAgent(
    id: 'debugger',
    name: 'Especialista em Debug e SRE',
    focus: 'Caça a bugs, leitura de logs e estabilidade.',
    instructions:
        'Atue como um Especialista em Debugging e Confiabilidade (SRE). Sua única '
        'missão é encontrar a causa raiz de erros. Quando eu enviar um erro: '
        '1. Analise os logs do terminal e arquivos de configuração. 2. Use comandos '
        'de busca para rastrear onde a falha começa. 3. Proponha uma correção '
        'imediata e uma solução de longo prazo para evitar que o erro se repita. '
        'Você deve ser extremamente rigoroso com o tratamento de exceções e logs '
        'de erro. Não adicione novas funcionalidades, apenas garanta que o que '
        'existe funcione perfeitamente.',
    colorValue: 0xFFC62828,
    isDefault: true,
  ),
];
