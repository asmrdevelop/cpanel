/*
# _assets/deferred/open-links-on-ios.js              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global window: false, jQuery: false */

(function() {
    "use strict";

    if (("standalone" in window.navigator) &&
        window.navigator.standalone) {

        // Code to make links open inside the mobile window on iOS
        jQuery(document).ready(function($) {
            $("a").click(function(event) {
                var alink = document.createElement("a");
                alink.href = $(this).attr("href");
                if (alink &&
                    alink.protocol.indexOf("http") !== -1 &&
                    alink.host.indexOf(document.location.host) !== -1) {
                    event.preventDefault();
                    window.location = alink.href;
                }
            });
        });
    }

}());
