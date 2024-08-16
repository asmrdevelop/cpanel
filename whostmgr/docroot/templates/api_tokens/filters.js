// Copyright 2022 cPanel, L.L.C. - All rights reserved.
// copyright@cpanel.net
// https://cpanel.net
// This code is subject to the cPanel license. Unauthorized copying is prohibited

function ipv6short(input) {
    "use strict";

    // remove all zeros to the right
    input = input.replace(/^(0{4}:)+/g, "::");

    // remove all zeros to the left
    input = input.replace(/(?::?0{4})+(\/\d+)?$/g, "::$1");

    // remove all leading zeros
    input = input.replace(/(:|^)(0{1,3})(?=[^0])/g, "$1");

    // find the longest group of continuous empty 16-bit hexets if string doesn't alreay contain ::
    if (input.match("::") === null) {
        var matches = input.match(/(:0{4})+/g);
        if (!matches) {
            return input;
        }
        var match = matches.reduce((a, b) => a.length > b.length ? a : b);
        input = input.replace(match, ":");
    }

    // replace remaning empty 16-bit hexets with a single 0
    return input.replace(/(?!:)(0{4})/g, "0");
}

define(
    [
        "angular",
    ],
    function(angular) {
        "use strict";
        var module = angular.module("whm.apiTokens.filters", []);
        module.filter("ipv6short", function() {
            return ipv6short;
        });

        return module;
    });
