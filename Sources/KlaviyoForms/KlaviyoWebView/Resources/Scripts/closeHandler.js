//
//  closeHandler.js
//  klaviyo-swift-sdk
//
//  Created by Andrew Balmer on 12/18/24.
//

const closeButton = document.getElementById('close-button');

closeButton.addEventListener('click', function() {
  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.closeMessageHandler) {
    console.log("user tapped close");
    window.webkit.messageHandlers.closeMessageHandler.postMessage('close');
  }
});
