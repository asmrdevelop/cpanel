/*
 * templates/multiphp_ini_editor/views/basicMode.js Copyright(c) 2020 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */
/* global ace: false */

define(
    [
        "angular",
        "lodash",
        "jquery",
        "cjt/util/locale",
        "ace",
        "uiBootstrap",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "cjt/decorators/growlDecorator",
        "app/services/configService"
    ],
    function(angular, _, $, LOCALE) {

        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "editorMode",
            ["$scope", "$location", "$routeParams", "$timeout", "spinnerAPI", "alertService", "growl", "growlMessages", "configService", "PAGE",
                function($scope, $location, $routeParams, $timeout, spinnerAPI, alertService, growl, growlMessages, configService, PAGE) {
                    var alreadyInformed = false;
                    var infoGrowlHandle;
                    $scope.processingEditor = false;
                    $scope.showEmptyMessage = false;
                    $scope.contentIsEmpty = true;
                    $scope.txtInFirstOption = LOCALE.maketext("[comment,used for highlight in select option]-- Not Available --[comment,used for highlight in select option]");
                    var editor;

                    $scope.loadContent = function() {
                        if ($scope.selectedVersion) {

                            // Destroy all growls before attempting to submit something.
                            growlMessages.destroyAllMessages();

                            spinnerAPI.start("loadingSpinner");
                            var version = $scope.selectedVersion;
                            alreadyInformed = false;
                            editorInProcess(true);
                            return configService
                                .fetchContent(version)
                                .then(function(content) {
                                    if (content !== "") {
                                        $scope.contentIsEmpty = false;

                                        // Using jquery way of decoding the html content.
                                        // Tried to use '_' version of unescape method but it
                                        // did not decode encoded version of apostrophe (')
                                        // where the code is &#39;
                                        var htmlContent = $("<div/>").html(content).text();

                                        // Create Ace editor object if it's not yet created.
                                        if (typeof (editor) === "undefined") {
                                            editor = ace.edit("editor");

                                            // The below line is added to disable a
                                            // warning message as required by ace editor
                                            // script.
                                            editor.$blockScrolling = Infinity;
                                            editor.setShowPrintMargin(false);
                                        }

                                        // Bring the text area into focus and scroll to
                                        // the top of the INI document if a new one is loaded.
                                        editor.focus();
                                        editor.scrollToRow(0);

                                        // Set the editor color theme.
                                        editor.setTheme("ace/theme/chrome");

                                        var editSession = ace.createEditSession(htmlContent);
                                        editor.setSession(editSession);
                                        if (typeof (editSession) !== "undefined") {
                                            editSession.setMode("ace/mode/ini");
                                            editor.on("change", $scope.informUser);
                                        }
                                    } else {
                                        $scope.contentIsEmpty = true;
                                    }
                                }, function(error) {

                                    // failure
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        id: "errorFetchDirectiveList"
                                    });
                                })
                                .then(function() {
                                    editorInProcess(false);
                                })
                                .finally(function() {
                                    spinnerAPI.stop("loadingSpinner");
                                    $scope.showEmptyMessage = !$scope.processingEditor && $scope.selectedVersion !== "" && $scope.contentIsEmpty;
                                });
                        } else {
                            resetForm();
                        }
                    };

                    $scope.informUser = function() {
                        if (!alreadyInformed) {
                            alreadyInformed = true;
                            growl.info(LOCALE.maketext("You must click “[_1]” to apply the new changes.", LOCALE.maketext("Save")),
                                {
                                    onopen: function() {
                                        infoGrowlHandle = this;
                                    }
                                }
                            );
                        }
                    };

                    $scope.save = function() {

                        // Destroy all growls before attempting to submit something.
                        growlMessages.destroyAllMessages();
                        alreadyInformed = false;
                        if ( typeof infoGrowlHandle !== "undefined" ) {
                            infoGrowlHandle.destroy();
                        }
                        editorInProcess(true);
                        var changedContent = _.escape(editor.getSession().getValue());

                        return configService.saveIniContent($scope.selectedVersion, changedContent)
                            .then(
                                function(data) {
                                    if (typeof (data) !== "undefined") {
                                        growl.success(LOCALE.maketext("Successfully saved the changes."));
                                    }
                                }, function(error) {

                                    // escape the error text to prevent XSS attacks.
                                    growl.error(_.escape(error));
                                })
                            .then(function() {
                                editorInProcess(false);
                            });
                    };

                    var editorInProcess = function(processing) {
                        if (typeof (editor) !== "undefined") {
                            editor.setReadOnly(processing);
                        }

                        $scope.processingEditor = processing;
                    };

                    var resetForm = function() {
                        $scope.showEmptyMessage = false;
                        $scope.contentIsEmpty = true;
                    };

                    var setDomainPhpDropdown = function(versionList) {

                        // versionList is sent to the function when the
                        // dropdown is bound the first time.
                        if (typeof (versionList) !== "undefined") {
                            $scope.phpVersions = versionList;
                        }

                        if ($scope.phpVersions.length > 0) {
                            $scope.phpVersionsEmpty = false;
                            $scope.txtInFirstOption = LOCALE.maketext("[comment,used for highlight in select option]-- Select a [asis,PHP] version --[comment,used for highlight in select option]");
                        } else {
                            $scope.phpVersionsEmpty = true;
                        }
                    };

                    $scope.$on("$viewContentLoaded", function() {

                        // Destroy all growls before attempting to submit something.
                        growlMessages.destroyAllMessages();

                        var versionListData = PAGE.php_versions;
                        var versionList = [];
                        if (versionListData.metadata.result) {

                            // Create a copy of the original list.
                            versionList = angular.copy(versionListData.data.versions);
                        } else {
                            growl.error(versionListData.metadata.reason);
                        }

                        // Bind PHP versions specific to domain dropdown list
                        setDomainPhpDropdown(versionList);
                    });
                }]);

        return controller;
    }
);
