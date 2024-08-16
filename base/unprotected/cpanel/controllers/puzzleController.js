/**
 * base/unprotected/controllers/puzzleController.js   Copyright(c) 2020 cPanel, L.L.C.
 *                                                              All rights reserved.
 * copyright@cpanel.net                                            http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited.
 */

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/validator/email-validator",
        "cjt/directives/validationItemDirective",
        "cjt/directives/validationContainerDirective"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "puzzleController", [
                function() {
                    var vm = this;

                    vm.focus = function() {
                        vm.isFocused = true;
                        var inputElem = document.getElementById("puzzle-guess-input");
                        inputElem.focus();
                    };

                    vm.blur = function () {
                        vm.isFocused = false;
                    };

                    return vm;
                }
            ]
        );

        return controller;
    }
);
