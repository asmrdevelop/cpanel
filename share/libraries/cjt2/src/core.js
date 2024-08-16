/*
# cjt/core.js                                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

// -----------------------------------------------------------------------
// DEVELOPER NOTES:
// -----------------------------------------------------------------------

/* global define: false, PAGE: true */

define(function() {
    "use strict";

    // ---------------------------
    // Constants
    // ---------------------------
    var PERIOD = ".";

    // ---------------------------
    // State
    // ---------------------------
    var instance = null;

    // Testing shim
    var locationService = {
        get_pathname: function() {
            return window.location.pathname;
        },
        get_port: function() {
            return window.location.port;
        },
        get_hostname: function() {
            return window.location.hostname;
        },
        get_protocol: function() {
            return window.location.protocol;
        }
    };

    // Testing shim
    var pageService = {
        get_configuration: function() {
            return PAGE;
        },
    };

    function CJT() {
        if (instance !== null) {
            throw new Error("Cannot instantiate more then one CJT, use CJT.getInstance()");
        }

        this.initialize(locationService, pageService);
    }

    // To make unit test happy
    if (window) {
        window.PAGE = window.PAGE || {};
    }

    /**
     * Check if the protocol is https.
     * @param  {String}  protocol
     * @return {Boolean}          true if its https: in any case, false otherwise.
     */
    function isHttps(protocol) {
        return (/^https:$/i).test(protocol);
    }

    /**
     * Check if the protocol is http.
     * @param  {String}  protocol
     * @return {Boolean}          true if its http: in any case, false otherwise.
     */
    function isHttp(protocol) {
        return (/^http:$/i).test(protocol);
    }

    /**
     * Strip any trailing slashes from a string.
     *
     * @method stripTrailingSlash
     * @param  {String} path   The path string to process.
     * @return {String}        The path string without a trailing slash.
     */
    function stripTrailingSlash(path) {
        return path && path.replace(/\/?$/, "");
    }

    /**
     * Add a trailing slashes to a string if it doesn't have one.
     *
     * @method ensureTrailingSlash
     * @param  {String} path   The path string to process.
     * @return {String}        The path string with a guaranteed trailing slash.
     */
    function ensureTrailingSlash(path) {
        return path && path.replace(/\/?$/, "/");
    }


    CJT.prototype = {
        name: "CJT",
        description: "cPanel Common JavaScript Library",
        version: "2.0.0.1",

        /**
         * List of application name constants
         * @name KNOWN_APPLICATIONS
         * @type {Object}
         */
        KNOWN_APPLICATIONS: {
            WHM: "whostmgr",
            CPANEL: "cpanel",
            WEBMAIL: "webmail",
            UNPROTECTED: "unprotected",
        },

        /**
         * Initialize the state for CJT
         */
        initialize: function(locationService, pageService) {

            var config = pageService.get_configuration();

            /**
             * List of common application configuration settings
             * @name config
             * @type {Object}
             */
            this.config = {

                /**
                 * Name of the actual mode the framework is running under
                 * @type {String} 'release' or 'debug'
                 */
                mode: config.MODE,

                /**
                 * Turn on/off debug features of the framework
                 * @name config.debug
                 * @type {Boolean}
                 */
                debug: config.MODE === "debug",

                /**
                 * Alternate base path for looking up the theme. Only used when the application
                 * is "other or unprotected". Defaults to the root of the site.
                 * @type {String}
                 */
                themePath: ensureTrailingSlash(config.THEME_PATH) || "/",

                /**
                 * Indicates the application is running under a proxy sub domain.
                 * @type {Boolean}
                 */
                isProxy: config.IS_PROXY || false,

                applicationName: config.APP_NAME || "",

                /**
                 * Indicates the application is running in an end to end testing environment.
                 * These environments use tools like Selenium and Protractor and are sensitive
                 * to timing issues in the UI. Applications and components should use this flag
                 * to turn off animations and other interactions that may complicate writing of
                 * the end to end tests.
                 * @type {[type]}
                 */
                e2e: config.IS_E2E || false
            };


            /**
             * @property {String} [protocol] Protocol used to access the page.
             */
            this.protocol = locationService.get_protocol();

            var port = locationService.get_port();
            if (!port) {

                // Since some browsers wont fill this in, we have to derive it from
                // the protocol if its not provided in the window.location object.
                if (isHttps(this.protocol)) {
                    port = "443";
                } else if (isHttp(this.protocol)) {
                    port = "80";
                }
            }

            // This will work in any context except a proxy URL to cpanel or webmail
            // that accesses a URL outside /frontend (cpanel) or /webmail (webmail),
            // but URLs like that are non-production by defintion.
            var port_path_app = {
                80: "other",
                443: "other",
                2082: "cpanel",
                2083: "cpanel",
                2086: "whostmgr",
                2087: "whostmgr",
                2095: "webmail",
                2096: "webmail",
                9876: "unittest",
                9877: "unittest",
                9878: "unittest",
                9879: "unittest",
                frontend: "cpanel",
                webmail: "webmail"
            };

            // State variables
            this._url_path = locationService.get_pathname();

            // ---------------------------------------------
            // Gets the session token from the url
            // ---------------------------------------------
            var path_match = (this._url_path.match(/((?:\/cpsess\d+)?)(?:\/([^\/]+))?/) || []);

            /**
             * @property {String} [domain] Domain used to access the page.
             */
            this.domain = locationService.get_hostname();

            /**
             * @property {Number} [port] Port used to access the product.
             */
            this.port = parseInt(port, 10);

            /**
             * @property {String} [applicationName] Name of the application
             */
            if (this.config.applicationName) {
                this.applicationName = this.config.applicationName;
            } else {
                if (!this.config.isProxy) {
                    this.applicationName = port_path_app[port] || port_path_app[path_match[2]] || "whostmgr";
                } else {

                    // For proxy subdomains, we look at the first subdomain to identify the application.
                    if (/^whm\./.test(this.domain)) {
                        this.applicationName = port_path_app[2087];
                    } else if (/^cpanel\./.test(this.domain)) {
                        this.applicationName = port_path_app[2083];
                    } else if (/^webmail\./.test(this.domain)) {
                        this.applicationName = port_path_app[2095];
                    }
                }
            }

            /**
             * @property {String} [session] Session token
             */
            this.securityToken = path_match[1] || "";

            this.applicationPath = this.securityToken ? this._url_path.replace(this.securityToken, "") : this._url_path;

            this.theme = "";
            this.themePath = "";
        },

        /**
         * Return whether we are running inside some other framework or application
         *
         * @method isUnitTest
         * @return {Boolean} true if this is an unrecognized application or framework; false otherwise
         */
        isOther: function() {
            return (/other/i).test(this.applicationName);
        },

        /**
         * Return whether we are running inside the unit test framework
         *
         * @method isUnitTest
         * @return {Boolean} true if this is unittest; false otherwise
         */
        isUnitTest: function() {
            return (/unittest/i).test(this.applicationName) || Boolean(window.__karma__);
        },

        /**
         * Return whether we are running inside an unprotected path
         *
         * @method isUnprotected
         * @return {Boolean} true if this is unprotected; false otherwise
         */
        isUnprotected: function() {
            return !this.securityToken && this.unprotected_paths.indexOf( stripTrailingSlash(this.applicationPath) ) !== -1;
        },

        unprotected_paths: ["/resetpass", "/invitation"],

        /**
         * Return whether we are running inside cpanel or something else (e.g., WHM)
         *
         * @method isCpanel
         * @return {Boolean} true if this is cpanel; false otherwise
         */
        isCpanel: function() {
            return (/cpanel/i).test(this.applicationName);
        },

        /**
         * Return whether we are running inside WHM or something else (e.g., whm)
         *
         * @method isWhm
         * @return {Boolean} true if this is whm; false otherwise
         */
        isWhm: function() {
            return (/whostmgr/i).test(this.applicationName);
        },

        /**
         * Check if the framework is running in an e2e test.
         *
         * @method  isE2E
         * @return {Boolean}     true if this is running in an e2e test run, false otherwise.
         */
        isE2E: function(e2e) {
            return this.e2e;
        },

        /**
         * Set the value for end to end testing mode.
         *
         * @method  setE2E
         * @param  {Boolean}  e2e true if this is an e2e test run, false otherwise.
         */
        setE2E: function(e2e) {
            if (typeof (e2e) === "undefined") {
                throw "Parameter e2e must be boolean.";
            } else if (typeof (e2e) !== "boolean") {
                throw "Parameter e2e must be boolean.";
            }
            this.e2e = e2e;
            window.__isE2E = e2e; // Publish this so the global onerror code can see it.
            this._updateE2EHandlers();
        },

        /**
         * Add any calls here that will change on enabling or disabling end-to-end testing.
         *
         * @method _updateE2EHandlers
         */
        _updateE2EHandlers: function() {

            // Add tasks and mods here a we find them.
            // TODO: Disable angular animations when e2e is enabled.
            // ...
        },

        /**
         * Return whether we are running inside WHM or something else (e.g., whm)
         *
         * @method  isWebmail
         * @return {Boolean} true if this is webmail; false otherwise
         */
        isWebmail: function() {
            return (/webmail/i).test(this.applicationName);
        },

        /**
         * Get the name of the theme from the URL if applicable.
         *
         * @method getTheme
         * @return {String} Name of the theme from the url
         */
        getTheme: function() {
            var theme = this.theme;
            if (!theme) {
                if (!this.isUnprotected() && ( this.isCpanel() || this.isWebmail() )) {
                    var folders = this._url_path.split("/");
                    this.theme = theme = folders[3];
                }
            }

            return theme;
        },

        /**
         * Get the path up to the theme if applicable to the current application.
         *
         * @method getThemePath
         * @return {String} Path including theme if applicable for the application.
         */
        getThemePath: function() {
            var themePath = this.themePath;
            if (!themePath) {
                themePath = this.securityToken + "/";
                if ( this.isUnprotected() ) {
                    themePath = this.config.themePath;
                } else if ( this.isCpanel() ) {
                    themePath += "frontend/" + this.getTheme() + "/";
                } else if ( this.isWebmail() ) {
                    themePath += "webmail/" + this.getTheme() + "/";
                } else if ( this.isUnitTest() ) {

                    // Unit tests
                    themePath = "/";
                } else if ( this.isOther() || PAGE.customThemePath) {

                    // For unrecognized applications, use the path passed in PAGE.THEME_PATH
                    themePath = this.config.themePath;
                }
                this.themePath = themePath;
            }
            return themePath;
        },

        /**
         * Get the domain relative path for the relative url path.
         *
         * @method buildPath
         * @return {String} Domain relative url path including theme if applicable for the application to the file.
         */
        buildPath: function(relative) {
            return this.getThemePath() + relative;
        },

        /**
         * Get the full url path for the relative url path.
         *
         * @method buildFullPath
         * @return {String} Full url path including theme if applicable for the application to the file.
         */
        buildFullPath: function(relative) {
            return this.protocol + "//" + this.domain + ":" + this.port + this.buildPath(relative);
        },

        /**
         * Get the url for the login ui.
         *
         * @method getLoginPath
         * @return {String} Url that will trigger a login.
         */
        getLoginPath: function() {
            return this.getRootPath();

            // TODO: Add redirect url once its supported by cpsvrd
            // return this.getRootPath() + "?redir=" + this.applicationPath;
        },

        /**
         * Get the url for the root of the application.
         *
         * @method getRootPath
         * @return {String} Url that will trigger a login.
         */
        getRootPath: function() {
            return this.protocol + "//" + this.domain + ":" + this.port;
        },

        /**
         * State management for the Unique Id generator.
         *
         * @private
         * @type {Object} - Contains the counters for the Unique Id generator.
         */
        _uniqueSets: {},

        /**
         * Generate a unique id based on the prefix.
         *
         * @param  {string} [prefix] Optional prefix for the id. Will default to id.
         * @param  {number} [start]  Optional start number. Defaults to 1.
         * @return {string}          Id that is unique within the context.
         */
        generateUniqueId: function(prefix, start) {
            prefix = prefix || "id";
            var id = start || 1;
            if (!this._uniqueSets[prefix]) {
                this._uniqueSets[prefix] = id;
            } else {
                id = ++this._uniqueSets[prefix];
            }
            return prefix + id;
        },

        /**
         * Conditionally log a message only in debug mode
         *
         * @method  debug
         * @param  {String} msg
         */
        debug: function(msg) {
            if (this.config.debug && window && window.console) {
                window.console.log(msg);
            }
        },

        /**
         * Log a message
         *
         * @method  debug
         * @param  {String} msg
         */
        log: function(msg) {
            if (window && window.console) {
                window.console.log(msg);
            }
        },

        /**
        Cloned from YUI 3.8.1 implementation so the CPANEL namespace can emulate
        the behavior of YAHOO namespace.

        Utility method for safely creating namespaces if they don't already exist.
        May be called statically on the CPANEL global object.

        When called statically, a namespace will be created on the CPANEL global
        object:

        // Create `CPANEL.your.namespace.here` as nested objects, preserving any
        // objects that already exist instead of overwriting them.
        CPANEL.namespace('your.namespace.here');

        Dots in the input string cause `namespace` to create nested objects for each
        token. If any part of the requested namespace already exists, the current
        object will be left in place and will not be overwritten. This allows
        multiple calls to `namespace` to preserve existing namespaced properties.

        If the first token in the namespace string is "CPANEL", that token is
        discarded.

        Be careful with namespace tokens. Reserved words may work in some browsers
        and not others. For instance, the following will fail in some browsers
        because the supported version of JavaScript reserves the word "long":

        CPANEL.namespace('really.long.nested.namespace');

        Note: If you pass multiple arguments to create multiple namespaces, only the
        last one created is returned from this function.

        @method namespace
        @param {String} namespace* One or more namespaces to create.
        @return {Object} Reference to the last namespace object created.
        **/
        namespace: function() {
            var a = arguments,
                o, i = 0,
                j, d, arg;
            for (; i < a.length; i++) {
                o = this; // Reset base object per argument or it will get reused from the last
                arg = a[i];
                if (arg.indexOf(PERIOD) > -1) { // Skip this if no "." is present
                    d = arg.split(PERIOD);

                    /* TODO: Figure out how to remove the linter issue */
                    if (d[0] === "CPANEL") {
                        if (d[1] === "v2") {
                            j = 2;
                        } else {
                            j = 1;
                        }
                    }
                    for (; j < d.length; j++) {
                        o[d[j]] = o[d[j]] || {};
                        o = o[d[j]];
                    }
                } else {
                    o[arg] = o[arg] || {};
                    o = o[arg]; // Reset base object to the new object so it's returned
                }
            }
            return o;
        }
    };

    /**
     * Singleton Constructor
     * @return {Object} Returns the CJT singleton.
     */
    CJT.getInstance = function() {
        if (instance === null) {
            instance = new CJT();
        }
        return instance;
    };

    // The one global so qa tests can easily poke this.
    window.__CJT2 = CJT.getInstance();

    return CJT.getInstance();
});
