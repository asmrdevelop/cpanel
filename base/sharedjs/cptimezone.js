// requires: jstz

( function(window) {
    "use strict";

    var JSTZ_RELATIVE_PATH = "sharedjs/jstz.min.js";
    var TIMEZONE_COOKIE = "timezone";

    var COOKIE_TIMEZONE_MISMATCH_CLASS = "if-timezone-cookie-needs-update";
    var DETECTED_TZ_CLASS = "detected-timezone";
    var SHOWN_CLASS = "shown";

    // cf. https://developer.mozilla.org/en-US/docs/Web/API/document/cookie
    function _get_cookie(sKey) {
        return decodeURIComponent(document.cookie.replace(new RegExp("(?:(?:^|.*;)\\s*" + encodeURIComponent(sKey).replace(/[\-\.\+\*]/g, "\\$&") + "\\s*\\=\\s*([^;]*).*$)|^.*$"), "$1")) || null;
    }

    // ----------------------------------------------------------------------

    function _detect_timezone() {
        return window.jstz.determine().name();
    }

    function reset_timezone_and_reload() {
        return reset_timezone( location.reload.bind(location) );
    }

    function _set_cookie(callback) {
        document.cookie = TIMEZONE_COOKIE + "=" + _detect_timezone() + "; path=/";
        if (callback) {
            callback();
        }
    }

    // Returns false: did nothing (does not execute callback)
    function set_timezone_if_unset(on_success) {
        return !_get_cookie(TIMEZONE_COOKIE) && reset_timezone(on_success);
    }

    function reset_timezone(on_success) {
        _set_cookie(on_success);
        return true;
    }

    function set_timezone_and_reload_if_unset() {
        return set_timezone_if_unset( location.reload.bind(location) );
    }

    // This will compare jstz's detected time zone with the cookie time zone
    // and, if there is a mismatch:
    //  1) Populate the DETECTED_TZ_CLASS nodes with the time zone.
    //  2) add the SHOWN_CLASS to all COOKIE_TIMEZONE_MISMATCH_CLASS nodes.
    //
    // This facilitates the display of links to reload the page with a
    // freshly-set timezone.
    //
    // TODO: This really is what AngularJS does best and should be redone
    // using that framework at some point.
    //
    function show_cookie_timezone_mismatch_nodes() {
        var detected_tz = _detect_timezone();
        if (detected_tz !== _get_cookie(TIMEZONE_COOKIE)) {
            var detected_nodes = document.querySelectorAll("." + DETECTED_TZ_CLASS);

            [].forEach.call(detected_nodes, function(n) {
                n.textContent = detected_tz;
            } );

            var show_nodes = document.querySelectorAll("." + COOKIE_TIMEZONE_MISMATCH_CLASS);
            [].forEach.call(show_nodes, function(n) {
                n.className += " " + SHOWN_CLASS;
            } );
        }
    }

    window.CPTimezone = {
        show_cookie_timezone_mismatch_nodes: show_cookie_timezone_mismatch_nodes,
        reset_timezone_and_reload: reset_timezone_and_reload,
        reset_timezone: reset_timezone,
        set_timezone_and_reload_if_unset: set_timezone_and_reload_if_unset
    };
}(window) );
