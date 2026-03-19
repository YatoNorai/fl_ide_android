import 'package:flutter/widgets.dart';

/// Simple compile-time string table. Access via [AppStrings.of(context)].
class AppStrings {
  final String _lang;

  const AppStrings._(this._lang);

  static AppStrings of(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final code = locale.languageCode;
    if (_table.containsKey(code)) return AppStrings._(code);
    return const AppStrings._('pt');
  }

  String _t(String key) => _table[_lang]?[key] ?? _table['en']?[key] ?? key;

  // ── Common ────────────────────────────────────────────────────────────────
  String get appName       => 'FL IDE';
  String get cancel        => _t('cancel');
  String get confirm       => _t('confirm');
  String get delete        => _t('delete');
  String get save          => _t('save');
  String get close         => _t('close');
  String get yes           => _t('yes');
  String get no            => _t('no');
  String get loading       => _t('loading');
  String get error         => _t('error');
  String get retry         => _t('retry');
  String get create        => _t('create');
  String get edit          => _t('edit');

  // ── Home ──────────────────────────────────────────────────────────────────
  String get newProject        => _t('newProject');
  String get newProjectSub     => _t('newProjectSub');
  String get openProject       => _t('openProject');
  String get openProjectSub    => _t('openProjectSub');
  String get terminal          => _t('terminal');
  String get terminalSub       => _t('terminalSub');
  String get settings          => _t('settings');
  String get settingsSub       => _t('settingsSub');

  // ── Projects screen ───────────────────────────────────────────────────────
  String get recentProjects    => _t('recentProjects');
  String get noProjects        => _t('noProjects');
  String get deleteProject     => _t('deleteProject');
  String get deleteProjectQ    => _t('deleteProjectQ');
  String get deleteProjectSub  => _t('deleteProjectSub');

  // ── Create project ────────────────────────────────────────────────────────
  String get projectName       => _t('projectName');
  String get packageName       => _t('packageName');
  String get selectSdk         => _t('selectSdk');
  String get createProject     => _t('createProject');
  String get creating          => _t('creating');
  String get noSdkInstalled    => _t('noSdkInstalled');

  // ── Settings main menu ────────────────────────────────────────────────────
  String get editor            => _t('editor');
  String get runDebug          => _t('runDebug');
  String get extensions        => _t('extensions');
  String get ai                => _t('ai');
  String get about             => _t('about');
  String get generalMenuSub    => _t('generalMenuSub');
  String get editorMenuSub     => _t('editorMenuSub');
  String get terminalMenuSub   => _t('terminalMenuSub');
  String get runDebugSub       => _t('runDebugSub');
  String get extensionsMenuSub => _t('extensionsMenuSub');
  String get aiMenuSub         => _t('aiMenuSub');
  String get aboutMenuSub      => _t('aboutMenuSub');

  // ── Settings: General ─────────────────────────────────────────────────────
  String get secLangRegion      => _t('secLangRegion');
  String get secThemeAppearance => _t('secThemeAppearance');
  String get followSystemTheme  => _t('followSystemTheme');
  String get followSystemOn     => _t('followSystemOn');
  String get followSystemOff    => _t('followSystemOff');
  String get darkMode           => _t('darkMode');
  String get darkModeOn         => _t('darkModeOn');
  String get darkModeOff        => _t('darkModeOff');
  String get amoledBlack        => _t('amoledBlack');
  String get amoledBlackSub     => _t('amoledBlackSub');
  String get dynamicColors      => _t('dynamicColors');
  String get dynamicColorsSub   => _t('dynamicColorsSub');
  String get themeActiveBannerSub => _t('themeActiveBannerSub');
  String themeActiveBanner(String name) =>
      _t('themeActiveBanner').replaceFirst('%s', name);

  // ── Settings: Editor – section headers ────────────────────────────────────
  String get secFontDisplay    => _t('secFontDisplay');
  String get secBehavior       => _t('secBehavior');
  String get secIndentation    => _t('secIndentation');
  String get secCursor         => _t('secCursor');
  String get secCodeStructure  => _t('secCodeStructure');
  String get secHighlight      => _t('secHighlight');
  String get secAdvanced       => _t('secAdvanced');

  // ── Settings: Editor – tiles ──────────────────────────────────────────────
  String get fontFamily            => _t('fontFamily');
  String get fontSize              => _t('fontSize');
  String get lineNumbers           => _t('lineNumbers');
  String get lineNumbersSub        => _t('lineNumbersSub');
  String get fixedGutter           => _t('fixedGutter');
  String get fixedGutterSub        => _t('fixedGutterSub');
  String get minimap               => _t('minimap');
  String get minimapSub            => _t('minimapSub');
  String get symbolBar             => _t('symbolBar');
  String get symbolBarSub          => _t('symbolBarSub');
  String get wordWrap              => _t('wordWrap');
  String get wordWrapSub           => _t('wordWrapSub');
  String get autoIndent            => _t('autoIndent');
  String get autoIndentSub         => _t('autoIndentSub');
  String get autoClosePairs        => _t('autoClosePairs');
  String get autoClosePairsSub     => _t('autoClosePairsSub');
  String get autoCompletion        => _t('autoCompletion');
  String get autoCompletionSub     => _t('autoCompletionSub');
  String get formatOnSave          => _t('formatOnSave');
  String get formatOnSaveSub       => _t('formatOnSaveSub');
  String get stickyScroll          => _t('stickyScroll');
  String get stickyScrollSub       => _t('stickyScrollSub');
  String get tabSize               => _t('tabSize');
  String get tabSizeSub            => _t('tabSizeSub');
  String get useSpaces             => _t('useSpaces');
  String get useSpacesSub          => _t('useSpacesSub');
  String get cursorBlinkSpeed      => _t('cursorBlinkSpeed');
  String get lightbulbActions      => _t('lightbulbActions');
  String get lightbulbActionsSub   => _t('lightbulbActionsSub');
  String get foldArrows            => _t('foldArrows');
  String get foldArrowsSub         => _t('foldArrowsSub');
  String get blockLines            => _t('blockLines');
  String get blockLinesSub         => _t('blockLinesSub');
  String get indentDots            => _t('indentDots');
  String get indentDotsSub         => _t('indentDotsSub');
  String get highlightCurrentLine      => _t('highlightCurrentLine');
  String get highlightCurrentLineSub   => _t('highlightCurrentLineSub');
  String get highlightActiveBlock      => _t('highlightActiveBlock');
  String get highlightActiveBlockSub   => _t('highlightActiveBlockSub');
  String get highlightStyle            => _t('highlightStyle');
  String get highlightStyleSub         => _t('highlightStyleSub');
  String get diagnosticIndicators      => _t('diagnosticIndicators');
  String get diagnosticIndicatorsSub   => _t('diagnosticIndicatorsSub');
  String get readOnly              => _t('readOnly');
  String get readOnlySub           => _t('readOnlySub');

