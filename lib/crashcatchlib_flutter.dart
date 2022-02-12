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
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    this._deviceId = prefs.getString("crashcatch_device_id") ?? "";

    if (this._deviceId == "")
    {
      this._deviceId = generateRandomString();
      await prefs.setString("crashcatch_device_id", this._deviceId!);
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
    dev.log("Sending the exception report to Crash Catch");
    String stacktrace = stack == null ? StackTrace.current.toString() : stack
        .toString();

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
    HashMap<String, String> decodedStack = _decodeStacktrace(stacktrace, crashType);

    String osVersion = "";
    String apiVersion = "";
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      String? version = androidInfo.version.release != null ? androidInfo.version.release : "";
      osVersion = "Android " + version!;
      apiVersion = androidInfo.version.sdkInt.toString();
    }
    else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      osVersion = "iOS " + iosInfo.utsname.release.toString();
    }
    else if (Platform.isWindows)
    {
      osVersion = "Windows";
      apiVersion = Platform.operatingSystemVersion;
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

    String defaultLocale = Platform.localeName;

    HashMap requestData = new HashMap<String, String?>();

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
    requestData["ScreenResolution"] = width.toString() + " x " + height.toString();
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
    List<String> stackLines = stack.split("\n");

    int stackLineIndex = crashType == CrashType.HANDLED ? 1 : 0;

    String firstLineOfStack = stackLines[stackLineIndex].replaceAll("package:", "");
    int startOfClassLoc = firstLineOfStack.indexOf("(");
    int startOfLineNumber = firstLineOfStack.indexOf(":", startOfClassLoc);
    String classLoc = firstLineOfStack.substring(startOfClassLoc+1, startOfLineNumber);
    String lineNo = firstLineOfStack.substring(startOfLineNumber+1, firstLineOfStack.indexOf(":", startOfLineNumber+1));

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
    //String _url = "https://engine.crashcatch.com/api";
    String _url = "http://192.168.1.8:6001/api";
    String requestUrl = _url + "/" + endpoint;
    
    dev.log("Request Data:");
    dev.log(json.encode(requestData));

    Map<String, String> requestHeaders;

    if (endpoint == "initialise" || this._sessionId == "") {
      requestHeaders = {
        "Content-Type": "application/json",
        "authorisation-token": this._apiKey
      };
    }
    else
      {
        String cookieString = "SESSIONID=" + this._sessionId;
        if (this._doLb.length > 0)
        {
          cookieString += "; DO-LB=" + this._doLb;
        }
        requestHeaders = {
          "Content-Type": "application/json",
          "authorisation-token": this._apiKey,
          "cookie": cookieString
        };
      }

    var response = await http.post(Uri.parse(requestUrl),
      body: json.encode(requestData),
      headers: requestHeaders
    );

    dev.log("Got Crash Catch Response");
    dev.log(response.toString());

    int statusCode = response.statusCode;
    if (statusCode == 200) {

      if (endpoint == "initialise") {
        Map<String, String> headers = response.headers;

        String cookieString = headers["set-cookie"]!;
        _parseCookieString(cookieString);

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
    dev.log("Crash Catch HTTP Status: " + response.statusCode.toString() + " Response: " + response.body);

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
