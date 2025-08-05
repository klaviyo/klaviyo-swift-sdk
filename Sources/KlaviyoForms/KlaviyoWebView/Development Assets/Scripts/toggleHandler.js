var _selector = document.querySelector('input[name=myCheckbox]');
_selector.addEventListener('change', function(event) {
  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.toggleMessageHandler) {
    console.log("toggle changed; new value: " + _selector.checked);
    window.webkit.messageHandlers.toggleMessageHandler.postMessage({
      "toggleEnabled": _selector.checked
    });
  }
});
