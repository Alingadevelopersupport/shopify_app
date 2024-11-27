//= require ./app_bridge_2.0.12.js

(function(window) {
  function appBridgeRedirect(url) {
    console.log("url", url)
    var AppBridge = window['app-bridge'];
    var createApp = AppBridge.default;
    var Redirect = AppBridge.actions.Redirect;
    var shopifyData = document.body.dataset;
    console.log("shopifyData", shopifyData)

    var app = createApp({
      apiKey: shopifyData.apiKey,
      host: shopifyData.host,
    });

    var normalizedLink = document.createElement('a');
    normalizedLink.href = url;

    Redirect.create(app).dispatch(Redirect.Action.REMOTE, normalizedLink.href);
  }

  window.appBridgeRedirect = appBridgeRedirect;
})(window);