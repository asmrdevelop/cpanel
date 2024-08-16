/*
# whostmgr/docroot/templates/license_purchase/views/checkoutController.js     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* global PAGE: false */

define(
    [
        "lodash",
        "angular",
        "cjt/util/locale",
        "cjt/util/query",
        "cjt/modules",
        "cjt/decorators/growlDecorator",
    ],
    function(_, angular, LOCALE, QUERY) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        // Setup the controller
        var controller = app.controller(
            "checkoutController", [
                "$scope",
                "$location",
                "$routeParams",
                "$window",
                "$timeout",
                "growl",
                "storeService",
                function($scope, $location, $routeParams, $window, $timeout, growl, storeService) {

                    var steps = [ "login", "generateOrder", "checkout", "installLicense", "licenseActivated" ];

                    var currentStepIndex = steps.indexOf($routeParams.nextStep) === -1 ? 0 : steps.indexOf($routeParams.nextStep);

                    // If during upgrade path from solo license.
                    var isUpgrade = false;

                    isUpgrade = $routeParams["everythingelse"] === "upgrade" || QUERY.parse_query_string(location.search.replace(/^\?/, ""))["upgrade"] === "1";

                    /**
                    * Gets the return URL
                    *
                    * @method getReturnURL
                    * @param {String} stepID for the step
                    */
                    var getReturnURL = function(stepID) {
                        var pageURL = PAGE.pageURL ? PAGE.pageURL : $location.absUrl();

                        // Because of <base> existing now, this needs to utilize the baseURL
                        var returnURL = PAGE.baseURL + pageURL + "/" + stepID;

                        if (isUpgrade) {
                            returnURL += "/upgrade";
                        }

                        return returnURL;
                    };

                    /**
                    * Redirect to WHM home page
                    *
                    * @method redirectToHomePage
                    */
                    var redirectToHomePage = function(timeoutInterval) {
                        var interval = timeoutInterval || 20000;

                        $timeout(function() {
                            $window.location.href = PAGE.baseURL;
                        }, interval);
                    };

                    /**
                    * Redirect to the store login
                    *
                    * @method storeLoginRedirect
                    */
                    var storeLoginRedirect = function() {
                        var returnURL = getReturnURL(steps[currentStepIndex + 1]);
                        return storeService.getLoginURL(returnURL).then(function(results) {
                            if ( results.data && results.data.length ) {
                                $window.location.href = results.data[0];
                            }
                        }, function(error) {
                            growl.error(LOCALE.maketext("The system encountered an error when it accessed the cPanel Store login [output,acronym,URL,Uniform Resource Locator]: [_1]", error) + " " + LOCALE.maketext("Redirecting to the [output,acronym,WHM,WebHost Manager] interface …"), { ttl: 20000, disableCountDown: false });
                            redirectToHomePage();
                        });
                    };

                    /**
                    * Executes the code based on nextStep URL parameter
                    *
                    * @method executeStep
                    */
                    var executeStep = function() {

                        // implies its a fresh start
                        if (!$routeParams.nextStep) {
                            storeLoginRedirect();
                            return;
                        }

                        // Verify Login, Get Access Token and Generate Order
                        if ($location.search().code && $routeParams.nextStep === "generateOrder") {

                            // Retaining the same return URL
                            var stepIndex = steps.indexOf($routeParams.nextStep);
                            var returnURI = getReturnURL(steps[stepIndex]);

                            return storeService.validateLoginToken($location.search().code, returnURI).then(function(results) {
                                if ( results.data && results.data.length ) {

                                    // Access Token to generate order
                                    var accessToken = results.data[0].access_token;
                                    if (accessToken) {

                                        // Return URI for checkout
                                        returnURI = getReturnURL(steps[currentStepIndex + 2]);

                                        storeService.generateLicenseOrder(accessToken, returnURI, isUpgrade).then(function(results) {
                                            if (results.data && results.data.length) {
                                                currentStepIndex = currentStepIndex + 1;

                                                if ( results.data[0] ) {
                                                    $window.location.href = results.data[0];
                                                } else {
                                                    growl.error(LOCALE.maketext("The system encountered an error when it generated your license order.") + " " + LOCALE.maketext("Redirecting to the [output,acronym,WHM,WebHost Manager] interface …"), { ttl: 20000, disableCountDown: false });
                                                    redirectToHomePage();
                                                }

                                            }
                                        }, function(error) {
                                            growl.error(LOCALE.maketext("The system encountered an error when it generated your license order.") + "<br />" + LOCALE.maketext("Error: “[_1]”", error) + "<br />" + LOCALE.maketext("Redirecting to the [output,acronym,WHM,WebHost Manager] interface …"), { ttl: 20000, disableCountDown: false });
                                            redirectToHomePage();
                                        });
                                    } else {
                                        growl.error(LOCALE.maketext("The system encountered a token validation error.") + " " + LOCALE.maketext("Redirecting to the [output,acronym,WHM,WebHost Manager] interface …"), { ttl: 20000, disableCountDown: false });
                                        redirectToHomePage();
                                    }
                                }
                            }, function(error) {
                                growl.error(LOCALE.maketext("The system encountered a token validation error.") + "<br />" + LOCALE.maketext("Error: “[_1]”", error) + "<br />" + LOCALE.maketext("Redirecting to the [output,acronym,WHM,WebHost Manager] interface …"), { ttl: 20000, disableCountDown: false });
                                redirectToHomePage();
                            });
                        }

                        if ($routeParams.nextStep === "installLicense" && $location.search().order_status) {
                            if ($location.search().order_status === "success") {
                                currentStepIndex = currentStepIndex + 1;
                                return storeService.updateLicense().then(function() {
                                    currentStepIndex = currentStepIndex + 1;

                                    growl.success(LOCALE.maketext("The system successfully updated the license.") + " " + LOCALE.maketext("Redirecting to the [output,acronym,WHM,WebHost Manager] interface …"), { ttl: 5000, disableCountDown: false });
                                    redirectToHomePage(5000);

                                }, function(error) {
                                    growl.error(LOCALE.maketext("The system encountered an error when it updated your license.") + "<br />" + LOCALE.maketext("Error: “[_1]”", error) + "<br />" + LOCALE.maketext("Redirecting to the [output,acronym,WHM,WebHost Manager] interface …"), { ttl: 20000, disableCountDown: false });

                                    redirectToHomePage();
                                });
                            } else if ($location.search().order_status === "cancelled") {
                                growl.error(LOCALE.maketext("The system successfully canceled the order.") + " " + LOCALE.maketext("Redirecting to the [output,acronym,WHM,WebHost Manager] interface …"), { ttl: 20000, disableCountDown: false });
                                redirectToHomePage();
                            } else if ($location.search().order_status === "error") {
                                growl.error(LOCALE.maketext("The system encountered an error.") + LOCALE.maketext("Redirecting to the [output,acronym,WHM,WebHost Manager] interface …"), { ttl: 20000, disableCountDown: false });
                                redirectToHomePage();
                            }
                        }
                    };

                    /**
                    * Gets the correct class for the step
                    *
                    * @method getStepClass
                    * @param {String} Class for the step
                    */
                    $scope.getStepClass = function(step) {
                        var stepIndex = steps.indexOf(step);
                        if (stepIndex !== -1) {
                            if (currentStepIndex > stepIndex) {
                                return "checkout-step-completed";
                            } else if (currentStepIndex === stepIndex) {
                                return "checkout-step-current";
                            }
                        }
                    };

                    // on load execute the appropriate step based on currentStep in URL
                    executeStep();
                }
            ]
        );

        return controller;
    }
);
