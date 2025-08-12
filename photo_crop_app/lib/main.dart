import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_crop_app/croppage.dart';

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
  File? _image;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.crop,
                    size: 100,
                    color: Colors.deepPurple,
                  ),
                  const SizedBox(height: 20),
                  
                  const Text(
                    'Choose a photo to crop',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),


                  // -- previews the image if available
                  imagePreviewWidget(),
                  const SizedBox(height: 20),

                  // -- Select from gallery --

                  ElevatedButton.icon(
                    onPressed: () {
                      _chosePhoto(true);
                    },
                    icon: const Icon(Icons.photo),
                    label: const Text('Pick from Gallery'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),

                  //  -- Chose from camera roll --

                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      _chosePhoto(false);
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Take a Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _chosePhoto(bool fromGallery) async{
    final picker = ImagePicker();
    
    final pickedImage = await picker.pickImage(
      source: fromGallery ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 100, // Enforces JPEG conversion
      preferredCameraDevice: CameraDevice.rear,
    );

    if(pickedImage != null) {
      
      setState(() {
        _image = File(pickedImage.path);
      });
    }
  }

  Widget imagePreviewWidget() {
    return 
    _image == null
    ? SizedBox()
    : ClipRRect(
      borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          onTap: () { 
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CropPage(image: _image!)),
            );
          
          },
          child: Image.file(  
            File(_image!.path),
            width: 200,
            height: 200,
            fit: BoxFit.cover,
          ),
        ),
      
    );
  }
}