/*
# cjt/util/flatObject.js                          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define: false     */
/* --------------------------*/


/**
 *
 * @module cjt/util/flatObject
 * @example
 *     var deep = {
 *         a: 1,
 *         b: {
 *             c: 1
 *             d: {
 *                 e: 1
 *             }
 *         }
 *     };
 *     var flat = FLAT.flatten(deep);
 *
 *     Now flat will look like:
 *
 *     {
 *        a: 1,
 *        b.c: 1,
 *        b.d.e: 1
 *     }
 */
define(function() {
    "use strict";

    /**
     * Convert a deep nested object into a single layer object with the properties named
     * with the full deep names with period separators.
     * @param  {Object} inputObject Deep object
     * @return {Object}             Flattened object
     */
    function flatten(inputObject) {
        var outputObject = {};

        for (var prop in inputObject) {
            if (inputObject.hasOwnProperty(prop)) {
                if ((typeof inputObject[prop]) === "object") {
                    var flatObject = flatten(inputObject[prop]);
                    for (var innerProp in flatObject) {
                        if (flatObject.hasOwnProperty(innerProp)) {
                            outputObject[prop + "." + innerProp] = flatObject[innerProp];
                        }
                    }
                } else {
                    outputObject[prop] = inputObject[prop];
                }
            }
        }
        return outputObject;
    }

    return {
        flatten: flatten
    };
});