  // ── Settings: Terminal/FileExplorer ───────────────────────────────────────
  String get showHiddenFiles    => _t('showHiddenFiles');
  String get showHiddenFilesSub => _t('showHiddenFilesSub');
  String get terminalFontSize   => _t('terminalFontSize');
  String get colorScheme        => _t('colorScheme');
  String get colorSchemeSub     => _t('colorSchemeSub');

  // ── Settings: Run & Debug ─────────────────────────────────────────────────
  String get rootfsPath        => _t('rootfsPath');
  String get homePath          => _t('homePath');
  String get projectsPath      => _t('projectsPath');
  String get installedSdks     => _t('installedSdks');
  String get noSdksInstalled   => _t('noSdksInstalled');
  String get installSdksSub    => _t('installSdksSub');
  String get lspPaths          => _t('lspPaths');
  String get binaryPath        => _t('binaryPath');
  String get installed         => _t('installed');

  // ── Settings: AI ──────────────────────────────────────────────────────────
  String get apiKeys           => _t('apiKeys');
  String get notConfigured     => _t('notConfigured');
  String get pasteApiKey       => _t('pasteApiKey');
  String get models            => _t('models');
  String get agents            => _t('agents');
  String get newAgent          => _t('newAgent');
  String get defaultLabel      => _t('defaultLabel');
  String get deleteAgent       => _t('deleteAgent');
  String get newAgentTitle     => _t('newAgentTitle');
  String get editAgentTitle    => _t('editAgentTitle');
  String get agentName         => _t('agentName');
  String get agentFocus        => _t('agentFocus');
  String get agentInstructions => _t('agentInstructions');
  String deleteAgentConfirm(String name) =>
      _t('deleteAgentConfirm').replaceFirst('%s', '"$name"');

  // ── Settings: About ───────────────────────────────────────────────────────
  String get developer         => _t('developer');
  String get supportedSdks     => _t('supportedSdks');
  String get licenseLabel      => _t('licenseLabel');
  String get mobileDevEnv      => _t('mobileDevEnv');

  // ── Settings general ──────────────────────────────────────────────────────
  String get language          => _t('language');
  String get languageSub       => _t('languageSub');
  String get followSystem      => _t('followSystem');
  String get appearance        => _t('appearance');
  String get general           => _t('general');

  // ── Onboarding ────────────────────────────────────────────────────────────
  String get permissions       => _t('permissions');
  String get permissionsSub    => _t('permissionsSub');
  String get environment       => _t('environment');
  String get environmentSub    => _t('environmentSub');
  String get finish            => _t('finish');
  String get next              => _t('next');
  String get back              => _t('back');
  String get storage           => _t('storage');
  String get storageSub        => _t('storageSub');
  String get installApps       => _t('installApps');
  String get installAppsSub    => _t('installAppsSub');
  String get granted           => _t('granted');
  String get allow             => _t('allow');
  String get installBootstrap  => _t('installBootstrap');
  String get bootstrapReady    => _t('ready');

  // ── Translation table ─────────────────────────────────────────────────────

