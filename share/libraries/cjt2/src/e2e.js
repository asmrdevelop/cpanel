/*
# cjt/e2e.js                                      Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

(function() {
    "use strict";

    window.__collectedErrors = [];
    window.onerror = function(error) {
        window.__collectedErrors.push(error);
    };
    window.getJavascriptErrors = function() {
        return window.__collectedErrors;
    };
    window.clearJavascriptErrors = function() {
        window.__collectedErrors = [];
    };
})();
