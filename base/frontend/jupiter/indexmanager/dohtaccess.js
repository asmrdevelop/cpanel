/*
# indexmanager/dohtaccess.js                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false */

define(
    [
        "jquery",
        "bootstrap"
    ], function($) {
        "use strict";

        var $exampleIndexFiles = $("#example-index-files");
        $("#toggle-example-index-files").click(function() {
            if ($exampleIndexFiles.hasClass("hidden")) {
                this.innerText = PAGE.hideLabel;
                $exampleIndexFiles.removeClass("hidden");
            } else {
                this.innerText = PAGE.showLabel;
                $exampleIndexFiles.addClass("hidden");
            }
        });
    }
);
