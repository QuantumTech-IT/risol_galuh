import 'dart:js' as js;

void callJsPrint(String htmlContent) {
  js.context.callMethod('callJsPrint', [htmlContent]);
}
