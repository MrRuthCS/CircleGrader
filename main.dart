import 'dart:typed_data'; // Required for Uint8List
import 'dart:math'; // Required for distance calculation
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img; // Import the image package
import 'package:audioplayers/audioplayers.dart';

// Global variable to hold the list of available cameras
late List<CameraDescription> cameras;

Future<void> main() async {
  // Ensure that plugin services are initialized so that `availableCameras()` can be called.
  WidgetsFlutterBinding.ensureInitialized();

  // Obtain a list of the available cameras on the device.
  cameras = await availableCameras();
  
  runApp(const CameraApp());
}

class CameraApp extends StatelessWidget {
  const CameraApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pixel Analyzer',
      theme: ThemeData.dark(),
      // Define the routes for navigation.
      routes: {
        '/': (context) => const InformationScreen(),
        '/camera': (context) => const CameraScreen(),
      },
      initialRoute: '/',
      debugShowCheckedModeBanner: false,
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({Key? key}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  // State variable to hold the current flash mode.
  FlashMode _currentFlashMode = FlashMode.off;

  final AudioPlayer _audioPlayer = AudioPlayer(); // Initialize player


  @override
  void initState() {
    super.initState();
    // To display the current output from the Camera, you need to create a
    // CameraController.
    _controller = CameraController(
      // Get a specific camera from the list of available cameras.
      cameras.first,
      // Define the resolution to use.
      ResolutionPreset.high,
      // Disable audio since we only need pictures.
      enableAudio: false,
    );


    // Next, initialize the controller. This returns a Future.
    _initializeControllerFuture = _controller.initialize().then((_) {
      // Set the initial flash mode once the controller is initialized.
      if (!mounted) return;
      _controller.setFlashMode(_currentFlashMode);
    });
  }

  @override
  void dispose() {
    // Dispose of the controller when the widget is disposed.
    _controller.dispose();

    _audioPlayer.dispose();

    super.dispose();
  }

  Future<void> _playSound() async {
    await _audioPlayer.play(AssetSource('shutter.mp3'), volume: 1.0);
  }

  // A map to define the next flash mode in the cycle.
  final Map<FlashMode, FlashMode> _nextFlashMode = {
    FlashMode.off: FlashMode.auto,
    FlashMode.auto: FlashMode.always,
    FlashMode.always: FlashMode.torch,
    FlashMode.torch: FlashMode.off,
  };

  // A map to associate flash modes with icons.
  final Map<FlashMode, IconData> _flashIcons = {
    FlashMode.off: Icons.flash_off,
    FlashMode.auto: Icons.flash_auto,
    FlashMode.always: Icons.flash_on,
    FlashMode.torch: Icons.highlight,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture Circle'),
        centerTitle: true,
        // Add a leading home button to the AppBar.
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () {
            // This is the main "home" screen, do nothing.
          },
        ),
        // Add an actions list for buttons on the right side.
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InformationScreen()),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            // If the Future is complete, display the preview in a Stack.
            return Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // The camera preview is the base layer.
                CameraPreview(_controller),
                // The CustomPaint widget draws the circles on top.
                CustomPaint(
                  size: Size.infinite,
                  painter: CirclePainter(),
                ),
              ],
            );
          } else {
            // Otherwise, display a loading indicator.
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      // Use a Row to display multiple FloatingActionButtons
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            // Button to toggle the flash.
            FloatingActionButton(
              heroTag: 'flash_button', // Unique hero tag
              onPressed: () async {
                try {
                  // Get the next flash mode from our map.
                  final nextMode = _nextFlashMode[_currentFlashMode]!;
                  // Set the flash mode on the controller.
                  await _controller.setFlashMode(nextMode);
                  // Update the state to rebuild the UI with the new icon.
                  setState(() {
                    _currentFlashMode = nextMode;
                  });
                } catch (e) {
                  print(e);
                }
              },
              child: Icon(_flashIcons[_currentFlashMode]),
            ),
            // Button to take the picture.
            FloatingActionButton(
              heroTag: 'camera_button', // Unique hero tag
              onPressed: () async {
                try {
                  await _initializeControllerFuture;
                  final imageFile = await _controller.takePicture();
                  final imageBytes = await imageFile.readAsBytes();

                  await _playSound();

                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AnalysisScreen(imageData: imageBytes),
                    ),
                  );
                } catch (e) {
                  print(e);
                }
              },
              child: const Icon(Icons.camera_alt),
            ),
          ],
        ),
      ),
    );
  }
}

