/*
# backup_configuration/views/destinations.js       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/table",
        "cjt/services/alertService",
        "cjt/directives/alertList",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/validator/datatype-validators",
        "cjt/validator/username-validators",
        "cjt/validator/compare-validators",
        "app/services/backupConfigurationServices",
        "app/services/validationLog"
    ],
    function(angular, _, LOCALE, Table) {
        "use strict";

        var app = angular.module("whm.backupConfiguration");

        var table = new Table();

        var controller = app.controller(
            "destinations", [
                "$scope",
                "$location",
                "$q",
                "$window",
                "backupConfigurationServices",
                "alertService",
                "$timeout",
                "validationLog",

                function(
                    $scope,
                    $location,
                    $q,
                    $window,
                    backupConfigurationServices,
                    alertService,
                    $timeout,
                    validationLog) {

                    /**
                     * Sets delete confirmation callout element to show and assigns
                     * destination properties to the $scope to be used when deleting destination
                     *
                     * @scope
                     * @method setupDeleteConfirmation
                     * @param {String} name - name of specific destination
                     * @param {String} id - unique identification string
                     */
                    $scope.setupDeleteConfirmation = function(name, id, index) {
                        $scope.index = index;
                        $scope.showDeleteConfirmation = !$scope.showDeleteConfirmation;
                        $scope.updating = !$scope.updating;
                        $scope.destinationName = name;
                        $scope.destinationId = id;
                    };

                    /**
                     * Handles backup enable toggle and sets scope property to remove
                     * focus from all inputs if backup is not enabled
                     *
                     * @scope
                     * @method enableBackupConfig
                     */
                    $scope.enableBackupConfig = function() {
                        if (!$scope.formData.backupenable) {
                            $scope.formEnabled = false;
                        } else {
                            $scope.formEnabled = true;
                        }
                    };

                    /**
                     * Is validation in progress for given destination.
                     *
                     * @scope
                     * @method isValidationInProgressFor
                     * @param {String} id - id of specific destination to test
                     * @returns {Boolean} is destination being validated
                     */
                    $scope.isValidationInProgressFor = function(destination) {
                        return validationLog.isValidationInProgressFor(destination);
                    };

                    /**
                     * Determine whether a validation process is current running.
                     *
                     * @scope
                     * @method isValidationRunning
                     * @returns {Boolean} is validation (multiple or single) process running
                     */
                    $scope.isValidationRunning = function() {
                        return validationLog.isValidationRunning();
                    };

                    /**
                     * Validates destination via API
                     *
                     * @scope
                     * @method validateDestination
                     * @param {String} id - id of specific destination to send to API
                     * @param {String} name - name of specific destination
                     * @param {Object} opts - options
                     * @param {Boolean} opts.all - if true dont clear the alert list since we are validating each destination.
                     * @returns {Promise<String>} - string indicating success
                     * @throws {Promise<String>} - string indicating error
                     */
                    $scope.validateDestination = function(id, name, opts) {
                        if (!opts) {
                            opts = {};
                        }

                        if (!opts.all) {
                            $scope.clearAlerts();
                        }

                        $scope.destinationState.validatingDestination = true;
                        $scope.displayAlertRows = [];
                        $scope.displayAlertRows.push(id);

                        var theDestination = _.find($scope.destinationState.destinationList, function(item) {
                            return item.id === id;
                        });

                        validationLog.add(theDestination);

                        $scope.currentlyValidating = validationLog.getLogEntries();

                        return backupConfigurationServices.validateDestination(id)
                            .then(function(success) {
                                var alertOptions = {
                                    type: "success",
                                    id: "validate-destination-succeeded-" + id,
                                    message: LOCALE.maketext("The validation for the “[_1]” destination succeeded.", _.escape(name)),
                                    closeable: true,
                                    autoClose: 10000,
                                };
                                if (opts.all) {
                                    alertOptions.replace = false;
                                }
                                validationLog.markAsComplete(id, alertOptions);
                                if (!$scope.destinationState.validatingAllDestinations) {
                                    alertService.add(alertOptions);
                                }
                            })
                            .catch(function(error) {
                                var alertOptions = {
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    replace: false,
                                    id: "validate-destination-failed-" + id,
                                };
                                if (opts.all) {
                                    alertOptions.replace = false;
                                }

                                // validation has failed, so mark existing entry in
                                // destinations list as disabled
                                theDestination.disabled = true;

                                validationLog.markAsComplete(id, alertOptions);
                                if (!$scope.destinationState.validatingAllDestinations) {
                                    alertService.add(alertOptions);
                                }
                            })
                            .finally(function() {
                                $scope.destinationState.validatingDestination = $scope.isValidationRunning();
                                $scope.destinationState.showValidationIconHint = true;
                            });
                    };

                    /**
                     * Retrieves all current destinations via API
                     *
                     * @scope
                     * @method getDestinations
                     */
                    $scope.getDestinations = function() {
                        $scope.destinationState.destinationListLoaded = false;
                        return backupConfigurationServices.getDestinationList()
                            .then(function(destinationsData) {
                                $scope.destinationState.destinationList = destinationsData;
                                $scope.destinationState.destinationListLoaded = true;
                                $scope.updating = false;
                                $scope.currentlyValidating = validationLog.getLogEntries();
                                $scope.setPagination(destinationsData);
                            }, function(error) {
                                $scope.destinationState.destinationListLoaded = true;
                                $scope.updating = false;
                                alertService.add({
                                    type: "danger",
                                    closeable: true,
                                    message: error,
                                    id: "fetch-destinations-failed"
                                });
                            });
                    };

                    /**
                     * Load data and get metadata for table of transports
                     *
                     * @scope
                     * @method setPagination
                     * @param  {Array.<TransportType>} transportData - array of transport objects
                     */
                    $scope.setPagination = function(transportData) {
                        if (transportData) {
                            table.load(transportData);
                            table.setSort("name,type", "asc");

                            // the next two lines should be removed if
                            // pagination for the table is implemented
                            table.meta.limit = transportData.length;
                            table.meta.pageSize = transportData.length;
                        }

                        table.update();
                        $scope.meta = table.getMetadata();
                        $scope.filteredDestinationList = table.getList();
                    };

                    $scope.updateTable = function() {
                        $scope.setPagination();
                    };

                    /**
                     * Sets path of destination template to retrieve
                     *
                     * @scope
                     * @method setTemplatePath
                     * @param {String} type - string indicating destination type selected
                     */
                    $scope.setTemplatePath = function(type) {
                        if (type === "Custom") {
                            $scope.templatePath = "views/customTransport.ptt";
                        } else if (type === "FTP") {
                            $scope.templatePath = "views/FTPTransport.ptt";
                        } else if (type === "GoogleDrive") {
                            $scope.templatePath = "views/GoogleTransport.ptt";
                        } else if (type === "Local" || type === "Additional Local Directory") {
                            $scope.templatePath = "views/LocalTransport.ptt";
                        } else if (type === "SFTP") {
                            $scope.templatePath = "views/SFTPTransport.ptt";
                        } else if (type === "Amazon S3" || type === "AmazonS3") {
                            $scope.templatePath = "views/AmazonS3Transport.ptt";
                        } else if (type === "Rsync") {
                            $scope.templatePath = "views/RsyncTransport.ptt";
                        } else if (type === "WebDAV") {
                            $scope.templatePath = "views/WebDAVTransport.ptt";
                        } else if (type === "S3Compatible") {
                            $scope.templatePath = "views/S3CompatibleTransport.ptt";
                        } else if (type === "Backblaze") {
                            $scope.templatePath = "views/B2.ptt";
                        }
                    };

                    /**
                     * Returns custom transport type where required.
                     *
                     * @scope
                     * @method getTransportType
                     * @param {String} type - string indicating destination type
                     * @returns {String} - type formatted for display
                     */
                    $scope.formattedTransportType = function(type) {
                        if (type === "Backblaze") {
                            return "Backblaze B2";
                        } else if (type === "GoogleDrive") {
                            return "Google Drive™";
                        }

                        return type;
                    };

                    /**
                     * Retrieves selected destination via API
                     *
                     * @scope
                     * @method getDestination
                     * @param {String} id - id of selected destination
                     * @param {String} type - type of selected destination
                     */
                    $scope.getDestination = function(id, type) {
                        $scope.destinationState.fetchingDestination = true;
                        $scope.destinationState.newMode = false;
                        $scope.setTemplatePath(type);

                        return backupConfigurationServices.getDestination(id)
                            .then(function(destinationData) {
                                $scope.destinationState.destination = destinationData;
                                $scope.destinationState.destinationMode = true;
                                $scope.destinationState.fetchingDestination = false;
                                $scope.destinationState.editMode = true;

                                if (type === "SFTP" || type === "Rsync") {
                                    $scope.getSSHKeyList();
                                }

                                if (type === "GoogleDrive") {
                                    $scope.checkCredentials(destinationData.googledrive.client_id, destinationData.googledrive.client_secret);
                                }
                            }, function(error) {
                                $scope.destinationState.fetchingDestination = false;
                                alertService.add({
                                    type: "danger",
                                    closeable: true,
                                    message: error,
                                    id: "fetch-destination-error"
                                });
                            });
                    };

                    /**
                     * Sets template path and creates new destination object
                     *
                     * @scope
                     * @method createNewDestination
                     * @param  {String} type - destination type
                     */
                    $scope.createNewDestination = function(type) {
                        $scope.destinationState.destination = {};
                        $scope.destinationState.editMode = false;
                        $scope.destinationState.newMode = true;
                        $scope.setTemplatePath(type);

                        /**
                         * New destination object created with default values per
                         * https://confluence0.cpanel.net/display/public/SDK/WHM+API+1+Functions+-+backup_destination_add
                         */

                        if (type === "Custom") {
                            $scope.destinationState.destination.custom = {
                                type: type,
                                timeout: 30
                            };
                        } else if (type === "FTP") {
                            $scope.destinationState.destination.ftp = {
                                type: type,
                                port: 21,
                                passive: true,
                                timeout: 30
                            };
                        } else if (type === "GoogleDrive") {
                            $scope.destinationState.destination.googledrive = {
                                type: type,
                                timeout: 30
                            };
                        } else if (type === "Local" || type === "Additional Local Directory") {
                            $scope.destinationState.destination.local = {
                                type: "Local",
                                mount: false
                            };
                        } else if (type === "SFTP") {
                            $scope.destinationState.destination.sftp = {
                                type: type,
                                authtype: "key",
                                port: 22,
                                timeout: 30
                            };
                            $scope.getSSHKeyList();
                        } else if (type === "AmazonS3") {
                            $scope.destinationState.destination.amazons3 = {
                                type: "AmazonS3",
                                timeout: 30
                            };
                        } else if (type === "S3Compatible") {
                            $scope.destinationState.destination.s3compatible = {
                                type: "S3Compatible",
                                timeout: 30
                            };
                        } else if (type === "Rsync") {
                            $scope.destinationState.destination.rsync = {
                                type: type,
                                authtype: "key",
                                timeout: 30,
                                port: 22
                            };
                            $scope.getSSHKeyList();
                        } else if (type === "WebDAV") {
                            $scope.destinationState.destination.webdav = {
                                type: type
                            };
                        } else if (type === "Backblaze") {
                            $scope.destinationState.destination.backblaze = {
                                type: type,
                                timeout: 180
                            };
                        }
                        $scope.destinationState.destinationMode = true;
                    };

                    /**
                     * Saves new destination via API
                     *
                     * @scope
                     * @param {<CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType | S3CompatibleTransportType>} destination - object representing destination config
                     * @param {Boolean} [shouldValidate] - whether the destination should also be validated as well as saved
                     * @method saveDestination
                     * @returns {Promise<String>} - id indicating success in case destination also needs to be validated
                     * @throws {Promise<String>} - string indicating error
                     */
                    $scope.saveDestination = function(destination, shouldValidate) {
                        $scope.clearAlerts();
                        $scope.destinationState.savingDestination = true;
                        var property = Object.keys(destination);
                        var destinationName = destination[property[0]]["name"];
                        if ($scope.destinationState.newMode) {
                            return backupConfigurationServices.setNewDestination(destination)
                                .then(function(response) {
                                    $scope.destinationId = response.id;
                                    $scope.destinationState.googleCredentialsGenerated = false;
                                    $scope.destinationState.destinationMode = false;
                                    $scope.destinationState.newMode = false;
                                    alertService.add({
                                        type: "success",
                                        autoClose: 5000,
                                        message: LOCALE.maketext("The system successfully saved the “[_1]” destination.", _.escape(destinationName)),
                                        id: "save-new-destination-success"
                                    });

                                    if (destination[property[0]]["type"] === "GoogleDrive") {
                                        $scope.destinationState.checkCredentialsOnSave = true;
                                        $scope.checkCredentials(destination[property[0]]["client_id"], destination[property[0]]["client_secret"], $scope.destinationState.checkCredentialsOnSave);
                                    }

                                    return $scope.getDestinations();
                                })
                                .then(function() {
                                    if (shouldValidate) {

                                        // pass all=true for options so save message not overwritten by validate message
                                        $scope.validateDestination($scope.destinationId, _.escape(destinationName), { all: true });
                                    }
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        closeable: true,
                                        message: _.escape(error),
                                        id: "save-new-destination-error"
                                    });
                                })
                                .finally(function() {
                                    $scope.destinationState.savingDestination = false;
                                });
                        } else if ($scope.destinationState.editMode) {
                            return backupConfigurationServices.updateCurrentDestination(destination)
                                .then(function(response) {
                                    $scope.destinationState.editMode = false;
                                    alertService.add({
                                        type: "success",
                                        autoClose: 5000,
                                        message: LOCALE.maketext("The system successfully saved the “[_1]” destination.", _.escape(destinationName)),
                                        id: "edit-destination-success"
                                    });

                                    if (destination[property[0]]["type"] === "GoogleDrive") {
                                        $scope.destinationState.checkCredentialsOnSave = true;
                                        $scope.checkCredentials(destination[property[0]]["client_id"], destination[property[0]]["client_secret"], $scope.destinationState.checkCredentialsOnSave);
                                    }

                                    $scope.destinationState.destinationMode = false;
                                    return $scope.getDestinations();
                                })
                                .then(function() {

                                    // update any existing entry in validation results table to reflect
                                    // potential edits to the name

                                    var editedId = destination[property[0]]["id"];

                                    validationLog.updateValidationInfo(editedId, _.escape(destinationName));

                                    if (shouldValidate) {

                                        // pass all=true for options so save message not overwritten by validate message
                                        $scope.validateDestination(destination[property[0]]["id"], _.escape(destinationName), { all: true });
                                    }
                                })
                                .catch(function(error) {
                                    alertService.add({
                                        type: "danger",
                                        closeable: true,
                                        message: error,
                                        id: "edit-destination-error"
                                    });
                                })
                                .finally(function() {
                                    $scope.destinationState.savingDestination = false;
                                });
                        }

                    };

                    /**
                     * Saves and validates destination, saveDestination resolves
                     * into destination id
                     *
                     * @scope
                     * @method saveAndValiidateDestination
                     * @param {<CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType | S3CompatibleTransportType>} destination - object representing destination config
                     */
                    $scope.saveAndValidateDestination = function(destination) {
                        var shouldValidate = true;
                        return $scope.saveDestination(destination, shouldValidate);
                    };

                    /**
                     * Cancels current destination configuration by clearing alerts
                     * and hiding destination view
                     *
                     * @scope
                     * @method cancelDestination
                     */
                    $scope.cancelDestination = function(skipScrolling) {
                        $scope.clearAlerts();

                        $scope.destinationState.destinationMode = false;
                        $scope.destinationState.editMode = false;
                        $scope.destinationState.newMode = false;
                        $scope.destinationState.googleCredentialsGenerated = false;
                        if (!skipScrolling) {
                            document.getElementById("additional_destinations_label").scrollIntoView();
                        }
                    };

                    /**
                     * Delete specific destination and then call getDestinations
                     * to display current list
                     *
                     * @scope
                     * @method deleteDestination
                     */
                    $scope.deleteDestination = function(id) {
                        $scope.deleting = true;
                        $scope.showDeleteConfirmation = false;
                        $scope.displayAlertRows = [];
                        $scope.displayAlertRows.push(id);

                        backupConfigurationServices.deleteDestination(id)
                            .then(function(success) {
                                $scope.deleting = false;

                                // delete existing entry from validation results if one exists
                                validationLog.remove(id);
                                $scope.currentlyValidating = validationLog.getLogEntries();
                                alertService.add({
                                    type: "success",
                                    autoClose: 5000,
                                    id: "delete-destination-success",
                                    message: LOCALE.maketext("The system successfully deleted the “[_1]” destination.", _.escape($scope.destinationName))
                                });
                                $scope.getDestinations();
                            }, function(error) {
                                $scope.deleting = false;
                                $scope.updating = false;
                                alertService.add({
                                    type: "danger",
                                    id: "delete-destination-failed",
                                    closeable: true,
                                    message: error
                                });
                            });
                    };

                    /**
                     * Toggle status of destination then call getDestinations to show current status
                     *
                     * @scope
                     * @method toggleStatus
                     * @param  {<CustomTransportType | FTPTransportType | GoogleTransportType | LocalTransportType | SFTPTransportType | AmazonS3TransportType | RsyncTransportType | WebDAVTransportType>} destination - object representing destination config
                     */
                    $scope.toggleStatus = function(destination) {
                        $scope.toggled = false;
                        $scope.updating = true;

                        $scope.displayAlertRows = [];
                        $scope.displayAlertRows.push(destination.id);

                        var disable,
                            message;
                        if (!destination.disabled) {
                            message = LOCALE.maketext("You disabled the destination “[_1]”.", _.escape(destination.name));
                            disable = true;
                        } else if (destination.disabled) {
                            message = LOCALE.maketext("You enabled the destination “[_1]”.", _.escape(destination.name));
                            disable = false;
                        }

                        return backupConfigurationServices.toggleStatus(destination.id, disable)
                            .then(function(success) {
                                alertService.add({
                                    type: "success",
                                    autoClose: 5000,
                                    id: "toggle-destination-success",
                                    message: message
                                });
                                destination.disabled = !destination.disabled;
                            }, function(error) {
                                alertService.add({
                                    type: "danger",
                                    closeable: true,
                                    id: "toggle-destination-failed",
                                    message: error
                                });
                            })
                            .finally(function() {

                                // toggled set to true so that "in process" message
                                // disappears, error message still visible
                                $scope.toggled = true;
                                $scope.updating = false;
                            });
                    };

                    /**
                     * Validate all current destinations via API
                     *
                     * @scope
                     * @method validateAllDestinations
                     */
                    $scope.validateAllDestinations = function() {
                        $scope.currentlyValidating = [];
                        $scope.destinationState.validatingAllDestinations = true;
                        var promises = [];

                        angular.forEach($scope.destinationState.destinationList, function(destination) {
                            promises.push($scope.validateDestination(destination.id, _.escape(destination.name), {
                                all: true
                            }));
                        });
                        return $q.all(promises).finally(function() {
                            $scope.destinationState.validatingAllDestinations = false;
                            $scope.destinationState.validatingDestination = $scope.isValidationRunning();
                        });
                    };

                    /**
                    * Checks whether the validation process for a particular
                    * destination succeeded.
                    *
                    * @scope
                    * @method validateAllSuccessFor
                    * @param {String} id - unique identification string
                    */
                    $scope.validateAllSuccessFor = function(id) {
                        return validationLog.validateAllSuccessFor(id);
                    };

                    /**
                     * Checks whether the validation process for a particular
                     * destination failed.
                     *
                     * @scope
                     * @method validateAllFailureFor
                     * @param {String} id - unique identification string
                     */
                    $scope.validateAllFailureFor = function(id) {
                        return validationLog.validateAllFailureFor(id);
                    };

                    /**
                    * Displays alert message for validation result
                    *
                    * @scope
                    * @method showValidationMessageFor
                    * @param {String} id - unique identification string
                    */
                    $scope.showValidationMessageFor = function(id) {
                        validationLog.showValidationMessageFor(id);
                    };

                    /**
                     * Generates Google user credentials
                     *
                     * @scope
                     * @method generateCredentials
                     * @param {String} clientId - unique identifying string of user from Google Drive API
                     * @param {String} clientSecret - unique secret string from Google Drive API
                     */
                    $scope.generateCredentials = function(clientId, clientSecret) {

                        $scope.destinationState.generatingCredentials = true;
                        return backupConfigurationServices.generateGoogleCredentials(clientId, clientSecret)
                            .then(function(response) {
                                $scope.destinationState.generatingCredentials = false;
                                alertService.add({
                                    type: "info",
                                    closeable: true,
                                    replace: false,
                                    message: LOCALE.maketext("A new window will appear that will allow you to generate Google® credentials."),
                                    id: "check-google-credentials-popup-" + clientId.substring(0, 6)
                                });
                                $timeout(function() {
                                    $window.open(response.uri, "generate_google_credentials");
                                }, 2000);
                            }, function(error) {
                                $scope.destinationState.generatingCredentials = false;
                                alertService.add({
                                    type: "danger",
                                    closeable: true,
                                    message: error,
                                    replace: false,
                                    id: "generate-google-credentials-failed-" + clientId.substring(0, 6)
                                });
                            });
                    };

                    /**
                     * Checks is Google user credentials are generated
                     *
                     * @scope
                     * @method checkCredentials
                     * @param  {String}  clientId - unique identifying string of user from Google Drive API
                     * @param  {String}  clientSecret - unique secret string from Google Drive API
                     * @param  {Boolean} checkOnSave - if the credentials should be checked from a save event
                     * @returns {Boolean} - returns false if credentials do not exist to alert user on save event
                     */
                    $scope.checkCredentials = function(clientId, clientSecret, checkOnSave) {
                        return backupConfigurationServices.checkForGoogleCredentials(clientId)
                            .then(function(exists) {
                                if (exists) {
                                    $scope.destinationState.googleCredentialsGenerated = true;
                                } else if (checkOnSave && !exists) {
                                    $scope.destinationState.googleCredentialsGenerated = false;
                                    alertService.add({
                                        type: "warning",
                                        closeable: true,
                                        replace: false,
                                        message: LOCALE.maketext("No [asis,Google Drive™] credentials have been generated for client id, “[_1]” ….", _.escape(clientId.substring(0, 5))) + LOCALE.maketext("You must generate new credentials to access destinations that require this client [asis,ID]."),
                                        id: "no-google-credentials-generated-warning-" + clientId.substring(0, 6)
                                    });
                                } else if (!checkOnSave) {
                                    $scope.generateCredentials(clientId, clientSecret);
                                }
                            }, function(error) {
                                $scope.destinationState.googleCredentialsGenerated = false;
                                alertService.add({
                                    type: "danger",
                                    closeable: true,
                                    message: error,
                                    group: "failed-during-check-google-credentials-error"
                                });
                            });
                    };

                    /**
                     * Toggles between showing and hiding key generation form
                     *
                     * @scope
                     * @method toggleKeyGenerationForm
                     */
                    $scope.toggleKeyGenerationForm = function() {
                        $scope.destinationState.showKeyGenerationForm = !$scope.destinationState.showKeyGenerationForm;
                    };

                    /**
                     * Creates new SSH key for SFTP transport
                     *
                     * @scope
                     * @method generateKey
                     * @param  {SSHKeyConfigType} keyConfig - object representing key configuration
                     */
                    $scope.generateKey = function(keyConfig) {
                        $scope.destinationState.generatingKey = true;
                        var username;
                        if ($scope.destinationState.destination.sftp) {
                            username = $scope.destinationState.destination.sftp.username;
                        } else if ($scope.destinationState.destination.rsync) {
                            username = $scope.destinationState.destination.rsync.username;
                        }
                        backupConfigurationServices.generateSSHKeyPair(keyConfig, username)
                            .then(function() {
                                $scope.destinationState.generatingKey = false;
                                alertService.add({
                                    type: "success",
                                    autoClose: 5000,
                                    id: "ssh-key-generation-succeeded",
                                    message: LOCALE.maketext("The system generated the key successfully.")
                                });

                                if ($scope.destinationState.destination.sftp) {
                                    $scope.destinationState.destination.sftp.privatekey = $scope.setPrivateKey(keyConfig.name);
                                } else if ($scope.destinationState.destination.rsync) {
                                    $scope.destinationState.destination.rsync.privatekey = $scope.setPrivateKey(keyConfig.name);
                                }

                                $scope.toggleKeyGenerationForm();
                                $scope.getSSHKeyList();
                            }, function(error) {
                                $scope.destinationState.generatingKey = false;
                                alertService.add({
                                    type: "danger",
                                    closeable: true,
                                    message: error,
                                    id: "ssh-key-generation-failed"
                                });
                            });
                    };

                    /**
                     * Gets list of all private SSH keys for root user
                     *
                     * @scope
                     * @method getSSHKeyList
                     */
                    $scope.getSSHKeyList = function() {
                        $scope.destinationState.sshKeyListLoaded = false;
                        backupConfigurationServices.listSSHKeys()
                            .then(function(response) {
                                $scope.destinationState.sshKeyListLoaded = true;
                                $scope.destinationState.sshKeyList = response;
                            }, function(error) {
                                $scope.destinationState.sshKeyListLoaded = true;
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    closeable: true,
                                    id: "ssh-keys-fetch-failed"
                                });

                            });
                    };

                    /**
                     * Sets private key path when key is chosen from list of keys that currently exist
                     *
                     * @scope
                     * @method setPrivateKey
                     * @param {String} key - name of private key file
                     */
                    $scope.setPrivateKey = function(key) {
                        var keyName = "/root/.ssh/" + key;
                        if ($scope.destinationState.destination.sftp) {
                            $scope.destinationState.destination.sftp.privatekey = keyName;
                        } else if ($scope.destinationState.destination.rsync) {
                            $scope.destinationState.destination.rsync.privatekey = keyName;
                        }

                        var privateKeyField = $window.document.getElementById("private_key");
                        if (typeof privateKeyField !== "undefined") {
                            privateKeyField.select();
                            privateKeyField.focus();
                        }

                        return keyName;
                    };

                    /**
                     * Locks key size at 1024 if algorithm chosen is DSA
                     *
                     * @scope
                     * @method toggleKeyType
                     * @param  {String} algorithm - string indicating what algorithm to use for key generation
                     */
                    $scope.toggleKeyType = function(algorithm) {
                        if (algorithm === "DSA") {
                            this.newSSHKey.bits = "1024";
                            this.destinationState.keyBitsSet = true;

                            if (!this.newSSHKey.name || this.newSSHKey.name === "") {
                                this.newSSHKey.name = "id_dsa";
                            }
                        } else if (algorithm === "RSA") {
                            this.newSSHKey.bits = "4096";
                            this.destinationState.keyBitsSet = false;

                            if (!this.newSSHKey.name || this.newSSHKey.name === "") {
                                this.newSSHKey.name = "id_rsa";
                            }
                        }
                    };

                    /**
                     * Clears alerts from all groups
                     *
                     * @scope
                     * @method clearAlerts
                     */
                    $scope.clearAlerts = function() {
                        alertService.clear();
                    };

                    /**
                     * Toggle SSL activation in WebDAV
                     *
                     * @scope
                     * @method toggleSSLWebDAV
                     */
                    $scope.toggleSSLWebDAV = function() {
                        $scope.destinationState.destination.webdav.ssl = !$scope.destinationState.destination.webdav.ssl;
                    };

                    /**
                     * Checks to make sure remote host does not loop back
                     *
                     * @scope
                     * @method checkForLoopBack
                     * @param  {String} host - name of remote host
                     */
                    $scope.checkForLoopBack = function(host) {
                        if (host === $scope.remoteHostLoopbackValue) {
                            $scope.destinationState.isLoopback = true;
                        } else {
                            $scope.destinationState.isLoopback = false;
                        }
                    };

                    /**
                     * Checks backup directory path for invalid characters
                     *
                     * @scope
                     * @method checkForDisallowedChars
                     * @param  {String} path - path to backup directory
                     * @param  {String} chars -string indicating disallowed characters
                     */
                    $scope.checkForDisallowedChars = function(path, chars) {

                        // test will always start at beginning of string
                        chars.lastIndex = 1;
                        var result = chars.test(path);
                        $scope.destinationState.isDisallowedChar = result;
                    };

                    /**
                     * Prevent typing of decimal points (periods) in field
                     *
                     * @scope
                     * @method noDecimalPoints
                     * @param {keyEvent} key event associated with key down
                     */

                    $scope.noDecimalPoints = function(keyEvent) {

                        // keyEvent is jQuery wrapper for KeyboardEvent
                        // better to look at properties in wrapped event
                        var actualEvent = keyEvent.originalEvent;

                        // future proofing: "key" is better property to use
                        // but is not completely supported
                        if ((actualEvent.hasOwnProperty("key") && actualEvent.key === ".") ||
                            (actualEvent.keyCode === 190)) {
                            keyEvent.preventDefault();
                        }
                    };

                    /**
                     * Prevent pasting of non-numbers in field
                     *
                     * @scope
                     * @method onlyNumbers
                     * @param {clipboardEvent} clipboard event associated with paste
                     */

                    $scope.onlyNumbers = function(pasteEvent) {
                        var pastedData = pasteEvent.originalEvent.clipboardData.getData("text");

                        if (!pastedData.match(/[0-9]+/)) {
                            pasteEvent.preventDefault();
                        }
                    };

                    /**
                     * Initialize page with default values
                     *
                     * @scope
                     * @method init
                     */
                    $scope.init = function() {
                        $scope.absolutePathRegEx = /^\/./;
                        $scope.relativePathRegEx = /^\w./;
                        $scope.remoteHostValidation = /^[a-z0-9.-]{1,}$/i;
                        $scope.remoteHostLoopbackValue = /^(127(\.\d+){1,3}|[0:]+1|localhost)$/i;
                        $scope.disallowedPathChars = /[\\?%*:|"<>]/g;

                        $scope.validating = false;
                        $scope.toggled = true;
                        $scope.saving = false;
                        $scope.deleting = false;
                        $scope.updating = false;
                        $scope.showDeleteConfirmation = false;
                        $scope.destinationName = "";
                        $scope.destinationId = "";
                        $scope.activeTab = 1;
                        $scope.currentlyValidating = validationLog.getLogEntries();

                        $scope.destinationState = {
                            destinationSelected: "Custom",
                            destinationMode: false,
                            savingDestination: false,
                            validatingDestination: $scope.isValidationRunning(),
                            fetchingDestination: false,
                            destinationListLoaded: false,
                            validatingAllDestinations: false,
                            destinationList: [],
                            newMode: false,
                            editMode: false,
                            generatingCredentials: false,
                            googleCredentialsGenerated: false,
                            showKeyGenerationForm: false,
                            generatingKey: false,
                            keyBitsSet: false,
                            sshKeyListLoaded: false,
                            isLoopback: false,
                            isDisallowedChar: false,
                            checkCredentialsOnSave: false,
                            showValidationIconHint: false
                        };

                        if (validationLog.hasLogEntries()) {
                            $scope.destinationState.showValidationIconHint = true;
                        }

                        $scope.meta = {};

                        $scope.displayAlertRows = [];
                        $scope.getDestinations();
                    };
                    $scope.init();
                }
            ]
        );

        return controller;
    }
);
