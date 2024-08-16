/*
# cjt/util/parse.js                               Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define: false     */
/* --------------------------*/

// TODO: Add tests for these

/**
 *
 * @module cjt/util/parse
 * @example
 *
 */
define(["lodash"], function(_) {
    "use strict";


    var booleanMap = {
        "no": false,
        "false": false,
        "yes": true,
        "true": true,
        "1": true,
        "0": false
    };

    function _parseBoolean( string ) {
        if (_.isUndefined(string) || _.isNull(string)) {
            return false;
        }

        string = (string + "").toLowerCase();
        return ( string in booleanMap && booleanMap.hasOwnProperty(string)) ? booleanMap[ string ] : !!string;
    }

    /**
     * Utility module for parsing various string representation into native types.
     *
     * @static
     * @public
     * @class parse
     */
    var parse = {

        /**
         * Parse a boolean using the lookup system.
         * @param  {String} string Input string to evaluate.
         * @return {Boolean}       true or false.
         */
        parseBoolean: _parseBoolean,

        /**
         * Parse a perl generated boolean.
         * @param  {String} string Input string to evaluate.
         * @return {Boolean}       true or false.
         */
        parsePerlBoolean: function( string ) {
            if (_.isUndefined(string) || _.isNull(string)) {
                return false;
            }

            if (string === "") {
                return false;
            }

            return _parseBoolean(string);
        },

        /**
         * Parse a string into a number
         * @param  {String} string       Input string to evaluate
         * @param  {Number} defaultValue Default value to use if the string is undefined, null, empty or NaN.
         * @return {Number}
         */
        parseNumber: function(string, defaultValue) {
            if (_.isUndefined(string) || _.isNull(string) || string === "") {
                return defaultValue;
            }

            var number = Number(string);
            if (isNaN(number)) {
                return defaultValue;
            }

            return number;
        },

        /**
         * Parse a string into a integer
         * @param  {String} string       Input string to evaluate
         * @param  {Number} defaultValue Default value to use if the string is undefined, null, empty or NaN.
         * @param  {Number} [base]       Optional base for the parsing. Defaults to 10.
         * @return {Number}
         */
        parseInteger: function(string, defaultValue, base) {
            if (!base) {
                base = 10;
            }

            if (_.isUndefined(string) || _.isNull(string) || string === "") {
                return defaultValue;
            }

            var number = parseInt(string, 10);
            if (isNaN(number)) {
                return defaultValue;
            }

            return number;
        }
    };

    return parse;
});
