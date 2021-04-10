library crashcatchlib_flutter;
import 'dart:collection';
import 'dart:io';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart';
import 'package:device_info/device_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:convert';

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
  String _deviceId;
  String _apiKey = "";
  String _sessionId = "";
  String _doLb = "";
  bool _initialisationCompleted = false;
  BuildContext _context;
  static List<HashMap<String, String>> _crashQueue;

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
      await prefs.setString("crashcatch_device_id", this._deviceId);
    }

    HashMap requestData = new HashMap<String, dynamic>();
    requestData["ProjectID"] = projectId;
    requestData["DeviceID"] = _deviceId;
    requestData["AppVersion"] = version;
    _sendRequest("initialise", requestData);

    this._setupUnhandledException();

  }

  void reportCrash(Exception exception, Severity severity, {StackTrace stack, Map<String, dynamic> customProperties = const {} }) async
  {
    String stacktrace = stack == null ? StackTrace.current.toString() : stack
        .toString();

    HashMap<String, String> requestData = await returnPostData(exception, stacktrace, severity, CrashType.HANDLED, customProperties);

    if (_initialisationCompleted) {
      _sendRequest("crash", requestData);
    }
    else
    {
      CrashCatch._crashQueue.add(requestData);
    }
  }

  void _sendUnhandledCrash(FlutterErrorDetails flutterErrorDetails) async
  {
    HashMap<String, String> requestData = await returnPostData(flutterErrorDetails, flutterErrorDetails.stack.toString(), Severity.HIGH, CrashType.UNHANDLED, {});
    if (_initialisationCompleted)
    {
      _sendRequest("crash", requestData);
    }
    else
      {
        CrashCatch._crashQueue.add(requestData);
      }
  }

  Future<HashMap<String, String>> returnPostData(Object exception, String stacktrace, Severity severity, CrashType crashType, Map<String, dynamic> customProperties) async
  {
    HashMap<String, String> decodedStack = _decodeStacktrace(stacktrace, crashType);

    String osVersion = "";
    String apiVersion = "";
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      osVersion = androidInfo.version.release;
      apiVersion = androidInfo.version.sdkInt.toString();
    }
    else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      osVersion = "iOS " + iosInfo.systemVersion;
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

    HashMap requestData = new HashMap<String, String>();

    if (exception is Exception)
    {
      Exception exceptionObj = exception;
      requestData["ExceptionType"] = exceptionObj.runtimeType.toString();
      requestData["ExceptionMessage"] = exceptionObj.toString();
    }
    else
    {
      FlutterErrorDetails exceptionObj = exception;
      requestData["ExceptionType"] = exceptionObj.exception.runtimeType.toString();
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
    requestData["OSVersionName"] = osVersion;
    requestData["APIVersion"] = apiVersion;

    if (customProperties.isNotEmpty)
    {
      requestData["CustomProperty"] = jsonEncode(customProperties);
    }
    return requestData;
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
    return decodedStack;
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
    String _url = "https://engine.crashcatch.com";
    String requestUrl = _url + "/" + endpoint;

    Map<String, String> requestHeaders;

    if (endpoint == "initialise" || this._sessionId == "") {
      requestHeaders = {
        "Content-Type": "application/x-www-form-urlencoded",
        "authorisation-token": this._apiKey
      };
    }
    else
      {
        requestHeaders = {
          "Content-Type": "application/x-www-form-urlencoded",
          "authorisation-token": this._apiKey,
          "cookie": "SESSIONID=" + this._sessionId
        };
      }

    var response = await http.post(Uri.parse(requestUrl),
      body: requestData,
      headers: requestHeaders
    );

    int statusCode = response.statusCode;
    if (statusCode == 200) {

      if (endpoint == "initialise") {
        Map<String, String> headers = response.headers;

        String cookieString = headers["set-cookie"];
        _parseCookieString(cookieString);

        if (this._sessionId != "") {
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
    List<String> cookies = cookieString.split(";");
    for (var i = 0; i < cookies.length; i++)
    {
      String cookie = cookies[i];
      if (cookie.startsWith("SESSIONID"))
      {
        List<String> keyValue = cookie.split("=");
        this._sessionId = keyValue[1];
      }
      else if (cookie.startsWith("DOLB"))
      {
        List<String> keyValue = cookie.split("=");
        this._doLb = keyValue[1];
      }
    }
  }


  String generateRandomString() {
    var random = Random.secure();
    var values = List<int>.generate(20, (i) =>  random.nextInt(255));
    return base64UrlEncode(values).toLowerCase();
  }
}