// A widget that displays the original image and a processed monochrome version.
class AnalysisScreen extends StatefulWidget {
  final Uint8List imageData;

  const AnalysisScreen({Key? key, required this.imageData}) : super(key: key);

  @override
  _AnalysisScreenState createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  Uint8List? _croppedOriginalImageData;
  Uint8List? _monochromeImageData;
  bool _isProcessingMonochrome = true;
  double _sliderValue = 128.0; // State for the slider's value.

  @override
  void initState() {
    super.initState();
    _initializeAndProcess();
  }

  // Runs once to prepare the cropped original and the first monochrome image.
  Future<void> _initializeAndProcess() async {
    final originalImage = img.decodeImage(widget.imageData);
    if (originalImage == null) {
      if (mounted) setState(() => _isProcessingMonochrome = false);
      return;
    }

    // --- Process the cropped original image for display ---
    final width = originalImage.width;
    final height = originalImage.height;
    final yOffset = ((height - width) / 2).floor();
    final croppedOriginal = img.copyCrop(originalImage, x:0, y:yOffset, width:width, height:width);
    
    // Set state for the top image
    if (mounted) {
      setState(() {
        _croppedOriginalImageData = Uint8List.fromList(img.encodeJpg(croppedOriginal));
      });
    }

    // --- Process the initial monochrome image ---
    await _createMonochromeImage(originalImage);
  }

  // Can be called repeatedly by the "Reprocess" button.
  Future<void> _createMonochromeImage([img.Image? originalImage]) async {
    if (mounted) setState(() => _isProcessingMonochrome = true);

    // Decode the image if it wasn't passed in from the initial run.
    final imageToProcess = originalImage ?? img.decodeImage(widget.imageData);
    if (imageToProcess == null) {
      if (mounted) setState(() => _isProcessingMonochrome = false);
      return;
    }

    final int threshold = _sliderValue.floor();
    final width = imageToProcess.width;
    final height = imageToProcess.height;
    final yOffset = ((height - width) / 2).floor();

    final monochromeImage = img.Image(width: width, height: width);
    for (int y = 0; y < width; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = imageToProcess.getPixel(x, y + yOffset);
        final brightness = (pixel.r + pixel.g + pixel.b) / 3;
        if (brightness > threshold) {
          monochromeImage.setPixelRgb(x, y, 255, 255, 255); // White
        } else {
          monochromeImage.setPixelRgb(x, y, 0, 0, 0); // Black
        }
      }
    }
    
    final processedImageData = Uint8List.fromList(img.encodeJpg(monochromeImage));
    if (mounted) {
      setState(() {
        _monochromeImageData = processedImageData;
        _isProcessingMonochrome = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monochrome'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () {
            Navigator.of(context).popUntil(ModalRoute.withName('/camera'));
          },
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InformationScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: <Widget>[
              // Display the processed monochrome image.
              _isProcessingMonochrome
                  ? const Center(child: CircularProgressIndicator())
                  : _monochromeImageData != null
                      ? Image.memory(_monochromeImageData!)
                      : const Text('Error processing image.'),
              
              const SizedBox(height: 16),

              // --- UI elements for threshold control ---
              Text('Adjust to remove noise: ${(_sliderValue/2.56).floor()}%', style: const TextStyle(fontSize: 16)),
              Slider(
                value: _sliderValue,
                min: 0,
                max: 255,
                divisions: 255,
                label: _sliderValue.floor().toString(),
                onChanged: (double value) {
                  setState(() {
                    _sliderValue = value;
                  });
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800], // A lighter shade of grey
                    ),
                    onPressed: () => _createMonochromeImage(), // Call the processing function.
                    child: const Text('Re-Scan'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800], // A lighter shade of grey
                    ),
                    onPressed: () {
                      if (_monochromeImageData != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ScoreScreen(
                              monochromeImageData: _monochromeImageData!,
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text('Score'),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),

              // --- Display for cropped original image ---
              _croppedOriginalImageData == null
                  ? const Center(child: CircularProgressIndicator())
                  : Image.memory(_croppedOriginalImageData!),
            ],
          ),
        ),
      ),
    );
  }
}

