<img src="https://crashcatch.com/images/logo.png" width="150">

# Introduction
The Flutter Crash Catch Library allows you to monitor crash and error reports across your Flutter projects running on Android and iOS Platforms on on the crash and error reporting service Crash Catch (https://crashcatch.com). 

# Installing
The first thing to do is  to add the Crash Catch library to your pubspec.yaml file under the dependencies. An example is below, ensure that the version number is the latest version number that is shown on the GitHub repositories tags. 

``` yaml
dependencies:
  flutter:
    sdk: flutter
	crashcatchlib_flutter: ^1.0.0.0
```
Replace 1.0.0.0 with the latest GitHub tag. 

Then run the Pub get command to update the dependencies as below:
```
flutter pub get
```

# Using the Library
If you project has multiple different screens, then you need to pass an instance of Crash Catch to the class Constructor (this is the recommended and most efficient use) or initialise on each new screen, and have a helper method that you can from anywhere to initalise and be able to update your API key or project ID in one place if you ever need to. 

Import the Crash Catch project into your class, as shown below:
``` Dart
import 'package:crashcatchlib_flutter/CrashCatch.dart';
```

Then create an instance of the library and passing in a BuildContext and send the initialisation request as follows:

``` Dart
class Home extends StatelessWidget {
	@override
  Widget build(BuildContext context) {
	CrashCatch crashCatch = new CrashCatch(context);
	crashCatch.initialiseCrashCatch("<project_id>", "<api_key>", "<project_version>");
	return (
		//Create your widget here
	);
  }
}
```
In the above example, you should update <your_project_id> and <api_key> from the project settings page which can be copied directly to your clipboard from the Crash Catch website. The <project_version> should be updated on each version release. 

If all you are worried about is capturing unhandled exceptions, then that's all you need to do, however, you report errors that occur within try/catch blocks as and when required. 

# Reporting Errors
Unhandled crashes and errors are automatically reported once Crash Catch is initialised. However, you can report errors that are caught within a try/catch block. 

This is done by calling the reportCrash method within the CrashCatch object. This takes two parameters, the exception object, and the severity, and an optional third parameter being the stack. 

If you don't want to pass the stack, then that's not a problem, if you don't the Crash Catch library, will automatically detect the stack for the current thread regardless and use that to send as part of the error. The second parameter is the severity, which can be one of three options, LOW, MEDIUM and HIGH using the Severity enum. 

This is done using the following example:

```Dart
try
{
	throw Exception("Something has gone wrong");
}
on Exception catch (e)
{
	crashCatch.reportCrash(e, Severity.LOW);
}
```

Alternatively, you can pass the stack to the reportCrash method as the 3rd parameter. This is done in the example below:

```
try
{
	throw Exception("Something has gone wrong");
}
on Exception catch (e, stacktrace)
{
	crashCatch.reportCrash(e, Severity.LOW, stacktrace);
}
```

There's also a fourth optional parameter on the reportCrash method where you can pass a Map<String, dynamic> object of custom properties, which can be used to provide custom information to help add debug information to help you diagnose why an error occurred. An example of this is blow:

```
try
{
	throw Exception("Something has gone wrong");
}
on Exception catch (e, stacktrace)
{
	crashCatch.reportCrash(e, Severity.HIGH, stack: stacktrace, customProperties: {
    	"key 1": "value 1",
		"key 2": "value 2",
		"Key 3": 3
	});
}
```

That's it you are fully set up to report crashes and errors on your flutter mobile projects. 