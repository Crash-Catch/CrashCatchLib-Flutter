library crashcatchlib_flutter;
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:convert';
import 'dart:io' show Platform;

import 'dart:developer' as dev;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:convert';
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
  String _projectId = "";
  String _versionName = "";
  String? _deviceId;
  String _apiKey = "";
  String _sessionId = "";
  String _doLb = "";
  bool _initialisationCompleted = false;
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
    this._projectId = projectId;
    this._apiKey = apiKey;
    this._versionName = version;

    //Check the app shared preferences to see if the device id has been set, if
    //not generate a random device id string

    print("Getting shared pref");
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    print("got shared prefs");
    print("Getting device id from shared prefs");
    this._deviceId = prefs.getString("crashcatch_device_id") ?? "";
    print("Device id is ${this._deviceId}");

    if (this._deviceId == "")
    {
      print("generating new device id");
      this._deviceId = generateRandomString();
      await prefs.setString("crashcatch_device_id", this._deviceId!);
      print("Set device id to ${this._deviceId}");
    }

    print("Setting hashmap");
    print("Got project id $projectId");
    print("device id $_deviceId");
    print("version $version");

    HashMap requestData = new HashMap<String, dynamic>();
    requestData["ProjectID"] = projectId;
    requestData["DeviceID"] = _deviceId;
    requestData["ProjectVersion"] = version;
    print("calling send request");
     _sendRequest("initialise", requestData as HashMap<String, dynamic>);
     print("send request called");

    this._setupUnhandledException();

  }

  void reportCrash(Exception exception, Severity severity, {StackTrace? stack, Map<String, dynamic> customProperties = const {} }) async
  {
    dev.log("Sending the exception report to Crash Catch");
    String stacktrace = stack == null ? StackTrace.current.toString() : stack
        .toString();

    print("got stack trace");

    HashMap<String, String?> requestData = await returnPostData(exception, stacktrace, severity, CrashType.HANDLED, customProperties);

    if (_initialisationCompleted) {
      dev.log("sending to crash catch as initialised");
      _sendRequest("crash", requestData);
    }
    else
    {
      dev.log("Adding to crash queue");
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
    print("about to call decode stack trace");
    HashMap<String, String> decodedStack = _decodeStacktrace(stacktrace, crashType);
    print("stack decoded");

    HashMap requestData = new HashMap<String, String?>();

    String osVersion = "";
    String apiVersion = "";

    print("checking platform version");
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
      print("Getting web platform information");
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

    print("Checked platform specific stuff");
    print("Getting width and height");
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
    print("got width and height");
    String defaultLocale = !kIsWeb ? Platform.localeName : "N/A";
    print("Got locale $defaultLocale}");


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

    requestData["DeviceID"] = this._deviceId;
    requestData["Stacktrace"] = stacktrace;
    requestData["Severity"] = _getSeverityString(severity);
    requestData["CrashType"] = crashType == CrashType.HANDLED ? "Handled" : "Unhandled";
    requestData["DeviceType"] = "Flutter";
    requestData["ProjectID"] = this._projectId;
    requestData["VersionName"] = this._versionName;

    requestData["ClassFile"] = decodedStack["Class"];
    requestData["LineNo"] = decodedStack["LineNo"];
    if (!kIsWeb)
    {
      requestData["ScreenResolution"] = width.toString() + " x " + height.toString();
    }
    requestData["Locale"] = defaultLocale;
    requestData["OSName"] = osVersion;
    requestData["OSVersion"] = apiVersion;

    print("OS Version '$osVersion', API Version: $apiVersion");

    if (customProperties.isNotEmpty)
    {
      requestData["CustomProperty"] = jsonEncode(customProperties);
    }
    return requestData as FutureOr<HashMap<String, String?>> ;
  }

  HashMap<String, String> _decodeStacktrace(String stack, CrashType crashType) {
    print("split stack by line");
    List<String> stackLines = stack.split("\n");
    print("stack successfully split");

    String classLoc = "";
    String lineNo = "";

    if (!kIsWeb) {
      int stackLineIndex = crashType == CrashType.HANDLED ? 1 : 0;
      print("stack line index is $stackLineIndex");
      print("stac trace is below");
      print(stack);

      String firstLineOfStack = stackLines[stackLineIndex].replaceAll(
          "package:", "");
      print("got first line of stack at $firstLineOfStack");
      int startOfClassLoc = firstLineOfStack.indexOf("(");
      print("start of class loc $startOfClassLoc");
      int startOfLineNumber = firstLineOfStack.indexOf(":", startOfClassLoc);
      print("start of line number $startOfLineNumber");
      classLoc = firstLineOfStack.substring(
          startOfClassLoc + 1, startOfLineNumber);
      print("class log $classLoc");
      lineNo = firstLineOfStack.substring(startOfLineNumber + 1,
          firstLineOfStack.indexOf(":", startOfLineNumber + 1));
      print("line no $lineNo");
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

      String firstLineOfStack = stackLines[stackLineIndex].replaceAll(
          "package:", "");
      print("got first line of stack at $firstLineOfStack");
      int startOfClassLoc = firstLineOfStack.indexOf("/");
      int startOfLineNumber = firstLineOfStack.indexOf(' ', startOfClassLoc) +1;
      int endOfLineNumber = firstLineOfStack.indexOf(":", startOfClassLoc);
      print("Last index of space is: ${firstLineOfStack.indexOf(' ', startOfClassLoc)}");
      classLoc = firstLineOfStack.substring(startOfClassLoc + 1, firstLineOfStack.indexOf(' ', startOfClassLoc));
      print("class log $classLoc");
      lineNo = firstLineOfStack.substring(startOfLineNumber, endOfLineNumber);
      print("line no $lineNo");
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
    print("send request called with endpoint $endpoint");
    //String _url = "https://engine.crashcatch.com/api";
    String _url = "http://192.168.1.8:6001/api";
    String requestUrl = _url + "/" + endpoint;

    Map<String, String> requestHeaders;

    if (endpoint == "initialise" || this._sessionId == "") {
      print("Initialising with ${this._apiKey}");
      requestHeaders = {
        "Content-Type": "application/json",
        "authorisation-token": this._apiKey
      };
    }
    else
      {
        print ("Session id ${this._sessionId}");
        String cookieString = "SESSIONID=" + this._sessionId;
        if (this._doLb.length > 0)
        {
          cookieString += "; DO-LB=" + this._doLb;
        }
        print("Got Cookie String $cookieString");
        requestHeaders = {
          "Content-Type": "application/json",
          "authorisation-token": this._apiKey,
          "session_id": this._sessionId,
          "cookie": cookieString
        };
      }

    print("Sending request to $requestUrl");
    var response = await http.post(Uri.parse(requestUrl),
      body: json.encode(requestData),
      headers: requestHeaders
    );

    print("got response");
    print("getting status code");
    int statusCode = response.statusCode;
    print ("got status code $statusCode");
    if (statusCode == 200) {

      if (endpoint == "initialise") {
        Map<String, String> headers = response.headers;

        print("getting set-cookie cookie string");
        print(headers);
        if (!kIsWeb)
        {
          String cookieString = headers["set-cookie"]!;
          print("got cookie string $cookieString");
          print("parsing the cookie string");
          _parseCookieString(cookieString);
          print("parsing cookie string completed");
        }
        else
        {
          print("getting session id from header");

            this._sessionId = headers["session_id"]!;
            print("session id is ${this._sessionId}");
        }

        if (this._sessionId.length != 0) {
          this._initialisationCompleted = true;

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
      this._initialisationCompleted = false;
      this._sessionId = "";
      CrashCatch._crashQueue.add(requestData);
    }

  }

  void _parseCookieString(String cookieString)
  {
    print("Parsing cookie string function");
    List<String> cookies = cookieString.split(";");
    print("split the cookie string successfully");
    cookies.addAll(cookieString.split(","));
    print("added ${cookies.length} cookies to cookie jar");
    for (var i = 0; i < cookies.length; i++)
    {
      String cookie = cookies[i];
      print("processing cookie $cookie");
      if (cookie.startsWith("SESSIONID"))
      {
        List<String> keyValue = cookie.split("=");
        String value = keyValue[1];
        if (value.contains(";"))
        {
           value = value.substring(0, value.indexOf(";"));
        }
        this._sessionId = value.trim();
      }
      else if (cookie.startsWith("DO-LB"))
      {
        List<String> keyValue = cookie.split("=");
        String value = keyValue[1];
        if (value.contains(";"))
        {
          value = value.substring(0, value.indexOf(";"));
        }
        this._doLb = value;
      }
    }
  }


  String generateRandomString() {
    var random = Random.secure();
    var values = List<int>.generate(20, (i) =>  random.nextInt(255));
    return base64UrlEncode(values).toLowerCase();
  }
}