enum ScanPhase { 
  topDown, 
  bottomUp, 
  leftToRight, 
  rightToLeft, 
  diagTlbr, // Top-Left to Bottom-Right
  diagBrTl, // Bottom-Right to Top-Left
  diagTrbl, // Top-Right to Bottom-Left
  diagBlTr, // Bottom-Left to Top-Right
  completed 
}

// A widget that displays the score screen with animation.
class ScoreScreen extends StatefulWidget {
  final Uint8List monochromeImageData;

  const ScoreScreen({Key? key, required this.monochromeImageData}) : super(key: key);

  @override
  _ScoreScreenState createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  img.Image? _decodedImage;
  Offset? _verticalDiameter1;
  Offset? _verticalDiameter2;
  double? _verticalDiameterLength;
  Offset? _horizontalDiameter1;
  Offset? _horizontalDiameter2;
  double? _horizontalDiameterLength;
  Offset? _diag1_p1, _diag1_p2;
  double? _diag1_length;
  Offset? _diag2_p1, _diag2_p2;
  double? _diag2_length;
  double? _averageDiameter;
  double? _averageDeviation;
  double? _circleScore;

  ScanPhase _scanPhase = ScanPhase.topDown;

  @override
  void initState() {
    super.initState();
    _decodedImage = img.decodeImage(widget.monochromeImageData);

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addListener(_scanImage);
    
    _animationController.forward();
  }

