/*
# directives/loc_validators.js                             Copyright 2022 cPanel, L.L.C.
#                                                                     All rights reserved.
# copyright@cpanel.net                                                   http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define([
    "angular",
    "cjt/util/locale",
    "cjt/validator/validator-utils",
    "cjt/validator/validateDirectiveFactory"
],
function(angular, LOCALE, validationUtils) {

    "use strict";

    var latitudeLongitudeRegex = /^(\d+)\s(\d+)\s(\d+(?:\.\d+)?)\s([A-Z]+)$/;

    var latitudeDegreeRegex = /^[0-9]{1,2}$/;
    var latitudeHemisphereRegex = /^[NS]$/;

    var longitudeDegreeRegex = /^[0-9]{1,3}$/;
    var longitudeHemisphereRegex = /^[EW]$/;

    var minuteRegex = /^[0-9]{1,2}$/;
    var secondsRegex = /^[0-9]{1,2}(?:\.[0-9]{1,3})?$/;

    var validators = {

        /**
         * Validates that Latitude is in the correct format - DMS
         *
         * @method validateLatitude
         * @param {String} val Text to validate
         * @return {Object} Validation result
         */
        validateLatitude: function(val) {
            var result = validationUtils.initializeValidationResult();

            var matches = val.match(latitudeLongitudeRegex);

            if (matches === null) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("Latitude must be entered in “Degree Minute Seconds Hemisphere” format. Example: “12 45 52.233 N”."));
                return result;
            }

            if (!latitudeDegreeRegex.test(matches[1]) || parseInt(matches[1]) > 90) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The first set of digits of Latitude are for Degrees. Degrees must be a 1 or 2 digit number between 0 and 90."));
            } else if (!minuteRegex.test(matches[2]) || parseInt(matches[2]) > 59) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The second set of digits of Latitude are for Minutes. Minutes must be a 1 or 2 digit number between 0 and 59."));
            } else if (!secondsRegex.test(matches[3]) || parseFloat(matches[3]) > 59.999) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The third set of digits of Latitude are for Seconds. Seconds can only have up to 3 decimal places, and must be between 0 and 59.999."));
            } else if (!latitudeHemisphereRegex.test(matches[4])) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The last character of Latitude is the hemisphere, which can only be N or S."));
            }

            return result;
        },

        /**
         * Validates that Longitude is in the correct format - DMS
         *
         * @method validateLongitude
         * @param {String} val Text to validate
         * @return {Object} Validation result
         */
        validateLongitude: function(val) {
            var result = validationUtils.initializeValidationResult();

            var matches = val.match(latitudeLongitudeRegex);

            if (matches === null) {
                result.isValid = false;
                result.add("locLon", LOCALE.maketext("Longitude must be entered in “Degree Minute Seconds Hemisphere” format. Example: “105 40 33.452 W”."));
                return result;
            }

            if (!longitudeDegreeRegex.test(matches[1]) || parseInt(matches[1]) > 180) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The first set of digits of Longitude are for Degrees. Degrees must be a 1 to 2 digit number between 0 and 180."));
            } else if (!minuteRegex.test(matches[2]) || parseInt(matches[2]) > 59) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The second set of digits of Longitude are for Minutes. Minutes must be a 1 or 2 digit number between 0 and 59."));
            } else if (!secondsRegex.test(matches[3]) || parseFloat(matches[3]) > 59.999) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The third set of digits of Longitude are for Seconds. Seconds can only have up to 3 decimal places, and must be between 0 and 59.999."));
            } else if (!longitudeHemisphereRegex.test(matches[4])) {
                result.isValid = false;
                result.add("locLat", LOCALE.maketext("The last character of Longitude is the hemisphere, which can only be E or W."));
            }

            return result;
        }

    };

    var validatorModule = angular.module("cjt2.validate");
    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(validators);
        }
    ]);

    return {
        methods: validators,
        name: "locValidators",
        description: "Validation library for LOC records.",
        version: 2.0,
    };
});
