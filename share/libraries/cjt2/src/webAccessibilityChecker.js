/*
# cjt/webAccessibilityChecker.js                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

(function() {
    "use strict";

    window.__accessibilityViolations = [];
    window.getAccessibilityViolations = function() {
        return window.__accessibilityViolations;
    };

    window.setAccessibilityViolations = function(violations) {
        window.__accessibilityViolations = violations;
    };

    window.clearAccessibilityViolations = function() {
        window.__accessibilityViolations = [];
    };

    window.runAccessibilityChecker = function(id) {
        var context = id || window.AXE_CONFIG.context || document;
        var options = window.AXE_CONFIG.options || {};

        return window.axe.run(context, options)
            .then(function(results) {
                window.setAccessibilityViolations(results.violations);
                return;
            });
    };

})();
