/*
# templates/greylist/views/base.js                    Copyright 2022 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, CPANEL, PAGE */
/* jshint -W100 */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/actionButtonDirective",
        "cjt/decorators/growlDecorator",
        "cjt/services/whm/nvDataService",
        "app/services/GreylistDataSource",
    ],
    function(angular, $, _, LOCALE, PARSE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "baseController",
            [
                "$scope",
                "$rootScope",
                "$q",
                "$uibModal",
                "GreylistDataSource",
                "growl",
                "growlMessages",
                "nvDataService",
                "PAGE",
                function(
                    $scope,
                    $rootScope,
                    $q,
                    $uibModal,
                    GreylistDataSource,
                    growl,
                    growlMessages,
                    nvDataService,
                    PAGE) {

                    $scope.greylistEnabled = GreylistDataSource.configSettings.is_enabled;

                    $scope.knobLabel = "\u00a0";

                    $scope.changing_status = false;
                    $scope.status_check_in_progress = false;

                    $scope.isNetblockTrusted = false;

                    var eximWarning = null;
                    $scope.trustNeighborsMessage = null;
                    var dismissModalInstance = null;
                    var maxNumberOfTimesToDisplayMessage = 1;
                    var trustNeighborsCount = 0;
                    var hideTrustNeighborsMessage;

                    var globallyClosingGrowls = false;

                    $scope.handle_keydown = function(event) {

                        // prevent the spacebar from scrolling the window
                        if (event.keyCode === 32) {
                            event.preventDefault();
                        }
                    };

                    $scope.handle_keyup = function(event) {

                        // bind to the spacebar and enter keys
                        if (event.keyCode === 32 || event.keyCode === 13) {
                            event.preventDefault();
                            $scope.toggle_status();
                        }
                    };

                    $scope.areWeDestroyingAllGrowls = function() {
                        return globallyClosingGrowls;
                    };

                    $scope.destroyAllGrowls = function() {
                        var deferred = $q.defer();

                        globallyClosingGrowls = true;
                        growlMessages.destroyAllMessages();
                        deferred.resolve(null);

                        return deferred.promise;
                    };

                    $scope.toggle_status = function() {
                        if ($scope.changing_status) {
                            return;
                        }

                        $scope.changing_status = true;

                        if ($scope.greylistEnabled) {
                            $scope.destroyAllGrowls()
                                .then(function() {
                                    globallyClosingGrowls = false;
                                });
                            GreylistDataSource.disable()
                                .then( function() {
                                    $scope.greylistEnabled = false;
                                    growl.success(LOCALE.maketext("[asis,Greylisting] is now disabled."));
                                }, function(error) {
                                    growl.error(error);
                                })
                                .finally( function() {
                                    $scope.changing_status = false;
                                });
                        } else {
                            GreylistDataSource.enable()
                                .then( function() {
                                    $scope.greylistEnabled = true;
                                    growl.success(LOCALE.maketext("[asis,Greylisting] is now enabled."));
                                }, function(error) {
                                    growl.error(error);
                                })
                                .finally( function() {
                                    $scope.changing_status = false;
                                });
                        }
                    };

                    $scope.growlEximWarning = function() {

                        // create a new growl to be displayed.
                        var messageCache = LOCALE.maketext("[asis,Exim] is disabled on the server which makes [asis,Greylisting] ineffective. Use the [output,url,_1,Service Manager page,_2] to enable [asis,Exim].",
                            PAGE.security_token + "/scripts/srvmng",
                            { "target": "_blank" });
                        eximWarning = growl.warning(messageCache,
                            {
                                onclose: function() {
                                    eximWarning = null;
                                }
                            }
                        );
                    };

                    $scope.get_status = function() {
                        if ($scope.status_check_in_progress) {
                            return;
                        }
                        $scope.status_check_in_progress = true;
                        return GreylistDataSource.status()
                            .then( function(results) {
                                if (!results.is_exim_enabled && !eximWarning) {
                                    $scope.growlEximWarning();
                                } else if (results.is_exim_enabled && eximWarning) {
                                    eximWarning.destroy();
                                    eximWarning = null;
                                }

                                if (results.is_enabled !== $scope.greylistEnabled) {

                                    // this test needs to run only if status has changed
                                    if (!results.is_enabled) {
                                        $scope.destroyAllGrowls()
                                            .then(function() {
                                                globallyClosingGrowls = false;
                                            });
                                    }
                                    growl.warning(LOCALE.maketext("The status for [asis,Greylisting] has changed, possibly in another browser session."));
                                }
                                $scope.greylistEnabled = results.is_enabled;
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.status_check_in_progress = false;
                            });
                    };


                    $scope.checkDismissNotice = function() {

                        // if we are already hiding the message
                        // we don't need to display it
                        if (hideTrustNeighborsMessage) {
                            return;
                        }

                        // if we are dismissing the message globally, then don't count it
                        if ($scope.areWeDestroyingAllGrowls()) {
                            return;
                        }

                        // if we are at the max and the netblock is not trusted
                        if ((trustNeighborsCount >= maxNumberOfTimesToDisplayMessage) &&
                            (!$scope.isNetblockTrusted) &&
                            (dismissModalInstance === null)) {

                            // then we should see if they want to dismiss the notice
                            dismissModalInstance = $uibModal.open({
                                templateUrl: "modal/dismissNetblockGrowl.html",
                                scope: $scope,
                            });
                        }
                    };

                    $scope.hideNetblockGrowlPermanently = function() {
                        dismissModalInstance.close();
                        dismissModalInstance = null;
                        hideTrustNeighborsMessage = true;

                        // just set it and don't check the return for now
                        nvDataService.set("whm_greylist_hide_netblock_prompt", 1);
                    };

                    $scope.cancelHideNetblockNotice = function() {
                        dismissModalInstance.dismiss();
                        dismissModalInstance = null;
                        hideTrustNeighborsMessage = false;
                    };


                    $scope.growlTrustMyNeighbors = function(ips, isTrusted) {

                        // check this first since it comes from NVData
                        // and the user's personal preference
                        if (hideTrustNeighborsMessage) {
                            return;
                        }

                        $scope.isNetblockTrusted = isTrusted;
                        if (isTrusted) {
                            return;
                        }

                        trustNeighborsCount++;
                        if ($scope.trustNeighborsMessage === null) {
                            var messageCache = LOCALE.maketext("Your neighboring [asis,IP] addresses are not in the Trusted Hosts list.");
                            $scope.trustNeighborsMessage = growl.info(messageCache,
                                {
                                    variables: {
                                        buttonLabel: LOCALE.maketext("Add to Trusted Hosts"),
                                        showAction: true,
                                        action: function() {
                                            $scope.addTrustedHost(ips, "The server's neighboring IP addresses")
                                                .then(function() {

                                                    // send an event to update the trusted hosts list
                                                    $scope.isNetblockTrusted = true;
                                                    $rootScope.$emit("TrustedHosts.UPDATE_LIST");
                                                    $scope.trustNeighborsMessage.destroy();
                                                });
                                        }
                                    },
                                    onclose: function() {
                                        $scope.checkDismissNotice();
                                        $scope.trustNeighborsMessage = null;
                                    }
                                }
                            );
                        }
                    };

                    $scope.addTrustedHost = function(ips, comment) {
                        if (!ips) {
                            return;
                        }

                        // normalize our data
                        if (!Array.isArray(ips)) {
                            ips = [ips];
                        }

                        return GreylistDataSource.addTrustedHosts(ips, comment)
                            .then( function(results) {
                                if (results.added.length === 1) {
                                    growl.success(LOCALE.maketext("You have successfully added “[_1]” to the Trusted Hosts list.",
                                        _.escape(results.added[0])));
                                } else if (results.added.length > 1) {
                                    growl.success(LOCALE.maketext("You have successfully added [quant,_1,record,records] to the Trusted Hosts list.",
                                        results.added.length));
                                }

                                for (var i = 0; i < results.updated.length; i++) {
                                    growl.success(LOCALE.maketext("You have successfully updated the comment for “[_1]”.", _.escape(results.updated[i])));
                                }

                                var rejectedIPs = Object.keys(results.rejected);
                                if (rejectedIPs.length > 0) {
                                    var accumulatedMessages = LOCALE.maketext("Some Host [asis,IP] addresses were not added to the Trusted Hosts list.");
                                    accumulatedMessages += "<br>";

                                    $scope.newTrustedHosts = rejectedIPs.join("\n");
                                    for (var ix = 0; ix < rejectedIPs.length; ix++) {
                                        if (results.rejected[rejectedIPs[ix]]) {
                                            accumulatedMessages += "<br>" + _.escape(results.rejected[rejectedIPs[ix]]);
                                        }
                                    }
                                    growl.error(accumulatedMessages);
                                }

                                return {
                                    status: true,
                                    rejected: rejectedIPs
                                };
                            }, function(errorDetails) {
                                var combinedMessage = errorDetails.main_message;
                                var secondaryCount = errorDetails.secondary_messages.length;
                                for (var z = 0; z < secondaryCount; z++) {
                                    if (z === 0) {
                                        combinedMessage += "<br>";
                                    }
                                    combinedMessage += "<br>";
                                    combinedMessage += errorDetails.secondary_messages[z];
                                }
                                growl.error(combinedMessage);
                                return {
                                    status: false
                                };
                            });
                    };

                    $scope.init = function() {

                        $(document).ready(function() {
                            if (!GreylistDataSource.configSettings.is_exim_enabled) {
                                $scope.growlEximWarning();
                            }

                            // get the nvdata we need
                            nvDataService.getObject("whm_greylist_hide_netblock_prompt")
                                .then(function(result) {
                                    if ("whm_greylist_hide_netblock_prompt" in result) {
                                        hideTrustNeighborsMessage = PARSE.parsePerlBoolean(result["whm_greylist_hide_netblock_prompt"]);
                                    }
                                });

                            // for window and tab changes
                            $(window).on("focus", function() {
                                $scope.get_status();
                            });
                        });
                    };

                    $scope.init();
                }
            ]
        );

        return controller;
    }
);
