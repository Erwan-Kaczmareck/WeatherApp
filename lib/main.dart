import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Pour utiliser jsonDecode
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'App Météo'),
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
  // Controller pour stocker la valeur de la barre de recherche
  final TextEditingController _searchController = TextEditingController();
  String _texteAPI = "Entrez une ville pour obtenir la météo"; // Texte initial
  String apiKey = "b3e40ac2dcca52585a078b69bb2d137d";
  bool isFahrenheit = false; // false = °C true = °F
  String? _iconUrl; // Variable pour stocker l'URL de l'icône
  String actualWeather = "";
  String urlWeatherAsset = "";
  String ville = "";
  List<Map<String, dynamic>>? hourlyWeatherData = [];
  final ScrollController _horizontalHourlyWeather = ScrollController();
  final ScrollController _horizontalDailyWeather = ScrollController();

  bool actualLocation =
      false; //false ville désigné, true ville trouvé avec longitude latitude
  List<Map<String, dynamic>> dailyWeatherData = [];

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  //ville favorite
  List<String> _favoriteCities = [];

  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadFavorites(); // Appel après le premier rendu de l'écran
      _initializeNotifications();
    });
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Météo'),
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: urlWeatherAsset.isNotEmpty
                ? AssetImage(urlWeatherAsset)
                : AssetImage('path/to/default/image.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        // Scrollbar englobant la page
        child: Scrollbar(
          thumbVisibility: true,
          trackVisibility: true,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Rechercher une ville',
                      prefixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.location_on),
                            onPressed: () async {
                              actualLocation = true;
                              try {
                                await getCurrentLocation();
                              } catch (e) {
                                print("Erreur de localisation: $e");
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: () {
                              actualLocation = false;
                              ville = _searchController.text;
                              getWeather(ville);
                              fetchWeatherData(ville);
                              fetchDailyWeatherData(ville);
                            },
                          ),
                        ],
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                ville = '';
                              });
                            },
                          ),
                          IconButton(
                            icon: Icon(
                              ville.isNotEmpty == true &&
                                      _favoriteCities.contains(ville)
                                  ? Icons.star
                                  : Icons.star_border_outlined,
                              color: ville.isNotEmpty == true &&
                                      _favoriteCities.contains(ville)
                                  ? Colors.yellow
                                  : null,
                            ),
                            onPressed: () {
                              if (ville.isNotEmpty == true) {
                                setState(() {
                                  if (_favoriteCities.contains(ville)) {
                                    _favoriteCities.remove(ville);
                                  } else {
                                    _favoriteCities.add(ville);
                                  }
                                  saveFavorites();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20.0),
                      ),
                      filled: true,
                      fillColor: const Color.fromARGB(255, 231, 233, 237),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                if (_favoriteCities.isNotEmpty)
                  Wrap(
                    spacing: 8.0,
                    children: _favoriteCities.map((city) {
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _searchController.text = city;
                            ville = city;
                          });
                          actualLocation = false;
                          getWeather(city);
                          fetchWeatherData(city);
                          fetchDailyWeatherData(ville);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12.0, vertical: 8.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.blue),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: Text(
                            city,
                            style: const TextStyle(
                              fontSize: 18, // Taille du texte
                              fontWeight: FontWeight
                                  .w500, // Épaisseur du texte pour plus de visibilité
                              color: Colors.black87, // Couleur du texte
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                const SizedBox(height: 16),

                // Bloc pour afficher les éléments principaux de météo
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white
                        .withOpacity(0.1), // Couleur de fond semi-transparente
                    borderRadius: BorderRadius.circular(12.0), // Coins arrondis
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        spreadRadius: 3,
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Bloc d'affichage principal de la météo (texte et température)
                      textBoxWeather(
                          _texteAPI), // Affiche le texte météo (température, conditions, etc.)
                      const SizedBox(height: 16),

                      // Icône météo principale
                      _iconUrl != null
                          ? Image.network(
                              _iconUrl!,
                              width: 100,
                              height: 100,
                            )
                          : const Text('Aucune icône disponible'),
                      const SizedBox(height: 16),

                      // Bouton pour changer d'unité (°C ↔ °F)
                      buttonFahrenheit(),
                    ],
                  ),
                ),

                const SizedBox(height: 50),

                // Température par heure
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Texte pour afficher le titre
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text(
                        "Temps de la journée : ",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),

                    // Container principal pour les informations météorologiques horaires
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: Colors.grey,
                          width: 3.0,
                        ),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        height: 150.0,
                        child: Scrollbar(
                          controller: _horizontalHourlyWeather,
                          thumbVisibility: true,
                          trackVisibility: true,
                          child: SingleChildScrollView(
                            controller: _horizontalHourlyWeather,
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: List.generate(hourlyWeatherData!.length,
                                  (index) {
                                var data = hourlyWeatherData![index];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0),
                                  child: Column(
                                    children: [
                                      Image.network(
                                        'http://openweathermap.org/img/wn/${data['icon']}@2x.png',
                                        width: 70,
                                        height: 70,
                                      ),
                                      Text(
                                        '${convertTemp(data['temp']).toInt()}°${isFahrenheit ? "F" : "C"}',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          color: Colors.black,
                                        ),
                                      ),
                                      Text(
                                        '${(index * 3).toInt()}h',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 50),

                // Prévisions pour la semaine

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Texte pour afficher le titre
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text(
                        "Temps de la semaine : ",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey, width: 3.0),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        height: 340.0,
                        child: Scrollbar(
                          controller: _horizontalDailyWeather,
                          thumbVisibility: true,
                          trackVisibility: true,
                          child: SingleChildScrollView(
                            controller: _horizontalDailyWeather,
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: dailyWeatherData
                                  .map((dayData) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8.0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              dayData['day'],
                                              style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 8.0),

                                            // Matin
                                            if (dayData['morning'] != null)
                                              Column(
                                                children: [
                                                  const Text(
                                                    "Matin",
                                                    style: TextStyle(
                                                        fontSize: 20,
                                                        color: Colors.black),
                                                  ),
                                                  Image.network(
                                                    'http://openweathermap.org/img/wn/${dayData['morning']['icon']}@2x.png',
                                                    width: 70,
                                                    height: 70,
                                                  ),
                                                  Text(
                                                    "${convertTemp(dayData['morning']['temp']).toInt()}°${isFahrenheit ? "F" : "C"}",
                                                    style: const TextStyle(
                                                        fontSize: 20,
                                                        color: Colors.black),
                                                  ),
                                                ],
                                              ),
                                            const SizedBox(height: 16.0),

                                            // Après-midi
                                            if (dayData['afternoon'] != null)
                                              Column(
                                                children: [
                                                  const Text(
                                                    "Après-midi",
                                                    style: TextStyle(
                                                        fontSize: 20,
                                                        color: Colors.black),
                                                  ),
                                                  Image.network(
                                                    'http://openweathermap.org/img/wn/${dayData['afternoon']['icon']}@2x.png',
                                                    width: 70,
                                                    height: 70,
                                                  ),
                                                  Text(
                                                    "${convertTemp(dayData['afternoon']['temp']).toInt()}°${isFahrenheit ? "F" : "C"}",
                                                    style: const TextStyle(
                                                        fontSize: 20,
                                                        color: Colors.black),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Fonction qui retourne un bouton météo avec une bordure
  Widget buttonWeather() => OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor:
              const Color.fromARGB(166, 0, 0, 0), // Couleur du texte
          side: const BorderSide(
              color: Color.fromARGB(166, 0, 0, 0)), // Couleur de la bordure
          backgroundColor: Colors.white, // Couleur de fond
        ),
        onPressed: () {
          String ville = _searchController.text;
          getWeather(ville);
          fetchWeatherData(ville);
          fetchDailyWeatherData(ville); // Appel API lors du clic
        },
        child: const Text('Obtenir la météo'),
      );

  Widget buttonFahrenheit() => OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 12.0),
          foregroundColor: Colors.black.withOpacity(0.8), // Couleur du texte
          side: const BorderSide(
            color: Colors.black54,
            width: 2.0,
          ), // Couleur et épaisseur de la bordure
          backgroundColor: Colors.white, // Couleur de fond
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0), // Coins arrondis
          ),
          elevation: 4, // Ombre pour relief
          shadowColor: Colors.grey.withOpacity(0.5),
          textStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ), // Taille et style du texte
        ),
        onPressed: () {
          isFahrenheit = !isFahrenheit;
          String ville = _searchController.text;
          if (actualLocation == false) {
            getWeather(ville); // Appel API lors du clic
            fetchWeatherData(ville);
            fetchDailyWeatherData(ville);
          } else {
            getCurrentLocation();
          }
        },
        child: const Text('C° / F°'),
      );

  // Afficher le texte de l'API
  Widget textBoxWeather(String texte) => Text(
        texte,
        overflow: TextOverflow.fade,
        maxLines: 3,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 40, // Définir la taille de la police ici
        ),
      );

  // Fonction pour obtenir les données météo
  Future<void> getWeather(String ville) async {
    String apiUrl =
        "https://api.openweathermap.org/data/2.5/weather?q=$ville&appid=$apiKey&units=metric&lang=fr";

    try {
      final reponse = await http.get(Uri.parse(apiUrl));

      if (reponse.statusCode == 200) {
        // Si la requête est réussie, on parse les données
        Map<String, dynamic> weatherData = jsonDecode(reponse.body);
        String description;
        //Si c'est des °C
        if (isFahrenheit == false) {
          description =
              "${weatherData['main']['temp'].toInt()} °C  ${weatherData['weather'][0]['description']}";
        } //Si c'est des °F
        else {
          description =
              "${(weatherData['main']['temp'] * 1.8 + 32).toInt()} °F  ${weatherData['weather'][0]['description']}";
        }
        actualWeather = weatherData['weather'][0]['description'];
        String iconCode = weatherData['weather'][0]['icon'];
        _iconUrl = "https://openweathermap.org/img/wn/$iconCode@2x.png";

        // Mettre à jour le texte avec les nouvelles données
        setState(() {
          _texteAPI = description;
        });
      } else {
        // Gérer les erreurs de requête
        setState(() {
          _texteAPI =
              "Erreur : Impossible de récupérer les données pour $ville.";
        });
      }
    } catch (e) {
      // Gérer les exceptions
      setState(() {
        _texteAPI = "Erreur : $e";
      });
    }
    urlWeatherAsset = getBackgroundImage(actualWeather);
  }

  String getBackgroundImage(String actualWeather) {
    switch (actualWeather) {
      case 'ciel dégagé':
        return 'assets/ciel-degager.jpg';
      case 'peu nuageux':
        return 'assets/peu-nuageux.jpg';
      case 'partiellement nuageux':
        return 'assets/peu-nuageux.jpg';
      case 'nuageux':
        return 'assets/peu-nuageux.jpg';
      case 'couvert':
        return 'assets/peu-nuageux.jpg';
      case 'pluie':
        return 'assets/pluie.jpg';
      case 'légère pluie':
        return 'assets/pluie.jpg';
      case 'pluie modérée':
        return 'assets/pluie.jpg';
      case 'neige':
        return 'assets/neige.jpg';
      case 'orage':
        return 'assets/orage.jpg';
      case 'brume':
        return 'assets/brume.jpg';
      default:
        return '';
    }
  }

  // Fonction pour convertir les températures
  double convertTemp(double temp) {
    return isFahrenheit
        ? (temp * 1.8) + 32
        : temp; // Convertir en °F si isFahrenheit est vrai
  }

  Future<void> fetchWeatherData(String ville) async {
    String apiUrl =
        "https://api.openweathermap.org/data/2.5/forecast?q=$ville&appid=$apiKey&units=metric&cnt=9";

    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);

        // Vérifier si la ville existe dans la réponse
        if (jsonResponse['cod'] == '404') {
          setState(() {
            hourlyWeatherData = []; // Réinitialiser les données météo
          });
          return; // Sortir de la fonction si la ville n'est pas trouvée
        }

        // Extraire les prévisions horaires sur 24 heures
        List<Map<String, dynamic>> weatherList = [];
        List<dynamic> hourlyList = jsonResponse['list'];

        for (var hourlyData in hourlyList) {
          double temp = hourlyData['main']['temp'];
          String icon = hourlyData['weather'][0]['icon'];

          weatherList.add({
            'temp': temp,
            'icon': icon,
          });
        }

        setState(() {
          hourlyWeatherData = weatherList; // Réinitialiser le message d'erreur
        });
      } else {
        // Afficher un message d'erreur générique
        setState(() {
          hourlyWeatherData = []; // Réinitialiser les données météo
        });
      }
    } catch (error) {
      setState(() {
        hourlyWeatherData = []; // Réinitialiser les données météo
      });
    }
  }

  // Méthode pour charger les favoris à partir de SharedPreferences
  Future<void> loadFavorites() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String>? favorites = prefs.getStringList('favoriteCities');
      if (favorites != null) {
        setState(() {
          _favoriteCities = favorites; // Convertir la liste en Set
        });
      }
    } catch (e) {
      print("Erreur lors du chargement des favoris: $e");
    }
  }

  // Méthode pour sauvegarder les favoris dans SharedPreferences
  Future<void> saveFavorites() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('favoriteCities', _favoriteCities.toList());
    } catch (e) {
      print("Erreur lors de la sauvegarde des favoris: $e");
    }
  }

  Future<void> fetchDailyWeatherData(String ville) async {
    String apiUrl =
        "https://api.openweathermap.org/data/2.5/forecast?q=$ville&appid=$apiKey&units=metric";

    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);

        if (jsonResponse['cod'] == '404') {
          setState(() {
            dailyWeatherData = [];
          });
          return;
        }

        Map<String, Map<String, dynamic>> groupedWeather = {};
        List<dynamic> hourlyList = jsonResponse['list'];

        for (var hourlyData in hourlyList) {
          String dateTime = hourlyData['dt_txt'];
          DateTime date = DateTime.parse(dateTime);

          // Utilisation de DateFormat pour obtenir le jour en fonction de la locale actuelle
          String formattedDay = DateFormat.EEEE().format(date);

          // Vérifiez si le temps contient de la pluie ou de l'orage
          List<dynamic> weatherConditions = hourlyData['weather'];
          bool isRainyOrStormy = weatherConditions.any((condition) =>
              condition['main'] == 'Rain' ||
              condition['main'] == 'Thunderstorm');

          // Si c'est le cas, vous pouvez afficher une notification ou une alerte
          if (isRainyOrStormy) {
            print(
                "Alerte: Prévisions de pluie ou d'orage pour le $formattedDay.");
            await _showNotification("Alerte Météo",
                "$ville : Prévisions de pluie ou d'orage pour $formattedDay.");
          }

          if (date.hour == 9 || date.hour == 15) {
            double temp = hourlyData['main']['temp'];
            String icon = hourlyData['weather'][0]['icon'];
            String period = date.hour == 9 ? "morning" : "afternoon";

            // Initialise le jour dans groupedWeather si non existant
            if (!groupedWeather.containsKey(formattedDay)) {
              groupedWeather[formattedDay] = {
                'day': formattedDay, // Utiliser le jour formaté
                'morning': null,
                'afternoon': null,
              };
            }

            // Ajouter les prévisions pour matin ou après-midi
            groupedWeather[formattedDay]![period] = {
              'temp': temp,
              'icon': icon,
            };
          }
        }

        // Convertir groupedWeather en une liste pour setState
        List<Map<String, dynamic>> weatherList = groupedWeather.values.toList();

        setState(() {
          dailyWeatherData = weatherList;
        });
      } else {
        setState(() {
          dailyWeatherData = [];
        });
      }
    } catch (error) {
      setState(() {
        dailyWeatherData = [];
      });
    }
  }

  Future<void> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Vérifier si les services de localisation sont activés
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Les services de localisation ne sont pas activés
      return Future.error('Les services de localisation sont désactivés.');
    }

    // Vérifier les permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Permission de localisation refusée.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Les permissions de localisation sont refusées de façon permanente.');
    }

    // Obtenir la position actuelle de l'utilisateur
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);

    double latitude = position.latitude;
    double longitude = position.longitude;

    getWeatherLongLat(latitude, longitude);
    fetchWeatherDataLongLat(latitude, longitude);
    fetchDailyWeatherDataLongLat(latitude, longitude);
  }

  Future<void> getWeatherLongLat(double latitude, double longitude) async {
    String apiUrl =
        "https://api.openweathermap.org/data/2.5/weather?lat=$latitude&lon=$longitude&appid=$apiKey&units=metric&lang=fr";

    try {
      final reponse = await http.get(Uri.parse(apiUrl));

      if (reponse.statusCode == 200) {
        // Si la requête est réussie, on parse les données
        Map<String, dynamic> weatherData = jsonDecode(reponse.body);
        String description;
        //Si c'est des °C
        if (isFahrenheit == false) {
          description =
              "${weatherData['main']['temp'].toInt()} °C   ${weatherData['weather'][0]['description']}";
        } //Si c'est des °F
        else {
          description =
              "${(weatherData['main']['temp'] * 1.8 + 32).toInt()} °F   ${weatherData['weather'][0]['description']}";
        }
        actualWeather = weatherData['weather'][0]['description'];
        String iconCode = weatherData['weather'][0]['icon'];
        _iconUrl = "https://openweathermap.org/img/wn/$iconCode@2x.png";

        // Mettre à jour le texte avec les nouvelles données
        setState(() {
          _texteAPI = description;
        });
      } else {
        // Gérer les erreurs de requête
        setState(() {
          _texteAPI =
              "Erreur : Impossible de récupérer les données pour $ville.";
        });
      }
    } catch (e) {
      // Gérer les exceptions
      setState(() {
        _texteAPI = "Erreur : $e";
      });
    }
    urlWeatherAsset = getBackgroundImage(actualWeather);
  }

  Future<void> fetchWeatherDataLongLat(
      double latitude, double longitude) async {
    String apiUrl =
        "https://api.openweathermap.org/data/2.5/forecast?lat=$latitude&lon=$longitude&appid=$apiKey&units=metric&lang=fr&cnt=9";

    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);

        // Vérifier si la ville existe dans la réponse
        if (jsonResponse['cod'] == '404') {
          setState(() {
            hourlyWeatherData = []; // Réinitialiser les données météo
          });
          return; // Sortir de la fonction si la ville n'est pas trouvée
        }

        // Extraire les prévisions horaires sur 24 heures
        List<Map<String, dynamic>> weatherList = [];
        List<dynamic> hourlyList = jsonResponse['list'];

        for (var hourlyData in hourlyList) {
          double temp = hourlyData['main']['temp'];
          String icon = hourlyData['weather'][0]['icon'];

          weatherList.add({
            'temp': temp,
            'icon': icon,
          });
        }

        setState(() {
          hourlyWeatherData = weatherList; // Réinitialiser le message d'erreur
        });
      } else {
        // Afficher un message d'erreur générique
        setState(() {
          hourlyWeatherData = []; // Réinitialiser les données météo
        });
      }
    } catch (error) {
      setState(() {
        hourlyWeatherData = []; // Réinitialiser les données météo
      });
    }
  }

  Future<void> fetchDailyWeatherDataLongLat(
      double latitude, double longitude) async {
    String apiUrl =
        "https://api.openweathermap.org/data/2.5/forecast?lat=$latitude&lon=$longitude&appid=$apiKey&units=metric&lang=fr";
    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);

        if (jsonResponse['cod'] == '404') {
          setState(() {
            dailyWeatherData = [];
          });
          return;
        }

        Map<String, Map<String, dynamic>> groupedWeather = {};
        List<dynamic> hourlyList = jsonResponse['list'];

        for (var hourlyData in hourlyList) {
          String dateTime = hourlyData['dt_txt'];
          DateTime date = DateTime.parse(dateTime);

          // Utilisation de DateFormat pour obtenir le jour en fonction de la locale actuelle
          //String formattedDay = DateFormat('EEEE').format(date);
          String formattedDay = DateFormat.EEEE().format(date);

          if (date.hour == 9 || date.hour == 15) {
            double temp = hourlyData['main']['temp'];
            String icon = hourlyData['weather'][0]['icon'];
            String period = date.hour == 9 ? "morning" : "afternoon";

            // Initialise le jour dans groupedWeather si non existant
            if (!groupedWeather.containsKey(formattedDay)) {
              groupedWeather[formattedDay] = {
                'day': formattedDay, // Utiliser le jour formaté
                'morning': null,
                'afternoon': null,
              };
            }

            // Ajouter les prévisions pour matin ou après-midi
            groupedWeather[formattedDay]![period] = {
              'temp': temp,
              'icon': icon,
            };
          }
        }

        // Convertir groupedWeather en une liste pour setState
        List<Map<String, dynamic>> weatherList = groupedWeather.values.toList();

        setState(() {
          dailyWeatherData = weatherList;
        });
      } else {
        setState(() {
          dailyWeatherData = [];
        });
      }
    } catch (error) {
      setState(() {
        dailyWeatherData = [];
      });
    }
  }

  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'weather_channel',
      'Weather Alerts',
      channelDescription: 'Channel for weather notifications',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0, // ID de la notification
      title,
      body,
      platformChannelSpecifics,
      payload: 'item x', // Optionnel, à utiliser pour la navigation
    );
  }
}
