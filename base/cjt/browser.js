/* ----------------------------------------------------------------------

NOTE: The following code is ONLY meant for displaying NOTICES, to the effect
of: "Your browser is too old; it looks like you might have better luck using
one of these browsers: X, Y, Z".

Do NOT use this code in place of feature detection. To determine if the
browser supports a feature (e.g., <canvas>), do:

var i_can_canvas = false;
try {
    i_can_canvas = document.createElement("canvas").getContext("2d");
} catch(e) {}

... rather than using any of this logic here.

In fact, as the comments below describe, you shouldn't get here until
you've actually done feature detection.

NOTE: Putting feature detection into this file was considered but rejected
because it would usually mean instantiating "throw-away" objects. We could
revisit that decision in the future.

 ---------------------------------------------------------------------- */

(function(window) {
    var YAHOO = window.YAHOO,
        CPANEL = window.CPANEL;

    // NOTE: This structure only needs to record when each platform FIRST
    // gained a browser that supports a given API.
    //
    // So, for example, Windows 8 doesn't need a "file_api" entry because
    // every shipping browser already supported the File API when Microsoft
    // released Windows 8.
    //
    // The first item in each array is the "ID test", which currently is always
    // a regular expression but can also be a function.
    var BROWSER_SUPPORT = {
        file_api: {
            android: [
                [/^2\.3/, "Firefox", "Opera"]
            ],
            macintosh: [
                [/^10\.6/, "Chrome", "Firefox", "Opera"],
                [/^10\.7/, "Chrome", "Firefox", "Opera", "Safari"]
            ],
            windows: [

                // WinXP and Vista didn't get IE10.
                [/^(?:6\.0|5\.[1-9])/, "Chrome", "Firefox", "Opera"],

                // Win7 shipped with IE9.
                [/^6\.1/, "Chrome", "Firefox", "Internet Explorer", "Opera"]
            ]
        }
    };

    function _parse_ua_data() {
        var YAHOO_ENV_UA = YAHOO.env.ua;

        var client_os = YAHOO_ENV_UA.os;
        var client_os_version;

        if (client_os) {
            var client_appstring = YAHOO_ENV_UA.gecko ? navigator.oscpu : navigator.appVersion;

            switch (client_os) {
                case "windows":
                    client_os_version = client_appstring.match(/Windows\s+NT\s+([^;]+)/);
                    break;
                case "macintosh":
                    client_os_version = client_appstring.match(/Mac\s+OS\s+(?:X\s+)?([\d._]+)/);
                    break;
            }

            if (client_os_version) {
                client_os_version = client_os_version[1].replace(/_/g, "."); // replace() is for MacOS
            }
        } else {
            if (YAHOO_ENV_UA.android) {
                client_os = "android";
                client_os_version = YAHOO_ENV_UA.android;
            } else if (YAHOO_ENV_UA.ios) {
                client_os = "ios";
                client_os_version = YAHOO_ENV_UA.ios;
            }
        }

        return {
            os: client_os,
            os_version: client_os_version
        };
    }

    /**
     * http://stackoverflow.com/questions/2450954/how-to-randomize-a-javascript-array
     */

    function _shuffle_array(array) {
        for (var i = array.length - 1; i > 0; i--) {
            var j = Math.floor(Math.random() * (i + 1));
            var temp = array[i];
            array[i] = array[j];
            array[j] = temp;
        }
        return array;
    }

    // This is factored out for testing purposes.

    function _get_browser_support_options(features) {

        var feature_browsers;

        var os_info = _parse_ua_data();
        var client_os = os_info.os;
        var client_os_version = os_info.os_version;

        if (client_os) {
            if (typeof features === "string") {
                features = [features];
            }

            features.forEach(function(feature) {
                var possibilities = BROWSER_SUPPORT[feature] && BROWSER_SUPPORT[feature][client_os];
                if (possibilities) {
                    possibilities.forEach(function(poss) {
                        var ptest = poss[0];
                        if (ptest instanceof RegExp) {
                            if (!ptest.test(client_os_version)) {
                                return;
                            }
                        } else if (ptest instanceof Function) {
                            if (!ptest(client_os_version)) {
                                return;
                            }
                        }

                        // >=2nd time through: delete keys that aren't in
                        // the current array.
                        if (feature_browsers) {
                            for (var browser in feature_browsers) {
                                if (poss.indexOf(browser) === -1) {
                                    delete feature_browsers[browser];
                                }
                            }
                        } else { // First time through: create keys for each browser.
                            feature_browsers = {};
                            poss.slice(1).forEach(function(browser) {
                                feature_browsers[browser] = true;
                            });
                        }
                    });
                }
            });

        }

        return feature_browsers && Object.keys(feature_browsers);
    }

    /**
     * Return a message with the best "knowable" advice to a user for
     * loading a page that needs the given feature/features.
     *
     * This *assumes* that we've already determined that the current
     * OS does not support the given feature. So if you ask for a message
     * about the File API, and you're running Windows 8, the response message
     * won't be very helpful because it'll think you're running something
     * "weird", when in fact you're just running something that doesn't need
     * this check (because every Windows 8 browser supports File API).
     *
     * We rely here on OS version detection, which is imprecise at best.
     *
     * Examples:
     *
     *   get_browser_support_message("file_api")
     *   -> Returns the browsers that support File API on the current OS.
     *
     *   get_browser_support_message( ["file_api", "cool_new_thing"] )
     *   -> Returns the browsers that support File API *and* "cool_new_thing"
     *      on the current OS.
     *
     * @method get_browser_support_message
     * @param features {String|Array} Which feature(s) to check for a message.
     * @return {String} The requested message.
     */

    function get_browser_support_message(features) {
        var feature_browsers = _get_browser_support_options(features);

        var os_notice;

        if (feature_browsers) {

            // Shuffle these so that we're not "preferring" one browser over another.
            feature_browsers = _shuffle_array(feature_browsers);

            if (feature_browsers.length === 1) {
                os_notice = LOCALE.maketext("Try this page with the latest available version for your platform of “[_1]”", feature_browsers[0]);
            } else {
                os_notice = LOCALE.maketext("Load this page with the latest available version for your platform of one of these web [numerate,_1,browser,browsers]: [join,~, ,_2]", feature_browsers.length, feature_browsers);
            }
        }

        return os_notice || LOCALE.maketext("Load this page with a newer web browser. (You may need to use another device.)");
    }

    CPANEL.browser = {
        NO_SUPPORT_MESSAGE: LOCALE.maketext("Your web browser lacks support for a feature that this page requires."),
        get_browser_support_message: get_browser_support_message,

        // exposed only for testing
        _get_browser_support_options: _get_browser_support_options
    };
}(window));
