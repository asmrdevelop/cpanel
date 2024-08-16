define(
    [
        "lodash",
        "angular",
        "cjt/validator/validator-utils",
        "app/services/parser",
        "cjt/validator/validateDirectiveFactory",
    ],
    function domainListValidator(_, angular, validationUtils, PARSER) {
        "use strict";

        var methods = {
            domainList: function domainList(input) {
                var result = validationUtils.initializeValidationResult();

                try {
                    PARSER.parseDomainsFromText(input);
                } catch (e) {
                    var errorHTMLs = e.map( function(o) {
                        return ( "<span class='code'>" + _.escape(o[0]) + "</span>: " + _.escape(o[1]) );
                    } );

                    var errorHTML;

                    if (errorHTMLs.length === 1) {
                        errorHTML = errorHTMLs[0];
                    } else {
                        errorHTML = "<ul><li>";
                        errorHTML += errorHTMLs.join("</li><li>");
                        errorHTML += "</li></ul>";
                    }

                    result.addError("domainList", errorHTML);
                }

                return result;
            },
        };

        var validatorModule = angular.module("cjt2.validate");

        validatorModule.run(["validatorFactory", function(validatorFactory) {
            validatorFactory.generate(methods);
        } ] );

        return {
            methods: methods,
            name: "domain-list",
            description: "Validate a list of domains, allowing wildcard.",
            version: 1.0,
        };
    }
);
