/* global define: false */

(function() {

    "use strict";

    // Constants
    var DEFAULT_REPLACE_PATTERN = /%/;
    var DEFAULT_LOCALE_EXTENSION = "-%";
    var DEFAULT_TEST_FN = function(name) {
        return true;
    };

    /**
     * Test if what is passed is a function.
     * @method isFunction
     * @param  {Object} fn
     * @return {Boolean}     true if fn is a function, false otherwise.
     */
    function isFunction(fn) {
        var getType = {};
        return fn && getType.toString.call(fn) === "[object Function]";
    }

    /**
     * Convert the configuration into a function depending on
     * how it is passed.
     *
     * @method setupIsLocalizableFunction
     * @param  {String|Regexp|Function} isLocalizableCfg
     * @return {Function}
     */
    function setupIsLocalizableFunction(isLocalizableCfg) {
        var isLocalizableFn;
        if (typeof isLocalizableCfg === "string") {
            var pattern = isLocalizableCfg;
            var regexp = new RegExp(pattern);
            isLocalizableFn = function(name) {
                return regexp.test(name);
            };
        } else if (isLocalizableCfg instanceof RegExp) {
            isLocalizableFn = function(name) {
                return isLocalizableCfg.test(name);
            };
        } else if (isFunction(isLocalizableCfg)) {
            isLocalizableFn = isLocalizableCfg;
        }

        if (!isLocalizableFn) {
            isLocalizableFn = DEFAULT_TEST_FN;
        }

        return isLocalizableFn;
    }

    /**
     * Initialize the replacement pattern.
     *
     * @method setupReplacePattern
     * @param  {String|Regexp} replace Candidate replacement pattern.
     * @return {Regexp}        Expression
     */
    function setupReplacePattern(replace) {
        var regexReplace;
        if (typeof replace === "string") {
            regexReplace = new RegExp(replace);
        } else if (replace instanceof RegExp) {
            regexReplace = replace;
        }
        if (!regexReplace) {
            regexReplace = DEFAULT_REPLACE_PATTERN;
        }

        return regexReplace;
    }

    /**
     * Initialize the configuration
     *
     * @method initConfig
     * @param  {Object} config
     */
    function initConfig(config) {
        if (config.locale) {
            if (!config.locale.isInitialized) {

                // We only want to do this once
                if (config.locale.isLocalizable) {

                    // Cache it so we don't have to do this for each call
                    config.locale.isLocalizable = setupIsLocalizableFunction(config.locale.isLocalizable);
                } else {
                    config.locale.isLocalizable = DEFAULT_TEST_FN;
                }

                if (!config.locale.replace) {
                    config.locale.replace = DEFAULT_REPLACE_PATTERN;
                } else {
                    config.locale.replace = setupReplacePattern(config.locale.replace);
                }

                if (!config.locale.extension) {
                    config.locale.extension = DEFAULT_LOCALE_EXTENSION;
                }

                config.locale.isInitialized = true;
            }
        } else {
            config.locale = {
                disabled: true,
                isInitialized: true
            };
        }
    }

    /**
     * Checks if the config has a current locale set
     *
     * @method hasCurrentLocale
     * @param  {Object}  config
     * @return {Boolean}
     */
    function hasCurrentLocale(config) {
        return config &&
               config.locale &&
               typeof (config.locale.currentLocale) !== "undefined" &&
               config.locale.currentLocale !== "";
    }

    define({
        version: "2.1.0",
        name: "cPanel locale requirejs plugin",
        description: "The locale requirejs plugin loads files and their related locale file.",

        /**
         * Load the localized resource if a locale is setup.
         *
         * @method load
         * @param  {String} name     Module to load.
         * @param  {Function} req    Require function instance.
         * @param  {Function} onload Load callback.
         * @param  {Object} config   Current requirejs configuration
         */
        load: function(name, req, onload, config) {

            // Handle configure normalization first.
            config = config || {};
            initConfig(config);

            if (!config.locale.disabled &&
                hasCurrentLocale(config) &&
                config.locale.isLocalizable(name)) {

                // Remove any query args from the url, before appending
                // the locale tag.
                //
                // Load the requested file and the lexicon for the requested file by
                // appending ?locale= to the js file
                var url = req.toUrl(name) || "";
                var queryArgs = url.split("?");
                var dest = queryArgs[0] +
                                (config.locale.addMin && queryArgs[0].indexOf(".min") === -1 ? ".min" : "") +
                                ".js?locale=" + config.locale.currentLocale +
                                "&locale_revision=" + config.locale.revision;

                req([dest], function(module, lexicon) {

                    // We are passing the lexicon to onload mainly for unit tests
                    // Most lexicon systems should just auto register themselves with
                    // some framework. The module must be first so that clients that
                    // need the return value will still get it in the position they expect.
                    onload(module, lexicon);
                });

            } else {

                // Load the requested file, probably debug mode
                // for development.
                req([name], function(value) {
                    onload(value);
                });
            }
        }
    });

})();
