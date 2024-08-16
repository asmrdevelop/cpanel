/*
# cjt/directives/focusFirstErrorDirective.js      Copyright(c) 2020 cPanel, L.L.C.
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
 * @module cjt/directives/focusFirstErrorDirective
 * @example
 * <form name="form" focus-first-error>
 *     <input name="foo" required>
 *     <input name="bar" required>
 *     <input name="bas" required>
 * </form>
 */
define(["angular"], function(angular) {

    var module = angular.module("cjt2.directives.focusFirstError", []);

    module.directive("focusFirstError", function() {
        return {
            retrict: "A",
            link: function(scope, elem) {
                if (elem[0].tagName === "FORM") {

                    // set up event handler on the form element
                    elem.on("submit", function() {

                        // find the first invalid element
                        var candidates = angular.element(elem[0].querySelector(".ng-invalid"));
                        if (candidates && candidates.length > 0) {
                            candidates[0].focus();
                        }
                    });
                } else {
                    throw "The focusFirstError directive can only be used on a FORM element.";
                }
            }
        };
    });
});
