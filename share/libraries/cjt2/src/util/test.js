/*
# cjt/util/test.js                                Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define:true */
/* --------------------------*/

// TODO: Add tests for these

/**
 *
 * @module cjt/util/test
 * @example

    require(["cjt/util/test"], function(TEST){

        var foo = {
            a : 100,
            b : {
                c : {
                    e: 105
                },
                d : "ninja"
            }
        };

        if (TEST.objectHasPath(foo, "a")) {
            // Should succeed.
        }

        if (TEST.objectHasPath(foo, "b.c.e")) {
            // Should succeed.
        }

        if (TEST.objectHasPath(foo, "a.b.c.e")) {
            // Should fail.
        }
    });
 */
define(["lodash"], function(_) {

    /**
     * Validate that the root object contains the structure defined by the path.
     *
     * @public
     * @static
     * @method  objectHasPath
     * @param  {Object} root Object to check for the given structure.
     * @param  {String} path String with all the properties required separated by "."s
     * @return {Boolean}     true if the structure exists, false otherwise.
     */
    var objectHasPath = function(root, path) {
        var parts = path.split(".");
        var context = root;
        if (!context) {
            return false;
        }

        for (var i = 0, l = parts.length; i < l; i++) {
            var part = parts[i];
            if (!(part in context)) {
                return false;
            }
            context = context[part];
        }

        return true;
    };

    /**
     * Validate that the root object contains the structure and the leaf is a function.
     *
     * @public
     * @static
     * @method objectHasFunction
     * @param  {Object} root Object to check for the given structure.
     * @param  {String} path String with all the properties required separated by "."s
     * @return {Boolean}     true if the structure exists and leaf is a function, false otherwise.
     */
    var objectHasFunction = function(root, path) {
        var parts = path.split(".");
        var context = root;
        if (!context) {
            return false;
        }

        for (var i = 0, l = parts.length; i < l; i++) {
            var part = parts[i];
            if (!(part in context)) {
                return false;
            }
            context = context[part];
        }

        return _.isFunction(context);
    };

    /**
     * Test if the object is a promise. This is an approximate
     * process since promise do not have a instance type. We
     * test for a then() method and then assume its a PROMISE A at
     * least.
     * @public
     * @static
     * @method isPromise
     * @param {Object} obj Object to test.
     * @return {Boolean} true if this looks like a promise, false otherwise.
     */
    var isPromise = function(obj) {
        return obj && obj.then && _.isFunction(obj.then);
    };

    /**
     * Test if the object is a $q promise. This is an approximate
     * process since promise do not have a instance type. We
     * test for a then() and a finally() method and then assume its
     * a $q from angular.
     * @public
     * @static
     * @method isQPromise
     * @param {Object} obj Object to test
     * @return {Boolean} true if this looks like a promise, false otherwise.
     */
    var isQPromise = function(obj) {
        return isPromise(obj) && obj["finally"] && _.isFunction(obj["finally"]);
    };

    /**
     * Provides various static utility testing functions.
     *
     * @class  test
     * @static
     */

    // Publish the component
    var test = {
        objectHasPath: objectHasPath,
        objectHasFunction: objectHasFunction,
        isPromise: isPromise,
        isQPromise: isQPromise
    };

    return test;

});
