import 'package:core/core.dart';
import 'package:sdk_manager/sdk_manager.dart';

// ── Android templates ─────────────────────────────────────────────────────────

enum AndroidTemplate {
  emptyActivity,
  basicViews,
  emptyCompose,
  bottomNavigation,
  loginActivity,
  scrollingActivity,
  navigationDrawer;

  String get label => switch (this) {
    AndroidTemplate.emptyActivity    => 'Empty Activity',
    AndroidTemplate.basicViews       => 'Basic Views',
    AndroidTemplate.emptyCompose     => 'Empty Compose',
    AndroidTemplate.bottomNavigation => 'Bottom Navigation',
    AndroidTemplate.loginActivity    => 'Login Activity',
    AndroidTemplate.scrollingActivity => 'Scrolling Activity',
    AndroidTemplate.navigationDrawer => 'Navigation Drawer',
  };

  String get description => switch (this) {
    AndroidTemplate.emptyActivity    => 'Atividade vazia com layout simples',
    AndroidTemplate.basicViews       => 'AppBar, conteúdo e botão de ação',
    AndroidTemplate.emptyCompose     => 'Jetpack Compose com Material 3',
    AndroidTemplate.bottomNavigation => 'Navegação inferior com 3 fragmentos',
    AndroidTemplate.loginActivity    => 'Tela de login com campos de entrada',
    AndroidTemplate.scrollingActivity => 'Toolbar recolhível com conteúdo rolável',
    AndroidTemplate.navigationDrawer => 'Gaveta de navegação lateral',
  };
}

// ── Flutter templates ─────────────────────────────────────────────────────────

enum FlutterTemplate {
  counterApp,
  emptyApp,
  materialApp,
  bottomNavApp,
  drawerApp,
  loginScreen,
  listApp,
  tabsApp;

  String get label => switch (this) {
    FlutterTemplate.counterApp   => 'Counter App',
    FlutterTemplate.emptyApp     => 'Empty App',
    FlutterTemplate.materialApp  => 'Material 3',
    FlutterTemplate.bottomNavApp => 'Bottom Nav',
    FlutterTemplate.drawerApp    => 'Drawer',
    FlutterTemplate.loginScreen  => 'Login',
    FlutterTemplate.listApp      => 'List View',
    FlutterTemplate.tabsApp      => 'Tabs',
  };

  String get description => switch (this) {
    FlutterTemplate.counterApp   => 'App padrão com contador de cliques',
    FlutterTemplate.emptyApp     => 'App mínimo sem código de demo',
    FlutterTemplate.materialApp  => 'Material 3 com tema e cards',
    FlutterTemplate.bottomNavApp => 'Navegação inferior com 3 telas',
    FlutterTemplate.drawerApp    => 'Gaveta de navegação lateral',
    FlutterTemplate.loginScreen  => 'Tela de login com formulário',
    FlutterTemplate.listApp      => 'Lista rolável com ListTiles',
    FlutterTemplate.tabsApp      => 'TabBar com 3 abas',
  };
}

// ── React Native templates ────────────────────────────────────────────────────

enum ReactNativeTemplate {
  blank,
  blankTypescript,
  tabs,
  flatList,
  settings,
  login;

  String get label => switch (this) {
    ReactNativeTemplate.blank           => 'Blank',
    ReactNativeTemplate.blankTypescript => 'Blank TS',
    ReactNativeTemplate.tabs            => 'Tabs (Expo)',
    ReactNativeTemplate.flatList        => 'Flat List',
    ReactNativeTemplate.settings        => 'Settings',
    ReactNativeTemplate.login           => 'Login',
  };

  String get description => switch (this) {
    ReactNativeTemplate.blank           => 'Projeto React Native vazio',
    ReactNativeTemplate.blankTypescript => 'Blank com TypeScript explícito',
    ReactNativeTemplate.tabs            => 'Navegação por abas com Expo Router',
    ReactNativeTemplate.flatList        => 'FlatList com itens e separadores',
    ReactNativeTemplate.settings        => 'SectionList estilo configurações',
    ReactNativeTemplate.login           => 'Tela de login com validação',
  };
}

// ── ProjectTemplate ───────────────────────────────────────────────────────────

class ProjectTemplate {
  final SdkType sdk;

  const ProjectTemplate(this.sdk);

