//
//  closeHandler.js
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 12/18/24.
//


window.addEventListener("klaviyoForms", function(e) {
  if (e.detail.type == 'close') {
    window.webkit?.messageHandlers?.closeHandler?.postMessage('close');
  }
});
