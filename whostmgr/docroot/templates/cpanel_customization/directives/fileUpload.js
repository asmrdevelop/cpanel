/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/directives/fileUpload.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "uiBootstrap",
        "app/directives/fileReader",
        "app/directives/fileType",
        "app/directives/triggerFor",
    ],
    function(angular, LOCALE, CJT) {
        "use strict";

        var module = angular.module("customize.directives.fileUpload", [
            "customize.directives.fileReader",
            "customize.directives.fileType",
            "customize.directives.triggerFor",
            "ui.bootstrap",
        ]);

        module.directive("cpFileUpload",
            [
                "$uibModal",
                function($uibModal) {
                    var TEMPLATE_PATH = "directives/fileUpload.phtml";
                    var RELATIVE_PATH = "templates/cpanel_customization/" + TEMPLATE_PATH;

                    return {
                        replace: true,
                        require: [ "^form", "ngModel" ],
                        restrict: "E",
                        scope: {
                            id: "@id",
                            title: "@title",
                            browseButtonLabel: "@browseButtonLabel",
                            deleteButtonTitle: "@deleteButtonTitle",
                            confirmDeleteMessage: "@confirmDeleteMessage",
                            previewTitle: "@previewTitle",
                            help: "@help",
                            fileTypeError: "@fileTypeError",
                            fileEmptyError: "@fileEmptyError",
                            fileMaxSizeError: "@fileMaxSizeError",
                            model: "=ngModel",
                            types: "=mimeTypes",
                            previewBgColor: "=previewBgColor",
                            onDelete: "&onDelete",
                            onChange: "&onChange",
                            onReset: "&onReset",
                            inputClasses: "@inputClass",
                            previewClasses: "@previewClass",
                        },
                        templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,
                        link: function(scope, element, attrs, controllers) {
                            scope.LOCALE = LOCALE;
                            var formController = controllers[0];
                            var modelController = controllers[1];

                            if (!scope.inputClasses) {
                                scope.inputClasses = "col-xs-12 col-sm-8 col-md-8 col-lg-6";
                            }

                            if (!scope.previewClasses) {
                                scope.previewClasses = "col-xs-12 col-sm-4 col-md-4 col-lg-4";
                            }

                            /**
                             * Generate a complete field name for a field in the upload form partial.
                             *
                             * @param {string} field - the partial name of the field in the form
                             * @returns {string}
                             */
                            scope.field = function(field) {
                                return "file_upload_" + field;
                            };

                            /**
                             * Check if the given form field is pritine.
                             *
                             * @param {string} field - the partial name of the field in the form
                             * @returns {boolean} - true if its pristine, false otherwise.
                             */
                            scope.isPristine = function(field) {
                                var fieldName = scope.field(field);
                                var f = formController[fieldName];
                                if (f) {
                                    return f.$pristine;
                                }
                                return true;
                            };

                            /**
                             * Check if the given form field is invalid.
                             *
                             * @param {string} field - the partial name of the field in the form
                             * @returns {boolean} - true if its invalid, false otherwise.
                             */
                            scope.isInvalid = function(field) {
                                var fieldName = scope.field(field);
                                var f = formController[fieldName];
                                if (f) {
                                    return f.$invalid;
                                }
                                return true;
                            };

                            /**
                             * Checks if the given field has the given error.
                             *
                             * @param {string} field - the partial name of the field in the form
                             * @param {string} kind - name of the error you are looking for.
                             * @returns {boolean} - the error object if present, undefined otherwise.
                             */
                            scope.errors = function(field, kind) {
                                var fieldName = scope.field(field);
                                var f = formController[fieldName];
                                if (f) {
                                    return f.$error[kind];
                                }
                                return;
                            };

                            /**
                             * Set the field to pristine.
                             *
                             * @param {string} field
                             */
                            scope.setPristine = function(field) {
                                var fieldName = scope.field(field);
                                var f = formController[fieldName];
                                if (f) {
                                    f.$setPristine();
                                }
                                return;
                            };

                            /**
                             * Creates a clean copy of the model.
                             *
                             * @param {FileModel} model
                             * @returns {FileModel}
                             */
                            function cleanCopy(original) {
                                var model = angular.copy(original);
                                model.data = "";
                                model.filename = "";
                                model.size = 0;
                                model.type = "";
                                delete model.error;
                                delete model.errorType;
                                return model;
                            }

                            /**
                             * @typedef FileModel
                             * @property {string} filename - name of the file to display
                             * @property {string} data - base 64 encoded file contents
                             * @property {boolean} saved - true if the file has been saved to the backend, false otherwise.
                             * @property {string} name - name of the property
                             */

                            /**
                             * Initiate a delete file operation
                             * @param {FileModel} model - the data model
                             */
                            scope.delete = function(model) {
                                scope.deleteLoading = true;
                                var promise = scope.onDelete(model);
                                if (promise && promise.then) {
                                    promise.then(function() {
                                        scope.deleteLoading = false;
                                        scope.model = cleanCopy(modelController.$modelValue);
                                        scope.setPristine(scope.id + "_file");
                                    });
                                } else {
                                    scope.deleteLoading = false;
                                    scope.model = cleanCopy(modelController.$modelValue);
                                    scope.setPristine(scope.id + "_file");
                                }
                            };

                            /**
                             * Confirms deleting
                             *
                             * @method confirmDelete
                             * @param {FileModel} model - the data model
                             */
                            scope.confirmDelete = function(model) {
                                if (model.saved) {

                                    var TEMPLATE_PATH = "directives/fileConfirmUploadDelete.phtml";
                                    var RELATIVE_PATH = "templates/cpanel_customization/" + TEMPLATE_PATH;

                                    $uibModal.open({
                                        templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,
                                        size: "sm",
                                        controller: [
                                            "$scope",
                                            "$uibModalInstance",
                                            function($scope, $uibModalInstance) {
                                                $scope.message = scope.confirmDeleteMessage;
                                                $scope.LOCALE = LOCALE;

                                                $scope.close = function close(confirmed) {
                                                    $uibModalInstance.close(confirmed);
                                                };
                                            },
                                        ],
                                    }).result.then(function(confirmed) {
                                        if (confirmed) {
                                            scope.delete(model);
                                        }
                                    });
                                } else {
                                    scope.model = cleanCopy(scope.model);

                                    var elId = scope.field(scope.id + "_file");

                                    var fileEl = angular.element("#" + elId);
                                    fileEl.val(null);

                                    // Clear the error state.
                                    formController[elId].$setValidity("fileSize", true);
                                    formController[elId].$setValidity("fileMaxSize", true);
                                    formController[elId].$setValidity("filetype", true);
                                    formController[elId].$setPristine();

                                    scope.onReset(scope.model);
                                }
                            };

                            scope.change = function() {
                                scope.onChange(scope.model);
                            };
                        },
                    };
                },
            ]
        );
    }
);
