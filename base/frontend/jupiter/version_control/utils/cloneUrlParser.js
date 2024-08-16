/*
 * version_control/utils/cloneUrlParser.js         Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* eslint-env amd */

define(function() {
    "use strict";

    function parseCloneUrl(cloneUrl) {
        var parts = {};

        if (!cloneUrl) {
            return parts;
        }

        // Correct IPv6 URLs of the form http(s)://[<ipv6addr]/... are handled properly.
        // However, incorrect IPv6 URLs - http(s)://<ipv6addr>/... are not handled well
        // because the parser assumes that if there is a : then that represents a port
        // number and thus authority is incorrectly parsed. Here we just parse out the
        // authority portion and check for more than 2 :'s. If found then the URL is not
        // valid
        var authority = cloneUrl.match(/^(https?:\/\/)?(?!\[)([^/]+)\/*(?!\])/);

        if (authority !== null && authority[2].match(/.*:.*:.*/)) {
            return parts;
        }

        parts.scheme = parseUrlParts(cloneUrl.match(/^\S+:\/\//i));
        parts.userInfo = parseUrlParts(cloneUrl.match(/^\S+@/i));
        parts.ipv6Authority = parseUrlParts(cloneUrl.match(/^\[\S+\]/i));
        if (parts.ipv6Authority) {
            parts.ipv6Authority = parts.ipv6Authority.replace(/(\[|\])/gi, "");
        }

        parts.authority =
            parts.ipv6Authority === null
                ? parseUrlParts(cloneUrl.split(/((:\d+\/)|(\/|:))/i))
                : null;

        // Parse out the port if it exists.
        parts.port = (cloneUrl.match(/^:\d+\//i)) ? parseUrlParts(cloneUrl.match(/^:(\d+)/i), 1) : null;
        parts.path = parseUrlParts(cloneUrl.match(/^\S+/i));
        parts.unparsed = cloneUrl;

        function parseUrlParts(matches, returnIndex) {
            returnIndex = returnIndex || 0;
            if (matches !== null && matches.length > 0) {
                cloneUrl = cloneUrl.replace(matches[0], "");
                return matches[returnIndex];
            }
            return null;
        }

        return parts;
    }

    return {
        parse: parseCloneUrl,
    };
});
