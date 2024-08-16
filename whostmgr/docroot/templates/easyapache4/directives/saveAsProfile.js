/*
# templates/easyapache4/directives/saveAsProfile.js            Copyright 2022 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "lodash",
        "cjt/decorators/growlDecorator",
        "app/services/ea4Data",
        "app/services/ea4Util",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective"
    ],
    function(angular, LOCALE, CJT, _) {

        // Retrieve the current application
        var app = angular.module("App");

        app.directive("saveAsProfile",
            [ "ea4Data", "ea4Util", "growl", "growlMessages",
                function(ea4Data, ea4Util, growl, growlMessages) {
                    var initContent = {
                        name: "",
                        filename: { name: "", valMsg: "" },
                        tags: [],
                        description: "",
                        version: "",
                        overwrite: false
                    };
                    var TEMPLATE_PATH = "directives/saveAsProfile.ptt";
                    var RELATIVE_PATH = "templates/easyapache4/" + TEMPLATE_PATH;

                    var ddo = {
                        replace: true,
                        restrict: "E",
                        templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,
                        scope: {
                            idPrefix: "@",
                            packages: "=",
                            actionHandler: "=",
                            position: "@",
                            onCancel: "&",
                            onSaveSuccess: "&",
                            onSaveError: "&",
                            show: "@",
                            saveButtonText: "@"
                        },
                        link: function postLink(scope, element, attrs) {
                            scope.saveAsData = _.cloneDeep(initContent);
                            scope.highlightOverwrite = false;
                            scope.actionHandler = scope.actionHandler || {};
                            scope.idPrefix = scope.idPrefix || "save";
                            scope.position = scope.position || "top";
                            scope.saveButtonText = scope.saveButtonText || LOCALE.maketext("Save");

                            /**
                             * Clears the save as profile form
                             *
                             * @method clearSaveProfileForm
                             */
                            var clearSaveProfileForm = function() {

                                // reseting model values
                                scope.saveAsData = _.cloneDeep(initContent);

                                if (scope.form && scope.form.$dirty) {
                                    scope.form.txtFilename.$setValidity("invalidFilename", true);

                                    // mark the form pristine
                                    scope.form.$setPristine();
                                }

                                if (!_.isUndefined(scope.onCancel)) {
                                    scope.onCancel({ position: scope.position });
                                }
                            };

                            /**
                             * Save as new profile.
                             *
                             * @method saveForm
                             */
                            scope.actionHandler.saveForm = function() {

                                // Destroy all growls before attempting to submit something.
                                growlMessages.destroyAllMessages();

                                // Throw console error when packages are not provided.
                                if (_.isUndefined(scope.packages)) {
                                    throw "Packages for the profile are not provided. Wherever this directive is used, make sure to fill the packages attribute correctly.";
                                }

                                if (scope.form.$valid) {

                                    // upload profile
                                    var overwrite = scope.saveAsData.overwrite ? 1 : 0;
                                    var inputTags = _.split(scope.saveAsData.tagsAsString, /\s*,\s*/);
                                    var filenameWithExt = scope.saveAsData.filename.name + ".json";
                                    var contentJson = {
                                        "name": scope.saveAsData.name,
                                        "desc": scope.saveAsData.desc,
                                        "pkgs": scope.packages,
                                        "tags": _.compact(inputTags)
                                    };

                                    return ea4Data.saveAsNewProfile(contentJson, filenameWithExt, overwrite)
                                        .then(function(data) {
                                            if (typeof data !== "undefined" && !_.isEmpty(data.path)) {

                                                // TODO: Make the profile name to be a link to profiles page in the message.
                                                growl.success(LOCALE.maketext("The system successfully saved the current packages to the “[_1]” profile. It is available in the EasyApache 4 profiles page.", _.escape(scope.saveAsData.name)));
                                                clearSaveProfileForm();
                                                if (!_.isUndefined(scope.onSaveSuccess)) {
                                                    scope.onSaveSuccess();
                                                }
                                            }
                                        }, function(response) {
                                            if (typeof response.data !== "undefined" && response.data.already_exists) {
                                                scope.highlightOverwrite = true;
                                            }
                                            if (!_.isUndefined(scope.onSaveSuccess)) {
                                                scope.onSaveError();
                                            }
                                            growl.error(_.escape(response.error));
                                        });
                                }
                            };

                            /**
                             * Cancel save action.
                             *
                             * @method cancel
                             */
                            scope.actionHandler.cancel = function() {
                                clearSaveProfileForm();
                            };

                            /**
                             * Run filename validation and set the validation
                             * inputs with the results accordingly.
                             *
                             * @method validateFilenameInput
                             */
                            scope.validateFilenameInput = function() {
                                var valData = ea4Util.validateFilename(scope.saveAsData.filename.name);
                                scope.saveAsData.filename.valMsg = valData.valMsg;
                                scope.form.txtFilename.$setValidity("invalidFilename", valData.valid);
                            };
                        }
                    };
                    return ddo;
                }
            ]
        );
    }
);
