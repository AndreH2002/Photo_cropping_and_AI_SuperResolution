import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photo Crop App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Photo Crop App'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: Text(widget.title, style: theme.textTheme.titleLarge),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.crop,
              size: 100,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              'Select a photo to crop',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            FilledButton.icon(
              onPressed: () {
                // Trigger photo picker logic here
              },
              icon: const Icon(Icons.photo_library),
              label: const Text('Choose from Gallery'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 15),
            OutlinedButton.icon(
              onPressed: () {
                // Trigger camera picker logic here
              },
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take a Photo'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}