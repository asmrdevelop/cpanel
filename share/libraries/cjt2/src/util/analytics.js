/*
# cpanel - share/libraries/cjt2/src/util/analytics.js
#                                                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global window: true, define: false */


(function() {
    "use strict";

    /**
     * @typedef  {Object}  AnalyticsState
     * @property {Boolean} enable - true to enable analytics logging, false otherwise.
     *
     * @function AnalyticsState
     * @constructor
     * @param {Object}  [options]   Optional set of initializaton options.
     * @param {Boolean} [options.enable]   If true, analytics logging will be enabled.
     */
    function AnalyticsState(options) {
        if( !(this instanceof AnalyticsState) ) {
            return new AnalyticsState(options);
        }

        this.update(this.DEFAULTS);
        this.update(options);
    }

    // Only properties that exist on this default object can be set via update()
    AnalyticsState.prototype.DEFAULTS = {
        enable: true,
    };

    /**
     * Given an object containing valid AnalyticsState properties, this method will
     * update the values of the AnalyticsState instance to the values provided by
     * said object.
     *
     * @method update
     * @param  {Object} options   The options and values to change.
     * @return {AnalyticsState}   The updated AnalyticsState instance.
     */
    AnalyticsState.prototype.update = function(options) {
        var self = this;
        options = _parseOptions(options);

        // Only update properties that are present in DEFAULTS
        var propNames = Object.keys( self.DEFAULTS );
        propNames.forEach(function(propName) {
            if(options.hasOwnProperty(propName)) {
                self[propName] = options[propName];
            }
        });

        return self;
    };

    /**
     * Serializes the AnalyticsState object into a JSON blob.
     *
     * @method serialize
     * @return {String}   A JSON string representing the analytics state.
     */
    AnalyticsState.prototype.serialize = function() {
        return JSON.stringify( this );
    };

    function _parseOptions(options) {
        if(!options) {
            return {};
        }

        if(options.hasOwnProperty("enable")) {
            options.enable = Boolean(options.enable);
        }

        return options;
    }

    // This is the actual return value
    var Analytics = {
        _constructor: AnalyticsState, // For testing purposes

        /**
         * Create an analytics state instance that carries the current client state.
         *
         * @method create
         * @static
         * @param  {Object} [options]   Optional set of initialization options.
         * @return {AnalyticsState}     A new analytics state object.
         */
        create: function create(options) {
            return new AnalyticsState(options);
        },

        /**
         * Test whether an object was created by the create method.
         *
         * @method isAnalyticsStateInstance
         * @static
         * @param  {Object} thingToTest   The object to test.
         * @return {Boolean}              True if it is an instance of AnalyticsState.
         */
        isAnalyticsStateInstance: function(thingToTest) {
            return (thingToTest instanceof AnalyticsState);
        },
    };

    if ( typeof define === "function" && define.amd ) {
        define([], function() {
            return Analytics;
        });
    } else {
        if (!window.CPANEL) {
            window.CPANEL = {};
        }
        window.CPANEL.Analytics = Analytics;
    }
}());
