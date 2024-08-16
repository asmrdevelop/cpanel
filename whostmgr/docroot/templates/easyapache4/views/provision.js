/*
# templates/easyapache4/views/provision.js                   Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "app/services/ea4Data",
        "app/services/ea4Util"
    ],
    function(angular, LOCALE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("provision",
            [ "$scope", "$location", "ea4Data", "spinnerAPI",
                function($scope, $location, ea4Data, spinnerAPI) {
                    var realTimeLog = "";

                    // REFACTOR: One-way binding eligible.
                    $scope.realTimeLogDisplay = "";
                    var errorDetected = false;

                    var startTailing = function() {
                        ea4Data.tailingLog($scope.buildID, $scope.currentTailingPosition)
                            .then(function(data) {

                                // $scope.inErrorMode = false;
                                var inErrorMode = false;
                                for (var i = 0, content = data.content; i < content.length; i++) {

                                    // Ignore the beginning and ending lines of log, replace them with more meaningful words
                                    if (content[i] === "-- " + $scope.buildID + " --") {
                                        var startText = LOCALE.maketext("Provision process started.");
                                        realTimeLog += startText + "\r\n";
                                        $scope.realTimeLogDisplay += "<span class='text-success'><strong>" + startText + "</strong></span>\r\n";
                                        continue;
                                    }
                                    if (content[i] === "-- /" + $scope.buildID + " --") {
                                        var endText = LOCALE.maketext("Provision process finished.");
                                        realTimeLog += endText + "\r\n";
                                        $scope.realTimeLogDisplay += "<span class='text-success'><strong>" + endText + "</strong></span>\r\n";
                                        continue;
                                    }

                                    realTimeLog += content[i] + "\r\n";
                                    content[i] = content[i].replace(/&/gm, "&amp;").replace(/</gm, "&lt;").replace(/>/gm, "&gt;").replace(/'/gm, "&#39;").replace(/"/gm, "&quot;");

                                    // Detect error messages
                                    if (content[i] === "-- error(" + $scope.buildID + ") --") {
                                        inErrorMode = true;
                                        errorDetected = true;
                                        continue;
                                    }
                                    if (content[i] === "-- /error(" + $scope.buildID + ") --") {
                                        inErrorMode = false;
                                        continue;
                                    }
                                    if (inErrorMode) {
                                        content[i] = "<span class='text-danger'>" + content[i] + "</span>";
                                    }

                                    if (/Error:.*/gm.test(content[i])) {
                                        content[i] = "<span class='text-danger'>" + content[i] + "</span>";
                                        errorDetected = true;
                                    }

                                    $scope.realTimeLogDisplay += content[i] + "\r\n";
                                }

                                // Because of the $scope digest, putting 100 ms delay on auto scrolling
                                // the output window
                                // TODO: Split this out into a directive to avoid touching the DOM directly
                                window.setTimeout(function() {
                                    var log = document.getElementById("log");
                                    if (log) {
                                        log.scrollTop = log.scrollHeight;
                                    }
                                }, 100);

                                $scope.currentTailingPosition = data.offset;
                                if (data.still_running) {
                                    window.setTimeout(startTailing(), 100);
                                } else {
                                    spinnerAPI.stop("provisionSpinner");
                                    $scope.finished = true;
                                    ea4Data.provisionReady(false);
                                }
                            });
                    };

                    var startProvision = function(provisionActions) {
                        spinnerAPI.start("provisionSpinner");
                        $scope.provisionStarted = true;
                        errorDetected = false;
                        ea4Data.doProvision(provisionActions.install,
                            provisionActions.uninstall,
                            provisionActions.upgrade,
                            provisionActions.profileId)
                            .then(function(data) {

                                // TODO: see if this shud be in scope
                                $scope.buildID = data.build;

                                // TODO: see if this shud be in scope
                                $scope.currentTailingPosition = 0;
                                startTailing();
                            }).finally(function() {

                                // every time we provision we are getting updates
                                // so we reset the update button state
                                $scope.customize.checkUpdateInfo.pkgNumber = 0;
                                $scope.customize.toggleUpdateButton();

                                ea4Data.clearEA4LocalStorageItems();
                                app.firstLoad = false;
                                ea4Data.php_set_session_save_path();
                            });
                    };

                    $scope.$on("$viewContentLoaded", function() {

                        // Reset wizard attributes.
                        $scope.customize.wizard.currentStep = "";
                        $scope.customize.wizard.showWizard = false;
                        var provisionActions = ea4Data.getData("provisionActions");
                        if (!ea4Data.provisionReady() ||
                        (typeof provisionActions === "undefined")) {
                            ea4Data.cancelOperation();
                        }

                        // REFACTOR: THIS part needs to be re-visited when working
                        // on using latest tail log method.
                        var hash = $location.hash();
                        if (hash === "bottom") {
                            startProvision(provisionActions);
                        } else {
                            $location.hash("bottom");
                        }
                    });

                    $scope.cancel = function() {
                        ea4Data.cancelOperation();
                    };

                    $scope.resultReady = function() {
                        var result = null;
                        if (!errorDetected) {
                            result = "alert-success";
                            $scope.resultSummary = LOCALE.maketext("The provision process is complete.");
                        } else {
                            result = "alert-danger";
                            $scope.resultSummary = LOCALE.maketext("The provision process exited with errors. Please check the log for details.");
                        }
                        return result;
                    };

                    var destroyClickedElement = function(event) {

                        // remove the link from the DOM
                        document.body.removeChild(event.target);
                    };

                    // REFACTOR: Need to be re-written.
                    $scope.saveLog = function() {

                        // grab the content of the form field and place it into a variable
                        var textToWrite = realTimeLog;
                        var textFileAsBlob = new Blob([textToWrite], { type: "text/plain" });
                        var fileNameToSaveAs = "log.txt";
                        var downloadLink = document.createElement("a");
                        downloadLink.download = fileNameToSaveAs;
                        downloadLink.innerHTML = "My Hidden Link";

                        window.URL = window.URL || window.webkitURL;

                        downloadLink.href = window.URL.createObjectURL(textFileAsBlob);
                        downloadLink.onclick = destroyClickedElement;
                        downloadLink.style.display = "none";
                        document.body.appendChild(downloadLink);

                        downloadLink.click();

                    };
                }
            ]
        );
    }
);
