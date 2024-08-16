/*
# templates/yumupdate/views/landing.js                    Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "jquery",
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "app/services/yumAPI",
        "cjt/directives/actionButtonDirective"
    ],
    function(angular, $, LOCALE, PARSE) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("ModalInstanceCtrl",
            ["$scope", "$uibModalInstance",
                function($scope, $uibModalInstance) {
                    $scope.closeModal = function() {
                        $uibModalInstance.close();
                    };

                    $scope.runIt = function() {
                        $uibModalInstance.close(true);
                    };
                }]);

        app.controller("landing",
            ["$scope", "$rootScope", "$location", "$anchorScroll", "$routeParams", "$q", "spinnerAPI", "alertService", "YumAPI", "$uibModal",
                function($scope, $rootScope, $location, $anchorScroll, $routeParams, $q, spinnerAPI, alertService, YumAPI, $uibModal) {

                    $scope.update = function() {
                        var $uibModalInstance = $uibModal.open({
                            templateUrl: "updateModalContent.tmpl",
                            controller: "ModalInstanceCtrl"
                        });

                        $uibModalInstance.result.then(function(proceed) {
                            if (proceed) {
                                $scope.runUpdate();
                            }
                        });
                    };

                    $scope.runUpdate = function() {
                        $scope.realTimeLog = "";
                        $scope.realTimeLogDisplay = "";
                        spinnerAPI.start("runningSpinner");
                        $scope.running = true;
                        YumAPI.run_update($scope.kernel).then(function(data) {
                            $scope.buildID = data.build;
                            $scope.currentTailingPosition = 0;
                            $scope.errorDetected = false;
                            $scope.tailing();
                        });
                    };

                    $scope.tailing = function() {
                        YumAPI.tailing_log($scope.buildID, $scope.currentTailingPosition).then(function(data) {
                            for (var i = 0; i < data.content.length; i++) {

                                // Ignore the beginning and ending lines of log, replace them with more meaningful words
                                if (data.content[i] === "-- " + $scope.buildID + " --") {
                                    $scope.realTimeLog += LOCALE.maketext("System update process has started.") + "\r\n";
                                    $scope.realTimeLogDisplay += "<span class='text-success'><strong>" + LOCALE.maketext("System update process has started.") + "</strong></span>\r\n";
                                    continue;
                                }
                                if (data.content[i] === "-- /" + $scope.buildID + " --") {
                                    $scope.realTimeLog += LOCALE.maketext("System update process has finished.") + "\r\n";
                                    $scope.realTimeLogDisplay += "<span class='text-success'><strong>" + LOCALE.maketext("System update process has finished.") + "</strong></span>\r\n";
                                    continue;
                                }

                                $scope.realTimeLog += data.content[i] + "\r\n";
                                if (/Error:.*/gm.test(data.content[i])) {
                                    data.content[i] = "<span class='text-danger'>" + data.content[i] + "</span>";
                                    $scope.errorDetected = true;
                                }

                                data.content[i] = data.content[i].replace(/&/gm, "&amp;").replace(/</gm, "&lt;").replace(/>/gm, "&gt;").replace(/'/gm, "&#39;").replace(/"/gm, "&quot;");

                                // Detect error messages
                                if (data.content[i] === "-- error(" + $scope.buildID + ") --") {
                                    $scope.inErrorMode = true;
                                    $scope.errorDetected = true;
                                    continue;
                                }
                                if (data.content[i] === "-- /error(" + $scope.buildID + ") --") {
                                    $scope.inErrorMode = false;
                                    continue;
                                }
                                if ($scope.inErrorMode) {
                                    data.content[i] = "<span class='text-danger'>" + data.content[i] + "</span>";
                                }

                                $scope.realTimeLogDisplay += data.content[i] + "\r\n";
                            }

                            // Because of the $scope digest, putting 100 ms delay on auto scrolling
                            window.setTimeout(function() {
                                $anchorScroll();
                            }, 100);
                            $scope.currentTailingPosition = data.offset;
                            if (data.still_running) {
                                window.setTimeout($scope.tailing(), 100);
                            } else {
                                spinnerAPI.stop("runningSpinner");
                                $scope.finished = true;
                                $scope.running = false;
                            }
                        });
                    };

                    $scope.saveLog = function() {

                        // grab the content of the form field and place it into a variable
                        var textToWrite = $scope.realTimeLog;
                        var textFileAsBlob = new Blob([textToWrite], { type: "text/plain" });
                        var fileNameToSaveAs = "log.txt";
                        var downloadLink = document.createElement("a");
                        downloadLink.download = fileNameToSaveAs;
                        downloadLink.innerHTML = "My Hidden Link";

                        window.URL = window.URL || window.webkitURL;

                        downloadLink.href = window.URL.createObjectURL(textFileAsBlob);
                        downloadLink.target = "_blank";
                        downloadLink.onclick = destroyClickedElement;
                        downloadLink.style.display = "none";
                        document.body.appendChild(downloadLink);

                        downloadLink.click();

                    };

                    $scope.init = function() {
                        var hash = $location.hash();
                        if (hash !== "bottom") {
                            $location.hash("bottom");
                        }
                        $scope.kernel = true;
                    };

                    $scope.init();

                    function destroyClickedElement(event) {

                        // remove the link from the DOM
                        document.body.removeChild(event.target);
                    }
                }]);
    }
);
