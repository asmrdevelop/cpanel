/*
# cpanel - base/sharedjs/zone_editor/directives/base_validators.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define([
    "angular",
    "cjt/validator/length-validators",
],
function(angular, lengthValidators) {
    "use strict";

    var MAX_CHAR_STRING_BYTE_LENGTH = 255;

    var validators = {
        characterStringValidator: function(val) {
            return lengthValidators.methods.maxUTF8Length(val, MAX_CHAR_STRING_BYTE_LENGTH);
        },
    };

    var validatorModule = angular.module("cjt2.validate");
    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(validators);
        },
    ]);

    return {
        methods: validators,
        name: "baseValidators",
        description: "General DNS record validation library",
        version: 1.0,
    };
});
