/*
 * cjt/startup.js                                     Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/**
 * DEVELOPERS NOTES:
 * This is common application startup code. Use it within *.dist.js files.
 */

/* global define: false, require: false */

define(function() {

    /**
     * Expands a list of dependencies. If one is not provided, then a default
     * list is generated from the passed in second argument.
     *
     * @method _expandDependencies description
     * @private
     * @param  {String|Array} dependencies
     * @return {Array}  List of dependencies to load.
     */
    function _expandDependencies(dependencies) {
        if (Array.isArray(dependencies)) {
            return dependencies;
        } else if (typeof dependencies === "string") {
            return [
                dependencies
            ];
        }
        throw "You must pass either an array of dependencies or a single string dependency";
    }


    return {

        /**
         * Start up the application with the requested dependencies.
         *
         * @method  startApplication
         * @param  {Array|String} dependencies List of dependencies.
         *   If a string is passed, it is converted into an array with that one item.
         *   The parameter defaults to:
         *
         *     [ "app/index" ]
         * @return {Object} reference to this so these can be chained
         */
        startApplication: function startApplication(dependencies) {
            dependencies = _expandDependencies(dependencies || "app/index");
            require(
                dependencies,
                function(APP) {
                    if (APP) {
                        APP();
                    }
                }
            );
            return this;
        },

        /**
         * Start up the master application with the requested
         * dependencies.
         *
         * @method  startMaster
         * @param  {Array|String} dependencies List of dependencies.
         *   If a string is passed, it is converted into an array with that one item.
         *   The parameter defaults to:
         *
         *     [ "master/master" ]
         * @return {Object} reference to this so these can be chained
         */
        startMaster: function startMaster(dependencies) {
            dependencies = _expandDependencies(dependencies || "master/master");
            require(
                dependencies,
                function(MASTER) {
                    if (MASTER) {
                        MASTER();
                    }
                });
            return this;
        },

        /**
         * Start up the master application with the requested
         * dependencies after a short delay.
         *
         * @method  deferStartMaster
         * @param  {Array|String} dependencies List of dependencies.
         *   If a string is passed, it is converted into an array with that one item.
         *   The parameter defaults to:
         *
         *     [ "master/master" ]
         * @return {Object} reference to this so these can be chained
         */
        deferStartMaster: function deferStartMaster(dependencies) {

            // Defer this since the primary task here is this page,
            // so we can wait a sec for the search tool to start working...
            var self = this;
            setTimeout(function() {
                self.startMaster(dependencies);
            });
            return this;
        }
    };
});
