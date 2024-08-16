/*
# convert_addon_to_account/directives/db_name_validators.js  Copyright(c) 2020 cPanel, L.L.C.
#                                                                      All rights reserved.
# copyright@cpanel.net                                                    http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* global define: false, CPANEL: false */
/* --------------------------*/

define([
    "angular",
    "cjt/validator/validator-utils",
    "cjt/util/locale",
    "cjt/validator/validateDirectiveFactory",
    "app/services/Databases"
],
function(angular, validationUtils, LOCALE, validateFactory, Databases) {
    var validators = {

        /**
             * Validate a MySQL Database Name
             * NOTE: This method depends on the old cjt/sql.js file being loaded
             *
             * @method mysqlDbName
             * @param {string} val - the value to be validated
             * @return a validation result object
             */
        mysqlDbName: function(val) {
            var result = validationUtils.initializeValidationResult();

            try {
                CPANEL.sql.verify_mysql_database_name(val);
                result.isValid = true;
            } catch (error) {
                result.isValid = false;
                result.add("db", error);
            }

            return result;
        },

        /**
             * Validate a Postgres Database Name
             * NOTE: This method depends on the old cjt/sql.js file being loaded
             *
             * @method postrgresDbName
             * @param {string} val - the value to be validated
             * @return a validation result object
             */
        postgresqlDbName: function(val) {
            var result = validationUtils.initializeValidationResult();

            try {
                CPANEL.sql.verify_postgresql_database_name(val);
                result.isValid = true;
            } catch (error) {
                result.isValid = false;
                result.add("db", error);
            }

            return result;
        }
    };

    var validatorModule = angular.module("cjt2.validate");

    validatorModule.run(["validatorFactory", "Databases",
        function(validatorFactory, Databases) {
            validatorFactory.generate(validators);
        }
    ]);

    return {
        methods: validators,
        name: "dbNameValidators",
        description: "Validation directives for db names.",
        version: 11.56,
    };
}
);
