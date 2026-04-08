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
  String get liquidGlass        => _t('liquidGlass');
  String get liquidGlassSub     => _t('liquidGlassSub');
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
  String get editorStatusBar           => _t('editorStatusBar');
  String get editorStatusBarSub        => _t('editorStatusBarSub');
  String get editorStatusBarInfo       => _t('editorStatusBarInfo');
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

  // ── SSH ──────────────────────────────────────────────────────────────────
  String get ssh                   => _t('ssh');
  String get sshMenuSub            => _t('sshMenuSub');
  String get sshEnabled            => _t('sshEnabled');
  String get sshEnabledSub         => _t('sshEnabledSub');
  String get sshHost               => _t('sshHost');
  String get sshPort               => _t('sshPort');
  String get sshUsername           => _t('sshUsername');
  String get sshPassword           => _t('sshPassword');
  String get sshKeyPath            => _t('sshKeyPath');
  String get sshUseKey             => _t('sshUseKey');
  String get sshPasswordAuth       => _t('sshPasswordAuth');
  String get sshKeyAuth            => _t('sshKeyAuth');
  String get sshRemoteProjectsPath => _t('sshRemoteProjectsPath');
  String get sshTestConnection     => _t('sshTestConnection');
  String get sshConnecting         => _t('sshConnecting');
  String get sshConnected          => _t('sshConnected');
  String get sshDisconnected       => _t('sshDisconnected');
  String get sshConnectionFailed   => _t('sshConnectionFailed');
  String get sshSection            => _t('sshSection');

  // ── Settings: About ───────────────────────────────────────────────────────
  String get developer         => _t('developer');
  String get supportedSdks     => _t('supportedSdks');
  String get licenseLabel      => _t('licenseLabel');
  String get mobileDevEnv      => _t('mobileDevEnv');

  // ── Extensions screen ─────────────────────────────────────────────────────
  String get extStore             => _t('extStore');
  String get extSdks              => _t('extSdks');
  String get extInstalledTab      => _t('extInstalledTab');
  String get extDarkThemes        => _t('extDarkThemes');
  String get extLightThemes       => _t('extLightThemes');
  String get extActiveTheme       => _t('extActiveTheme');
  String get extInstalledSection  => _t('extInstalledSection');
  String get extNoThemes          => _t('extNoThemes');
  String get extNoSdks            => _t('extNoSdks');
  String get extNoExtensions      => _t('extNoExtensions');
  String get extGoToStore         => _t('extGoToStore');
  String get extActivate          => _t('extActivate');
  String get extDeactivate        => _t('extDeactivate');
  String get extInstall           => _t('extInstall');
  String get extUninstall         => _t('extUninstall');
  String get extUpdate            => _t('extUpdate');
  String get extActive            => _t('extActive');
  String get extDarkThemeLabel    => _t('extDarkThemeLabel');
  String get extLightThemeLabel   => _t('extLightThemeLabel');
  String get extInstallQ          => _t('extInstallQ');
  String get extInstallBody       => _t('extInstallBody');
  String get extDeleteQ           => _t('extDeleteQ');
  String get extDeleteBody        => _t('extDeleteBody');
  String get extInstalled2        => _t('extInstalled2');

  // ── Workspace peek bar ────────────────────────────────────────────────────
  String get peekCreatingProject  => _t('peekCreatingProject');
  String get peekLoadingProject   => _t('peekLoadingProject');
  String get peekStartingLsp      => _t('peekStartingLsp');
  String get peekSyncingDeps      => _t('peekSyncingDeps');
  String get peekReady            => _t('peekReady');
  String get peekSwipeUp          => _t('peekSwipeUp');

  // ── Workspace sync banner ─────────────────────────────────────────────────
  String syncBannerMsg(String cmd)  => _t('syncBannerMsg').replaceFirst('%s', cmd);
  String get syncBannerIgnore       => _t('syncBannerIgnore');
  String get syncBannerRun          => _t('syncBannerRun');

  // ── Workspace dialogs / menus ─────────────────────────────────────────────
  String get wsCloseProject       => _t('wsCloseProject');
  String get wsCloseProjectQ      => _t('wsCloseProjectQ');
  String get wsCloseProjectBody   => _t('wsCloseProjectBody');
  String get wsCloseYes           => _t('wsCloseYes');
  String get wsUndo               => _t('wsUndo');
  String get wsRedo               => _t('wsRedo');
  String get wsSyncProject        => _t('wsSyncProject');
  String get wsSearchInFile       => _t('wsSearchInFile');
  String get wsCommands           => _t('wsCommands');
  String get wsHotReload          => _t('wsHotReload');
  String get wsHotRestart         => _t('wsHotRestart');

  // ── Settings: info dialog ─────────────────────────────────────────────────
  String get settingInfoTitle          => _t('settingInfoTitle');
  // General info
  String get followSystemThemeInfo     => _t('followSystemThemeInfo');
  String get darkModeInfo              => _t('darkModeInfo');
  String get amoledBlackInfo           => _t('amoledBlackInfo');
  String get dynamicColorsInfo         => _t('dynamicColorsInfo');
  String get liquidGlassInfo           => _t('liquidGlassInfo');
  String get languageInfo              => _t('languageInfo');
  // Editor font & display info
  String get fontFamilyInfo            => _t('fontFamilyInfo');
  String get fontSizeInfo              => _t('fontSizeInfo');
  String get lineNumbersInfo           => _t('lineNumbersInfo');
  String get fixedGutterInfo           => _t('fixedGutterInfo');
  String get minimapInfo               => _t('minimapInfo');
  String get symbolBarInfo             => _t('symbolBarInfo');
  // Editor behavior info
  String get wordWrapInfo              => _t('wordWrapInfo');
  String get autoIndentInfo            => _t('autoIndentInfo');
  String get autoClosePairsInfo        => _t('autoClosePairsInfo');
  String get autoCompletionInfo        => _t('autoCompletionInfo');
  String get formatOnSaveInfo          => _t('formatOnSaveInfo');
  String get stickyScrollInfo          => _t('stickyScrollInfo');
  // Editor indentation info
  String get tabSizeInfo               => _t('tabSizeInfo');
  String get useSpacesInfo             => _t('useSpacesInfo');
  // Editor cursor info
  String get cursorBlinkSpeedInfo      => _t('cursorBlinkSpeedInfo');
  // Editor code structure info
  String get lightbulbActionsInfo      => _t('lightbulbActionsInfo');
  String get foldArrowsInfo            => _t('foldArrowsInfo');
  String get blockLinesInfo            => _t('blockLinesInfo');
  String get indentDotsInfo            => _t('indentDotsInfo');
  // Editor highlight info
  String get highlightCurrentLineInfo  => _t('highlightCurrentLineInfo');
  String get highlightActiveBlockInfo  => _t('highlightActiveBlockInfo');
  String get highlightStyleInfo        => _t('highlightStyleInfo');
  // Editor advanced info
  String get diagnosticIndicatorsInfo  => _t('diagnosticIndicatorsInfo');
  String get readOnlyInfo              => _t('readOnlyInfo');

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
      // SSH
      'ssh': 'SSH Remoto',
      'sshMenuSub': 'Conectar ao PC remoto via SSH',
      'sshEnabled': 'Ativar modo SSH',
      'sshEnabledSub': 'Usar PC remoto em vez dos SDKs locais',
      'sshHost': 'Host / Endereço IP',
      'sshPort': 'Porta',
      'sshUsername': 'Usuário',
      'sshPassword': 'Senha',
      'sshKeyPath': 'Caminho da chave privada',
      'sshUseKey': 'Usar autenticação por chave',
      'sshPasswordAuth': 'Senha',
      'sshKeyAuth': 'Chave SSH',
      'sshRemoteProjectsPath': 'Caminho remoto dos projetos',
      'sshTestConnection': 'Testar Conexão',
      'sshConnecting': 'Conectando...',
      'sshConnected': 'Conectado',
      'sshDisconnected': 'Desconectado',
      'sshConnectionFailed': 'Falha na conexão',
      'sshSection': 'Conexão SSH',
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
      'liquidGlass': 'Liquid Glass',
      'liquidGlassSub': 'Efeito de vidro líquido em barras e painéis',
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
      'editorStatusBar': 'Barra de status do editor',
      'editorStatusBarSub': 'Linha, coluna e total de linhas',
      'editorStatusBarInfo': 'Exibe a barra inferior do editor que mostra a linha atual, coluna e total de linhas do arquivo.',
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
      // Extensions
      'extStore': 'Loja',
      'extSdks': 'SDKs',
      'extInstalledTab': 'Instalados',
      'extDarkThemes': 'Temas Escuros',
      'extLightThemes': 'Temas Claros',
      'extActiveTheme': 'Tema Ativo',
      'extInstalledSection': 'Instalados',
      'extNoThemes': 'Nenhum tema disponível.',
      'extNoSdks': 'Nenhum SDK disponível.',
      'extNoExtensions': 'Nenhuma extensão instalada ainda.',
      'extGoToStore': 'Acesse a Loja para instalar temas.',
      'extActivate': 'Ativar tema',
      'extDeactivate': 'Desativar tema',
      'extInstall': 'Instalar',
      'extUninstall': 'Desinstalar',
      'extUpdate': 'Atualizar',
      'extActive': 'Ativo',
      'extDarkThemeLabel': 'Tema escuro',
      'extLightThemeLabel': 'Tema claro',
      'extInstallQ': 'Instalar tema?',
      'extInstallBody': 'O tema será salvo no seu dispositivo.',
      'extDeleteQ': 'Excluir tema?',
      'extDeleteBody': 'O tema será removido do seu dispositivo.',
      'extInstalled2': 'Instalado',
      // Workspace peek bar
      'peekCreatingProject': 'Criando projeto...',
      'peekLoadingProject': 'Carregando projeto...',
      'peekStartingLsp': 'Carregando LSP...',
      'peekSyncingDeps': 'Instalando dependências...',
      'peekReady': 'Projeto pronto',
      'peekSwipeUp': 'Deslize para cima para acessar o terminal',
      // Workspace sync banner
      'syncBannerMsg': 'Instalar dependências com "%s"?',
      'syncBannerIgnore': 'Ignorar',
      'syncBannerRun': 'Instalar',
      // Workspace dialogs / menus
      'wsCloseProject': 'Fechar projeto',
      'wsCloseProjectQ': 'Fechar projeto?',
      'wsCloseProjectBody': 'Tem certeza que deseja fechar o projeto atual? Alterações não salvas serão perdidas.',
      'wsCloseYes': 'Sim, fechar',
      'wsUndo': 'Desfazer',
      'wsRedo': 'Refazer',
      'wsSyncProject': 'Sincronizar projeto',
      'wsSearchInFile': 'Pesquisar no arquivo…',
      'wsCommands': 'Comandos',
      'wsHotReload': 'Hot Reload',
      'wsHotRestart': 'Hot Restart',
      // Setting info dialog
      'settingInfoTitle': 'Sobre esta configuração',
      'followSystemThemeInfo': 'Quando ativado, o app muda automaticamente entre os temas claro e escuro conforme a preferência do sistema. Desativar permite escolher manualmente o tema.',
      'darkModeInfo': 'Alterna o app para uma paleta de cores escuras. Disponível apenas quando "Seguir tema do sistema" está desativado.',
      'amoledBlackInfo': 'Substitui o fundo do tema escuro por preto puro (#000000). Reduz o consumo de energia em telas OLED/AMOLED.',
      'dynamicColorsInfo': 'Usa cores dinâmicas Material You extraídas do papel de parede (Android 12+). Aplica cores de destaque em todo o app.',
      'liquidGlassInfo': 'Ativa o efeito de refração de vidro acelerado por GPU na barra de apps, painel inferior e drawer. Requer o renderizador Impeller.',
      'languageInfo': 'Altera o idioma de exibição de todo o app. Pode ser necessário reiniciar o app em alguns dispositivos.',
      'fontFamilyInfo': 'Define a fonte usada no editor de código. Fontes monoespaçadas são recomendadas para melhor legibilidade do código.',
      'fontSizeInfo': 'Controla o tamanho do texto no editor em pixels. Valores maiores melhoram a legibilidade; menores mostram mais código de uma vez.',
      'lineNumbersInfo': 'Exibe os números de linha na margem esquerda do editor. Útil para navegar e referenciar linhas específicas.',
      'fixedGutterInfo': 'Quando ativado, a coluna de números de linha permanece fixada ao rolar horizontalmente, para que você sempre saiba em qual linha está.',
      'minimapInfo': 'Mostra uma prévia em miniatura do arquivo inteiro no lado direito do editor, permitindo navegação rápida pelo código.',
      'symbolBarInfo': 'Adiciona uma barra de símbolos acima do teclado com caracteres comuns de programação como { } ; = que são difíceis de digitar no celular.',
      'wordWrapInfo': 'Quebra linhas longas para que caibam na largura do editor. Desativar permite que as linhas se estendam além da tela com rolagem horizontal.',
      'autoIndentInfo': 'Mantém automaticamente o nível de indentação correto ao pressionar Enter, correspondendo à indentação da linha atual.',
      'autoClosePairsInfo': 'Insere automaticamente o fechamento de colchetes ou aspas ao digitar um de abertura: ( → (), { → {}, [ → [], " → "".',
      'autoCompletionInfo': 'Mostra um popup de sugestões ao digitar, oferecendo completions baseadas no servidor de linguagem e no contexto do arquivo.',
      'formatOnSaveInfo': 'Executa automaticamente o formatador de código (ex. DartFormatter) ao salvar um arquivo, mantendo o estilo consistente.',
      'stickyScrollInfo': 'Fixa o cabeçalho da classe, função ou bloco atual no topo do editor ao rolar, para que você sempre saiba em qual escopo está.',
      'tabSizeInfo': 'Define quantos espaços representam um nível de indentação. Valores comuns são 2 (web/TypeScript) e 4 (Python/Java).',
      'useSpacesInfo': 'Quando ativado, pressionar Tab insere espaços em vez de um caractere de tabulação real (\\t).',
      'cursorBlinkSpeedInfo': 'Controla o intervalo em milissegundos entre os ciclos de piscar do cursor. Valores menores piscam mais rápido; maiores, mais devagar.',
      'lightbulbActionsInfo': 'Exibe um ícone de lâmpada ao selecionar código, oferecendo ações rápidas como refatoração, correções e importações automáticas.',
      'foldArrowsInfo': 'Exibe setas de recolher/expandir ao lado de blocos de código (funções, classes, ifs) para ocultar seções do código.',
      'blockLinesInfo': 'Desenha linhas guias verticais que mostram a estrutura de indentação do código, ajudando a visualizar os limites dos blocos.',
      'indentDotsInfo': 'Exibe pequenos pontos em cada nível de indentação antes do primeiro caractere, tornando a profundidade de indentação mais visível.',
      'highlightCurrentLineInfo': 'Aplica um fundo sutil na linha onde o cursor de texto está posicionado, facilitando a localização do cursor.',
      'highlightActiveBlockInfo': 'Muda a cor de fundo de todo o bloco de código (função, classe, etc.) que contém o cursor.',
      'highlightStyleInfo': '"fill" colore a linha inteira; "stroke" desenha uma borda; "accentBar" adiciona uma barra colorida à esquerda; "none" desativa o destaque.',
      'diagnosticIndicatorsInfo': 'Mostra sublinhados ondulados em código com erros (vermelho) ou avisos (amarelo), fornecidos pelo servidor de linguagem.',
      'readOnlyInfo': 'Quando ativado, toda edição é desabilitada — o arquivo é exibido mas não pode ser modificado. Útil para visualizar logs ou arquivos de referência.',
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
      // SSH
      'ssh': 'SSH Remote',
      'sshMenuSub': 'Connect to remote PC via SSH',
      'sshEnabled': 'Enable SSH mode',
      'sshEnabledSub': 'Use remote PC instead of local SDKs',
      'sshHost': 'Host / IP address',
      'sshPort': 'Port',
      'sshUsername': 'Username',
      'sshPassword': 'Password',
      'sshKeyPath': 'Private key path',
      'sshUseKey': 'Use key authentication',
      'sshPasswordAuth': 'Password',
      'sshKeyAuth': 'SSH Key',
      'sshRemoteProjectsPath': 'Remote projects path',
      'sshTestConnection': 'Test Connection',
      'sshConnecting': 'Connecting...',
      'sshConnected': 'Connected',
      'sshDisconnected': 'Not connected',
      'sshConnectionFailed': 'Connection failed',
      'sshSection': 'SSH Connection',
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
      'liquidGlass': 'Liquid Glass',
      'liquidGlassSub': 'Liquid glass effect on bars and panels',
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
      'editorStatusBar': 'Editor Status Bar',
      'editorStatusBarSub': 'Line, column and total lines',
      'editorStatusBarInfo': 'Shows the bottom bar of the editor displaying current line, column and total line count.',
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
      // Extensions
      'extStore': 'Store',
      'extSdks': 'SDKs',
      'extInstalledTab': 'Installed',
      'extDarkThemes': 'Dark Themes',
      'extLightThemes': 'Light Themes',
      'extActiveTheme': 'Active Theme',
      'extInstalledSection': 'Installed',
      'extNoThemes': 'No themes available.',
      'extNoSdks': 'No SDKs available.',
      'extNoExtensions': 'No extensions installed yet.',
      'extGoToStore': 'Go to Store to install themes.',
      'extActivate': 'Activate theme',
      'extDeactivate': 'Deactivate theme',
      'extInstall': 'Install',
      'extUninstall': 'Uninstall',
      'extUpdate': 'Update',
      'extActive': 'Active',
      'extDarkThemeLabel': 'Dark theme',
      'extLightThemeLabel': 'Light theme',
      'extInstallQ': 'Install theme?',
      'extInstallBody': 'The theme will be saved to your device.',
      'extDeleteQ': 'Delete theme?',
      'extDeleteBody': 'The theme will be removed from your device.',
      'extInstalled2': 'Installed',
      // Workspace peek bar
      'peekCreatingProject': 'Creating project...',
      'peekLoadingProject': 'Loading project...',
      'peekStartingLsp': 'Starting LSP...',
      'peekSyncingDeps': 'Installing dependencies...',
      'peekReady': 'Project ready',
      'peekSwipeUp': 'Swipe up to access the terminal',
      // Workspace sync banner
      'syncBannerMsg': 'Install dependencies with "%s"?',
      'syncBannerIgnore': 'Ignore',
      'syncBannerRun': 'Install',
      // Workspace dialogs / menus
      'wsCloseProject': 'Close project',
      'wsCloseProjectQ': 'Close project?',
      'wsCloseProjectBody': 'Are you sure you want to close the current project? Any unsaved changes will be lost.',
      'wsCloseYes': 'Yes, close',
      'wsUndo': 'Undo',
      'wsRedo': 'Redo',
      'wsSyncProject': 'Sync project',
      'wsSearchInFile': 'Search in file…',
      'wsCommands': 'Commands',
      'wsHotReload': 'Hot Reload',
      'wsHotRestart': 'Hot Restart',
      // Setting info dialog
      'settingInfoTitle': 'About this setting',
      'followSystemThemeInfo': 'When enabled, the app automatically switches between light and dark themes based on your device\'s system preference. Disabling this lets you manually choose the theme.',
      'darkModeInfo': 'Switches the app to a dark color palette. Only available when "Follow System Theme" is disabled.',
      'amoledBlackInfo': 'Replaces the dark theme background with pure black (#000000). Reduces power consumption on OLED/AMOLED screens.',
      'dynamicColorsInfo': 'Uses Material You dynamic colors extracted from your wallpaper (Android 12+). Applies accent colors throughout the app.',
      'liquidGlassInfo': 'Enables a GPU-accelerated glass refraction effect on the app bar, bottom sheet, and drawer. Requires the Impeller renderer.',
      'languageInfo': 'Changes the display language of the entire app. May require an app restart on some devices.',
      'fontFamilyInfo': 'Selects the font used in the code editor. Monospace fonts are recommended for code readability.',
      'fontSizeInfo': 'Controls the size of text in the code editor in pixels. Larger values improve readability; smaller values show more code at once.',
      'lineNumbersInfo': 'Displays line numbers in the left margin of the editor. Useful for navigation and referencing specific lines.',
      'fixedGutterInfo': 'When enabled, the line number column stays fixed while you scroll horizontally, so you always see which line you\'re on.',
      'minimapInfo': 'Shows a miniature preview of your entire file on the right side of the editor, allowing quick navigation through the code.',
      'symbolBarInfo': 'Adds a toolbar above the keyboard with common programming symbols like { } ; = that are hard to type on mobile.',
      'wordWrapInfo': 'Wraps long lines so they fit within the editor width. Disabling this lets lines extend beyond the screen with horizontal scrolling.',
      'autoIndentInfo': 'Automatically maintains the correct indentation level when you press Enter, matching the indentation of the current line.',
      'autoClosePairsInfo': 'Automatically inserts the closing bracket or quote when you type an opening one: ( → (), { → {}, [ → [], " → "".',
      'autoCompletionInfo': 'Shows a suggestion popup while you type, offering completions based on the language server and current file context.',
      'formatOnSaveInfo': 'Automatically runs the language formatter (e.g. DartFormatter) every time you save a file, keeping code style consistent.',
      'stickyScrollInfo': 'Pins the enclosing class, function or block header at the top of the editor viewport as you scroll, so you always know your current scope.',
      'tabSizeInfo': 'Sets how many spaces represent one indentation level. Common values are 2 (web/TypeScript) and 4 (Python/Java).',
      'useSpacesInfo': 'When enabled, pressing Tab inserts spaces instead of a real tab character (\\t).',
      'cursorBlinkSpeedInfo': 'Controls the interval in milliseconds between cursor blink cycles. Lower values blink faster; higher values blink slower.',
      'lightbulbActionsInfo': 'Shows a lightbulb icon when code is selected, offering quick actions like refactoring, code fixes, and automatic imports.',
      'foldArrowsInfo': 'Displays collapse/expand arrows next to code blocks (functions, classes, if-blocks) so you can hide sections of code.',
      'blockLinesInfo': 'Draws vertical guide lines that show the indentation structure of the code, helping you see block boundaries.',
      'indentDotsInfo': 'Shows small dots at each indent level before the first character, making indentation depth more visible.',
      'highlightCurrentLineInfo': 'Applies a subtle background tint to the line where the text cursor is currently positioned.',
      'highlightActiveBlockInfo': 'Changes the background color of the entire code block (function, class, etc.) that contains the cursor.',
      'highlightStyleInfo': '"fill" colors the whole line; "stroke" draws a border; "accentBar" adds a colored bar on the left; "none" disables highlighting.',
      'diagnosticIndicatorsInfo': 'Shows wavy underlines under code that has errors (red) or warnings (yellow), provided by the language server.',
      'readOnlyInfo': 'When enabled, all editing is disabled — the file is displayed but cannot be modified. Useful for viewing logs or reference files.',
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
      'liquidGlass': 'Liquid Glass',
      'liquidGlassSub': 'Efecto de vidrio líquido en barras y paneles',
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
      // Extensions
      'extStore': 'Tienda',
      'extSdks': 'SDKs',
      'extInstalledTab': 'Instalados',
      'extDarkThemes': 'Temas Oscuros',
      'extLightThemes': 'Temas Claros',
      'extActiveTheme': 'Tema Activo',
      'extInstalledSection': 'Instalados',
      'extNoThemes': 'No hay temas disponibles.',
      'extNoSdks': 'No hay SDKs disponibles.',
      'extNoExtensions': 'No hay extensiones instaladas.',
      'extGoToStore': 'Ve a la Tienda para instalar temas.',
      'extActivate': 'Activar tema',
      'extDeactivate': 'Desactivar tema',
      'extInstall': 'Instalar',
      'extUninstall': 'Desinstalar',
      'extUpdate': 'Actualizar',
      'extActive': 'Activo',
      'extDarkThemeLabel': 'Tema oscuro',
      'extLightThemeLabel': 'Tema claro',
      'extInstallQ': '¿Instalar tema?',
      'extInstallBody': 'El tema se guardará en tu dispositivo.',
      'extDeleteQ': '¿Eliminar tema?',
      'extDeleteBody': 'El tema se eliminará de tu dispositivo.',
      'extInstalled2': 'Instalado',
      // Workspace peek bar
      'peekCreatingProject': 'Creando proyecto...',
      'peekLoadingProject': 'Cargando proyecto...',
      'peekStartingLsp': 'Iniciando LSP...',
      'peekSyncingDeps': 'Instalando dependencias...',
      'peekReady': 'Proyecto listo',
      'peekSwipeUp': 'Desliza hacia arriba para acceder al terminal',
      // Workspace sync banner
      'syncBannerMsg': '¿Instalar dependencias con "%s"?',
      'syncBannerIgnore': 'Ignorar',
      'syncBannerRun': 'Instalar',
      // Workspace dialogs / menus
      'wsCloseProject': 'Cerrar proyecto',
      'wsCloseProjectQ': '¿Cerrar proyecto?',
      'wsCloseProjectBody': '¿Estás seguro de que deseas cerrar el proyecto actual? Los cambios no guardados se perderán.',
      'wsCloseYes': 'Sí, cerrar',
      'wsUndo': 'Deshacer',
      'wsRedo': 'Rehacer',
      'wsSyncProject': 'Sincronizar proyecto',
      'wsSearchInFile': 'Buscar en archivo…',
      'wsCommands': 'Comandos',
      'wsHotReload': 'Hot Reload',
      'wsHotRestart': 'Hot Restart',
      // Setting info dialog
      'settingInfoTitle': 'Acerca de este ajuste',
      'followSystemThemeInfo': 'Al activarlo, la app cambia automáticamente entre temas claro y oscuro según la preferencia del sistema. Desactivarlo permite elegir el tema manualmente.',
      'darkModeInfo': 'Cambia la app a una paleta de colores oscuros. Solo disponible cuando "Seguir tema del sistema" está desactivado.',
      'amoledBlackInfo': 'Reemplaza el fondo del tema oscuro con negro puro (#000000). Reduce el consumo de energía en pantallas OLED/AMOLED.',
      'dynamicColorsInfo': 'Usa los colores dinámicos Material You extraídos del fondo de pantalla (Android 12+). Aplica colores de acento en toda la app.',
      'liquidGlassInfo': 'Activa el efecto de refracción de vidrio acelerado por GPU en la barra de apps, panel inferior y drawer.',
      'languageInfo': 'Cambia el idioma de visualización de toda la app. Puede requerir reiniciar la app en algunos dispositivos.',
      'fontFamilyInfo': 'Selecciona la fuente utilizada en el editor de código. Se recomiendan fuentes monoespaciadas para mayor legibilidad.',
      'fontSizeInfo': 'Controla el tamaño del texto en el editor en píxeles. Valores mayores mejoran la legibilidad; menores muestran más código a la vez.',
      'lineNumbersInfo': 'Muestra los números de línea en el margen izquierdo del editor. Útil para navegar y referenciar líneas específicas.',
      'fixedGutterInfo': 'Cuando está activado, la columna de números de línea permanece fija al desplazarse horizontalmente.',
      'minimapInfo': 'Muestra una vista previa en miniatura del archivo completo en el lado derecho del editor, permitiendo navegación rápida.',
      'symbolBarInfo': 'Añade una barra de símbolos sobre el teclado con caracteres comunes de programación como { } ; = difíciles de escribir en móvil.',
      'wordWrapInfo': 'Ajusta las líneas largas para que quepan en el ancho del editor. Desactivarlo permite que las líneas se extiendan más allá de la pantalla.',
      'autoIndentInfo': 'Mantiene automáticamente el nivel de sangría correcto al presionar Enter, según la sangría de la línea actual.',
      'autoClosePairsInfo': 'Inserta automáticamente el cierre de paréntesis o comillas al escribir el de apertura: ( → (), { → {}, [ → [], " → "".',
      'autoCompletionInfo': 'Muestra un menú de sugerencias mientras escribes, basado en el servidor de lenguaje y el contexto del archivo.',
      'formatOnSaveInfo': 'Ejecuta automáticamente el formateador de código al guardar un archivo, manteniendo un estilo consistente.',
      'stickyScrollInfo': 'Fija el encabezado del bloque actual en la parte superior del editor al desplazarse, para saber siempre en qué ámbito estás.',
      'tabSizeInfo': 'Define cuántos espacios representan un nivel de sangría. Valores comunes son 2 (web/TypeScript) y 4 (Python/Java).',
      'useSpacesInfo': 'Al activarlo, Tab inserta espacios en lugar de un carácter de tabulación real (\\t).',
      'cursorBlinkSpeedInfo': 'Controla el intervalo en milisegundos entre los ciclos de parpadeo del cursor.',
      'lightbulbActionsInfo': 'Muestra un icono de bombilla al seleccionar código, con acciones rápidas como refactorización, correcciones e importaciones.',
      'foldArrowsInfo': 'Muestra flechas de colapso junto a bloques de código (funciones, clases, ifs) para ocultar secciones.',
      'blockLinesInfo': 'Dibuja líneas guía verticales que muestran la estructura de sangría del código, ayudando a ver los límites de los bloques.',
      'indentDotsInfo': 'Muestra pequeños puntos en cada nivel de sangría antes del primer carácter, haciendo la profundidad de sangría más visible.',
      'highlightCurrentLineInfo': 'Aplica un fondo sutil en la línea donde se encuentra el cursor de texto.',
      'highlightActiveBlockInfo': 'Cambia el color de fondo de todo el bloque de código (función, clase, etc.) que contiene el cursor.',
      'highlightStyleInfo': '"fill" colorea la línea; "stroke" dibuja un borde; "accentBar" añade una barra coloreada a la izquierda; "none" desactiva.',
      'diagnosticIndicatorsInfo': 'Muestra subrayados ondulados en código con errores (rojo) o advertencias (amarillo), proporcionados por el servidor de lenguaje.',
      'readOnlyInfo': 'Al activarlo, toda edición queda deshabilitada — el archivo se muestra pero no puede modificarse. Útil para ver logs o archivos de referencia.',
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
      'liquidGlass': 'Liquid Glass',
      'liquidGlassSub': 'Effet verre liquide sur les barres et panneaux',
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
      // Extensions
      'extStore': 'Boutique',
      'extSdks': 'SDKs',
      'extInstalledTab': 'Installés',
      'extDarkThemes': 'Thèmes Sombres',
      'extLightThemes': 'Thèmes Clairs',
      'extActiveTheme': 'Thème Actif',
      'extInstalledSection': 'Installés',
      'extNoThemes': 'Aucun thème disponible.',
      'extNoSdks': 'Aucun SDK disponible.',
      'extNoExtensions': 'Aucune extension installée.',
      'extGoToStore': 'Allez dans la Boutique pour installer des thèmes.',
      'extActivate': 'Activer le thème',
      'extDeactivate': 'Désactiver le thème',
      'extInstall': 'Installer',
      'extUninstall': 'Désinstaller',
      'extUpdate': 'Mettre à jour',
      'extActive': 'Actif',
      'extDarkThemeLabel': 'Thème sombre',
      'extLightThemeLabel': 'Thème clair',
      'extInstallQ': 'Installer le thème ?',
      'extInstallBody': 'Le thème sera enregistré sur votre appareil.',
      'extDeleteQ': 'Supprimer le thème ?',
      'extDeleteBody': 'Le thème sera supprimé de votre appareil.',
      'extInstalled2': 'Installé',
      // Workspace peek bar
      'peekCreatingProject': 'Création du projet...',
      'peekLoadingProject': 'Chargement du projet...',
      'peekStartingLsp': 'Démarrage du LSP...',
      'peekSyncingDeps': 'Installation des dépendances...',
      'peekReady': 'Projet prêt',
      'peekSwipeUp': 'Glissez vers le haut pour accéder au terminal',
      // Workspace sync banner
      'syncBannerMsg': 'Installer les dépendances avec "%s" ?',
      'syncBannerIgnore': 'Ignorer',
      'syncBannerRun': 'Installer',
      // Workspace dialogs / menus
      'wsCloseProject': 'Fermer le projet',
      'wsCloseProjectQ': 'Fermer le projet ?',
      'wsCloseProjectBody': 'Voulez-vous vraiment fermer le projet en cours ? Les modifications non enregistrées seront perdues.',
      'wsCloseYes': 'Oui, fermer',
      'wsUndo': 'Annuler',
      'wsRedo': 'Rétablir',
      'wsSyncProject': 'Synchroniser le projet',
      'wsSearchInFile': 'Rechercher dans le fichier…',
      'wsCommands': 'Commandes',
      'wsHotReload': 'Hot Reload',
      'wsHotRestart': 'Hot Restart',
      // Setting info dialog
      'settingInfoTitle': 'À propos de ce paramètre',
      'followSystemThemeInfo': 'Lorsqu\'il est activé, l\'app bascule automatiquement entre thèmes clair et sombre selon la préférence du système. Désactiver permet de choisir manuellement.',
      'darkModeInfo': 'Bascule l\'app vers une palette de couleurs sombres. Disponible uniquement si "Suivre le thème système" est désactivé.',
      'amoledBlackInfo': 'Remplace le fond sombre par du noir pur (#000000). Réduit la consommation d\'énergie sur les écrans OLED/AMOLED.',
      'dynamicColorsInfo': 'Utilise les couleurs dynamiques Material You extraites du fond d\'écran (Android 12+). Applique des couleurs d\'accentuation dans toute l\'app.',
      'liquidGlassInfo': 'Active l\'effet de réfraction de verre accéléré par GPU sur la barre d\'apps, le panneau inférieur et le tiroir.',
      'languageInfo': 'Change la langue d\'affichage de toute l\'app. Peut nécessiter un redémarrage de l\'app sur certains appareils.',
      'fontFamilyInfo': 'Sélectionne la police utilisée dans l\'éditeur de code. Les polices mono-espacées sont recommandées pour la lisibilité du code.',
      'fontSizeInfo': 'Contrôle la taille du texte dans l\'éditeur en pixels. Des valeurs plus grandes améliorent la lisibilité; des plus petites montrent plus de code à la fois.',
      'lineNumbersInfo': 'Affiche les numéros de ligne dans la marge gauche de l\'éditeur. Utile pour naviguer et référencer des lignes spécifiques.',
      'fixedGutterInfo': 'Lorsqu\'il est activé, la colonne de numéros de ligne reste fixe lors du défilement horizontal.',
      'minimapInfo': 'Affiche un aperçu miniature du fichier entier sur le côté droit de l\'éditeur, permettant une navigation rapide.',
      'symbolBarInfo': 'Ajoute une barre de symboles au-dessus du clavier avec des caractères de programmation courants comme { } ; = difficiles à saisir sur mobile.',
      'wordWrapInfo': 'Coupe les longues lignes pour qu\'elles s\'adaptent à la largeur de l\'éditeur. Désactiver permet un défilement horizontal.',
      'autoIndentInfo': 'Maintient automatiquement le niveau d\'indentation correct en appuyant sur Entrée, selon l\'indentation de la ligne actuelle.',
      'autoClosePairsInfo': 'Insère automatiquement la fermeture des parenthèses ou guillemets lors de la saisie de l\'ouverture: ( → (), { → {}, [ → [], " → "".',
      'autoCompletionInfo': 'Affiche un menu de suggestions pendant la saisie, basé sur le serveur de langage et le contexte du fichier.',
      'formatOnSaveInfo': 'Exécute automatiquement le formateur de code lors de l\'enregistrement d\'un fichier, maintenant un style cohérent.',
      'stickyScrollInfo': 'Épingle l\'en-tête du bloc en cours en haut de l\'éditeur lors du défilement, pour toujours connaître la portée actuelle.',
      'tabSizeInfo': 'Définit le nombre d\'espaces par niveau d\'indentation. Les valeurs courantes sont 2 (web/TypeScript) et 4 (Python/Java).',
      'useSpacesInfo': 'Lorsqu\'il est activé, Tab insère des espaces plutôt qu\'un caractère de tabulation réel (\\t).',
      'cursorBlinkSpeedInfo': 'Contrôle l\'intervalle en millisecondes entre les cycles de clignotement du curseur.',
      'lightbulbActionsInfo': 'Affiche une icône d\'ampoule lors de la sélection de code, avec des actions rapides comme la refactorisation, corrections et importations.',
      'foldArrowsInfo': 'Affiche des flèches de repli à côté des blocs de code (fonctions, classes, ifs) pour masquer des sections.',
      'blockLinesInfo': 'Dessine des lignes guides verticales montrant la structure d\'indentation du code, aidant à visualiser les limites des blocs.',
      'indentDotsInfo': 'Affiche de petits points à chaque niveau d\'indentation avant le premier caractère, rendant la profondeur d\'indentation plus visible.',
      'highlightCurrentLineInfo': 'Applique un fond subtil sur la ligne où se trouve le curseur de texte.',
      'highlightActiveBlockInfo': 'Change la couleur de fond de tout le bloc de code (fonction, classe, etc.) contenant le curseur.',
      'highlightStyleInfo': '"fill" colore la ligne; "stroke" dessine un contour; "accentBar" ajoute une barre colorée à gauche; "none" désactive le surlignage.',
      'diagnosticIndicatorsInfo': 'Affiche des soulignements ondulés sur le code avec des erreurs (rouge) ou avertissements (jaune), fournis par le serveur de langage.',
      'readOnlyInfo': 'Lorsqu\'il est activé, toute édition est désactivée — le fichier est affiché mais ne peut pas être modifié. Utile pour consulter des logs ou fichiers de référence.',
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
      'liquidGlass': 'Liquid Glass',
      'liquidGlassSub': 'Flüssigglaseffekt auf Leisten und Panels',
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
      // Extensions
      'extStore': 'Store',
      'extSdks': 'SDKs',
      'extInstalledTab': 'Installiert',
      'extDarkThemes': 'Dunkle Themen',
      'extLightThemes': 'Helle Themen',
      'extActiveTheme': 'Aktives Thema',
      'extInstalledSection': 'Installiert',
      'extNoThemes': 'Keine Themen verfügbar.',
      'extNoSdks': 'Keine SDKs verfügbar.',
      'extNoExtensions': 'Noch keine Erweiterungen installiert.',
      'extGoToStore': 'Gehen Sie zum Store, um Themen zu installieren.',
      'extActivate': 'Thema aktivieren',
      'extDeactivate': 'Thema deaktivieren',
      'extInstall': 'Installieren',
      'extUninstall': 'Deinstallieren',
      'extUpdate': 'Aktualisieren',
      'extActive': 'Aktiv',
      'extDarkThemeLabel': 'Dunkles Thema',
      'extLightThemeLabel': 'Helles Thema',
      'extInstallQ': 'Thema installieren?',
      'extInstallBody': 'Das Thema wird auf Ihrem Gerät gespeichert.',
      'extDeleteQ': 'Thema löschen?',
      'extDeleteBody': 'Das Thema wird von Ihrem Gerät entfernt.',
      'extInstalled2': 'Installiert',
      // Workspace peek bar
      'peekCreatingProject': 'Projekt wird erstellt...',
      'peekLoadingProject': 'Projekt wird geladen...',
      'peekStartingLsp': 'LSP wird gestartet...',
      'peekSyncingDeps': 'Abhängigkeiten werden installiert...',
      'peekReady': 'Projekt bereit',
      'peekSwipeUp': 'Nach oben wischen, um auf das Terminal zuzugreifen',
      // Workspace sync banner
      'syncBannerMsg': 'Abhängigkeiten mit "%s" installieren?',
      'syncBannerIgnore': 'Ignorieren',
      'syncBannerRun': 'Installieren',
      // Workspace dialogs / menus
      'wsCloseProject': 'Projekt schließen',
      'wsCloseProjectQ': 'Projekt schließen?',
      'wsCloseProjectBody': 'Möchten Sie das aktuelle Projekt wirklich schließen? Nicht gespeicherte Änderungen gehen verloren.',
      'wsCloseYes': 'Ja, schließen',
      'wsUndo': 'Rückgängig',
      'wsRedo': 'Wiederholen',
      'wsSyncProject': 'Projekt synchronisieren',
      'wsSearchInFile': 'In Datei suchen…',
      'wsCommands': 'Befehle',
      'wsHotReload': 'Hot Reload',
      'wsHotRestart': 'Hot Restart',
      // Setting info dialog
      'settingInfoTitle': 'Über diese Einstellung',
      'followSystemThemeInfo': 'Wenn aktiviert, wechselt die App automatisch zwischen hellem und dunklem Thema basierend auf den Systemeinstellungen. Deaktivieren ermöglicht manuelle Auswahl.',
      'darkModeInfo': 'Schaltet die App auf eine dunkle Farbpalette um. Nur verfügbar, wenn "Systemthema folgen" deaktiviert ist.',
      'amoledBlackInfo': 'Ersetzt den dunklen Hintergrund durch reines Schwarz (#000000). Reduziert den Stromverbrauch bei OLED/AMOLED-Displays.',
      'dynamicColorsInfo': 'Verwendet dynamische Material You-Farben aus dem Hintergrundbild (Android 12+). Wendet Akzentfarben in der gesamten App an.',
      'liquidGlassInfo': 'Aktiviert den GPU-beschleunigten Glasrefractions-Effekt auf der App-Leiste, dem unteren Panel und der Seitenleiste.',
      'languageInfo': 'Ändert die Anzeigesprache der gesamten App. Möglicherweise ist ein Neustart der App auf einigen Geräten erforderlich.',
      'fontFamilyInfo': 'Wählt die Schriftart für den Code-Editor aus. Monospace-Schriften werden für die Code-Lesbarkeit empfohlen.',
      'fontSizeInfo': 'Steuert die Textgröße im Editor in Pixeln. Größere Werte verbessern die Lesbarkeit; kleinere zeigen mehr Code auf einmal.',
      'lineNumbersInfo': 'Zeigt Zeilennummern im linken Rand des Editors an. Nützlich für die Navigation und Referenzierung bestimmter Zeilen.',
      'fixedGutterInfo': 'Wenn aktiviert, bleibt die Zeilennummernspalte beim horizontalen Scrollen fixiert, sodass Sie immer sehen, auf welcher Zeile Sie sich befinden.',
      'minimapInfo': 'Zeigt eine Miniaturvorschau der gesamten Datei auf der rechten Seite des Editors für schnelle Navigation.',
      'symbolBarInfo': 'Fügt eine Symbolleiste über der Tastatur mit häufigen Programmierzeichen wie { } ; = hinzu, die auf Mobilgeräten schwer zu tippen sind.',
      'wordWrapInfo': 'Bricht lange Zeilen um, damit sie in die Editor-Breite passen. Deaktivieren ermöglicht horizontales Scrollen.',
      'autoIndentInfo': 'Behält beim Drücken von Enter automatisch die korrekte Einrückungsebene bei, entsprechend der aktuellen Zeile.',
      'autoClosePairsInfo': 'Fügt automatisch das schließende Klammer- oder Anführungszeichen ein: ( → (), { → {}, [ → [], " → "".',
      'autoCompletionInfo': 'Zeigt während der Eingabe ein Vorschlagsfenster basierend auf dem Language Server und dem Dateikontext.',
      'formatOnSaveInfo': 'Führt beim Speichern automatisch den Code-Formatierer aus, um einen konsistenten Code-Stil beizubehalten.',
      'stickyScrollInfo': 'Fixiert beim Scrollen den Kopfbereich des aktuellen Blocks oben im Editor, sodass Sie immer Ihren aktuellen Gültigkeitsbereich kennen.',
      'tabSizeInfo': 'Legt fest, wie viele Leerzeichen eine Einrückungsebene darstellen. Übliche Werte sind 2 (Web/TypeScript) und 4 (Python/Java).',
      'useSpacesInfo': 'Wenn aktiviert, fügt Tab Leerzeichen statt eines echten Tabulatorzeichens (\\t) ein.',
      'cursorBlinkSpeedInfo': 'Steuert das Intervall in Millisekunden zwischen den Cursor-Blinkzyklen.',
      'lightbulbActionsInfo': 'Zeigt ein Glühbirnen-Symbol bei der Code-Auswahl mit schnellen Aktionen wie Refactoring, Korrekturen und automatischen Importen.',
      'foldArrowsInfo': 'Zeigt Einklapp-Pfeile neben Code-Blöcken (Funktionen, Klassen, Ifs), um Abschnitte auszublenden.',
      'blockLinesInfo': 'Zeichnet vertikale Führungslinien, die die Einrückungsstruktur des Codes zeigen und Blockgrenzen sichtbar machen.',
      'indentDotsInfo': 'Zeigt kleine Punkte auf jeder Einrückungsebene vor dem ersten Zeichen, um die Einrückungstiefe sichtbarer zu machen.',
      'highlightCurrentLineInfo': 'Wendet einen subtilen Hintergrund auf die Zeile an, in der sich der Textcursor befindet.',
      'highlightActiveBlockInfo': 'Ändert die Hintergrundfarbe des gesamten Code-Blocks (Funktion, Klasse usw.), der den Cursor enthält.',
      'highlightStyleInfo': '"fill" färbt die Zeile; "stroke" zeichnet einen Rahmen; "accentBar" fügt eine farbige Leiste links hinzu; "none" deaktiviert die Hervorhebung.',
      'diagnosticIndicatorsInfo': 'Zeigt gewellte Unterstreichungen bei Code mit Fehlern (rot) oder Warnungen (gelb), bereitgestellt vom Language Server.',
      'readOnlyInfo': 'Wenn aktiviert, ist alle Bearbeitung deaktiviert — die Datei wird angezeigt, kann aber nicht geändert werden. Nützlich für Logs oder Referenzdateien.',
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
