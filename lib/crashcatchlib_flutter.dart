library crashcatchlib_flutter;
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_browser_detect/web_browser_detect.dart';

enum Severity {
  LOW,
  MEDIUM,
  HIGH
}

enum CrashType {
  HANDLED,
  UNHANDLED
}

class CrashCatch
{
  static String _projectId = "";
  static String _versionName = "";
  static String? _deviceId;
  static String _apiKey = "";
  static String _sessionId = "";
  static String _doLb = "";
  static bool _initialisationCompleted = false;
  late BuildContext _context;
  static late List<HashMap<String, dynamic>> _crashQueue;

  CrashCatch(BuildContext buildContext) {
    this._context = buildContext;
    CrashCatch._crashQueue = [];
  }

  void _setupUnhandledException() {
    FlutterError.onError = (FlutterErrorDetails details) {
      _sendUnhandledCrash(details);
    };
  }

  void initialiseCrashCatch(String projectId, String apiKey, String version) async
  {
    print("Initialising Crash Catch");
    _projectId = projectId;
    _apiKey = apiKey;
    _versionName = version;

    //Check the app shared preferences to see if the device id has been set, if
    //not generate a random device id string

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString("crashcatch_device_id") ?? "";

    if (_deviceId == "")
    {
      _deviceId = generateRandomString();
      prefs.setString("crashcatch_device_id", _deviceId!);
    }


    HashMap requestData = new HashMap<String, dynamic>();
    requestData["ProjectID"] = projectId;
    requestData["DeviceID"] = _deviceId;
    requestData["ProjectVersion"] = version;


     _sendRequest("initialise", requestData as HashMap<String, dynamic>);

    this._setupUnhandledException();

  }

  void reportCrash(Exception exception, Severity severity, {StackTrace? stack, Map<String, dynamic> customProperties = const {} }) async
  {
    print("Reporting Crash");
    String stacktrace = stack == null ? StackTrace.current.toString() : stack
        .toString();

    HashMap<String, String?> requestData = await returnPostData(exception, stacktrace, severity, CrashType.HANDLED, customProperties);

    if (_initialisationCompleted) {
      print("Initialisation completed, sending request");
      _sendRequest("crash", requestData);
    }
    else
    {
      print("Initialisation not completed added to queue");
      CrashCatch._crashQueue.add(requestData);
    }
  }

  void _sendUnhandledCrash(FlutterErrorDetails flutterErrorDetails) async
  {
    HashMap<String, String?> requestData = await returnPostData(flutterErrorDetails, flutterErrorDetails.stack.toString(), Severity.HIGH, CrashType.UNHANDLED, {});
    if (_initialisationCompleted)
    {
      _sendRequest("crash", requestData);
    }
    else
      {
        CrashCatch._crashQueue.add(requestData);
      }
  }

  Future<HashMap<String, String?>> returnPostData(Object exception, String stacktrace, Severity severity, CrashType crashType, Map<String, dynamic> customProperties) async
  {
    HashMap<String, String> decodedStack = _decodeStacktrace(stacktrace, crashType);

    HashMap requestData = new HashMap<String, String?>();

    String osVersion = "";
    String apiVersion = "";
    requestData["DeviceId"] = _deviceId;
    if (!kIsWeb)
    {
      if (Platform.isAndroid) {
        DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        String? version = androidInfo.version.release != null ? androidInfo.version.release : "";
        osVersion = "Android " + version!;
        apiVersion = androidInfo.version.sdkInt.toString();
      }
      else if (Platform.isIOS) {
        osVersion = Platform.operatingSystem;
        apiVersion = Platform.operatingSystemVersion;
      }
      else if (Platform.isWindows)
      {
        osVersion = "Windows";
        apiVersion = Platform.operatingSystemVersion;
      }
    }
    else
    {
      osVersion = "N/A";
      final Browser browserDetails = Browser();

      String browser = browserDetails.browser;
      String? browserVersion = browserDetails.version;

      requestData["Browser"] = browser;
      requestData["BrowserVersion"] = browserVersion;

      String height = MediaQuery.of(_context).size.height.toString();
      String width = MediaQuery.of(_context).size.width.toString();

      requestData["BrowserWidthHeight"] = width + " x " + height;

    }

    int width = MediaQuery
        .of(_context)
        .size
        .width
        .ceil();
    int height = MediaQuery
        .of(_context)
        .size
        .height
        .ceil();
    String defaultLocale = !kIsWeb ? Platform.localeName : "N/A";


    if (exception is Exception)
    {
      Exception exceptionObj = exception;
      requestData["ExceptionType"] = exceptionObj.runtimeType.toString();
      requestData["ExceptionMessage"] = exceptionObj.toString();
    }
    else
    {
      FlutterErrorDetails exceptionObj = exception as FlutterErrorDetails;
      requestData["ExceptionType"] = exceptionObj.exception.runtimeType.toString();
      requestData["ExceptionMessage"] = exceptionObj.exception.toString();
    }

    requestData["DeviceID"] = _deviceId;
    requestData["Stacktrace"] = stacktrace;
    requestData["Severity"] = _getSeverityString(severity);
    requestData["CrashType"] = crashType == CrashType.HANDLED ? "Handled" : "Unhandled";
    requestData["DeviceType"] = "Flutter";
    requestData["ProjectID"] = _projectId;
    requestData["VersionName"] = _versionName;

    requestData["ClassFile"] = decodedStack["Class"];
    requestData["LineNo"] = decodedStack["LineNo"];
    if (!kIsWeb)
    {
      requestData["ScreenResolution"] = width.toString() + " x " + height.toString();
    }
    requestData["Locale"] = defaultLocale;
    requestData["OSName"] = osVersion;
    requestData["OSVersion"] = apiVersion;


    if (customProperties.isNotEmpty)
    {
      requestData["CustomProperty"] = jsonEncode(customProperties);
    }
    return requestData as FutureOr<HashMap<String, String?>> ;
  }

