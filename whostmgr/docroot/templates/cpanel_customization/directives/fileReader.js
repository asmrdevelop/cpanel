/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/directives/fileReader.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [
        "angular",
        "cjt/util/locale",
        "app/constants",
    ],
    function(angular, LOCALE, CONSTANTS) {
        "use strict";

        var module = angular.module("customize.directives.fileReader", []);

        module.directive("fileReader", [
            "$q",
            function($q) {
                return {
                    restrict: "A",
                    require: [ "?ngModel" ],
                    priority: 20,
                    link: function(scope, element, attrs, controllers) {
                        var ngModel = controllers[0];

                        // To use this attribute directive a parent element must:
                        // * have an ngModel attribute
                        // * be an <input> element
                        // * have an type attribute of 'file'
                        if (!ngModel || element[0].tagName !== "INPUT" || !attrs["type"] || attrs["type"] !== "file") {
                            return;
                        }

                        ngModel.$render = function() {};

                        /**
                         * Helper used to mock behavior in tests
                         * @param {HtmlFileInput} el
                         * @returns {File}
                         */
                        scope._getFiles = function(el) {
                            return el.files;
                        };

                        /**
                         * Helper used to mock behavior in tests
                         * @returns {number}
                         */
                        scope._getMaxSize = function() {
                            return CONSTANTS.MAX_FILE_SIZE;
                        };

                        /**
                         * Merge file data to the model object.
                         *
                         * @param {ngModelController} ngModel
                         * @param {File} file
                         * @param {string} data
                         * @returns {Object} The updated model.
                         */
                        scope._mergeToModel = function(ngModel, file, data) {
                            var model = angular.copy(ngModel.$modelValue);
                            model.filename = file.name;
                            model.size = file.size;
                            model.type = file.type;
                            model.data = data;

                            delete model.error;
                            delete model.errorKey;
                            return model;
                        };

                        /**
                         * Update the model with the error information.
                         *
                         * @param {Object} model - Model to store the data into.
                         * @param {String} message - Human readable message
                         * @param {String} key - Machine identifier for the error.
                         */
                        scope._setModelError = function(model, message, key) {
                            model.error = message;
                            model.errorKey = key;
                        };

                        /**
                         * Converts a file into a base64 encoded string.
                         *
                         * @async
                         * @param {File} file - As defined here: https://developer.mozilla.org/en-US/docs/Web/API/File
                         * @returns {string} The base64 encoded file contents.
                         */
                        scope._toBase64 = function(file) {
                            var deferred = $q.defer();
                            var maxSize = scope._getMaxSize();
                            var model;

                            if (file.size > maxSize) {

                                // We resolve instead of reject to allow the validation to get all
                                // the info and make decisions based on it. We only exclude the costly
                                // .data property
                                model = scope._mergeToModel(ngModel, file, "");
                                scope._setModelError(model, LOCALE.maketext("The file is larger than the maximum of [numf,_1] kilobytes.", maxSize), "maxsize");
                                deferred.resolve(model);
                                return deferred.promise;
                            }

                            var reader = new FileReader();
                            reader.addEventListener("loadend", function(e) {
                                scope.$apply(function() {
                                    model = scope._mergeToModel(ngModel, file, e.target.result);
                                    deferred.resolve(model);
                                });
                            });

                            reader.addEventListener("error", function(e) {
                                scope.$apply(function() {

                                    // We resolve instead of reject to allow the validation to get all
                                    // the info and make decisions based on it. We only exclude the costly
                                    // .data property
                                    model = scope._mergeToModel(ngModel, file, "");
                                    scope._setModelError(model, e && e.target ? e.target.error : LOCALE.maketext("An unknown error occurred while reading the file contents."), "readFailed");
                                    deferred.resolve(model);
                                });
                            });

                            try {
                                reader.readAsDataURL(file);
                            } catch (error) {

                                // Catch any synchronous errors.

                                // We resolve instead of reject to allow the validation to get all
                                // the info and make decisions based on it. We only exclude the costly
                                // .data property
                                model = scope._mergeToModel(ngModel, file, "");
                                scope._setModelError(model, error ? error : LOCALE.maketext("An unknown error occurred while reading the file contents."), "readFailed");
                                deferred.resolve(model);
                            }

                            return deferred.promise;
                        };

                        element.bind("change", function(e) {
                            scope.$apply(function() {
                                var el = e.target;
                                var files = scope._getFiles(el);
                                if (!files || !files.length) {
                                    return;
                                }

                                var file = files[0];
                                if (file && file.size !== 0) {
                                    scope._toBase64(file)
                                        .then(function(value) {
                                            ngModel.$setViewValue(value);  // NOTE: This will trigger the $parsers above.
                                        });
                                }
                                return;
                            });
                        });
                    },
                };
            },
        ]);
    }
);
