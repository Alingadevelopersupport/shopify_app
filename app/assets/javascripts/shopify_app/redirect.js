//= require ./app_bridge_redirect.js

(function () {
  function redirect() {
    var redirectTargetElement = document.getElementById("redirection-target");
    alert("call redirect.js");
    console.log("redirectTargetElement", redirectTargetElement)
    if (!redirectTargetElement) {
      return;
    }

    var targetInfo = JSON.parse(redirectTargetElement.dataset.target);
    console.log("targetInfo", targetInfo)
    console.log("targetInfo.url", targetInfo.url)
    if (window.top == window.self) {
      console.log("window.top", window.top)
      // If the current window is the 'parent', change the URL by setting location.href
      window.top.location.href = targetInfo.url;
    } else {
      console.log("call else")
      // If the current window is the 'child' or embedded, change the parent's URL with
      // App Bridge redirect. This case can happen when an app updates its access scopes,
      // or the unlikely scenario where the shop thinks the app is installed, but the
      // app does not have an record for the shop.
      window.appBridgeRedirect(targetInfo.url);
    }
  }

  document.addEventListener("DOMContentLoaded", redirect);

  // In the turbolinks context, neither DOMContentLoaded nor turbolinks:load
  // consistently fires. This ensures that we at least attempt to fire in the
  // turbolinks situation as well.
  redirect();
})();
