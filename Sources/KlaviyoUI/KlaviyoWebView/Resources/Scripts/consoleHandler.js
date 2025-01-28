/**
 * Inject this script file from native code into the head of the HTML document
 * Format string like this, where strWrapperScript is the contents of this file
 * and strJsonConfig is the json-encoded handoff parameters detailed below
 * Always be careful to put quotes around your string arguments! *
 *
 *    strWrapperScript + "('" + strJsonConfig + "');"
 *
 * @param strJsonConfig - JSON encoded handoff dictionary containing:
 *    bridgeName: String - name of the native message handler
 */
(function bridgeWrapper(strJsonConfig) {

  //Initialize web wrapper object
  window.WebViewBridge = new Bridge(JSON.parse(strJsonConfig));

  /**
   * Bridge object to handle communication between JavaScript and Native
   */
  function Bridge(opts) {
    opts = opts || {};

    return {
      opts: opts,

      /**
       * Bool test if this is an Apple WKWebView
       */
      isApple: function () {
        return !!window.webkit && !!window.webkit.messageHandlers[opts.bridgeName];
      },

      /**
       * Method to post string message to native layer
       *
       * Native layer should implement a common interface
       * for reacting to messages of particular type
       *
       * @param type {String}
       * @param data {Object}
       */
      postMessageToNative: function (payload) {
        try {
          const serializedPayload = JSON.stringify(payload);

          if (this.isApple()) {
            window.webkit.messageHandlers[opts.bridgeName].postMessage(serializedPayload);
          }
        } catch (e) {
          unlinkConsole()
          console.error("Failed to post message to native layer:", e.message);
        }
      },
    }
  }

  function unlinkConsole() {
    ["log", "warn", "error"].forEach(function (method) {
      var bckKey = "_" + method
      console[method] = console[bckKey];
      delete console[bckKey]
    });
  }

  /**
   * Send all console output to native layer
   */
  if (!!window.WebViewBridge.opts.linkConsole) {
    ["log", "warn", "error"].forEach(function (method) {
      var _method = console[method];
      var bckKey = "_" + method
      console[bckKey] = _method
      console[method] = function () {
        var args = Array.prototype.slice.call(arguments, 0),
        message;

        try {
          message = JSON.stringify(args);
        } catch (e) {
          message = "Couldn't parse arguments.";
        }

        WebViewBridge.postMessageToNative({
          level: method,
          message: message
        });

        return _method.apply(console, arguments);
      };
    });
  }
})