  void _scanImage() {
    if (_decodedImage == null || _scanPhase == ScanPhase.completed) return;

    final width = _decodedImage!.width;
    final height = _decodedImage!.height;

    switch (_scanPhase) {
      case ScanPhase.topDown:
        final currentY = ((height * _animationController.value).floor()).clamp(0, height - 1);
        int firstX = -1, lastX = -1;
        for (int x = 0; x < width; x++) {
          if (_decodedImage!.getPixel(x, currentY).r == 0) {
            if (firstX == -1) firstX = x;
            lastX = x;
          }
        }
        if (firstX != -1) {
          _moveToNextPhase(ScanPhase.bottomUp, p1: Offset(firstX + (lastX - firstX) / 2.0, currentY.toDouble()));
          return;
        }
        break;
      case ScanPhase.bottomUp:
        final currentY = ((height * (1.0 - _animationController.value)).floor()).clamp(0, height - 1);
        int firstX = -1, lastX = -1;
        for (int x = 0; x < width; x++) {
          if (_decodedImage!.getPixel(x, currentY).r == 0) {
            if (firstX == -1) firstX = x;
            lastX = x;
          }
        }
        if (firstX != -1) {
          _moveToNextPhase(ScanPhase.leftToRight, p2: Offset(firstX + (lastX - firstX) / 2.0, currentY.toDouble()));
          return;
        }
        break;
      case ScanPhase.leftToRight:
        final currentX = ((width * _animationController.value).floor()).clamp(0, width - 1);
        int firstY = -1, lastY = -1;
        for (int y = 0; y < height; y++) {
          if (_decodedImage!.getPixel(currentX, y).r == 0) {
            if (firstY == -1) firstY = y;
            lastY = y;
          }
        }
        if (firstY != -1) {
          _moveToNextPhase(ScanPhase.rightToLeft, p1: Offset(currentX.toDouble(), firstY + (lastY - firstY) / 2.0));
          return;
        }
        break;
      case ScanPhase.rightToLeft:
        final currentX = ((width * (1.0 - _animationController.value)).floor()).clamp(0, width - 1);
        int firstY = -1, lastY = -1;
        for (int y = 0; y < height; y++) {
          if (_decodedImage!.getPixel(currentX, y).r == 0) {
            if (firstY == -1) firstY = y;
            lastY = y;
          }
        }
        if (firstY != -1) {
          _moveToNextPhase(ScanPhase.diagTlbr, p2: Offset(currentX.toDouble(), firstY + (lastY - firstY) / 2.0));
          return;
        }
        break;
      case ScanPhase.diagTlbr:
        final kMax = width + height - 2;
        final k = (_animationController.value * kMax).floor();
        List<Offset> blackPixels = [];
        for (int x = 0; x <= k; x++) {
          int y = k - x;
          if (x < width && y >= 0 && y < height && _decodedImage!.getPixel(x, y).r == 0) {
            blackPixels.add(Offset(x.toDouble(), y.toDouble()));
          }
        }
        if (blackPixels.isNotEmpty) {
          final p1 = blackPixels.first;
          final p2 = blackPixels.last;
          _moveToNextPhase(ScanPhase.diagBrTl, p1: Offset(p1.dx + (p2.dx - p1.dx) / 2.0, p1.dy + (p2.dy - p1.dy) / 2.0));
          return;
        }
        break;
      case ScanPhase.diagBrTl:
        final kMax = width + height - 2;
        final k = ((1.0 - _animationController.value) * kMax).floor();
        List<Offset> blackPixels = [];
        for (int x = k; x >= 0; x--) {
          int y = k - x;
          if (x < width && y >= 0 && y < height && _decodedImage!.getPixel(x, y).r == 0) {
            blackPixels.add(Offset(x.toDouble(), y.toDouble()));
          }
        }
        if (blackPixels.isNotEmpty) {
          final p1 = blackPixels.first;
          final p2 = blackPixels.last;
          _moveToNextPhase(ScanPhase.diagTrbl, p2: Offset(p1.dx + (p2.dx - p1.dx) / 2.0, p1.dy + (p2.dy - p1.dy) / 2.0));
          return;
        }
        break;
      case ScanPhase.diagTrbl:
        final kMin = -(height - 1);
        final kMax = width - 1;
        final k = kMin + (_animationController.value * (kMax - kMin)).floor();
        List<Offset> blackPixels = [];
        for (int x = 0; x < width; x++) {
          int y = x - k;
          if (y >= 0 && y < height && _decodedImage!.getPixel(x, y).r == 0) {
            blackPixels.add(Offset(x.toDouble(), y.toDouble()));
          }
        }
        if (blackPixels.isNotEmpty) {
          final p1 = blackPixels.first;
          final p2 = blackPixels.last;
          _moveToNextPhase(ScanPhase.diagBlTr, p1: Offset(p1.dx + (p2.dx - p1.dx) / 2.0, p1.dy + (p2.dy - p1.dy) / 2.0));
          return;
        }
        break;
      case ScanPhase.diagBlTr:
        final kMin = -(height - 1);
        final kMax = width - 1;
        final k = kMax - (_animationController.value * (kMax - kMin)).floor();
        List<Offset> blackPixels = [];
        for (int x = width - 1; x >= 0; x--) {
          int y = x - k;
          if (y >= 0 && y < height && _decodedImage!.getPixel(x, y).r == 0) {
            blackPixels.add(Offset(x.toDouble(), y.toDouble()));
          }
        }
        if (blackPixels.isNotEmpty) {
          final p1 = blackPixels.first;
          final p2 = blackPixels.last;
          _moveToNextPhase(ScanPhase.completed, p2: Offset(p1.dx + (p2.dx - p1.dx) / 2.0, p1.dy + (p2.dy - p1.dy) / 2.0));
          return;
        }
        break;
      case ScanPhase.completed:
        break;
    }
    setState(() {});
  }

