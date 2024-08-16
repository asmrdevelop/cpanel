/*
# base/frontend/jupiter/js2/ssl/index.js                      Copyright 2022 cPanel, L.L.C.
#                                                                             All rights Reserved.
# copyright@cpanel.net                                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

(function(window, document) {

    "use strict";

    var defaultKeyTypeForm = document.getElementById("defaultKeyTypeForm");
    var keyChangWarningCallout = document.getElementById("keyChangWarningCallout");
    var lnkShowHideHelpButton = document.getElementById("lnkShowHideHelp");
    var bodyContentElement = document.querySelector(".body-content");

    /**
     * Called up updating of the selection of the key type.
     * Will determine whether to show the change warning callout.
     *
     */
    function defaultKeyTypeFormUpdated(e) {
        var theForm = e.currentTarget;

        if (PAGE.has_autossl) {
            if (PAGE.old_choice !== theForm.default_ssl_key_type.value) {
                keyChangWarningCallout.classList.remove("hidden");
            } else {
                keyChangWarningCallout.classList.add("hidden");
            }
        }
    }

    /**
     * Toggle the display of the help element by toggling the show-help-text class
     *
     */
    function toggleHelp() {
        bodyContentElement.classList.toggle("show-help-text");
    }

    // initiate by adding event listeners
    if (defaultKeyTypeForm && keyChangWarningCallout) {
        defaultKeyTypeForm.addEventListener("change", defaultKeyTypeFormUpdated);
    }
    if (lnkShowHideHelpButton && bodyContentElement) {
        lnkShowHideHelpButton.addEventListener("click", toggleHelp);
    }
})(window, document);
