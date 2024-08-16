/*
# cjt/util/class.js                               Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

/* jshint -W098 */

define([ ],
    function() {
        "use strict";

        return {

            /**
             * Create a named constructor for a subclass.
             * The “myConstructor” logic gets executed after the parent’s
             * constructor logic in the subclass.
             *
             * @static
             * @method subclass
             * @parentConstructor   {Function}  The parent class’s constructor
             * @name                {String}    The new constructor’s name,
             *                                  which will show up in stack
             *                                  traces and thus aid debugging.
             * @myConstructor       {Function}  (optional) Constructor logic.
             *
             * @return {Function} The new constructor. This will never be the
             *                    same function as “myConstructor”, though
             *                    it will call “myConstructor”.
             */
            subclass: function subclass(parentConstructor, name, myConstructor) {
                if (!name) {
                    console.log(arguments);
                    throw "I need a name!";
                }

                var instantiate = function() {
                    parentConstructor.apply(this, arguments);
                    if (myConstructor) {
                        myConstructor.apply(this, arguments);
                    }
                };

                // Do it this way to get a “named” function; this helps
                // with reading stack traces and the like.
                // cf. https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/function
                //
                /* jshint -W061 */
                var newClass = eval("[function %() { instantiate.apply(this, arguments) }][0]".replace(/%/, name));
                /* jshint +W061 */

                newClass.prototype = Object.create(parentConstructor.prototype);

                return newClass;
            },

        };
    }
);
