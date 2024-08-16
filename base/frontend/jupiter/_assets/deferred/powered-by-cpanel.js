/*
# _assets/deferred/powered-by-cpanel.js              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global window: false */

(function() {
    "use strict";

    // Code to make sure that powered by cpanel is
    // not removed by third party plugins or JavaScript
    window.addEventListener("load", function() {

        setTimeout(function() {
            var footer = document.querySelector("#cp-footer");
            var cpLogo = footer.shadowRoot.querySelector("#cp-logo");

            var img = null;
            if (footer) {
                img = cpLogo.shadowRoot.querySelector("#imgPoweredByCpanel");
            }

            if (img === null ||
                img.getAttribute("src").indexOf(window.MASTER.footerLogo) === -1) {
                window.location = "/";
            }
        }, 3000);

    });
}());
