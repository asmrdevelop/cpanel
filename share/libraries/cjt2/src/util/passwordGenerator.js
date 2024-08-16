/*
# cjt/utils/passwordGenerator.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(["lodash"], function(_) {

    var MINIMUM_LENGTH = 5;
    var MAXIMUM_LENGTH = 18;
    var DEFAULT_OPTIONS = {
        length: 12,
        uppercase: true,
        lowercase: true,
        numbers: true,
        symbols: true
    };

    var CHARACTER_SETS = {
        uppercase: "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        lowercase: "abcdefghijklmnopqrstuvwxyz",
        numbers: "0123456789",
        symbols: "!@#$%^&*()-_=+{}[];,.?~"
    };

    var _buildCharacterSet = function(options) {
        var chars = "";
        if (options.uppercase) {
            chars += CHARACTER_SETS.uppercase;
        }

        if (options.lowercase) {
            chars += CHARACTER_SETS.lowercase;
        }

        if (options.numbers) {
            chars += CHARACTER_SETS.numbers;
        }

        if (options.symbols) {
            chars += CHARACTER_SETS.symbols;
        }
        return chars;
    };

    return {
        MINIMUM_LENGTH: MINIMUM_LENGTH,
        MAXIMUM_LENGTH: MAXIMUM_LENGTH,
        DEFAULT_OPTIONS: DEFAULT_OPTIONS,
        CHARACTER_SETS: CHARACTER_SETS,
        generate: function(options) {
            if (!options) {
                options = {};
            }

            // Set the defaults
            _.defaults(options, DEFAULT_OPTIONS);

            // Validate the types of characters
            if (!options.uppercase && !options.lowercase && !options.numbers && !options.symbols) {
                throw "invalid options, you must select at lest one character set to generate from.";
            }

            // Validate the length and adjust as needed.
            if (_.isUndefined(options.length) || !_.isNumber(options.length) || options.length < MINIMUM_LENGTH) {
                options.length = DEFAULT_OPTIONS.length;
            } else if (options.length > MAXIMUM_LENGTH) {
                options.length = MAXIMUM_LENGTH;
            }

            var chars = _buildCharacterSet(options);

            // generate the password
            var password = "";
            for (var i = 0; i < options.length; i++) {
                var index = Math.floor(Math.random() * chars.length);
                password += chars.substring(index, index + 1);
            }

            return password;
        },
        _buildCharacterSet: _buildCharacterSet
    };
});
