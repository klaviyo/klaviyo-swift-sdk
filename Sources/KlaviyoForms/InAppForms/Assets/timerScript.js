(function () {
      // Get the native bridge by name
      const nativeBridgeName = document.head.getAttribute("data-native-bridge-name");

      // Save original implementations
      const _nativeSetTimeout = window.setTimeout;
      const _nativeSetInterval = window.setInterval;

      // Helper to post message to native bridge
      function postTimerMessage(type, duration) {
        const nativeBridge = window.webkit?.messageHandlers?.[nativeBridgeName] ?? window[nativeBridgeName];
        if (nativeBridge && typeof nativeBridge.postMessage === "function") {
          nativeBridge.postMessage(JSON.stringify({
            type: "timer",
            data: {
              timerType: type,
              duration: duration || 0,
            }
          }));
        }
      }

      // Override setTimeout
      window.setTimeout = function (fn, delay, ...args) {
        if (delay) {
          postTimerMessage("setTimeout", delay);
          console.log(fn, delay)
        }
        return _nativeSetTimeout(fn, delay, ...args);
      };

      // Override setInterval
      window.setInterval = function (fn, delay, ...args) {
        if (delay) {
          postTimerMessage("setInterval", delay);
          console.log(fn, delay)
        }
        return _nativeSetInterval(fn, delay, ...args);
      };
    })();
