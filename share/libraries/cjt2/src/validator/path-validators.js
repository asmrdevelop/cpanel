/*
# path-validators.js                            Copyright(c) 2020 cPanel, L.L.C.
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
 * This module has a collection of path validators
 *
 * @module path-validators
 * @requires angular, lodash, validator-utils, validate, locale
 */
define([
    "angular",
    "lodash",
    "cjt/validator/validator-utils",
    "cjt/util/locale",
    "cjt/validator/validateDirectiveFactory"
],
function(angular, _, validationUtils, LOCALE) {

    var INVALID_PATH_CHARS = ["\\", "*", "|", "\"", "<", ">"];
    var INVALID_PATH_REGEX = new RegExp("[" + _.escapeRegExp(INVALID_PATH_CHARS.join("")) + "]");
    var MAX_PATH_LENGTH = 255;

    /**
     * Validate document root
     *
     * @method validPath
     * @param {string} document root path
     * @return {object} validation result
     */
    var pathValidators = {
        validPath: function(val) {
            var result = validationUtils.initializeValidationResult();

            if (val === null || typeof val === "undefined") {
                result.isValid = false;
                result.add("path", LOCALE.maketext("You must specify a valid path."));
                return result;
            }

            if (INVALID_PATH_REGEX.test(val)) {
                result.isValid = false;
                result.add("path",
                    LOCALE.maketext("The path cannot contain the following characters: [join, ,_1]",
                        INVALID_PATH_CHARS));
                return result;
            }

            var folderNames = val.split("/");

            if (folderNames && folderNames.length > 0) {

                for (var i = 0, len = folderNames.length; i <  len; i++) {

                    var name = folderNames[i];

                    if (name.length > MAX_PATH_LENGTH) {
                        result.isValid = false;
                        result.add("path",
                            LOCALE.maketext("Folder name is long by [quant,_1,byte,bytes]. The maximum allowed length is [quant,_2,byte,bytes].",
                                name.length - MAX_PATH_LENGTH,
                                MAX_PATH_LENGTH));
                        return result;
                    }

                    if (name === "." || name === "..") {
                        result.isValid = false;
                        result.add("path",
                            LOCALE.maketext("You cannot use the [list_and,_1] directories.", [".", ".."]));
                        return result;
                    }
                }
            }

            return result;
        }
    };

    var validatorModule = angular.module("cjt2.validate");

    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(pathValidators);
        }
    ]);

    return {
        methods: pathValidators,
        name: "path-validators",
        description: "Validation library for paths.",
        version: 2.0,
    };

});