  HashMap<String, String> _decodeStacktrace(String stack, CrashType crashType) {
    List<String> stackLines = stack.split("\n");

    String classLoc = "";
    String lineNo = "";

    if (!kIsWeb) {
      int stackLineIndex = crashType == CrashType.HANDLED ? 1 : 0;

      String firstLineOfStack = stackLines[stackLineIndex].replaceAll("package:", "");
      int startOfClassLoc = firstLineOfStack.indexOf("(");

      int startOfLineNumber = firstLineOfStack.indexOf(":", startOfClassLoc);

      classLoc = firstLineOfStack.substring(startOfClassLoc + 1, startOfLineNumber);

      lineNo = firstLineOfStack.substring(startOfLineNumber + 1,
          firstLineOfStack.indexOf(":", startOfLineNumber + 1));

    }
    else
    {
      int stackLineIndex = 0;
      for (int i = 0; i < stackLines.length; i++) {
          if (stackLines[i].indexOf('dart-sdk') == -1 && stackLines[i].indexOf('crashcatchlib') == -1)
          {
            stackLineIndex = i;
            break;
          }
      }

      String firstLineOfStack = stackLines[stackLineIndex].replaceAll("package:", "");

      int startOfClassLoc = firstLineOfStack.indexOf("/");
      int startOfLineNumber = firstLineOfStack.indexOf(' ', startOfClassLoc) +1;
      int endOfLineNumber = firstLineOfStack.indexOf(":", startOfClassLoc);

      classLoc = firstLineOfStack.substring(startOfClassLoc + 1, firstLineOfStack.indexOf(' ', startOfClassLoc));

      lineNo = firstLineOfStack.substring(startOfLineNumber, endOfLineNumber);

    }

    HashMap decodedStack = HashMap<String, String>();
    decodedStack["Class"] = classLoc;
    decodedStack["LineNo"] = lineNo;
    return decodedStack as HashMap<String, String>;
  }

  String _getSeverityString(Severity severity)
  {
    switch (severity)
    {
      case Severity.LOW:
        return "Low";
      case Severity.MEDIUM:
        return "Medium";
      case Severity.HIGH:
        return "High";
    }
  }

  void _sendRequest(String endpoint, HashMap<String, dynamic> requestData) async
  {
    String _url = "https://engine.crashcatch.com/api";
    String requestUrl = _url + "/" + endpoint;

    Map<String, String> requestHeaders;
    if (requestData["DeviceID"] == null) {
      requestData["DeviceID"] = _deviceId;
    }

    if (endpoint == "initialise") {
      requestHeaders = {
        "Content-Type": "application/json",
        "authorisation-token": _apiKey
      };

      if (_sessionId.length != 0)
      {
        print("The initialisation session id header is being set to: " + _sessionId);
        requestHeaders["session_id"] = _sessionId;
      }
      else
      {
        print("The initialisation session id is not set so no header being sent");
      }
    }
    else
    {
      String cookieString = "SESSIONID=" + _sessionId;
      if (_doLb.length > 0)
      {
        cookieString += "; DO-LB=" + _doLb;
      }
      requestHeaders = {
        "Content-Type": "application/json",
        "authorisation-token": _apiKey,
        "session_id": _sessionId,
        "cookie": cookieString
      };
    }
    print("Sending request with session id: " + requestHeaders["session_id"].toString());
    print("Request Headers");
    print(requestHeaders);

    var response = await http.post(Uri.parse(requestUrl),
      body: json.encode(requestData),
      headers: requestHeaders
    );


    int statusCode = response.statusCode;
    print("Endpoint $endpoint status code is $statusCode");
    if (statusCode == 200) {

      if (endpoint == "initialise") {
        Map<String, String> headers = response.headers;

        if (kIsWeb)
        {
          print("Initialising session id from cookie as web device");
          String cookieString = headers["set-cookie"]!;
          _parseCookieString(cookieString);
        }
        else
        {
          print("Initialising session id from header. Headers below");
          print(headers);
            _sessionId = headers["session_id"]!;
            print("The session id is:" + _sessionId);

        }
        print("Session id is " + _sessionId);
        if (_sessionId.length != 0 && _deviceId != null) {
          _initialisationCompleted = true;

          if (CrashCatch._crashQueue.length > 0)
          {
            for (int i = 0; i < CrashCatch._crashQueue.length; i++)
            {
              _sendRequest("crash", CrashCatch._crashQueue[i]);
            }
            CrashCatch._crashQueue.clear();
          }
        }
      }
    }
    else
    {
      _initialisationCompleted = false;
      CrashCatch._crashQueue.add(requestData);
    }

  }

  void _parseCookieString(String cookieString)
  {

    List<String> cookies = cookieString.split(";");

    cookies.addAll(cookieString.split(","));
    for (var i = 0; i < cookies.length; i++)
    {
      String cookie = cookies[i];
      if (cookie.startsWith("SESSIONID"))
      {
        List<String> keyValue = cookie.split("=");
        String value = keyValue[1];
        if (value.contains(";"))
        {
           value = value.substring(0, value.indexOf(";"));
        }
        _sessionId = value.trim();
      }
      else if (cookie.startsWith("DO-LB"))
      {
        List<String> keyValue = cookie.split("=");
        String value = keyValue[1];
        if (value.contains(";"))
        {
          value = value.substring(0, value.indexOf(";"));
        }
        _doLb = value;
      }
    }
  }


  String generateRandomString() {
    var random = Random.secure();
    var values = List<int>.generate(20, (i) =>  random.nextInt(255));
    return base64UrlEncode(values).toLowerCase();
  }
}
