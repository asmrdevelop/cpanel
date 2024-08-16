/*
# templates/greylist/util/ipPadder.js             Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(function() {
    return {
        ipPadder: function(value) {
            if (!value) {
                return "";
            }
            if (typeof value !== "string") {
                return "";
            }

            var padded_ip = "";
            var split_ip = value.split(".");
            for (var i = 0; i < split_ip.length; i++) {
                var this_section = split_ip[i];
                while (this_section.length < 3) {
                    this_section = "0" + this_section;
                }
                padded_ip += this_section;
            }

            return padded_ip;
        }

    };
});