  String createCommand(String projectName, String parentDir,
      {String? overrideNewProjectCmd,
       bool remoteIsWindows = false,
       // Android
       String androidLanguage = 'kotlin',
       int androidMinSdk = 24,
       AndroidTemplate androidTemplate = AndroidTemplate.emptyActivity,
       bool useGroovy = false,
       // Flutter
       FlutterTemplate flutterTemplate = FlutterTemplate.counterApp,
       // React Native
       ReactNativeTemplate rnTemplate = ReactNativeTemplate.blank}) {
    final def = SdkDefinition.forType(sdk);
    final raw = overrideNewProjectCmd ?? def.newProjectCmd;

    final cmd = raw
        .replaceAll(r'$name', projectName)
        .replaceAll('mkdir -p ', remoteIsWindows ? 'mkdir ' : 'mkdir -p ');

    final projectPath = '$parentDir/$projectName';

    final base = remoteIsWindows
        ? 'cd "$parentDir"; $cmd'
        : 'cd "$parentDir" && $cmd';

    // ── Flutter ───────────────────────────────────────────────────────────────
    if (sdk == SdkType.flutter && !remoteIsWindows) {
      // --empty flag for minimal template
      final flutterCmd = flutterTemplate == FlutterTemplate.emptyApp
          ? cmd.replaceFirst('flutter create ', 'flutter create --empty ')
          : cmd;
      final flutterBase = 'cd "$parentDir" && $flutterCmd';
      final patch = _flutterTemplatePatch(projectPath, projectName, flutterTemplate);
      return '$flutterBase && ${_flutterAndroidFixes(projectPath, useGroovy: useGroovy)} && $patch';
    }

    // ── Android SDK ───────────────────────────────────────────────────────────
    if (sdk == SdkType.androidSdk && !remoteIsWindows) {
      return '$base && ${_androidProjectScaffold(
        projectPath, projectName,
        language: androidLanguage,
        minSdk: androidMinSdk,
        template: androidTemplate,
        useGroovy: useGroovy,
      )}';
    }

    // ── React Native ──────────────────────────────────────────────────────────
    if (sdk == SdkType.reactNative && !remoteIsWindows) {
      final rnCmd = rnTemplate == ReactNativeTemplate.tabs
          ? '$cmd --template tabs'
          : cmd;
      final baseCmd =
          'cd "$parentDir" && rm -rf "$projectName" 2>/dev/null; $rnCmd';
      final patch = _rnTemplatePatch(projectPath, rnTemplate);
      return patch == 'true' ? baseCmd : '$baseCmd && $patch';
    }

    return base;
  }

  // ── Flutter post-creation patches ─────────────────────────────────────────

  static String _flutterTemplatePatch(
      String projectPath, String projectName, FlutterTemplate template) {
    switch (template) {
      case FlutterTemplate.counterApp:
      case FlutterTemplate.emptyApp:
        return 'true'; // no-op
      case FlutterTemplate.materialApp:
      case FlutterTemplate.bottomNavApp:
      case FlutterTemplate.drawerApp:
      case FlutterTemplate.loginScreen:
      case FlutterTemplate.listApp:
      case FlutterTemplate.tabsApp:
        final content = _flutterMainDart(projectName, template);
        return '''
(
cat > "$projectPath/lib/main.dart" << \'__LAYEREOF__\'
$content
__LAYEREOF__
echo "✓ Applied ${template.label} template to lib/main.dart"
) 2>&1''';
    }
  }

  static String _flutterMainDart(String projectName, FlutterTemplate template) {
    switch (template) {
      case FlutterTemplate.materialApp:
        return '''
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$projectName',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.inversePrimary,
        title: const Text('$projectName'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome!',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: Icon(Icons.star, color: cs.primary),
                title: const Text('Feature one'),
                subtitle: const Text('Tap to get started'),
                onTap: () {},
              ),
            ),
            Card(
              child: ListTile(
                leading: Icon(Icons.settings, color: cs.secondary),
                title: const Text('Feature two'),
                subtitle: const Text('Another option'),
                onTap: () {},
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}''';

      case FlutterTemplate.bottomNavApp:
        return '''
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$projectName',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  static const _screens = <Widget>[
    _HomeScreen(),
    _SearchScreen(),
    _ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: const Center(child: Text('Home Screen')),
      );
}

class _SearchScreen extends StatelessWidget {
  const _SearchScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Search')),
        body: const Center(child: Text('Search Screen')),
      );
}

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: Text('Profile Screen')),
      );
}''';

      case FlutterTemplate.drawerApp:
        return '''
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$projectName',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const _titles = <String>['Home', 'Profile', 'Settings'];
  static const _icons  = <IconData>[Icons.home, Icons.person, Icons.settings];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.inversePrimary,
        title: Text(_titles[_selectedIndex]),
      ),
      drawer: NavigationDrawer(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) {
          setState(() => _selectedIndex = i);
          Navigator.pop(context);
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 16, 10),
            child: Text('Menu',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          ...List.generate(
            _titles.length,
            (i) => NavigationDrawerDestination(
              icon: Icon(_icons[i]),
              label: Text(_titles[i]),
            ),
          ),
        ],
      ),
      body: Center(
        child: Text(
          _titles[_selectedIndex],
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}''';

      case FlutterTemplate.loginScreen:
        return '''
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$projectName',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.lock_rounded, size: 64, color: cs.primary),
              const SizedBox(height: 24),
              Text(
                'Sign In',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {},
                style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: 16)),
                child: const Text('Sign In',
                    style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {},
                child: const Text('Create account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}''';

      case FlutterTemplate.listApp:
        return '''
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$projectName',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const ListScreen(),
    );
  }
}

class ListScreen extends StatelessWidget {
  const ListScreen({super.key});

  static const _titles = <String>[
    'Item one', 'Item two', 'Item three',
    'Item four', 'Item five',
  ];
  static const _icons = <IconData>[
    Icons.star, Icons.favorite, Icons.bolt,
    Icons.explore, Icons.settings,
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.inversePrimary,
        title: const Text('$projectName'),
      ),
      body: ListView.separated(
        itemCount: _titles.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1),
        itemBuilder: (context, i) => ListTile(
          leading: Icon(_icons[i], color: cs.primary),
          title: Text(_titles[i]),
          subtitle: const Text('Subtitle description'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {},
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}''';

      case FlutterTemplate.tabsApp:
        return '''
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$projectName',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TabsScreen(),
    );
  }
}

class TabsScreen extends StatelessWidget {
  const TabsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor:
              Theme.of(context).colorScheme.inversePrimary,
          title: const Text('$projectName'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.home), text: 'Home'),
              Tab(icon: Icon(Icons.explore), text: 'Explore'),
              Tab(icon: Icon(Icons.person), text: 'Profile'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            Center(child: Text('Home Tab')),
            Center(child: Text('Explore Tab')),
            Center(child: Text('Profile Tab')),
          ],
        ),
      ),
    );
  }
}''';

      default:
        return ''; // shouldn't reach here
    }
  }

  // ── React Native post-creation patches ────────────────────────────────────

  static String _rnTemplatePatch(
      String projectPath, ReactNativeTemplate template) {
    switch (template) {
      case ReactNativeTemplate.blank:
      case ReactNativeTemplate.blankTypescript:
      case ReactNativeTemplate.tabs:
        return 'true'; // handled by flag or left as-is
      case ReactNativeTemplate.flatList:
      case ReactNativeTemplate.settings:
      case ReactNativeTemplate.login:
        final content = _rnAppTsx(template);
        return '''
(
cat > "$projectPath/App.tsx" << \'__LAYEREOF__\'
$content
__LAYEREOF__
echo "✓ Applied ${template.label} template to App.tsx"
) 2>&1''';
    }
  }

  /// Returns the App.tsx source for a React Native template.
  /// Uses raw strings so TypeScript template literals (\${...}) are preserved.
  static String _rnAppTsx(ReactNativeTemplate template) {
    switch (template) {
      case ReactNativeTemplate.flatList:
        return r'''
import React from 'react';
import {
  FlatList,
  SafeAreaView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';

type Item = { id: string; title: string; subtitle: string };

const DATA: Item[] = Array.from({ length: 15 }, (_, i) => ({
  id: String(i + 1),
  title: `Item ${i + 1}`,
  subtitle: `Subtitle for item ${i + 1}`,
}));

export default function App() {
  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerText}>My List</Text>
      </View>
      <FlatList
        data={DATA}
        keyExtractor={(item) => item.id}
        ItemSeparatorComponent={() => <View style={styles.separator} />}
        renderItem={({ item }) => (
          <TouchableOpacity style={styles.item} activeOpacity={0.7}>
            <Text style={styles.title}>{item.title}</Text>
            <Text style={styles.subtitle}>{item.subtitle}</Text>
          </TouchableOpacity>
        )}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container:  { flex: 1, backgroundColor: '#fff' },
  header:     { padding: 16, backgroundColor: '#2196F3' },
  headerText: { fontSize: 20, fontWeight: 'bold', color: '#fff' },
  item:       { padding: 16 },
  title:      { fontSize: 16, fontWeight: '600', color: '#111' },
  subtitle:   { fontSize: 13, color: '#666', marginTop: 2 },
  separator:  { height: 1, backgroundColor: '#f0f0f0' },
});
''';

      case ReactNativeTemplate.settings:
        return r'''
import React, { useState } from 'react';
import {
  SafeAreaView,
  SectionList,
  StyleSheet,
  Switch,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';

type RowItem =
  | { kind: 'toggle'; label: string; key: string }
  | { kind: 'link'; label: string; value?: string };

const SECTIONS: { title: string; data: RowItem[] }[] = [
  {
    title: 'Account',
    data: [
      { kind: 'link', label: 'Profile', value: 'Edit' },
      { kind: 'link', label: 'Email', value: 'user@example.com' },
    ],
  },
  {
    title: 'Preferences',
    data: [
      { kind: 'toggle', label: 'Notifications', key: 'notif' },
      { kind: 'toggle', label: 'Dark Mode', key: 'dark' },
    ],
  },
  {
    title: 'Support',
    data: [
      { kind: 'link', label: 'Help Center' },
      { kind: 'link', label: 'About' },
    ],
  },
];

export default function App() {
  const [toggles, setToggles] = useState<Record<string, boolean>>({});
  return (
    <SafeAreaView style={styles.container}>
      <SectionList
        sections={SECTIONS}
        keyExtractor={(item, i) => item.label + i}
        renderSectionHeader={({ section }) => (
          <Text style={styles.sectionHeader}>{section.title}</Text>
        )}
        ItemSeparatorComponent={() => (
          <View style={styles.separator} />
        )}
        renderItem={({ item }) =>
          item.kind === 'toggle' ? (
            <View style={styles.row}>
              <Text style={styles.label}>{item.label}</Text>
              <Switch
                value={!!toggles[item.key]}
                onValueChange={(v) =>
                  setToggles((prev) => ({ ...prev, [item.key]: v }))
                }
              />
            </View>
          ) : (
            <TouchableOpacity style={styles.row}>
              <Text style={styles.label}>{item.label}</Text>
              {item.value ? (
                <Text style={styles.value}>{item.value}</Text>
              ) : null}
            </TouchableOpacity>
          )
        }
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f2f2f7' },
  sectionHeader: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    fontSize: 13,
    color: '#6e6e6e',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: '#fff',
    paddingHorizontal: 16,
    paddingVertical: 14,
  },
  label:     { fontSize: 16, color: '#111' },
  value:     { fontSize: 16, color: '#8e8e93' },
  separator: { height: 1, backgroundColor: '#e5e5ea', marginLeft: 16 },
});
''';

      case ReactNativeTemplate.login:
        return r'''
import React, { useState } from 'react';
import {
  Alert,
  KeyboardAvoidingView,
  Platform,
  SafeAreaView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';

export default function App() {
  const [email,    setEmail]    = useState('');
  const [password, setPassword] = useState('');
  const [secure,   setSecure]   = useState(true);

  const handleLogin = () => {
    if (!email || !password) {
      Alert.alert('Error', 'Please fill in all fields.');
      return;
    }
    Alert.alert('Welcome', `Logging in as ${email}`);
  };

  return (
    <SafeAreaView style={styles.container}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.inner}
      >
        <View style={styles.iconWrap}>
          <Text style={styles.iconText}>🔐</Text>
        </View>
        <Text style={styles.title}>Sign In</Text>
        <TextInput
          style={styles.input}
          placeholder="Email"
          placeholderTextColor="#aaa"
          keyboardType="email-address"
          autoCapitalize="none"
          value={email}
          onChangeText={setEmail}
        />
        <TextInput
          style={styles.input}
          placeholder="Password"
          placeholderTextColor="#aaa"
          secureTextEntry={secure}
          value={password}
          onChangeText={setPassword}
        />
        <TouchableOpacity style={styles.button} onPress={handleLogin}>
          <Text style={styles.buttonText}>Sign In</Text>
        </TouchableOpacity>
        <TouchableOpacity onPress={() => {}}>
          <Text style={styles.link}>Don't have an account? Sign up</Text>
        </TouchableOpacity>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#fff' },
  inner: {
    flex: 1,
    justifyContent: 'center',
    paddingHorizontal: 28,
  },
  iconWrap: { alignItems: 'center', marginBottom: 16 },
  iconText: { fontSize: 52 },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: 32,
    color: '#111',
  },
  input: {
    height: 52,
    borderWidth: 1.5,
    borderColor: '#ddd',
    borderRadius: 12,
    paddingHorizontal: 16,
    marginBottom: 16,
    fontSize: 16,
    color: '#111',
  },
  button: {
    backgroundColor: '#2196F3',
    paddingVertical: 16,
    borderRadius: 12,
    marginBottom: 16,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
    textAlign: 'center',
  },
  link: { textAlign: 'center', color: '#2196F3', fontSize: 14 },
});
''';

      default:
        return '';
    }
  }

  // ── Flutter Android fixes ─────────────────────────────────────────────────

  static String _flutterAndroidFixes(String projectPath,
      {bool useGroovy = false}) {
    // All version constants embedded directly — no Dart interpolation inside
    // shell sed patterns, which avoids quote-delimiter collisions.
    const ndkVersion        = '27.1.12297006';
    const buildToolsVersion = '35.0.0';
    const androidSdkDir     = r'$PREFIX/opt/android-sdk';

    // Gradle file path depends on DSL choice.
    final gradleFile = useGroovy
        ? '$projectPath/android/app/build.gradle'
        : '$projectPath/android/app/build.gradle.kts';

    // Build the KTS/Groovy-specific sed snippets as plain Dart strings so
    // there is never a raw-string delimiter collision with shell quotes.
    final ndkReplaceExpr = useGroovy
        ? 's/ndkVersion flutter.ndkVersion/ndkVersion "$ndkVersion"/g'
        : 's/ndkVersion = flutter.ndkVersion/ndkVersion = "$ndkVersion"/g';
    final btoolsLine = useGroovy
        ? '    buildToolsVersion "$buildToolsVersion"'
        : '    buildToolsVersion = "$buildToolsVersion"';

    // Use a shell variable for the NDK version so the sed expression stays
    // entirely in double quotes — no single-quote/raw-string nesting needed.
    return '(\n'
        '  NDK_VER="$ndkVersion"\n'
        '  BTOOLS_VER="$buildToolsVersion"\n'
        '  SDK_ROOT="\${ANDROID_HOME:-$androidSdkDir}"\n'
        '\n'
        '  # ── flutter config ──────────────────────────────────────────────\n'
        '  flutter config --android-sdk "\$SDK_ROOT" 2>/dev/null && echo "✓ flutter config --android-sdk"\n'
        '\n'
        '  # ── local.properties ────────────────────────────────────────────\n'
        '  PROPS="$projectPath/android/local.properties"\n'
        '  NDK_DIR=\$(ls -d "\$SDK_ROOT/ndk/\$NDK_VER" 2>/dev/null || ls -d "\$SDK_ROOT/ndk/"* 2>/dev/null | sort -rV | head -1)\n'
        '  CMAKE_DIR=\$(ls -d "\$SDK_ROOT/cmake/"*/bin/cmake 2>/dev/null | sort -rV | head -1 | sed "s|/bin/cmake||")\n'
        '  {\n'
        '    printf "sdk.dir=%s\\n" "\$SDK_ROOT"\n'
        '    [ -n "\$NDK_DIR" ]   && printf "ndk.dir=%s\\n"   "\$NDK_DIR"\n'
        '    [ -n "\$CMAKE_DIR" ] && printf "cmake.dir=%s\\n" "\$CMAKE_DIR"\n'
        '  } > "\$PROPS"\n'
        '  echo "✓ Wrote local.properties"\n'
        '\n'
        '  # ── build.gradle(.kts) ──────────────────────────────────────────\n'
        '  GRADLE="$gradleFile"\n'
        '  if [ -f "\$GRADLE" ]; then\n'
        '    sed -i "$ndkReplaceExpr" "\$GRADLE"\n'
        '    grep -qF "ndkVersion" "\$GRADLE" || true\n'
        '    if ! grep -qF "buildToolsVersion" "\$GRADLE"; then\n'
        '      sed -i "/compileSdk/a\\\\\\n$btoolsLine" "\$GRADLE"\n'
        '    fi\n'
        '    echo "✓ ndkVersion=\$NDK_VER buildToolsVersion=\$BTOOLS_VER"\n'
        '  fi\n'
        '\n'
        '  # ── gradle.properties ───────────────────────────────────────────\n'
        '  GPROPS="$projectPath/android/gradle.properties"\n'
        '  if [ -f "\$GPROPS" ]; then\n'
        '    sed -i "s/-Xmx[0-9]*[mMgG]/-Xmx512m/g" "\$GPROPS"\n'
        '    sed -i "/-XX:MaxMetaspaceSize/d" "\$GPROPS"\n'
        '    sed -i "/-XX:+HeapDumpOnOutOfMemoryError/d" "\$GPROPS"\n'
        '    echo "✓ Capped Gradle JVM heap"\n'
        '  fi\n'
        '  AAPT2_BIN=\$(find "\$SDK_ROOT/build-tools/\$BTOOLS_VER" -name aapt2 2>/dev/null | head -1)\n'
        '  [ -z "\$AAPT2_BIN" ] && AAPT2_BIN=\$(find "\$SDK_ROOT/build-tools" -name aapt2 2>/dev/null | sort -rV | head -1)\n'
        '  if [ -n "\$AAPT2_BIN" ] && [ -f "\$GPROPS" ]; then\n'
        '    sed -i "/android.aapt2FromMavenOverride/d" "\$GPROPS"\n'
        '    printf "\\nandroid.aapt2FromMavenOverride=%s\\n" "\$AAPT2_BIN" >> "\$GPROPS"\n'
        '    echo "✓ aapt2 → \$AAPT2_BIN"\n'
        '  fi\n'
        ') 2>&1';
  }

  // ── Native Android scaffold ───────────────────────────────────────────────

  static String _androidProjectScaffold(
    String projectPath,
    String projectName, {
    String language = 'kotlin',
    int minSdk = 24,
    AndroidTemplate template = AndroidTemplate.emptyActivity,
    bool useGroovy = false,
  }) {
    final isKotlin = (template == AndroidTemplate.emptyCompose)
        ? true
        : language.toLowerCase() != 'java';
    final srcDir = isKotlin ? 'kotlin' : 'java';
    final fileExt = isKotlin ? 'kt' : 'java';

    final safePkg = projectName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final pkg = 'com.example.$safePkg';
    final pkgDir = pkg.replaceAll('.', '/');

    var className = projectName
        .split(RegExp(r'[_\-\s]+'))
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join()
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (className.isEmpty || !RegExp(r'[a-zA-Z]').hasMatch(className[0])) {
      className = 'Main$className';
    }
    className += 'Activity';

    final safeName = projectName.replaceAll('"', r'\"');

    final isCompose = template == AndroidTemplate.emptyCompose;
    final settingsContent   = _aSettingsGradle(safeName, useGroovy: useGroovy);
    final rootBuildContent  = _aRootBuildGradle(isKotlin, isCompose: isCompose, useGroovy: useGroovy);
    final appBuildContent   = _aAppBuildGradle(pkg, minSdk, template, isKotlin, useGroovy: useGroovy);
    final manifestContent   = _aManifest(pkg, className, template);
    final activityContent   = _aActivity(pkg, className, template, isKotlin);
    final mainLayoutContent = _aMainLayout(template);
    final themesContent     = _aThemesXml(isCompose);
    final extraFiles        = _aExtraFiles(
        projectPath, pkg, pkgDir, className, template, isKotlin, fileExt, srcDir);

    final hasLayout = template != AndroidTemplate.emptyCompose;
    final needsMenuDir = template == AndroidTemplate.bottomNavigation ||
        template == AndroidTemplate.navigationDrawer;
    final extraMkdir = needsMenuDir
        ? 'mkdir -p "$projectPath/app/src/main/res/menu"'
        : '';

    // Build file names depend on DSL choice
    final settingsFile = useGroovy ? 'settings.gradle'     : 'settings.gradle.kts';
    final rootFile     = useGroovy ? 'build.gradle'        : 'build.gradle.kts';
    final appFile      = useGroovy ? 'app/build.gradle'    : 'app/build.gradle.kts';

    return '''
(
set -e
mkdir -p "$projectPath/app/src/main/$srcDir/$pkgDir"
mkdir -p "$projectPath/app/src/main/res/values"
mkdir -p "$projectPath/app/src/main/res/layout"
mkdir -p "$projectPath/gradle/wrapper"
$extraMkdir

cat > "$projectPath/$settingsFile" << \'__LAYEREOF__\'
$settingsContent
__LAYEREOF__

cat > "$projectPath/$rootFile" << \'__LAYEREOF__\'
$rootBuildContent
__LAYEREOF__

cat > "$projectPath/$appFile" << \'__LAYEREOF__\'
$appBuildContent
__LAYEREOF__

cat > "$projectPath/app/src/main/AndroidManifest.xml" << \'__LAYEREOF__\'
$manifestContent
__LAYEREOF__

cat > "$projectPath/app/src/main/$srcDir/$pkgDir/$className.$fileExt" << \'__LAYEREOF__\'
$activityContent
__LAYEREOF__

${hasLayout ? '''cat > "$projectPath/app/src/main/res/layout/activity_main.xml" << \'__LAYEREOF__\'
$mainLayoutContent
__LAYEREOF__''' : '# Compose: no layout XML needed'}

$extraFiles

cat > "$projectPath/app/src/main/res/values/strings.xml" << \'__LAYEREOF__\'
<resources>
    <string name="app_name">$safeName</string>
</resources>
__LAYEREOF__

cat > "$projectPath/app/src/main/res/values/themes.xml" << \'__LAYEREOF__\'
$themesContent
__LAYEREOF__

SDK_ROOT_LP="\${ANDROID_HOME:-\$PREFIX/opt/android-sdk}"
# Detect the highest installed NDK version (ls -d sorts; sort -rV picks latest)
NDK_DIR=\$(ls -d "\$SDK_ROOT_LP/ndk/"* 2>/dev/null | sort -rV | head -1)
if [ -n "\$NDK_DIR" ]; then
  printf "sdk.dir=\$SDK_ROOT_LP\\nndk.dir=\$NDK_DIR\\n" > "$projectPath/local.properties"
else
  # No NDK installed — write only sdk.dir so Gradle doesn't fail on a bad ndk.dir
  printf "sdk.dir=\$SDK_ROOT_LP\\n" > "$projectPath/local.properties"
fi

SDK_ROOT="\${ANDROID_HOME:-\$PREFIX/opt/android-sdk}"
AAPT2_BIN=\$(find "\$SDK_ROOT/build-tools" -name aapt2 2>/dev/null | sort -rV | head -1)
AAPT2_LINE=""
if [ -n "\$AAPT2_BIN" ]; then
  AAPT2_LINE="android.aapt2FromMavenOverride=\$AAPT2_BIN"
fi

cat > "$projectPath/gradle.properties" << __LAYEREOF__
org.gradle.jvmargs=-Xmx512m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
\$AAPT2_LINE
__LAYEREOF__

# Write a shim gradlew that delegates to system gradle (works offline)
cat > "$projectPath/gradlew" << \'__LAYEREOF__\'
#!/bin/sh
exec gradle "\$@"
__LAYEREOF__
chmod +x "$projectPath/gradlew"

# Detect the system gradle version for the wrapper properties
GRADLE_VER=\$(gradle --version 2>/dev/null | awk '/^Gradle /{print \$2; exit}')
GRADLE_VER=\${GRADLE_VER:-8.6}

cat > "$projectPath/gradle/wrapper/gradle-wrapper.properties" << __LAYEREOF__
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\\://services.gradle.org/distributions/gradle-\$GRADLE_VER-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
__LAYEREOF__

# Try to generate gradle-wrapper.jar using the system gradle.
# We restore our shim afterwards so builds don't download Gradle from the internet.
if command -v gradle > /dev/null 2>&1; then
  (cd "$projectPath" && gradle wrapper --gradle-version="\$GRADLE_VER" --quiet 2>/dev/null && echo "✓ gradle-wrapper.jar generated") || true
  # Restore the offline shim (gradle wrapper overwrites gradlew)
  printf '#!/bin/sh\nexec gradle "\$@"\n' > "$projectPath/gradlew"
  chmod +x "$projectPath/gradlew"
fi

echo "✓ $safeName (${template.label}, ${isKotlin ? 'Kotlin' : 'Java'}, API $minSdk)"
) 2>&1''';
  }

  // ── Android file content generators ──────────────────────────────────────

  static String _aSettingsGradle(String projectName, {bool useGroovy = false}) {
    if (useGroovy) {
      return '''
pluginManagement {
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = '$projectName'
include ':app\'''';
    }
    return '''
pluginManagement {
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "$projectName"
include(":app")''';
  }

  static String _aRootBuildGradle(bool isKotlin, {bool isCompose = false, bool useGroovy = false}) {
    if (useGroovy) {
      final kt = isKotlin
          ? "\n    id 'org.jetbrains.kotlin.android' version '2.0.21' apply false"
          : '';
      final compose = (isKotlin && isCompose)
          ? "\n    id 'org.jetbrains.kotlin.plugin.compose' version '2.0.21' apply false"
          : '';
      return """
plugins {
    id 'com.android.application' version '8.3.2' apply false$kt$compose
}""";
    }
    final kt = isKotlin
        ? '\n    id("org.jetbrains.kotlin.android") version "2.0.21" apply false'
        : '';
    // Kotlin 2.0 bundles the Compose compiler — needs the compose plugin declared here.
    final compose = (isKotlin && isCompose)
        ? '\n    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false'
        : '';
    return '''
plugins {
    id("com.android.application") version "8.3.2" apply false$kt$compose
}''';
  }

  static String _aAppBuildGradle(
      String pkg, int minSdk, AndroidTemplate template, bool isKotlin,
      {bool useGroovy = false}) {
    if (template == AndroidTemplate.emptyCompose) {
      // Compose always uses KTS (Groovy Compose DSL is unusual; keep KTS)
      return '''
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "$pkg"
    compileSdk = 35
    defaultConfig {
        applicationId = "$pkg"
        minSdk = $minSdk
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }
    buildTypes { release { isMinifyEnabled = false } }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
}
dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.09.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.core:core-ktx:1.13.1")
    debugImplementation("androidx.compose.ui:ui-tooling")
}''';
    }

    if (useGroovy) {
      final ktPlugin = isKotlin ? "\n    id 'org.jetbrains.kotlin.android'" : '';
      final coreLib  = isKotlin ? 'core-ktx' : 'core';
      final ktOpts   = isKotlin ? "\n    kotlinOptions { jvmTarget = '17' }" : '';
      final fragDep  = template == AndroidTemplate.bottomNavigation
          ? "\n    implementation 'androidx.fragment:fragment${isKotlin ? '-ktx' : ''}:1.6.2'"
          : '';
      final drawerDepG = template == AndroidTemplate.navigationDrawer
          ? "\n    implementation 'androidx.drawerlayout:drawerlayout:1.2.0'"
          : '';
      return """
plugins {
    id 'com.android.application'$ktPlugin
}
android {
    namespace '$pkg'
    compileSdk 35
    defaultConfig {
        applicationId '$pkg'
        minSdk $minSdk
        targetSdk 35
        versionCode 1
        versionName '1.0'
    }
    buildTypes { release { minifyEnabled false } }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }$ktOpts
}
dependencies {
    implementation 'androidx.core:$coreLib:1.13.1'
    implementation 'androidx.appcompat:appcompat:1.7.0'
    implementation 'com.google.android.material:material:1.12.0'
    implementation 'androidx.constraintlayout:constraintlayout:2.1.4'$fragDep$drawerDepG
}""";
    }

    final ktPlugin = isKotlin ? '\n    id("org.jetbrains.kotlin.android")' : '';
    final coreLib  = isKotlin ? 'core-ktx' : 'core';
    final ktOpts   = isKotlin ? '\n    kotlinOptions { jvmTarget = "17" }' : '';
    final fragDep  = template == AndroidTemplate.bottomNavigation
        ? '\n    implementation("androidx.fragment:fragment${isKotlin ? '-ktx' : ''}:1.6.2")'
        : '';
    final drawerDep = template == AndroidTemplate.navigationDrawer
        ? '\n    implementation("androidx.drawerlayout:drawerlayout:1.2.0")'
        : '';

    return '''
plugins {
    id("com.android.application")$ktPlugin
}
android {
    namespace = "$pkg"
    compileSdk = 35
    defaultConfig {
        applicationId = "$pkg"
        minSdk = $minSdk
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }
    buildTypes { release { isMinifyEnabled = false } }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }$ktOpts
}
dependencies {
    implementation("androidx.core:$coreLib:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")$fragDep$drawerDep
}''';
  }

  static String _aManifest(
      String pkg, String className, AndroidTemplate template) {
    // Always use the AppTheme defined in res/values/themes.xml
    const theme = '@style/Theme.AppTheme';
    return '''
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:allowBackup="true"
        android:label="@string/app_name"
        android:theme="$theme">
        <activity android:name=".$className" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>''';
  }

  // ── themes.xml generator ──────────────────────────────────────────────────

  /// Generates res/values/themes.xml for a native Android project.
  ///
  /// [isCompose] – when true the base theme is a plain MaterialTheme with no
  /// ActionBar (Compose manages its own toolbar); otherwise a
  /// Theme.Material3.DayNight.NoActionBar descendant is used so AppCompat
  /// and Material Components work correctly out of the box.
  static String _aThemesXml(bool isCompose) {
    if (isCompose) {
      // Compose uses ComponentActivity. The theme must still be a Material3
      // descendant so that the window insets and dynamic color APIs work
      // correctly on Android 12+.  NoActionBar avoids a duplicate system bar.
      return '''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.AppTheme" parent="Theme.Material3.DayNight.NoActionBar" />
</resources>''';
    }

    // Views-based projects: Material3 with DayNight + NoActionBar so the app
    // can set its own MaterialToolbar via setSupportActionBar().
    return '''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.AppTheme" parent="Theme.Material3.DayNight.NoActionBar">
        <!-- Customize your Material 3 theme here -->
    </style>
</resources>''';
  }

  static String _aActivity(
      String pkg, String className, AndroidTemplate template, bool isKotlin) =>
      isKotlin
          ? _aKotlinActivity(pkg, className, template)
          : _aJavaActivity(pkg, className, template);

  static String _aKotlinActivity(
      String pkg, String className, AndroidTemplate template) {
    switch (template) {
      case AndroidTemplate.emptyActivity:
        return '''
package $pkg

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class $className : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
    }
}''';

      case AndroidTemplate.basicViews:
        return '''
package $pkg

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.google.android.material.snackbar.Snackbar

class $className : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        setSupportActionBar(findViewById<MaterialToolbar>(R.id.toolbar))
        findViewById<FloatingActionButton>(R.id.fab).setOnClickListener { view ->
            Snackbar.make(view, "Replace with your action", Snackbar.LENGTH_LONG)
                .setAction("Action", null).show()
        }
    }
}''';

      case AndroidTemplate.emptyCompose:
        return '''
package $pkg

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

class $className : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize(),
                        color = MaterialTheme.colorScheme.surface) {
                    Greeting("Android")
                }
            }
        }
    }
}

@Composable
fun Greeting(name: String, modifier: Modifier = Modifier) {
    Text(text = "Hello \$name!", modifier = modifier)
}''';

      case AndroidTemplate.bottomNavigation:
        return '''
package $pkg

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.Fragment
import com.google.android.material.bottomnavigation.BottomNavigationView

class $className : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        val navView: BottomNavigationView = findViewById(R.id.nav_view)
        if (savedInstanceState == null) loadFragment(HomeFragment())
        navView.setOnItemSelectedListener { item ->
            when (item.itemId) {
                R.id.navigation_home          -> loadFragment(HomeFragment())
                R.id.navigation_dashboard     -> loadFragment(DashboardFragment())
                R.id.navigation_notifications -> loadFragment(NotificationsFragment())
            }
            true
        }
    }
    private fun loadFragment(f: Fragment) =
        supportFragmentManager.beginTransaction().replace(R.id.fragment_container, f).commit()
}''';

      case AndroidTemplate.loginActivity:
        return '''
package $pkg

import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.textfield.TextInputEditText

class $className : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        val emailInput    = findViewById<TextInputEditText>(R.id.email_input)
        val passwordInput = findViewById<TextInputEditText>(R.id.password_input)
        val signInBtn     = findViewById<android.widget.Button>(R.id.sign_in_button)
        signInBtn.setOnClickListener {
            val email    = emailInput.text?.toString()?.trim() ?: ""
            val password = passwordInput.text?.toString() ?: ""
            if (email.isEmpty() || password.isEmpty()) {
                Toast.makeText(this, "Preencha todos os campos", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(this, "Entrando…", Toast.LENGTH_SHORT).show()
            }
        }
    }
}''';

      case AndroidTemplate.scrollingActivity:
        return '''
package $pkg

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.appbar.CollapsingToolbarLayout
import com.google.android.material.appbar.MaterialToolbar

class $className : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        val collapsingToolbar = findViewById<CollapsingToolbarLayout>(R.id.toolbar_layout)
        collapsingToolbar.title = getString(R.string.app_name)
    }
}''';

      case AndroidTemplate.navigationDrawer:
        return '''
package $pkg

import android.os.Bundle
import androidx.appcompat.app.ActionBarDrawerToggle
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.GravityCompat
import androidx.drawerlayout.widget.DrawerLayout
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.navigation.NavigationView

class $className : AppCompatActivity() {
    private lateinit var drawerLayout: DrawerLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        val toolbar: MaterialToolbar = findViewById(R.id.toolbar)
        setSupportActionBar(toolbar)
        drawerLayout = findViewById(R.id.drawer_layout)
        val toggle = ActionBarDrawerToggle(
            this, drawerLayout, toolbar,
            android.R.string.ok, android.R.string.cancel)
        drawerLayout.addDrawerListener(toggle)
        toggle.syncState()
        val navView: NavigationView = findViewById(R.id.nav_view)
        navView.setNavigationItemSelectedListener { item ->
            drawerLayout.closeDrawers()
            true
        }
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (drawerLayout.isDrawerOpen(GravityCompat.START)) {
            drawerLayout.closeDrawers()
        } else {
            super.onBackPressed()
        }
    }
}''';
    }
  }

  static String _aJavaActivity(
      String pkg, String className, AndroidTemplate template) {
    switch (template) {
      case AndroidTemplate.emptyActivity:
        return '''
package $pkg;

import android.os.Bundle;
import androidx.appcompat.app.AppCompatActivity;

public class $className extends AppCompatActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
    }
}''';

      case AndroidTemplate.basicViews:
        return '''
package $pkg;

import android.os.Bundle;
import androidx.appcompat.app.AppCompatActivity;
import com.google.android.material.appbar.MaterialToolbar;
import com.google.android.material.floatingactionbutton.FloatingActionButton;
import com.google.android.material.snackbar.Snackbar;

public class $className extends AppCompatActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        MaterialToolbar toolbar = findViewById(R.id.toolbar);
        setSupportActionBar(toolbar);
        FloatingActionButton fab = findViewById(R.id.fab);
        fab.setOnClickListener(view ->
            Snackbar.make(view, "Replace with your action", Snackbar.LENGTH_LONG)
                .setAction("Action", null).show());
    }
}''';

      case AndroidTemplate.emptyCompose:
        return _aKotlinActivity(pkg, className, template);

      case AndroidTemplate.bottomNavigation:
        return '''
package $pkg;

import android.os.Bundle;
import androidx.appcompat.app.AppCompatActivity;
import androidx.fragment.app.Fragment;
import com.google.android.material.bottomnavigation.BottomNavigationView;

public class $className extends AppCompatActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        BottomNavigationView navView = findViewById(R.id.nav_view);
        if (savedInstanceState == null) loadFragment(new HomeFragment());
        navView.setOnItemSelectedListener(item -> {
            int id = item.getItemId();
            if (id == R.id.navigation_home)          loadFragment(new HomeFragment());
            else if (id == R.id.navigation_dashboard)     loadFragment(new DashboardFragment());
            else if (id == R.id.navigation_notifications) loadFragment(new NotificationsFragment());
            return true;
        });
    }
    private void loadFragment(Fragment fragment) {
        getSupportFragmentManager().beginTransaction()
            .replace(R.id.fragment_container, fragment).commit();
    }
}''';

      case AndroidTemplate.loginActivity:
        return '''
package $pkg;

import android.os.Bundle;
import android.widget.Button;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;
import com.google.android.material.textfield.TextInputEditText;

public class $className extends AppCompatActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        TextInputEditText emailInput    = findViewById(R.id.email_input);
        TextInputEditText passwordInput = findViewById(R.id.password_input);
        Button signInBtn = findViewById(R.id.sign_in_button);
        signInBtn.setOnClickListener(v -> {
            String email    = emailInput.getText() != null ? emailInput.getText().toString().trim() : "";
            String password = passwordInput.getText() != null ? passwordInput.getText().toString() : "";
            if (email.isEmpty() || password.isEmpty()) {
                Toast.makeText(this, "Preencha todos os campos", Toast.LENGTH_SHORT).show();
            } else {
                Toast.makeText(this, "Entrando…", Toast.LENGTH_SHORT).show();
            }
        });
    }
}''';

      case AndroidTemplate.scrollingActivity:
        return '''
package $pkg;

import android.os.Bundle;
import androidx.appcompat.app.AppCompatActivity;
import com.google.android.material.appbar.CollapsingToolbarLayout;
import com.google.android.material.appbar.MaterialToolbar;

public class $className extends AppCompatActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        MaterialToolbar toolbar = findViewById(R.id.toolbar);
        setSupportActionBar(toolbar);
        CollapsingToolbarLayout collapsingToolbar = findViewById(R.id.toolbar_layout);
        collapsingToolbar.setTitle(getString(R.string.app_name));
    }
}''';

      case AndroidTemplate.navigationDrawer:
        return '''
package $pkg;

import android.os.Bundle;
import androidx.appcompat.app.ActionBarDrawerToggle;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.view.GravityCompat;
import androidx.drawerlayout.widget.DrawerLayout;
import com.google.android.material.appbar.MaterialToolbar;
import com.google.android.material.navigation.NavigationView;

public class $className extends AppCompatActivity {
    private DrawerLayout drawerLayout;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        MaterialToolbar toolbar = findViewById(R.id.toolbar);
        setSupportActionBar(toolbar);
        drawerLayout = findViewById(R.id.drawer_layout);
        ActionBarDrawerToggle toggle = new ActionBarDrawerToggle(
            this, drawerLayout, toolbar,
            android.R.string.ok, android.R.string.cancel);
        drawerLayout.addDrawerListener(toggle);
        toggle.syncState();
        NavigationView navView = findViewById(R.id.nav_view);
        navView.setNavigationItemSelectedListener(item -> {
            drawerLayout.closeDrawers();
            return true;
        });
    }

    @Override
    public void onBackPressed() {
        if (drawerLayout.isDrawerOpen(GravityCompat.START)) {
            drawerLayout.closeDrawers();
        } else {
            super.onBackPressed();
        }
    }
}''';
    }
  }

  static String _aMainLayout(AndroidTemplate template) {
    switch (template) {
      case AndroidTemplate.emptyActivity:
      case AndroidTemplate.emptyCompose:
        return '''
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Hello World!"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />
</androidx.constraintlayout.widget.ConstraintLayout>''';

      case AndroidTemplate.basicViews:
        return '''
<?xml version="1.0" encoding="utf-8"?>
<androidx.coordinatorlayout.widget.CoordinatorLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <com.google.android.material.appbar.AppBarLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:fitsSystemWindows="true">
        <com.google.android.material.appbar.MaterialToolbar
            android:id="@+id/toolbar"
            android:layout_width="match_parent"
            android:layout_height="?attr/actionBarSize" />
    </com.google.android.material.appbar.AppBarLayout>
    <include layout="@layout/content_main" />
    <com.google.android.material.floatingactionbutton.FloatingActionButton
        android:id="@+id/fab"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="bottom|end"
        android:layout_marginEnd="16dp"
        android:layout_marginBottom="16dp"
        app:srcCompat="@android:drawable/ic_input_add" />
</androidx.coordinatorlayout.widget.CoordinatorLayout>''';

      case AndroidTemplate.bottomNavigation:
        return '''
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical">
    <FrameLayout
        android:id="@+id/fragment_container"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1" />
    <com.google.android.material.bottomnavigation.BottomNavigationView
        android:id="@+id/nav_view"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        app:menu="@menu/bottom_nav_menu" />
</LinearLayout>''';

      case AndroidTemplate.loginActivity:
        return '''
<?xml version="1.0" encoding="utf-8"?>
<ScrollView
    xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:padding="24dp"
        android:gravity="center_horizontal">
        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="Sign In"
            android:textSize="28sp"
            android:textStyle="bold"
            android:layout_marginTop="48dp"
            android:layout_marginBottom="32dp" />
        <com.google.android.material.textfield.TextInputLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:hint="Email"
            style="@style/Widget.Material3.TextInputLayout.OutlinedBox"
            android:layout_marginBottom="16dp">
            <com.google.android.material.textfield.TextInputEditText
                android:id="@+id/email_input"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:inputType="textEmailAddress" />
        </com.google.android.material.textfield.TextInputLayout>
        <com.google.android.material.textfield.TextInputLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:hint="Password"
            style="@style/Widget.Material3.TextInputLayout.OutlinedBox"
            android:layout_marginBottom="24dp">
            <com.google.android.material.textfield.TextInputEditText
                android:id="@+id/password_input"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:inputType="textPassword" />
        </com.google.android.material.textfield.TextInputLayout>
        <com.google.android.material.button.MaterialButton
            android:id="@+id/sign_in_button"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Sign In"
            android:padding="14dp" />
    </LinearLayout>
</ScrollView>''';

      case AndroidTemplate.scrollingActivity:
        return '''
<?xml version="1.0" encoding="utf-8"?>
<androidx.coordinatorlayout.widget.CoordinatorLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <com.google.android.material.appbar.AppBarLayout
        android:id="@+id/app_bar"
        android:layout_width="match_parent"
        android:layout_height="192dp">
        <com.google.android.material.appbar.CollapsingToolbarLayout
            android:id="@+id/toolbar_layout"
            android:layout_width="match_parent"
            android:layout_height="match_parent"
            app:layout_scrollFlags="scroll|exitUntilCollapsed"
            app:contentScrim="?attr/colorPrimaryContainer">
            <com.google.android.material.appbar.MaterialToolbar
                android:id="@+id/toolbar"
                android:layout_width="match_parent"
                android:layout_height="?attr/actionBarSize"
                app:layout_collapseMode="pin" />
        </com.google.android.material.appbar.CollapsingToolbarLayout>
    </com.google.android.material.appbar.AppBarLayout>
    <androidx.core.widget.NestedScrollView
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        app:layout_behavior="@string/appbar_scrolling_view_behavior">
        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:padding="16dp"
            android:text="Scrollable content goes here.\n\nAdd more content to see the collapsing toolbar effect when scrolling." />
    </androidx.core.widget.NestedScrollView>
</androidx.coordinatorlayout.widget.CoordinatorLayout>''';

      case AndroidTemplate.navigationDrawer:
        return '''
<?xml version="1.0" encoding="utf-8"?>
<androidx.drawerlayout.widget.DrawerLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:id="@+id/drawer_layout"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:orientation="vertical">
        <com.google.android.material.appbar.MaterialToolbar
            android:id="@+id/toolbar"
            android:layout_width="match_parent"
            android:layout_height="?attr/actionBarSize" />
        <FrameLayout
            android:id="@+id/content_frame"
            android:layout_width="match_parent"
            android:layout_height="match_parent">
            <TextView
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:layout_gravity="center"
                android:text="Main Content" />
        </FrameLayout>
    </LinearLayout>
    <com.google.android.material.navigation.NavigationView
        android:id="@+id/nav_view"
        android:layout_width="wrap_content"
        android:layout_height="match_parent"
        android:layout_gravity="start"
        app:menu="@menu/nav_drawer_menu" />
</androidx.drawerlayout.widget.DrawerLayout>''';
    }
  }

  static String _aExtraFiles(
    String projectPath, String pkg, String pkgDir, String className,
    AndroidTemplate template, bool isKotlin, String fileExt, String srcDir,
  ) {
    switch (template) {
      case AndroidTemplate.emptyActivity:
      case AndroidTemplate.emptyCompose:
      case AndroidTemplate.loginActivity:
      case AndroidTemplate.scrollingActivity:
        return '';

      case AndroidTemplate.basicViews:
        return '''
cat > "$projectPath/app/src/main/res/layout/content_main.xml" << \'__LAYEREOF__\'
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    app:layout_behavior="@string/appbar_scrolling_view_behavior">
    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Hello World!"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />
</androidx.constraintlayout.widget.ConstraintLayout>
__LAYEREOF__
''';

      case AndroidTemplate.navigationDrawer:
        return '''
cat > "$projectPath/app/src/main/res/menu/nav_drawer_menu.xml" << \'__LAYEREOF__\'
<?xml version="1.0" encoding="utf-8"?>
<menu xmlns:android="http://schemas.android.com/apk/res/android">
    <group android:checkableBehavior="single">
        <item android:id="@+id/nav_home"
              android:icon="@android:drawable/ic_menu_compass"
              android:title="Home" />
        <item android:id="@+id/nav_gallery"
              android:icon="@android:drawable/ic_menu_gallery"
              android:title="Gallery" />
        <item android:id="@+id/nav_settings"
              android:icon="@android:drawable/ic_menu_preferences"
              android:title="Settings" />
    </group>
</menu>
__LAYEREOF__
''';

      case AndroidTemplate.bottomNavigation:
        final buf = StringBuffer();
        buf.writeln('''
cat > "$projectPath/app/src/main/res/menu/bottom_nav_menu.xml" << \'__LAYEREOF__\'
<?xml version="1.0" encoding="utf-8"?>
<menu xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:id="@+id/navigation_home"
          android:icon="@android:drawable/ic_menu_compass"
          android:title="Home" />
    <item android:id="@+id/navigation_dashboard"
          android:icon="@android:drawable/ic_menu_sort_by_size"
          android:title="Dashboard" />
    <item android:id="@+id/navigation_notifications"
          android:icon="@android:drawable/ic_popup_reminder"
          android:title="Notifications" />
</menu>
__LAYEREOF__
''');
        for (final name in ['Home', 'Dashboard', 'Notifications']) {
          final lower = name.toLowerCase();
          buf.writeln('''
cat > "$projectPath/app/src/main/res/layout/fragment_$lower.xml" << \'__LAYEREOF__\'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent">
    <TextView android:layout_width="match_parent" android:layout_height="match_parent"
        android:gravity="center" android:text="$name Fragment" />
</FrameLayout>
__LAYEREOF__
''');
          final content = isKotlin
              ? _aKotlinFragment(pkg, name)
              : _aJavaFragment(pkg, name);
          buf.writeln('''
cat > "$projectPath/app/src/main/$srcDir/$pkgDir/${name}Fragment.$fileExt" << \'__LAYEREOF__\'
$content
__LAYEREOF__
''');
        }
        return buf.toString();
    }
  }

  static String _aKotlinFragment(String pkg, String name) => '''
package $pkg

import android.os.Bundle
import android.view.*
import androidx.fragment.app.Fragment

class ${name}Fragment : Fragment() {
    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?,
                              savedInstanceState: Bundle?): View? =
        inflater.inflate(R.layout.fragment_${name.toLowerCase()}, container, false)
}''';

  static String _aJavaFragment(String pkg, String name) => '''
package $pkg;

import android.os.Bundle;
import android.view.*;
import androidx.annotation.*;
import androidx.fragment.app.Fragment;

public class ${name}Fragment extends Fragment {
    @Nullable @Override
    public View onCreateView(@NonNull LayoutInflater inflater,
                             @Nullable ViewGroup container,
                             @Nullable Bundle savedInstanceState) {
        return inflater.inflate(R.layout.fragment_${name.toLowerCase()}, container, false);
    }
}''';

  static ProjectTemplate forSdk(SdkType sdk) => ProjectTemplate(sdk);

  // ── Repair helpers ────────────────────────────────────────────────────────

  static String repairFlutterAndroid(String projectPath) {
    const androidSdkDir = r'$PREFIX/opt/android-sdk';
    return r'''
(
  GPROPS="''' +
        projectPath +
        r'''/android/gradle.properties"
  if [ ! -f "$GPROPS" ]; then echo "gradle.properties not found"; exit 1; fi
  sed -i 's/-Xmx[0-9]*[mMgG]/-Xmx512m/g' "$GPROPS"
  sed -i '/-XX:MaxMetaspaceSize/d' "$GPROPS"
  sed -i '/-XX:+HeapDumpOnOutOfMemoryError/d' "$GPROPS"
  echo "✓ Capped JVM"
  SDK_ROOT="${ANDROID_HOME:-''' +
        androidSdkDir +
        r'''}"
  AAPT2_BIN=$(find "$SDK_ROOT/build-tools" -name aapt2 2>/dev/null | sort -rV | head -1)
  if [ -n "$AAPT2_BIN" ]; then
    sed -i '/android\.aapt2FromMavenOverride/d' "$GPROPS"
    printf '\nandroid.aapt2FromMavenOverride=%s\n' "$AAPT2_BIN" >> "$GPROPS"
    echo "✓ aapt2 override → $AAPT2_BIN"
  fi
) 2>&1''';
  }

  static String repairNativeAndroid(String projectPath) {
    const androidSdkDir = r'$PREFIX/opt/android-sdk';
    return r'''
(
  GPROPS="''' +
        projectPath +
        r'''/gradle.properties"
  if [ ! -f "$GPROPS" ]; then echo "gradle.properties not found"; exit 1; fi
  sed -i 's/-Xmx[0-9]*[mMgG]/-Xmx512m/g' "$GPROPS"
  sed -i '/-XX:MaxMetaspaceSize/d' "$GPROPS"
  sed -i '/-XX:+HeapDumpOnOutOfMemoryError/d' "$GPROPS"
  echo "✓ Capped JVM"
  SDK_ROOT="${ANDROID_HOME:-''' +
        androidSdkDir +
        r'''}"
  AAPT2_BIN=$(find "$SDK_ROOT/build-tools" -name aapt2 2>/dev/null | sort -rV | head -1)
  if [ -n "$AAPT2_BIN" ]; then
    sed -i '/android\.aapt2FromMavenOverride/d' "$GPROPS"
    printf '\nandroid.aapt2FromMavenOverride=%s\n' "$AAPT2_BIN" >> "$GPROPS"
    echo "✓ aapt2 override → $AAPT2_BIN"
  fi
) 2>&1''';
  }
}