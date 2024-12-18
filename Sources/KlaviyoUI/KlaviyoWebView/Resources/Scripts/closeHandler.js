//
//  closeHandler.js
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 12/18/24.
//


window.addEventListener("klaviyoForms", function(e) {
  if (e.detail.type == 'close') {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.closeHandler) {
      window.webkit.messageHandlers.closeHandler.postMessage('close');
    }
  }
});
