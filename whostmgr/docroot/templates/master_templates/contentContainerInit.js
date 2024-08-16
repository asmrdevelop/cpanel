/*
 * master_templates/contentContainerInit.js           Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */
(function() {

    "use strict";

    /**
     * We create two different ways to trigger initialization because both methods
     * are valid, the first callback fired differs by page, and we want to begin
     * initialization as soon as either condition is met.
     */
    window.addEventListener("load", function() {
        dispatchInitEvent("load event");
    });

    var observer = new MutationObserver(function() {
        var contentContainer = document.getElementById("contentContainer");
        if ( contentContainer !== null && contentContainer.firstElementChild ) {
            observer.disconnect();

            dispatchInitEvent("MutationObserver");
        }
    });

    observer.observe(window.document.documentElement, {
        childList: true,
        subtree: true
    });

    /**
     * Dispatches the event if it hasn't already done so in the past.
     */
    var eventDispatched;
    function dispatchInitEvent(triggerName) {
        if (eventDispatched) {
            return;
        }

        eventDispatched = true;

        if (window.location.href.indexOf("debug=1") !== -1) {
            console.log("content-container-init triggered via " + triggerName); // eslint-disable-line no-console
        }

        var event = new CustomEvent("content-container-init");
        window.dispatchEvent(event);
    }
})();