  void _moveToNextPhase(ScanPhase nextPhase, {Offset? p1, Offset? p2}) {
    _animationController.stop();
    if (mounted) {
      setState(() {
        if (_scanPhase == ScanPhase.topDown) {
          _verticalDiameter1 = p1;
        } else if (_scanPhase == ScanPhase.bottomUp) {
          _verticalDiameter2 = p2;
          _verticalDiameterLength = (_verticalDiameter1! - _verticalDiameter2!).distance;
        } else if (_scanPhase == ScanPhase.leftToRight) {
          _horizontalDiameter1 = p1;
        } else if (_scanPhase == ScanPhase.rightToLeft) {
          _horizontalDiameter2 = p2;
          _horizontalDiameterLength = (_horizontalDiameter1! - _horizontalDiameter2!).distance;
        } else if (_scanPhase == ScanPhase.diagTlbr) {
          _diag1_p1 = p1;
        } else if (_scanPhase == ScanPhase.diagBrTl) {
          _diag1_p2 = p2;
          _diag1_length = (_diag1_p1! - _diag1_p2!).distance;
        } else if (_scanPhase == ScanPhase.diagTrbl) {
          _diag2_p1 = p1;
        } else if (_scanPhase == ScanPhase.diagBlTr) {
          _diag2_p2 = p2;
          _diag2_length = (_diag2_p1! - _diag2_p2!).distance;
          _averageDiameter = (_verticalDiameterLength! + _horizontalDiameterLength! + _diag1_length! + _diag2_length!) / 4;
          final dev1 = (_averageDiameter! - _verticalDiameterLength!).abs();
          final dev2 = (_averageDiameter! - _horizontalDiameterLength!).abs();
          final dev3 = (_averageDiameter! - _diag1_length!).abs();
          final dev4 = (_averageDiameter! - _diag2_length!).abs();
          _averageDeviation = (dev1 + dev2 + dev3 + dev4) / 4;
          _circleScore = 100.0 - (_averageDeviation! * 0.6);
        }
        _scanPhase = nextPhase;
      });
      if (nextPhase != ScanPhase.completed) {
        _animationController.reset();
        _animationController.forward();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Score'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () {
            Navigator.of(context).popUntil(ModalRoute.withName('/camera'));
          },
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _decodedImage == null
                  ? const Text('Error decoding image for scoring.')
                  : Stack(
                      children: [
                        Image.memory(widget.monochromeImageData),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: ScorePainter(
                              animation: _animationController,
                              image: _decodedImage!,
                              scanPhase: _scanPhase,
                              verticalDiameter1: _verticalDiameter1,
                              verticalDiameter2: _verticalDiameter2,
                              horizontalDiameter1: _horizontalDiameter1,
                              horizontalDiameter2: _horizontalDiameter2,
                              diag1_p1: _diag1_p1,
                              diag1_p2: _diag1_p2,
                              diag2_p1: _diag2_p1,
                              diag2_p2: _diag2_p2,
                            ),
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 24),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Table(
                          columnWidths: const {
                            0: FlexColumnWidth(1),
                            1: FlexColumnWidth(1),
                            2: FlexColumnWidth(1),
                          },
                          children: [
                            TableRow(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8.0),
                                  child: Text('Diameter', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8.0),
                                  child: Text('Length', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8.0),
                                  child: Text('Deviation', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const Text('Vertical', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text(_verticalDiameterLength?.round().toString() ?? '...'),
                                Text(_averageDiameter != null ? (_averageDiameter! - _verticalDiameterLength!).abs().toStringAsFixed(1) : '...'),
                              ],
                            ),
                            TableRow(
                              children: [
                                const Text('Horizontal', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text(_horizontalDiameterLength?.round().toString() ?? '...'),
                                Text(_averageDiameter != null ? (_averageDiameter! - _horizontalDiameterLength!).abs().toStringAsFixed(1) : '...'),
                              ],
                            ),
                            TableRow(
                              children: [
                                const Text('Diagonal1', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text(_diag1_length?.round().toString() ?? '...'),
                                Text(_averageDiameter != null ? (_averageDiameter! - _diag1_length!).abs().toStringAsFixed(1) : '...'),
                              ],
                            ),
                            TableRow(
                              children: [
                                const Text('Diagonal2', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text(_diag2_length?.round().toString() ?? '...'),
                                Text(_averageDiameter != null ? (_averageDiameter! - _diag2_length!).abs().toStringAsFixed(1) : '...'),
                              ],
                            ),
                            if (_averageDiameter != null)
                              TableRow(
                                children: [
                                  const Text('Avg', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text(_averageDiameter?.toStringAsFixed(1) ?? '...'),
                                  Text(_averageDeviation?.toStringAsFixed(1) ?? '...'),
                                ],
                              ),
                          ],
                        ),
                        if (_circleScore != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Circle Score: ${_circleScore?.toStringAsFixed(1) ?? '...'}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom painter for the scoring animation.
class ScorePainter extends CustomPainter {
  final Animation<double> animation;
  final img.Image image;
  final ScanPhase scanPhase;
  final Offset? verticalDiameter1, verticalDiameter2;
  final Offset? horizontalDiameter1, horizontalDiameter2;
  final Offset? diag1_p1, diag1_p2;
  final Offset? diag2_p1, diag2_p2;

  ScorePainter({
    required this.animation,
    required this.image,
    required this.scanPhase,
    this.verticalDiameter1,
    this.verticalDiameter2,
    this.horizontalDiameter1,
    this.horizontalDiameter2,
    this.diag1_p1,
    this.diag1_p2,
    this.diag2_p1,
    this.diag2_p2,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2.0;
    
    // Draw scanning line
    if (scanPhase != ScanPhase.completed) {
      if (scanPhase == ScanPhase.topDown || scanPhase == ScanPhase.bottomUp) {
        final y = (scanPhase == ScanPhase.topDown) ? size.height * animation.value : size.height * (1.0 - animation.value);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      } else if (scanPhase == ScanPhase.leftToRight || scanPhase == ScanPhase.rightToLeft) {
        final x = (scanPhase == ScanPhase.leftToRight) ? size.width * animation.value : size.width * (1.0 - animation.value);
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      } else if (scanPhase == ScanPhase.diagTlbr || scanPhase == ScanPhase.diagBrTl) {
        final kMax = size.width + size.height;
        final k = (scanPhase == ScanPhase.diagTlbr) ? animation.value * kMax : (1.0 - animation.value) * kMax;
        final p1 = Offset(max(0, k - size.height), min(k, size.height));
        final p2 = Offset(min(k, size.width), max(0, k - size.width));
        canvas.drawLine(p1, p2, linePaint);
      } else if (scanPhase == ScanPhase.diagTrbl || scanPhase == ScanPhase.diagBlTr) {
        final kMin = -size.height;
        final kMax = size.width;
        final k = (scanPhase == ScanPhase.diagTrbl) ? kMin + (animation.value * (kMax - kMin)) : kMax - (animation.value * (kMax - kMin));
        final p1 = Offset(max(0, k), max(0, -k));
        final p2 = Offset(min(size.width, size.height + k), min(size.height, size.width - k));
        canvas.drawLine(p1, p2, linePaint);
      }
    }

    final double scaleX = size.width / image.width;
    final double scaleY = size.height / image.height;

    void drawPoint(Offset? point) {
      if (point != null) {
        final circlePaint = Paint()..color = Colors.blue;
        final canvasPoint = Offset(point.dx * scaleX, point.dy * scaleY);
        canvas.drawCircle(canvasPoint, 5, circlePaint);
      }
    }

    void drawLine(Offset? p1, Offset? p2) {
      if (p1 != null && p2 != null) {
        final canvasP1 = Offset(p1.dx * scaleX, p1.dy * scaleY);
        final canvasP2 = Offset(p2.dx * scaleX, p2.dy * scaleY);
        canvas.drawLine(canvasP1, canvasP2, linePaint);
      }
    }

    drawPoint(verticalDiameter1);
    drawPoint(verticalDiameter2);
    drawLine(verticalDiameter1, verticalDiameter2);

    drawPoint(horizontalDiameter1);
    drawPoint(horizontalDiameter2);
    drawLine(horizontalDiameter1, horizontalDiameter2);

    drawPoint(diag1_p1);
    drawPoint(diag1_p2);
    drawLine(diag1_p1, diag1_p2);

    drawPoint(diag2_p1);
    drawPoint(diag2_p2);
    drawLine(diag2_p1, diag2_p2);
  }

  @override
  bool shouldRepaint(covariant ScorePainter oldDelegate) => true;
}


// A widget that displays information about the app.
class InformationScreen extends StatelessWidget {
  const InformationScreen({Key? key}) : super(key: key);

  // Helper method to create styled text. Makes the text section below easy to modify.
  Widget _buildInfoText(String text, {bool isTitle = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: isTitle ? 22 : 16,
          fontWeight: isTitle ? FontWeight.bold : FontWeight.normal,
          height: 1.3,
        ),
      ),
    );
  }

  // Helper method to create styled text. Makes the text section below easy to modify.
  Widget _buildInfoTextPurple(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          height: 1.3,
          color: Color.fromRGBO(238, 233, 238, 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if this is the first route in the navigation stack.
    final bool isFirstRoute = !Navigator.canPop(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Circle Grader'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () {
            if (!isFirstRoute) {
              Navigator.of(context).popUntil(ModalRoute.withName('/camera'));
            }
            // Navigator.of(context).pushAndRemoveUntil(
            //  MaterialPageRoute(builder: (context) => const CameraScreen()),
            //  (route) => false,
            //);
          },
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // We are already on the info screen, do nothing.
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ListView( 
          children: <Widget>[
            if (isFirstRoute) ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[800], // A lighter shade of grey
                ),
                onPressed: () {
                  Navigator.of(context).pushReplacementNamed('/camera');
                },
                child: const Text('Start Camera'),
              ),
              const SizedBox(height: 16),
            ],
            // Image.asset('assets/sandCircles1024.png'),
            Image.asset('assets/archimedesPainting.png'),
            const SizedBox(height: 16),
            // ==================================================
            // ===         EDIT THE TEXT BELOW              ===
            // ==================================================
            
            _buildInfoTextPurple(
              'Since the time of Archimedes, people have been enthralled with drawing circles. This app provides one measure of how well you can draw one.',
              //color: Colors.purple,
            ),
   
            _buildInfoText('Instructions', isTitle: true),
            _buildInfoText(
              '1. Click "Start Camera" (or Home 🏠) above when you are ready to capture your circle drawing.'
            ),
            _buildInfoText(
              '2. If needed, tap the flash icon (⚡️) to cycle through flash modes: Off, Auto, On, and Torch.'
            ),
            _buildInfoText(
              '3. Tap the camera icon (📷) to take a photo of your drawn circle.'
            ),
            _buildInfoText(
              '4. On the Monochrome screen, if needed, adjust the "Threshold" and tap "Convert" to update the rendering.'
            ),
            _buildInfoText(
              '5. Tap "Score" to see the animated analysis of your circle.'
            ),
            _buildInfoText(
              '6. Tap the home icon (🏠) at any time to return to the main camera screen to capture another circle.'
            ),
            
            const SizedBox(height: 24), // Adds space between sections

            _buildInfoText('About Circle Grader', isTitle: true),
            _buildInfoText(
              'This application was developed through a dedicated collaboration of myself (MrRuth) and my son (Matthew). Feel free to learn more about our projects at MrRuth.com. We sincerely hope you enjoy using this app.'
            ),
            const SizedBox(height: 16),
            Image.asset('assets/aiEng1024.png'),

            // ==================================================
            // ===         END OF EDITABLE TEXT             ===
            // ==================================================
          ],
        ),
      ),
    );
  }
}

// Custom painter class to draw the circles on the camera preview.
class CirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Define the properties of the paint to be used for the circles.
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke // Draw the outline, not a filled circle.
      ..strokeWidth = 2.0; // The thickness of the circle's line.

    // Calculate the center point of the canvas.
    final center = Offset(size.width / 2, size.height / 2);

    // Calculate the radius for the outer circle. It will touch the edges of the canvas width.
    final outerRadius = size.width / 2;
    canvas.drawCircle(center, outerRadius, paint);

    // Calculate the radius for the inner circle.
    // Ensure the radius is not negative if the screen is very small.
    final innerRadius = (size.width - 150) / 2;
    if (innerRadius > 0) {
      canvas.drawCircle(center, innerRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CirclePainter oldDelegate) {
    return false;
  }
}
