/*
# cpanel - share/libraries/cjt2/src/config.debug.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* WARNING -- removed: `PAGE: false` per cplint. No idea what this may impact! */
/* global module: false, global: true  */
/* exported require */

/**
 * Debug Configuration
 */

(function() {

    "use strict";

    var require = (function() {

        /**
         * Trim trailing slashes to prevent // in paths.
         * @param  {String} url Url to process.
         * @return {String} Cleaned up url.
         */
        function trimTrailingSlash(url) {
            if (url) {
                return url.replace(/\/$/, "");
            }
            return url;
        }

        /**
         * Trim leading slashes to prevent // in paths.
         * @param  {String} url Url to process.
         * @return {String} Cleaned up url.
         */
        function trimLeadingSlash(url) {
            if (url) {
                return url.replace(/^\//, "");
            }
            return url;
        }

        var preamble, root, libRoot, isCjtBuild, includeApp, masterPath, shareRoot;

        var isBrowser = typeof (window) !== "undefined";
        if (isBrowser) {

            // Gets the session token from the url
            var url = window.location.href.toString();
            var parts = url.split("/");
            var session = parts[3];
            if (session.indexOf("cpsess") !== 0) {
                session = "";
            }


            // Build the cleaned up paths
            preamble = parts.slice(0, 6).join("/");
            root = trimTrailingSlash(PAGE.THEME_PATH || "");
            root = trimTrailingSlash(PAGE.MAGIC) + root;
            root = trimTrailingSlash(root);
            libRoot = root + "/libraries";
            shareRoot = root + "/shared";
            PAGE.APP_PATH = trimLeadingSlash(trimTrailingSlash(PAGE.APP_PATH));
            isCjtBuild = false;
            includeApp = true;
            masterPath     = PAGE.masterPath;
        } else {
            preamble = global.BUILD_BASE;
            root = global.BUILD_ROOT;
            libRoot = global.BUILD_ROOT;
            libRoot = global.BUILD_ROOT;
            shareRoot = global.BUILD_ROOT;
            isCjtBuild = global.BUILD_CJT;
            includeApp = global.INCLUDE_APP;
            masterPath     = "";
        }

        var paths = {

            // AMD Plugins
            text: libRoot + "/requirejs/plugins/text_2.0.12/text",
            locale: libRoot + "/cjt2/plugins/locale",
            shared: shareRoot,

            // Application Support Libraries
            bootstrap: libRoot + "/bootstrap/source/dist/js/bootstrap",
            jquery: libRoot + "/jquery/current/jquery",
            lodash: libRoot + "/lodash/4.8.2/lodash",
            moment: libRoot + "/moment/optimized/moment-with-locales",
            qrcode: libRoot + "/qrcodejs/0.0.1/qrcode",

            // Angular specific libraries
            angular: libRoot + "/angularjs/1.4.4/angular",
            ngRoute: libRoot + "/angularjs/1.4.4/angular-route",
            ngAnimate: libRoot + "/angularjs/1.4.4/angular-animate",
            ngSanitize: libRoot + "/angularjs/1.4.4/angular-sanitize",
            ngAria: libRoot + "/angularjs/1.4.4/angular-aria",
            uiBootstrap: libRoot + "/angular-ui-bootstrap/source/ui-bootstrap-tpls-1.2.5",
            "angular-growl": libRoot + "/angular-growl-2/build/angular-growl.min",

            // Other libraries
            handlebars: libRoot + "/handlebars/handlebars",
            "jquery-chosen": libRoot + "/chosen/1.5.1/chosen.jquery",
            "angular-chosen": libRoot + "/angular-chosen/1.4.0/dist/angular-chosen",
            "angular-ui-scroll": libRoot + "/angular-ui-scroll/1.6.1/dist/ui-scroll.min",
            "angular-ui-scroll-grid": libRoot + "/angular-ui-scroll/1.6.1/dist/ui-scroll-grid",
            "angular-ui-scroll-jqlite": libRoot + "/angular-ui-scroll/1.6.1/dist/ui-scroll-jqlite",
            ace: libRoot + "/ace-editor/optimized/src-min-noconflict/ace",
            xterm: libRoot + "/xtermjs/xterm",
            "xterm/addons/fit/fit": libRoot + "/xtermjs/addons/fit/fit",
            punycode: libRoot + "/punycodejs/punycode",
        };

        // Application Paths
        if (includeApp) {
            paths["app"] = root + "/" + PAGE.APP_PATH;
        }

        if (!isCjtBuild) {
            paths["cjt"] = libRoot + "/cjt2";
        } else {
            paths["cjt"] = "../src";
        }

        if (masterPath) {
            paths["master"] = root + "/" + masterPath;
        }

        function buildUrlArgs(PAGE) {
            var urlArgs = [];
            if (PAGE.CACHE_BUST) {
                urlArgs.push("bust=" + (new Date()).getTime());
            }
            if (PAGE.OPTIMIZED) {
                urlArgs.push("optimized=1");
            }
            if (PAGE.MODE === "debug") {
                urlArgs.push("debug=1");
            }

            return urlArgs.join("&");
        }

        var config = {

            // By default load any module IDs from js/lib
            baseUrl: preamble,

            // except, if the module ID starts with "app",
            // load it from the js/app directory. paths
            // config is relative to the baseUrl, and
            // never includes a ".js" extension since
            // the paths config could be for a directory.
            paths: paths,

            shim: {
                "lodash": {
                    exports: "_"
                },
                "angular": {
                    exports: "angular",
                    deps: ["jquery"]
                },
                "ngRoute": {
                    exports: "ngRoute",
                    deps: ["angular"]
                },
                "ngAnimate": {
                    exports: "ngAnimate",
                    deps: ["angular"]
                },
                "ngSanitize": {
                    exports: "ngSanitize",
                    deps: ["angular"]
                },
                "ngAria": {
                    exports: "ngAria",
                    deps: ["angular"]
                },
                "uiBootstrap": {
                    exports: "uiBootstrap",
                    deps: ["angular"]
                },
                "angular-growl": {
                    exports: "angularGrowl",
                    deps: ["angular"]
                },
                "bootstrap": {
                    deps: ["jquery"]
                },
                "qrcode": {
                    exports: "QRCode"
                },
                "jquery-chosen": {
                    deps: ["jquery"]
                },
                "angular-chosen": {
                    deps: ["angular", "jquery", "jquery-chosen"]
                },
                "angular-ui-scroll": {
                    deps: ["angular", "jquery"]
                },
                "angular-ui-scroll-jqlite": {
                    deps: ["angular"]
                },
                "angular-ui-scroll-grid": {
                    deps: ["angular", "angular-ui-scroll"]
                },
                "handlebars": {
                    exports: "Handlebars"
                }
            },
            urlArgs: buildUrlArgs(PAGE)
        };

        return config;
    })();


    if (typeof (module) !== "undefined" && module.exports) {

        // We are in the build environment, so export it via exports
        module.exports.config = require;
    } else {

        // This is runtime so make it a global
        window.require = require;
    }
})();
