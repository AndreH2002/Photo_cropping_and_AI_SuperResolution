import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:saver_gallery/saver_gallery.dart';

import 'esrgan_service.dart';



class CropPage extends StatefulWidget {
  const CropPage({super.key, required this.image});
  final File image;
  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  late File originalImage;
  File? copyOfImage;
  final esrgan = ESRGAN_Service();

  bool isEnhancing = false;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    originalImage = widget.image;
    esrgan.loadModel();
    _initImageCopy();
  }

  void _initImageCopy() async {
    //this creates a copy of the image that we will want to save cropped later with a new filename with the current date to ensure uniquness
    final copied = 
      await originalImage.copy('${originalImage.parent.path}/copy_${DateTime.now().millisecondsSinceEpoch}.jpg');
    setState(() {
      copyOfImage = copied;
    });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        
        title: const Text('Editor'),
        backgroundColor: Colors.deepPurple,
        actions: [
          TextButton(
            onPressed: null, 
            child: const Text(
              'Done',
              style: TextStyle(color: Colors.white70),
            ),
          )
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: copyOfImage == null || isEnhancing == true
              ? const CircularProgressIndicator()
              : Column(
                children: [
                  Expanded(child: Image.file(copyOfImage!)),
                ],
              ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
          
              //Crop button
              ElevatedButton.icon(
                onPressed: () async{
                  if(copyOfImage != null) {
                    final cropped = await _cropImage(imageFile: copyOfImage!);
                    if (cropped != null) {
                      setState(() {
                        copyOfImage = cropped;
                      });
                    }
                  }
                  
                },
                icon: const Icon(Icons.crop),
                label: const Text('Crop Image'),
                
              ),
          
              //Revert Button
              ElevatedButton.icon(  
                onPressed: () {
                  setState(() {
                    copyOfImage = originalImage;
                  });
                },
          
                icon: const Icon(Icons.refresh),
                label: const Text('Revert to original'),
              ),
              
            //Enhance Button
              ElevatedButton.icon(
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Enhance'),
              onPressed: isEnhancing
                ? null // Disable while enhancing
                : () async {
                setState(() => isEnhancing = true);
          
                if (copyOfImage != null) {
                final enhancedImage = await esrgan.enhanceFile(copyOfImage!);
          
                setState(() {
                  if (enhancedImage != null) {
                    copyOfImage = enhancedImage;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Image enhanced successfully')),
                    );
                  } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enhancement failed')),
                );
                }
                isEnhancing = false;
                });
                } else {
                  setState(() => isEnhancing = false);
                  }
                },
              ),

              //Save Button
              IconButton(
                onPressed: () async{
                  final result = await _savePhoto();
                  if(result != null) {
                    if(context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(  
                      SnackBar(content: Text('Image saved to gallery')),
                      );
                    }
                    
                  }
                  else {
                    if(context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to save image')),
                      );
                    }
                    
                  }
                }, 
                icon: Icon(Icons.download),
              ),
          
            ],
          ),
        ),
      ),
    );
  }




  Future<File?> _cropImage({required File imageFile})  async{
    CroppedFile? croppedImage = 
      await ImageCropper().cropImage(sourcePath: imageFile.path);
    if(croppedImage == null) return null;

    return File(croppedImage.path);
  }


  Future <SaveResult?> _savePhoto() async {
    if(copyOfImage != null){

        Uint8List bytes = await copyOfImage!.readAsBytes();

       final result = await SaverGallery.saveImage(  
        bytes,
        fileName: copyOfImage!.path,
        quality: 100,
        skipIfExists: false,
    );
    return result;
    }
    return null;
  }

  Future<bool> checkAndRequestPermissions({required bool skipIfExists}) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return false; // Only Android and iOS platforms are supported
  }

  if (Platform.isAndroid) {
    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = deviceInfo.version.sdkInt;

    if (skipIfExists) {
      // Read permission is required to check if the file already exists
      return sdkInt >= 33
          ? await Permission.photos.request().isGranted
          : await Permission.storage.request().isGranted;
    } else {
      // No read permission required for Android SDK 29 and above
      return sdkInt >= 29 ? true : await Permission.storage.request().isGranted;
    }
  } else if (Platform.isIOS) {
    // iOS permission for saving images to the gallery
    return skipIfExists
        ? await Permission.photos.request().isGranted
        : await Permission.photosAddOnly.request().isGranted;
  }

  return false; 
}
}