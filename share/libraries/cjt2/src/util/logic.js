/*
# cjt/util/logic.js                               Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    function($) {

        return {

            /**
             * If value1 defined, compare value1 to value2, otherwise return the default value
             *
             * @method compareOrDefault
             * @param  {String} value1 First operand if defined
             * @param  {String} value2 Second operand if first is defined.
             * @param  {Boolean} def   Default value if first operand is undefined.
             * @return {Boolean}
             */
            compareOrDefault: function(value1, value2, def) {
                if (typeof (value1) !== "undefined") {
                    return value1 === value2;
                } else {
                    return def;
                }
            },

            /**
             * Translates a pair of binary operands to a named state. Useful for translating independent states
             * to shared state variable for things like radio buttons that need to share a model.
             * @param  {Boolean} arg1      State 1
             * @param  {Boolean} arg2      State 2
             * @param  {Any} both_true     Returned if both state args are true.
             * @param  {Any} arg1_true     Returned if only arg1 is true.
             * @param  {Any} arg2_true     Returned if only arg2 is true.
             * @param  {Any} none_true     Returned if neither arg1 or arg2 are true
             * @return {Any}               See above.
             */
            translateBinaryAndToState: function(arg1, arg2, both_true, arg1_true, arg2_true, none_true) {
                if (arg1 && arg2) {
                    return both_true;
                } else if (arg1) {
                    return arg1_true;
                } else if (arg2) {
                    return arg2_true;
                } else {
                    return none_true;
                }
            }

        };
    }
);