  static const Map<String, Map<String, String>> _table = {
    'pt': {
      'cancel': 'Cancelar',
      'confirm': 'Confirmar',
      'delete': 'Excluir',
      'save': 'Salvar',
      'close': 'Fechar',
      'yes': 'Sim',
      'no': 'Não',
      'loading': 'Carregando...',
      'error': 'Erro',
      'retry': 'Tentar novamente',
      'create': 'Criar',
      'edit': 'Editar',
      // Home
      'newProject': 'Novo projeto',
      'newProjectSub': 'Criar um novo projeto a partir de um modelo',
      'openProject': 'Abrir projeto',
      'openProjectSub': 'Abrir um projeto existente',
      'terminal': 'Terminal',
      'terminalSub': 'Abrir uma sessão de terminal avulsa',
      'settings': 'Configurações',
      'settingsSub': 'Editor, aparência e extensões',
      // Projects
      'recentProjects': 'Projetos recentes',
      'noProjects': 'Nenhum projeto ainda',
      'deleteProject': 'Excluir projeto',
      'deleteProjectQ': 'Excluir projeto?',
      'deleteProjectSub': 'Esta ação não pode ser desfeita. Os arquivos do projeto serão removidos permanentemente.',
      // Create project
      'projectName': 'Nome do projeto',
      'packageName': 'Nome do pacote',
      'selectSdk': 'Selecionar SDK',
      'createProject': 'Criar projeto',
      'creating': 'Criando...',
      'noSdkInstalled': 'Nenhum SDK instalado. Instale um SDK primeiro.',
      // Settings main menu
      'editor': 'Editor',
      'runDebug': 'Executar & Depurar',
      'extensions': 'Extensões',
      'ai': 'IA',
      'about': 'Sobre',
      'generalMenuSub': 'Aparência e comportamento.',
      'editorMenuSub': 'Preferências do editor de código.',
      'terminalMenuSub': 'Configurações do terminal integrado.',
      'runDebugSub': 'SDKs e opções de compilação.',
      'extensionsMenuSub': 'Temas e complementos.',
      'aiMenuSub': 'Chaves de API e agentes.',
      'aboutMenuSub': 'Informações do aplicativo.',
      // General
      'secLangRegion': 'Idioma & Região',
      'secThemeAppearance': 'Tema & Aparência',
      'followSystemTheme': 'Seguir tema do sistema',
      'followSystemOn': 'Usando tema do sistema',
      'followSystemOff': 'Controle manual do tema',
      'darkMode': 'Modo escuro',
      'darkModeOn': 'Tema escuro ativo',
      'darkModeOff': 'Tema claro ativo',
      'amoledBlack': 'Preto AMOLED',
      'amoledBlackSub': 'Fundo preto puro para telas OLED',
      'dynamicColors': 'Cores dinâmicas',
      'dynamicColorsSub': 'Cores Material You do papel de parede',
      'themeActiveBanner': 'Tema %s ativo',
      'themeActiveBannerSub': 'As configurações de aparência estão desativadas. Desative o tema nas Extensões para usar as configurações padrão.',
      // Editor section headers
      'secFontDisplay': 'Fonte & Exibição',
      'secBehavior': 'Comportamento',
      'secIndentation': 'Indentação',
      'secCursor': 'Cursor',
      'secCodeStructure': 'Estrutura de Código',
      'secHighlight': 'Destaque',
      'secAdvanced': 'Avançado',
      // Editor tiles
      'fontFamily': 'Família de fonte',
      'fontSize': 'Tamanho da fonte',
      'lineNumbers': 'Números de linha',
      'lineNumbersSub': 'Mostrar números de linha na margem',
      'fixedGutter': 'Margem fixa',
      'fixedGutterSub': 'Números de linha fixos durante a rolagem',
      'minimap': 'Minimapa',
      'minimapSub': 'Painel de prévia do código à direita',
      'symbolBar': 'Barra de símbolos',
      'symbolBarSub': 'Atalhos de teclado mobile { } ; = …',
      'wordWrap': 'Quebra de linha',
      'wordWrapSub': 'Quebrar linhas longas na largura do editor',
      'autoIndent': 'Auto-indentação',
      'autoIndentSub': 'Manter indentação automaticamente',
      'autoClosePairs': 'Fechar pares auto.',
      'autoClosePairsSub': 'Fechar automaticamente ( { [ " \'',
      'autoCompletion': 'Autocompletar',
      'autoCompletionSub': 'Sugestões de código durante a digitação',
      'formatOnSave': 'Formatar ao salvar',
      'formatOnSaveSub': 'Aplicar DartFormatter ao salvar',
      'stickyScroll': 'Rolagem aderente',
      'stickyScrollSub': 'Manter o escopo atual visível no topo',
      'tabSize': 'Tamanho do tab',
      'tabSizeSub': 'Número de espaços por nível de indentação',
      'useSpaces': 'Usar espaços',
      'useSpacesSub': 'Inserir espaços em vez de tabulação',
      'cursorBlinkSpeed': 'Velocidade de piscar',
      'lightbulbActions': 'Ações de lâmpada',
      'lightbulbActionsSub': 'Ícone de ação rápida ao selecionar código',
      'foldArrows': 'Setas de recolher',
      'foldArrowsSub': 'Setas para recolher blocos de código',
      'blockLines': 'Linhas de bloco',
      'blockLinesSub': 'Guias verticais de indentação',
      'indentDots': 'Pontos de indentação',
      'indentDotsSub': 'Pontos antes do primeiro caractere',
      'highlightCurrentLine': 'Destacar linha atual',
      'highlightCurrentLineSub': 'Colorir a linha onde o cursor está',
      'highlightActiveBlock': 'Destacar bloco ativo',
      'highlightActiveBlockSub': 'Mudar cor dentro do escopo ativo',
      'highlightStyle': 'Estilo de destaque',
      'highlightStyleSub': 'Como a linha atual é destacada',
      'diagnosticIndicators': 'Indicadores de diagnóstico',
      'diagnosticIndicatorsSub': 'Sublinhados de erro e aviso',
      'readOnly': 'Somente leitura',
      'readOnlySub': 'Desativar toda edição no editor',
      // Terminal / File Explorer
      'showHiddenFiles': 'Mostrar arquivos ocultos',
      'showHiddenFilesSub': 'Exibir arquivos começando com .',
      'terminalFontSize': 'Tamanho da fonte',
      'colorScheme': 'Esquema de cores',
      'colorSchemeSub': 'Tema de cores do terminal',
      // Run & Debug
      'rootfsPath': 'Caminho RootFS',
      'homePath': 'Caminho Home',
      'projectsPath': 'Caminho de projetos',
      'installedSdks': 'SDKs instalados',
      'noSdksInstalled': 'Nenhum SDK instalado',
      'installSdksSub': 'Instale SDKs pelo workspace',
      'lspPaths': 'Caminhos LSP',
      'binaryPath': 'Caminho do binário',
      'installed': 'Instalado',
      // AI
      'apiKeys': 'Chaves de API',
      'notConfigured': 'Não configurado',
      'pasteApiKey': 'Cole sua chave de API aqui',
      'models': 'Modelos',
      'agents': 'Agentes',
      'newAgent': 'Novo agente',
      'defaultLabel': 'Padrão',
      'deleteAgent': 'Excluir agente',
      'deleteAgentConfirm': 'Excluir %s? Esta ação não pode ser desfeita.',
      'newAgentTitle': 'Novo Agente',
      'editAgentTitle': 'Editar Agente',
      'agentName': 'Nome',
      'agentFocus': 'Área de foco',
      'agentInstructions': 'Instruções do sistema',
      // About
      'developer': 'Desenvolvedor',
      'supportedSdks': 'SDKs Suportados',
      'licenseLabel': 'Licença',
      'mobileDevEnv': 'Ambiente de Desenvolvimento Mobile',
      // Settings general
      'language': 'Idioma',
      'languageSub': 'Idioma do aplicativo',
      'followSystem': 'Seguir o sistema',
      'appearance': 'Aparência',
      'general': 'Geral',
      // Onboarding
      'permissions': 'Permissões',
      'permissionsSub': 'Algumas permissões são necessárias para o funcionamento correto do app.',
      'environment': 'Ambiente',
      'environmentSub': 'O Bootstrap instala o ambiente Linux necessário para compilar e executar projetos.',
      'finish': 'Concluir',
      'next': 'Próximo',
      'back': 'Voltar',
      'storage': 'Armazenamento',
      'storageSub': 'Necessário para acessar e salvar projetos no dispositivo.',
      'installApps': 'Instalar aplicativos',
      'installAppsSub': 'Necessário para instalar APKs gerados pelo app.',
      'granted': 'Concedida',
      'allow': 'Permitir',
      'installBootstrap': 'Instalar Bootstrap',
      'ready': 'Instalado',
    },
    'en': {
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'delete': 'Delete',
      'save': 'Save',
      'close': 'Close',
      'yes': 'Yes',
      'no': 'No',
      'loading': 'Loading...',
      'error': 'Error',
      'retry': 'Retry',
      'create': 'Create',
      'edit': 'Edit',
      'newProject': 'New project',
      'newProjectSub': 'Create a new project from a template',
      'openProject': 'Open project',
      'openProjectSub': 'Open an existing project',
      'terminal': 'Terminal',
      'terminalSub': 'Open a standalone shell session',
      'settings': 'Settings',
      'settingsSub': 'Editor, appearance and extensions',
      'recentProjects': 'Recent projects',
      'noProjects': 'No projects yet',
      'deleteProject': 'Delete project',
      'deleteProjectQ': 'Delete project?',
      'deleteProjectSub': 'This action cannot be undone. The project files will be permanently removed.',
      'projectName': 'Project name',
      'packageName': 'Package name',
      'selectSdk': 'Select SDK',
      'createProject': 'Create project',
      'creating': 'Creating...',
      'noSdkInstalled': 'No SDK installed. Install an SDK first.',
      // Settings main menu
      'editor': 'Editor',
      'runDebug': 'Run & Debug',
      'extensions': 'Extensions',
      'ai': 'AI',
      'about': 'About',
      'generalMenuSub': 'Appearance and behavior settings.',
      'editorMenuSub': 'Code editor preferences.',
      'terminalMenuSub': 'Built-in terminal settings.',
      'runDebugSub': 'SDKs and build options.',
      'extensionsMenuSub': 'Themes and add-ons.',
      'aiMenuSub': 'API keys and agent configurations.',
      'aboutMenuSub': 'App information.',
      // General
      'secLangRegion': 'Language & Region',
      'secThemeAppearance': 'Theme & Appearance',
      'followSystemTheme': 'Follow System Theme',
      'followSystemOn': 'App follows system theme',
      'followSystemOff': 'Manual theme control',
      'darkMode': 'Dark Mode',
      'darkModeOn': 'Dark theme active',
      'darkModeOff': 'Light theme active',
      'amoledBlack': 'AMOLED Black',
      'amoledBlackSub': 'Pure black background for OLED screens',
      'dynamicColors': 'Dynamic Colors',
      'dynamicColorsSub': 'Use Material You colors from wallpaper',
      'themeActiveBanner': 'Theme %s active',
      'themeActiveBannerSub': 'Appearance settings are disabled. Disable the theme in Extensions to use default settings.',
      // Editor section headers
      'secFontDisplay': 'Font & Display',
      'secBehavior': 'Behavior',
      'secIndentation': 'Indentation',
      'secCursor': 'Cursor',
      'secCodeStructure': 'Code Structure',
      'secHighlight': 'Highlight',
      'secAdvanced': 'Advanced',
      // Editor tiles
      'fontFamily': 'Font Family',
      'fontSize': 'Font Size',
      'lineNumbers': 'Line Numbers',
      'lineNumbersSub': 'Show line numbers in the gutter',
      'fixedGutter': 'Fixed Gutter',
      'fixedGutterSub': 'Line numbers stay fixed while scrolling',
      'minimap': 'Minimap',
      'minimapSub': 'Code preview panel on the right',
      'symbolBar': 'Symbol Bar',
      'symbolBarSub': 'Mobile keyboard helpers { } ; = …',
      'wordWrap': 'Word Wrap',
      'wordWrapSub': 'Wrap long lines to the editor width',
      'autoIndent': 'Auto-Indent',
      'autoIndentSub': 'Maintain indentation automatically',
      'autoClosePairs': 'Auto-Close Pairs',
      'autoClosePairsSub': 'Auto-close ( { [ " \' brackets',
      'autoCompletion': 'Auto-Completion',
      'autoCompletionSub': 'Code suggestion popup while typing',
      'formatOnSave': 'Format on Save',
      'formatOnSaveSub': 'Apply DartFormatter on Save',
      'stickyScroll': 'Sticky Scroll',
      'stickyScrollSub': 'Keep the current scope visible at the top',
      'tabSize': 'Tab Size',
      'tabSizeSub': 'Number of spaces per indent level',
      'useSpaces': 'Use Spaces',
      'useSpacesSub': 'Insert spaces instead of tab characters',
      'cursorBlinkSpeed': 'Cursor Blink Speed',
      'lightbulbActions': 'Lightbulb Actions',
      'lightbulbActionsSub': 'Quick-action icon when code is selected',
      'foldArrows': 'Fold Arrows',
      'foldArrowsSub': 'Arrows to collapse code blocks',
      'blockLines': 'Block Lines',
      'blockLinesSub': 'Vertical indentation guide lines',
      'indentDots': 'Indent Dots',
      'indentDotsSub': 'Dots before first character (VS Code style)',
      'highlightCurrentLine': 'Highlight Current Line',
      'highlightCurrentLineSub': 'Tint the line where the cursor is',
      'highlightActiveBlock': 'Highlight Active Block',
      'highlightActiveBlockSub': 'Change color inside the active scope',
      'highlightStyle': 'Highlight Style',
      'highlightStyleSub': 'How the current line is highlighted',
      'diagnosticIndicators': 'Diagnostic Indicators',
      'diagnosticIndicatorsSub': 'Error and warning squiggles',
      'readOnly': 'Read Only',
      'readOnlySub': 'Disable all editing in the editor',
      // Terminal / File Explorer
      'showHiddenFiles': 'Show Hidden Files',
      'showHiddenFilesSub': 'Display files starting with .',
      'terminalFontSize': 'Font Size',
      'colorScheme': 'Color Scheme',
      'colorSchemeSub': 'Terminal color theme',
      // Run & Debug
      'rootfsPath': 'RootFS Path',
      'homePath': 'Home Path',
      'projectsPath': 'Projects Path',
      'installedSdks': 'Installed SDKs',
      'noSdksInstalled': 'No SDKs installed',
      'installSdksSub': 'Install SDKs from the workspace',
      'lspPaths': 'LSP Paths',
      'binaryPath': 'Binary path',
      'installed': 'Installed',
      // AI
      'apiKeys': 'API Keys',
      'notConfigured': 'Not configured',
      'pasteApiKey': 'Paste your API key here',
      'models': 'Models',
      'agents': 'Agents',
      'newAgent': 'New agent',
      'defaultLabel': 'Default',
      'deleteAgent': 'Delete agent',
      'deleteAgentConfirm': 'Delete %s? This cannot be undone.',
      'newAgentTitle': 'New Agent',
      'editAgentTitle': 'Edit Agent',
      'agentName': 'Name',
      'agentFocus': 'Focus area',
      'agentInstructions': 'System instructions',
      // About
      'developer': 'Developer',
      'supportedSdks': 'Supported SDKs',
      'licenseLabel': 'License',
      'mobileDevEnv': 'Mobile Development Environment',
      // Settings general
      'language': 'Language',
      'languageSub': 'App language',
      'followSystem': 'Follow system',
      'appearance': 'Appearance',
      'general': 'General',
      // Onboarding
      'permissions': 'Permissions',
      'permissionsSub': 'Some permissions are required for the app to work correctly.',
      'environment': 'Environment',
      'environmentSub': 'Bootstrap installs the Linux environment needed to build and run projects.',
      'finish': 'Finish',
      'next': 'Next',
      'back': 'Back',
      'storage': 'Storage',
      'storageSub': 'Required to access and save projects on the device.',
      'installApps': 'Install apps',
      'installAppsSub': 'Required to install APKs generated by the app.',
      'granted': 'Granted',
      'allow': 'Allow',
      'installBootstrap': 'Install Bootstrap',
      'ready': 'Installed',
    },
    'es': {
      'cancel': 'Cancelar',
      'confirm': 'Confirmar',
      'delete': 'Eliminar',
      'save': 'Guardar',
      'close': 'Cerrar',
      'yes': 'Sí',
      'no': 'No',
      'loading': 'Cargando...',
      'error': 'Error',
      'retry': 'Reintentar',
      'create': 'Crear',
      'edit': 'Editar',
      'newProject': 'Nuevo proyecto',
      'newProjectSub': 'Crear un nuevo proyecto desde una plantilla',
      'openProject': 'Abrir proyecto',
      'openProjectSub': 'Abrir un proyecto existente',
      'terminal': 'Terminal',
      'terminalSub': 'Abrir una sesión de terminal independiente',
      'settings': 'Ajustes',
      'settingsSub': 'Editor, apariencia y extensiones',
      'recentProjects': 'Proyectos recientes',
      'noProjects': 'Sin proyectos aún',
      'deleteProject': 'Eliminar proyecto',
      'deleteProjectQ': '¿Eliminar proyecto?',
      'deleteProjectSub': 'Esta acción no se puede deshacer. Los archivos del proyecto serán eliminados permanentemente.',
      'projectName': 'Nombre del proyecto',
      'packageName': 'Nombre del paquete',
      'selectSdk': 'Seleccionar SDK',
      'createProject': 'Crear proyecto',
      'creating': 'Creando...',
      'noSdkInstalled': 'No hay SDK instalado. Instala un SDK primero.',
      // Settings main menu
      'editor': 'Editor',
      'runDebug': 'Ejecutar & Depurar',
      'extensions': 'Extensiones',
      'ai': 'IA',
      'about': 'Acerca de',
      'generalMenuSub': 'Apariencia y comportamiento.',
      'editorMenuSub': 'Preferencias del editor de código.',
      'terminalMenuSub': 'Configuración del terminal integrado.',
      'runDebugSub': 'SDKs y opciones de compilación.',
      'extensionsMenuSub': 'Temas y complementos.',
      'aiMenuSub': 'Claves de API y agentes.',
      'aboutMenuSub': 'Información de la aplicación.',
      // General
      'secLangRegion': 'Idioma & Región',
      'secThemeAppearance': 'Tema & Apariencia',
      'followSystemTheme': 'Seguir tema del sistema',
      'followSystemOn': 'Usando tema del sistema',
      'followSystemOff': 'Control manual del tema',
      'darkMode': 'Modo oscuro',
      'darkModeOn': 'Tema oscuro activo',
      'darkModeOff': 'Tema claro activo',
      'amoledBlack': 'Negro AMOLED',
      'amoledBlackSub': 'Fondo negro puro para pantallas OLED',
      'dynamicColors': 'Colores dinámicos',
      'dynamicColorsSub': 'Colores Material You del fondo de pantalla',
      'themeActiveBanner': 'Tema %s activo',
      'themeActiveBannerSub': 'Los ajustes de apariencia están desactivados. Desactiva el tema en Extensiones para usar los ajustes predeterminados.',
      // Editor section headers
      'secFontDisplay': 'Fuente & Visualización',
      'secBehavior': 'Comportamiento',
      'secIndentation': 'Sangría',
      'secCursor': 'Cursor',
      'secCodeStructure': 'Estructura del código',
      'secHighlight': 'Resaltado',
      'secAdvanced': 'Avanzado',
      // Editor tiles
      'fontFamily': 'Familia de fuente',
      'fontSize': 'Tamaño de fuente',
      'lineNumbers': 'Números de línea',
      'lineNumbersSub': 'Mostrar números de línea en el margen',
      'fixedGutter': 'Margen fijo',
      'fixedGutterSub': 'Números fijos al desplazarse',
      'minimap': 'Minimapa',
      'minimapSub': 'Panel de vista previa a la derecha',
      'symbolBar': 'Barra de símbolos',
      'symbolBarSub': 'Atajos de teclado móvil { } ; = …',
      'wordWrap': 'Ajuste de línea',
      'wordWrapSub': 'Ajustar líneas largas al ancho del editor',
      'autoIndent': 'Auto-sangría',
      'autoIndentSub': 'Mantener sangría automáticamente',
      'autoClosePairs': 'Cerrar pares auto.',
      'autoClosePairsSub': 'Cerrar automáticamente ( { [ " \'',
      'autoCompletion': 'Autocompletar',
      'autoCompletionSub': 'Sugerencias de código al escribir',
      'formatOnSave': 'Formatear al guardar',
      'formatOnSaveSub': 'Aplicar DartFormatter al guardar',
      'stickyScroll': 'Desplazamiento fijo',
      'stickyScrollSub': 'Mantener el ámbito actual visible arriba',
      'tabSize': 'Tamaño de tabulación',
      'tabSizeSub': 'Espacios por nivel de sangría',
      'useSpaces': 'Usar espacios',
      'useSpacesSub': 'Insertar espacios en lugar de tabulaciones',
      'cursorBlinkSpeed': 'Velocidad de parpadeo',
      'lightbulbActions': 'Acciones de bombilla',
      'lightbulbActionsSub': 'Icono de acción rápida al seleccionar código',
      'foldArrows': 'Flechas de pliegue',
      'foldArrowsSub': 'Flechas para contraer bloques de código',
      'blockLines': 'Líneas de bloque',
      'blockLinesSub': 'Guías verticales de sangría',
      'indentDots': 'Puntos de sangría',
      'indentDotsSub': 'Puntos antes del primer carácter',
      'highlightCurrentLine': 'Resaltar línea actual',
      'highlightCurrentLineSub': 'Colorear la línea del cursor',
      'highlightActiveBlock': 'Resaltar bloque activo',
      'highlightActiveBlockSub': 'Cambiar color dentro del ámbito activo',
      'highlightStyle': 'Estilo de resaltado',
      'highlightStyleSub': 'Cómo se resalta la línea actual',
      'diagnosticIndicators': 'Indicadores de diagnóstico',
      'diagnosticIndicatorsSub': 'Subrayados de error y aviso',
      'readOnly': 'Solo lectura',
      'readOnlySub': 'Desactivar edición en el editor',
      // Terminal / File Explorer
      'showHiddenFiles': 'Mostrar archivos ocultos',
      'showHiddenFilesSub': 'Mostrar archivos que empiezan con .',
      'terminalFontSize': 'Tamaño de fuente',
      'colorScheme': 'Esquema de colores',
      'colorSchemeSub': 'Tema de colores del terminal',
      // Run & Debug
      'rootfsPath': 'Ruta RootFS',
      'homePath': 'Ruta Home',
      'projectsPath': 'Ruta de proyectos',
      'installedSdks': 'SDKs instalados',
      'noSdksInstalled': 'No hay SDKs instalados',
      'installSdksSub': 'Instala SDKs desde el workspace',
      'lspPaths': 'Rutas LSP',
      'binaryPath': 'Ruta binaria',
      'installed': 'Instalado',
      // AI
      'apiKeys': 'Claves de API',
      'notConfigured': 'No configurado',
      'pasteApiKey': 'Pega tu clave de API aquí',
      'models': 'Modelos',
      'agents': 'Agentes',
      'newAgent': 'Nuevo agente',
      'defaultLabel': 'Predeterminado',
      'deleteAgent': 'Eliminar agente',
      'deleteAgentConfirm': '¿Eliminar %s? Esta acción no se puede deshacer.',
      'newAgentTitle': 'Nuevo Agente',
      'editAgentTitle': 'Editar Agente',
      'agentName': 'Nombre',
      'agentFocus': 'Área de enfoque',
      'agentInstructions': 'Instrucciones del sistema',
      // About
      'developer': 'Desarrollador',
      'supportedSdks': 'SDKs Soportados',
      'licenseLabel': 'Licencia',
      'mobileDevEnv': 'Entorno de Desarrollo Móvil',
      // Settings general
      'language': 'Idioma',
      'languageSub': 'Idioma de la aplicación',
      'followSystem': 'Seguir sistema',
      'appearance': 'Apariencia',
      'general': 'General',
      // Onboarding
      'permissions': 'Permisos',
      'permissionsSub': 'Algunos permisos son necesarios para el correcto funcionamiento de la app.',
      'environment': 'Entorno',
      'environmentSub': 'Bootstrap instala el entorno Linux necesario para compilar y ejecutar proyectos.',
      'finish': 'Finalizar',
      'next': 'Siguiente',
      'back': 'Atrás',
      'storage': 'Almacenamiento',
      'storageSub': 'Necesario para acceder y guardar proyectos en el dispositivo.',
      'installApps': 'Instalar apps',
      'installAppsSub': 'Necesario para instalar APKs generados por la app.',
      'granted': 'Concedido',
      'allow': 'Permitir',
      'installBootstrap': 'Instalar Bootstrap',
      'ready': 'Instalado',
    },
    'fr': {
      'cancel': 'Annuler',
      'confirm': 'Confirmer',
      'delete': 'Supprimer',
      'save': 'Enregistrer',
      'close': 'Fermer',
      'yes': 'Oui',
      'no': 'Non',
      'loading': 'Chargement...',
      'error': 'Erreur',
      'retry': 'Réessayer',
      'create': 'Créer',
      'edit': 'Modifier',
      'newProject': 'Nouveau projet',
      'newProjectSub': 'Créer un nouveau projet depuis un modèle',
      'openProject': 'Ouvrir un projet',
      'openProjectSub': 'Ouvrir un projet existant',
      'terminal': 'Terminal',
      'terminalSub': 'Ouvrir une session de terminal autonome',
      'settings': 'Paramètres',
      'settingsSub': 'Éditeur, apparence et extensions',
      'recentProjects': 'Projets récents',
      'noProjects': 'Aucun projet encore',
      'deleteProject': 'Supprimer le projet',
      'deleteProjectQ': 'Supprimer le projet ?',
      'deleteProjectSub': 'Cette action est irréversible. Les fichiers du projet seront supprimés définitivement.',
      'projectName': 'Nom du projet',
      'packageName': 'Nom du package',
      'selectSdk': 'Sélectionner le SDK',
      'createProject': 'Créer le projet',
      'creating': 'Création...',
      'noSdkInstalled': 'Aucun SDK installé. Installez d\'abord un SDK.',
      // Settings main menu
      'editor': 'Éditeur',
      'runDebug': 'Exécuter & Déboguer',
      'extensions': 'Extensions',
      'ai': 'IA',
      'about': 'À propos',
      'generalMenuSub': 'Apparence et comportement.',
      'editorMenuSub': 'Préférences de l\'éditeur.',
      'terminalMenuSub': 'Paramètres du terminal intégré.',
      'runDebugSub': 'SDKs et options de build.',
      'extensionsMenuSub': 'Thèmes et modules complémentaires.',
      'aiMenuSub': 'Clés API et agents.',
      'aboutMenuSub': 'Informations sur l\'application.',
      // General
      'secLangRegion': 'Langue & Région',
      'secThemeAppearance': 'Thème & Apparence',
      'followSystemTheme': 'Suivre le thème système',
      'followSystemOn': 'Thème système actif',
      'followSystemOff': 'Contrôle manuel du thème',
      'darkMode': 'Mode sombre',
      'darkModeOn': 'Thème sombre actif',
      'darkModeOff': 'Thème clair actif',
      'amoledBlack': 'Noir AMOLED',
      'amoledBlackSub': 'Fond noir pour écrans OLED',
      'dynamicColors': 'Couleurs dynamiques',
      'dynamicColorsSub': 'Couleurs Material You depuis le fond d\'écran',
      'themeActiveBanner': 'Thème %s actif',
      'themeActiveBannerSub': 'Les paramètres d\'apparence sont désactivés. Désactivez le thème dans Extensions pour utiliser les paramètres par défaut.',
      // Editor section headers
      'secFontDisplay': 'Police & Affichage',
      'secBehavior': 'Comportement',
      'secIndentation': 'Indentation',
      'secCursor': 'Curseur',
      'secCodeStructure': 'Structure du code',
      'secHighlight': 'Mise en surbrillance',
      'secAdvanced': 'Avancé',
      // Editor tiles
      'fontFamily': 'Famille de police',
      'fontSize': 'Taille de police',
      'lineNumbers': 'Numéros de ligne',
      'lineNumbersSub': 'Afficher les numéros de ligne',
      'fixedGutter': 'Gouttière fixe',
      'fixedGutterSub': 'Numéros fixes lors du défilement',
      'minimap': 'Minimap',
      'minimapSub': 'Panneau aperçu du code à droite',
      'symbolBar': 'Barre de symboles',
      'symbolBarSub': 'Raccourcis clavier mobile { } ; = …',
      'wordWrap': 'Retour à la ligne',
      'wordWrapSub': 'Adapter les longues lignes à la largeur',
      'autoIndent': 'Indentation auto',
      'autoIndentSub': 'Maintenir l\'indentation automatiquement',
      'autoClosePairs': 'Fermeture auto.',
      'autoClosePairsSub': 'Fermer automatiquement ( { [ " \'',
      'autoCompletion': 'Autocomplétion',
      'autoCompletionSub': 'Suggestions de code en cours de frappe',
      'formatOnSave': 'Formater à l\'enregistrement',
      'formatOnSaveSub': 'Appliquer DartFormatter à l\'enregistrement',
      'stickyScroll': 'Défilement collant',
      'stickyScrollSub': 'Garder la portée actuelle visible',
      'tabSize': 'Taille de tabulation',
      'tabSizeSub': 'Espaces par niveau d\'indentation',
      'useSpaces': 'Utiliser des espaces',
      'useSpacesSub': 'Insérer des espaces plutôt que des tabulations',
      'cursorBlinkSpeed': 'Vitesse de clignotement',
      'lightbulbActions': 'Actions ampoule',
      'lightbulbActionsSub': 'Icône d\'action rapide lors de la sélection',
      'foldArrows': 'Flèches de repliement',
      'foldArrowsSub': 'Flèches pour réduire les blocs',
      'blockLines': 'Lignes de bloc',
      'blockLinesSub': 'Guides verticaux d\'indentation',
      'indentDots': 'Points d\'indentation',
      'indentDotsSub': 'Points avant le premier caractère',
      'highlightCurrentLine': 'Surbriller la ligne courante',
      'highlightCurrentLineSub': 'Colorer la ligne du curseur',
      'highlightActiveBlock': 'Surbriller le bloc actif',
      'highlightActiveBlockSub': 'Changer la couleur dans la portée active',
      'highlightStyle': 'Style de surbrillance',
      'highlightStyleSub': 'Comment la ligne courante est surlignée',
      'diagnosticIndicators': 'Indicateurs de diagnostic',
      'diagnosticIndicatorsSub': 'Soulignements d\'erreur et d\'avertissement',
      'readOnly': 'Lecture seule',
      'readOnlySub': 'Désactiver toute édition',
      // Terminal / File Explorer
      'showHiddenFiles': 'Afficher les fichiers cachés',
      'showHiddenFilesSub': 'Afficher les fichiers commençant par .',
      'terminalFontSize': 'Taille de police',
      'colorScheme': 'Jeu de couleurs',
      'colorSchemeSub': 'Thème de couleurs du terminal',
      // Run & Debug
      'rootfsPath': 'Chemin RootFS',
      'homePath': 'Chemin Home',
      'projectsPath': 'Chemin des projets',
      'installedSdks': 'SDKs installés',
      'noSdksInstalled': 'Aucun SDK installé',
      'installSdksSub': 'Installez des SDKs depuis l\'espace de travail',
      'lspPaths': 'Chemins LSP',
      'binaryPath': 'Chemin du binaire',
      'installed': 'Installé',
      // AI
      'apiKeys': 'Clés API',
      'notConfigured': 'Non configuré',
      'pasteApiKey': 'Collez votre clé API ici',
      'models': 'Modèles',
      'agents': 'Agents',
      'newAgent': 'Nouvel agent',
      'defaultLabel': 'Par défaut',
      'deleteAgent': 'Supprimer l\'agent',
      'deleteAgentConfirm': 'Supprimer %s ? Cette action est irréversible.',
      'newAgentTitle': 'Nouvel Agent',
      'editAgentTitle': 'Modifier l\'Agent',
      'agentName': 'Nom',
      'agentFocus': 'Domaine de compétence',
      'agentInstructions': 'Instructions système',
      // About
      'developer': 'Développeur',
      'supportedSdks': 'SDKs Supportés',
      'licenseLabel': 'Licence',
      'mobileDevEnv': 'Environnement de développement mobile',
      // Settings general
      'language': 'Langue',
      'languageSub': 'Langue de l\'application',
      'followSystem': 'Suivre le système',
      'appearance': 'Apparence',
      'general': 'Général',
      // Onboarding
      'permissions': 'Autorisations',
      'permissionsSub': 'Certaines autorisations sont nécessaires au bon fonctionnement de l\'app.',
      'environment': 'Environnement',
      'environmentSub': 'Bootstrap installe l\'environnement Linux nécessaire pour compiler et exécuter des projets.',
      'finish': 'Terminer',
      'next': 'Suivant',
      'back': 'Retour',
      'storage': 'Stockage',
      'storageSub': 'Requis pour accéder et enregistrer des projets sur l\'appareil.',
      'installApps': 'Installer des apps',
      'installAppsSub': 'Requis pour installer les APKs générés par l\'app.',
      'granted': 'Accordé',
      'allow': 'Autoriser',
      'installBootstrap': 'Installer Bootstrap',
      'ready': 'Installé',
    },
    'de': {
      'cancel': 'Abbrechen',
      'confirm': 'Bestätigen',
      'delete': 'Löschen',
      'save': 'Speichern',
      'close': 'Schließen',
      'yes': 'Ja',
      'no': 'Nein',
      'loading': 'Laden...',
      'error': 'Fehler',
      'retry': 'Erneut versuchen',
      'create': 'Erstellen',
      'edit': 'Bearbeiten',
      'newProject': 'Neues Projekt',
      'newProjectSub': 'Ein neues Projekt aus einer Vorlage erstellen',
      'openProject': 'Projekt öffnen',
      'openProjectSub': 'Ein vorhandenes Projekt öffnen',
      'terminal': 'Terminal',
      'terminalSub': 'Eine eigenständige Terminal-Sitzung öffnen',
      'settings': 'Einstellungen',
      'settingsSub': 'Editor, Erscheinungsbild und Erweiterungen',
      'recentProjects': 'Letzte Projekte',
      'noProjects': 'Noch keine Projekte',
      'deleteProject': 'Projekt löschen',
      'deleteProjectQ': 'Projekt löschen?',
      'deleteProjectSub': 'Diese Aktion kann nicht rückgängig gemacht werden. Die Projektdateien werden dauerhaft entfernt.',
      'projectName': 'Projektname',
      'packageName': 'Paketname',
      'selectSdk': 'SDK auswählen',
      'createProject': 'Projekt erstellen',
      'creating': 'Erstellen...',
      'noSdkInstalled': 'Kein SDK installiert. Bitte zuerst ein SDK installieren.',
      // Settings main menu
      'editor': 'Editor',
      'runDebug': 'Ausführen & Debuggen',
      'extensions': 'Erweiterungen',
      'ai': 'KI',
      'about': 'Über',
      'generalMenuSub': 'Erscheinungsbild und Verhalten.',
      'editorMenuSub': 'Code-Editor-Einstellungen.',
      'terminalMenuSub': 'Einstellungen des integrierten Terminals.',
      'runDebugSub': 'SDKs und Build-Optionen.',
      'extensionsMenuSub': 'Themen und Add-ons.',
      'aiMenuSub': 'API-Schlüssel und Agenten.',
      'aboutMenuSub': 'App-Informationen.',
      // General
      'secLangRegion': 'Sprache & Region',
      'secThemeAppearance': 'Design & Erscheinungsbild',
      'followSystemTheme': 'Systemdesign folgen',
      'followSystemOn': 'Systemdesign wird verwendet',
      'followSystemOff': 'Manuelles Design',
      'darkMode': 'Dunkelmodus',
      'darkModeOn': 'Dunkles Design aktiv',
      'darkModeOff': 'Helles Design aktiv',
      'amoledBlack': 'AMOLED Schwarz',
      'amoledBlackSub': 'Reines Schwarz für OLED-Displays',
      'dynamicColors': 'Dynamische Farben',
      'dynamicColorsSub': 'Material You Farben vom Hintergrund',
      'themeActiveBanner': 'Design %s aktiv',
      'themeActiveBannerSub': 'Erscheinungsbild-Einstellungen sind deaktiviert. Deaktiviere das Design unter Erweiterungen.',
      // Editor section headers
      'secFontDisplay': 'Schrift & Anzeige',
      'secBehavior': 'Verhalten',
      'secIndentation': 'Einrückung',
      'secCursor': 'Cursor',
      'secCodeStructure': 'Codestruktur',
      'secHighlight': 'Hervorhebung',
      'secAdvanced': 'Erweitert',
      // Editor tiles
      'fontFamily': 'Schriftfamilie',
      'fontSize': 'Schriftgröße',
      'lineNumbers': 'Zeilennummern',
      'lineNumbersSub': 'Zeilennummern in der Randleiste anzeigen',
      'fixedGutter': 'Feste Randleiste',
      'fixedGutterSub': 'Zeilennummern beim Scrollen fixiert',
      'minimap': 'Minimap',
      'minimapSub': 'Codevorschau rechts',
      'symbolBar': 'Symbolleiste',
      'symbolBarSub': 'Mobile Tastaturhilfen { } ; = …',
      'wordWrap': 'Zeilenumbruch',
      'wordWrapSub': 'Lange Zeilen umbrechen',
      'autoIndent': 'Auto-Einrückung',
      'autoIndentSub': 'Einrückung automatisch beibehalten',
      'autoClosePairs': 'Paare auto. schließen',
      'autoClosePairsSub': 'Auto. schließen ( { [ " \'',
      'autoCompletion': 'Autovervollständigung',
      'autoCompletionSub': 'Codevorschläge beim Tippen',
      'formatOnSave': 'Beim Speichern formatieren',
      'formatOnSaveSub': 'DartFormatter beim Speichern anwenden',
      'stickyScroll': 'Festes Scrollen',
      'stickyScrollSub': 'Aktuellen Bereich oben anzeigen',
      'tabSize': 'Tab-Größe',
      'tabSizeSub': 'Leerzeichen pro Einrückung',
      'useSpaces': 'Leerzeichen verwenden',
      'useSpacesSub': 'Leerzeichen statt Tabulatoren einfügen',
      'cursorBlinkSpeed': 'Cursor-Blinkrate',
      'lightbulbActions': 'Glühbirnen-Aktionen',
      'lightbulbActionsSub': 'Schnellaktions-Symbol bei Auswahl',
      'foldArrows': 'Einklappungspfeile',
      'foldArrowsSub': 'Pfeile zum Einklappen von Codeblöcken',
      'blockLines': 'Blocklinien',
      'blockLinesSub': 'Vertikale Einrückungslinien',
      'indentDots': 'Einrückungspunkte',
      'indentDotsSub': 'Punkte vor dem ersten Zeichen',
      'highlightCurrentLine': 'Aktuelle Zeile hervorheben',
      'highlightCurrentLineSub': 'Cursorzeile einfärben',
      'highlightActiveBlock': 'Aktiven Block hervorheben',
      'highlightActiveBlockSub': 'Farbe im aktiven Bereich ändern',
      'highlightStyle': 'Hervorhebungsstil',
      'highlightStyleSub': 'Wie die aktuelle Zeile hervorgehoben wird',
      'diagnosticIndicators': 'Diagnose-Indikatoren',
      'diagnosticIndicatorsSub': 'Fehler- und Warnunterstriche',
      'readOnly': 'Schreibgeschützt',
      'readOnlySub': 'Alle Bearbeitungen deaktivieren',
      // Terminal / File Explorer
      'showHiddenFiles': 'Versteckte Dateien anzeigen',
      'showHiddenFilesSub': 'Dateien mit . anzeigen',
      'terminalFontSize': 'Schriftgröße',
      'colorScheme': 'Farbschema',
      'colorSchemeSub': 'Terminal-Farbdesign',
      // Run & Debug
      'rootfsPath': 'RootFS-Pfad',
      'homePath': 'Home-Pfad',
      'projectsPath': 'Projektepfad',
      'installedSdks': 'Installierte SDKs',
      'noSdksInstalled': 'Keine SDKs installiert',
      'installSdksSub': 'SDKs über den Arbeitsbereich installieren',
      'lspPaths': 'LSP-Pfade',
      'binaryPath': 'Binärpfad',
      'installed': 'Installiert',
      // AI
      'apiKeys': 'API-Schlüssel',
      'notConfigured': 'Nicht konfiguriert',
      'pasteApiKey': 'API-Schlüssel hier einfügen',
      'models': 'Modelle',
      'agents': 'Agenten',
      'newAgent': 'Neuer Agent',
      'defaultLabel': 'Standard',
      'deleteAgent': 'Agent löschen',
      'deleteAgentConfirm': '%s löschen? Diese Aktion kann nicht rückgängig gemacht werden.',
      'newAgentTitle': 'Neuer Agent',
      'editAgentTitle': 'Agent bearbeiten',
      'agentName': 'Name',
      'agentFocus': 'Schwerpunktbereich',
      'agentInstructions': 'Systemanweisungen',
      // About
      'developer': 'Entwickler',
      'supportedSdks': 'Unterstützte SDKs',
      'licenseLabel': 'Lizenz',
      'mobileDevEnv': 'Mobile Entwicklungsumgebung',
      // Settings general
      'language': 'Sprache',
      'languageSub': 'App-Sprache',
      'followSystem': 'System folgen',
      'appearance': 'Erscheinungsbild',
      'general': 'Allgemein',
      // Onboarding
      'permissions': 'Berechtigungen',
      'permissionsSub': 'Einige Berechtigungen sind für die korrekte Funktion der App erforderlich.',
      'environment': 'Umgebung',
      'environmentSub': 'Bootstrap installiert die Linux-Umgebung, die zum Erstellen und Ausführen von Projekten benötigt wird.',
      'finish': 'Fertigstellen',
      'next': 'Weiter',
      'back': 'Zurück',
      'storage': 'Speicher',
      'storageSub': 'Erforderlich für den Zugriff und das Speichern von Projekten auf dem Gerät.',
      'installApps': 'Apps installieren',
      'installAppsSub': 'Erforderlich zum Installieren von APKs, die von der App generiert werden.',
      'granted': 'Erteilt',
      'allow': 'Erlauben',
      'installBootstrap': 'Bootstrap installieren',
      'ready': 'Installiert',
    },
  };
}

/// Supported languages shown in the language picker.
const kSupportedLanguages = <({String code, String name, String native})>[
  (code: '',   name: 'System default',  native: 'Padrão do sistema'),
  (code: 'pt', name: 'Portuguese',      native: 'Português'),
  (code: 'en', name: 'English',         native: 'English'),
  (code: 'es', name: 'Spanish',         native: 'Español'),
  (code: 'fr', name: 'French',          native: 'Français'),
  (code: 'de', name: 'German',          native: 'Deutsch'),
];
