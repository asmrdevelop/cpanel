/*
    #                                                 Copyright(c) 2020 cPanel, L.L.C.
    #                                                           All rights reserved.
    # copyright@cpanel.net                                         http://cpanel.net
    # This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

(function() {

    // check to be sure the CPANEL global object already exists
    if (typeof CPANEL == "undefined" || !CPANEL) {
        alert("You must include the CPANEL global object before including keyboard.js!");
    } else {
        var _is_old_ie = YAHOO.env.ua.ie && (YAHOO.env.ua.ie < 9);

        /**
        This only works with keypress listeners since it works on character codes,
        not key codes. Key codes pertain to the *key* pressed, while character
        codes pertain to the character that that key press produces.

        Browsers confuse the two in the keyCode and charCode properties.

        These methods are not foolproof; particular problems:
            * The "alpha" logic only applies to English/US-ASCII.
              Other languages' keyboards will not work correctly,
              and non-Latin alphabets will be completely broken.
            * Mouse pasting will circumvent these methods.
            * Some methods break keyboard pasting in some browsers (e.g., FF 13).

        In light of the above, use this code with caution.

        @module keyboard
    */

        /**
        The urls class URLs for AJAX calls.
        @class keyboard
        @namespace CPANEL
        @extends CPANEL
    */
        CPANEL.keyboard = {
            NUMERIC: /[0-9]/,
            LOWER_CASE_ALPHA: /[a-z]/,
            UPPER_CASE_ALPHA: /[A-Z]/,
            ALPHA: /[a-zA-Z]/,
            ALPHA_NUMERIC: /[a-zA-Z0-9]/,

            /**
            Processes the keyboard input to ignore keys outside the range.
            @name _onKeyPressAcceptValues
            @private
            @param [EventObject] e - event object passed by the framework.
            @param [RegEX] charReg - single character matching expression
        */
            _onKeyPressAcceptValues: function(e, charReg) {
                if (!charReg) {
                    return true;
                }

                // We need to reject keypress events that come from arrow keys etc.
                // We detect this in Firefox and Opera by checking for !charCode;
                // no other browser seems to fire keypress in those instances.
                //
                // We also need to ignore IE <8 since it only reports keyCode
                // for keypress in any circumstance, though it never fires keypress
                // on arrow keys.
                if (!_is_old_ie && !e.charCode) {
                    return true;
                }

                var charCode = EVENT.getCharCode(e);

                // Test to see if this character key is allowed
                var keyChar = String.fromCharCode(charCode);
                return charReg.test(keyChar);
            },

            /**
            Tests if a keypress was the return key
            @name isReturnKey
            @param [EventObject] e - event object passed by the framework.
        */
            isReturnKey: function(e) {
                return EVENT.getCharCode(e) == 13;
            },

            /**
            Allows only numeric keys to be processed.
            NOTE: This BREAKS copy/pasting with the keyboard in Firefox 13.
            @name allowNumericKey
            @param [EventObject] e - event object passed by the framework.
        */
            allowNumericKey: function(e) {
                var ok = CPANEL.keyboard._onKeyPressAcceptValues(e, CPANEL.keyboard.NUMERIC);
                if (!ok) {
                    EVENT.preventDefault(e);
                }
                return ok;
            },

            /**
            Allows only lower-case alpha (ASCII-English) keys to be processed.
            @name allowLowerCaseAlphaKey
            @param [EventObject] e - event object passed by the framework.
        */
            allowLowerCaseAlphaKey: function(e) {
                var ok = CPANEL.keyboard._onKeyPressAcceptValues(e, CPANEL.keyboard.LOWER_CASE_ALPHA);
                if (!ok) {
                    EVENT.preventDefault(e);
                }
                return ok;
            },

            /**
            Allows only upper-case alpha (ASCII-English) keys to be processed.
            NOTE: This BREAKS copy/pasting with the keyboard in Firefox 13.
            @name allowUpperCaseAlphaKey
            @param [EventObject] e - event object passed by the framework.
        */
            allowUpperCaseAlphaKey: function(e) {
                var ok = CPANEL.keyboard._onKeyPressAcceptValues(e, CPANEL.keyboard.UPPER_CASE_ALPHA);
                if (!ok) {
                    EVENT.preventDefault(e);
                }
                return ok;
            },

            /**
            Allows only alpha (ASCII-English) keys to be processed.
            @name allowAlphaKey
            @param [EventObject] e - event object passed by the framework.
        */
            allowAlphaKey: function(e) {
                var ok = CPANEL.keyboard._onKeyPressAcceptValues(e, CPANEL.keyboard.ALPHA);
                if (!ok) {
                    EVENT.preventDefault(e);
                }
                return ok;
            },

            /**
            Allows only alpha (ASCII-English) and numeric keys to be processed.
            @name allowAlphaNumericKey
            @param [EventObject] e - event object passed by the framework.
        */
            allowAlphaNumericKey: function(e) {
                var ok = CPANEL.keyboard._onKeyPressAcceptValues(e, CPANEL.keyboard.ALPHA_NUMERIC);
                if (!ok) {
                    EVENT.preventDefault(e);
                }
                return ok;
            },

            /**
            Allows only keys that match the single character matching rule to be processed.
            Matching rules should only contain match patterns for single unicode characters.
            @name allowAlphaNumericKey
            @param [EventObject] e - event object passed by the framework.
            @parem [Regex] charReg - pattern matching rules for any single character.
        */
            allowPatternKey: function(e, charReg) {
                var ok = CPANEL.keyboard._onKeyPressAcceptValues(e, charReg);
                if (!ok) {
                    EVENT.preventDefault(e);
                }
                return ok;
            }
        };
    }

}());
