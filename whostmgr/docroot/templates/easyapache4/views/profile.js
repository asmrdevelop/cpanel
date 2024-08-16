/*
# templates/easyapache4/views/profile.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

/* eslint-disable no-console, no-use-before-define, camelcase, no-useless-escape */

define(
    [
        "angular",
        "cjt/util/locale",
        "lodash",
        "cjt/services/alertService",
        "cjt/directives/alertList",
        "cjt/decorators/growlDecorator",
        "app/directives/fileModel",
        "app/directives/fileType",
        "app/directives/fileSize",
        "app/services/ea4Data",
        "app/services/ea4Util",
        "app/services/pkgResolution",
    ],
    function(angular, LOCALE, _) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("profile",
            [ "$scope", "$timeout", "$location", "$uibModal", "ea4Data", "ea4Util", "alertService", "growl", "growlMessages",
                function($scope, $timeout, $location, $uibModal, ea4Data, ea4Util, alertService, growl, growlMessages) {
                    $scope.profileList = [];
                    $scope.activeProfile = {};
                    $scope.loadingProfiles = false;
                    $scope.errorOccurred = false;
                    $scope.noProfiles = false;
                    $scope.upload = {
                        show: false,
                        profile: {},
                        content: {},
                        disableLocalSec: true,
                        localSecIsOpen: true,
                        disableUrlSec: false,
                        urlSecIsOpen: false,
                        url: {
                            value: "",
                            filename: "",
                            filenameValMsg: "",
                            showFilenameInput: false,
                        },
                        overwrite: false,
                        highlightOverwrite: false,
                    };
                    $scope.convertProfile = { show: false };

                    var _ea4Recommendations = {};

                    $scope.isLoading = function() {
                        return ( $scope.loadingProfiles || $scope.loadingProfileData );
                    };

                    var resetEA4UI = function() {

                        // Reset wizard attributes.
                        // TODO: This will stay here until ui.router is implemented
                        // in the next template refactor.
                        $scope.customize.wizard.currentStep = "";
                        $scope.customize.wizard.showWizard = false;

                        alertService.clear();

                        // This cancels any previously customized packages.
                        ea4Data.clearEA4LocalStorageItems();
                    };

                    var customizeProfile = function(thisProfile) {

                        // This cancels any previously customized packages.
                        ea4Data.clearEA4LocalStorageItems();
                        ea4Data.setData(
                            {
                                "selectedPkgs": thisProfile.pkgs,
                                "customize": true,
                                "ea4Recommendations": _ea4Recommendations,
                            });
                        $location.path("loadPackages");
                    };

                    var goProvision = function(thisProfile) {
                        ea4Data.setData( { "selectedProfile": thisProfile } );
                        $location.path("review");
                    };

                    $scope.$on("$viewContentLoaded", function() {
                        resetEA4UI();
                        $scope.loadProfiles();
                    });

                    $scope.checkForEA4Updates = function() {
                        $scope.customize.checkUpdateInfo = angular.copy(ea4Util.checkUpdateInfo);
                        var promise = ea4Data.getPkgInfoList();
                        promise.then(function(data) {
                            if (typeof data !== "undefined") {
                                var rawPkgList = data;
                                ea4Data.setData({ "ea4RawPkgList": rawPkgList });
                                var updatePkgs = _.map(_.filter(rawPkgList, ["state", "updatable"]), function(pkg) {
                                    return pkg.package;
                                });

                                // Count the number of packages in updatable state.
                                $scope.customize.checkUpdateInfo.pkgNumber = updatePkgs.length;
                                $scope.customize.toggleUpdateButton();
                            }
                            $scope.customize.checkUpdateInfo.isLoading = false;
                        }, function(error) {
                            alertService.add({
                                type: "danger",
                                message: error,
                                id: "alertMessages",
                                closeable: false,
                            });
                        });
                    };

                    $scope.loadProfiles = function() {
                        $scope.profileList = [];
                        $scope.loadingProfiles = true;
                        ea4Data.getProfiles().then(function(profData) {
                            if (typeof profData !== "undefined") {

                                $scope.noProfiles = false;
                                $scope.checkForEA4Updates();
                                $scope.loadingProfileData = true;
                                ea4Data.getEA4Recommendations().
                                    then(function(result) {
                                        _ea4Recommendations = result.data;
                                        setProfileData(profData, _ea4Recommendations); // eslint-disable-line no-use-before-define
                                    }, function(error) {
                                        showProfileErrors(error);
                                    }).finally(function() {
                                        $scope.loadingProfileData = false;
                                    });
                            } else {
                                $scope.noProfiles = true;
                            }
                        }, function(error) {
                            if (error) {
                                $scope.errorOccurred = true;
                                ea4Data.setData( { "ea4ThrewError": true } );
                                $location.path("yumUpdate");
                            }
                        }).finally(function() {
                            $scope.loadingProfiles = false;
                        });
                    };

                    $scope.viewProfile = function(thisProfile) {
                        var viewingProfile = angular.copy(thisProfile);
                        $uibModal.open({
                            templateUrl: "profileModalContent.tmpl",
                            controller: "ModalInstanceCtrl",
                            resolve: {
                                data: function() {
                                    return viewingProfile;
                                },
                            },
                        });
                    };

                    $scope.customizeCurrentProfile = function(thisProfile) {
                        customizeProfile(thisProfile);
                    };

                    $scope.proceedNext = function(thisProfile, customize) {

                        // Track if customize button clicked or provision button clicked.
                        $scope.clickedCustomize = customize;

                        // Show a warning if there are packages in profile not on server.
                        if (!thisProfile.isValid) {
                            thisProfile.showValidationWarning = true;
                            return;
                        }

                        thisProfile.showValidationWarning = false;
                        $scope.continueAction(thisProfile);
                    };

                    $scope.continueAction = function(thisProfile) {
                        var customize = $scope.clickedCustomize;

                        // Reset the clicked variable for next use.
                        $scope.clickedCustomize = false;

                        // Insert Apache 2.4 into the profile. This ensures people
                        // get apache in whatever state their profile is.
                        if (thisProfile.pkgs.indexOf("ea-apache24") === -1) {
                            thisProfile.pkgs.push("ea-apache24");
                        }

                        if (customize) {
                            customizeProfile(thisProfile);
                        } else {
                            goProvision(thisProfile);
                        }
                    };

                    /**
                     * Resets the clicked variable for next use.
                     *
                     * @method reset
                     */
                    $scope.reset = function(thisProfile) {
                        $scope.clickedCustomize = false;
                        thisProfile.showValidationWarning = false;
                    };

                    $scope.hideRecommendations = function(activeProfile) {
                        activeProfile.showRecommendations = false;

                        // Upon closing recommendation panel, return focus to recommendation link for screenreader/keyboard users
                        $timeout(function() {
                            angular.element("#toggleRecommendations").focus();
                        });
                    };

                    $scope.showRecommendations = function(activeProfile) {
                        activeProfile.showRecommendations = true;

                        // Apply focus to recommendation container for screenreader/keyboard users
                        $timeout(function() {
                            angular.element("#recommendations_container").focus();
                        });
                    };

                    var recommendationsOfActiveProfile = function(activeProfile, recommendations) {
                        var currPkgList = activeProfile.pkgs;
                        var filterPkgsWithRecos = _.intersection(currPkgList, _.keys(recommendations));
                        var filteredRecos = {};
                        _.each(filterPkgsWithRecos, function(pkg) {
                            var reco = recommendations[pkg];
                            var recosList = ea4Util.decideShowHideRecommendations(reco, currPkgList, true, pkg);  // passing 'true' as args to get recommendations of installed packages.
                            // On the profiles page show only recommendations that have level: danger.
                            recosList = _.filter(recosList, ["level", "danger"]);
                            if (!_.isEmpty(recosList)) {
                                filteredRecos[pkg] = {};
                                filteredRecos[pkg].recosList = recosList;
                                filteredRecos[pkg].show = !_.every(recosList, [ "show", false ]);

                                // Set the footnote.
                                filteredRecos[pkg].footNote = LOCALE.maketext("These recommendations appear because you have “[_1]” installed on your system.", pkg);
                            }
                        });

                        return filteredRecos;
                    };

                    /* Upload Popover section */
                    var resetValidators = function(formInput) {
                        var valErrors = formInput.$error;
                        if (typeof valErrors !== "undefined") {
                            _.each(_.keys(valErrors), function(valKey) {
                                $scope.formUpload.profile_file.$setValidity(valKey, true);
                            });
                        }
                    };

                    /**
                     * Clears everything in the upload popover.
                     *
                     * @method clearUploadPopover
                     */
                    var clearUploadPopover = function() {

                        // Destroy all growls before attempting to submit something.
                        growlMessages.destroyAllMessages();

                        // reseting model values
                        var uploadData = $scope.upload;
                        uploadData.content = {};
                        uploadData.overwrite = false;
                        uploadData.highlightOverwrite = false;
                        uploadData.disableLocalSec = true;
                        uploadData.localSecIsOpen = true;
                        uploadData.disableUrlSec = false;
                        uploadData.urlSecIsOpen = false;

                        clearUploadLocalForm($scope.upload);
                        clearUploadUrlForm($scope.upload.url);
                    };

                    /**
                     * Clears the upload local section in Upload accordion.
                     *
                     * @method clearUploadLocalForm
                     */
                    var clearUploadLocalForm = function(uploadData) {

                        // reseting upload local section.
                        uploadData.profile = {};

                        if ($scope.formUpload && $scope.formUpload.$dirty) {
                            resetValidators($scope.formUpload.profile_file);

                            // mark the form pristine
                            $scope.formUpload.$setPristine();

                            try {
                                angular.element("#profile_file").val(null); // for IE11, latest browsers
                            } catch (error) {

                                // For IE10 and others
                                angular.element("#form_upload_profile").reset();
                            }
                        }
                    };

                    /**
                     * Clears the upload url section in Upload accordion.
                     *
                     * @method clearUploadUrlForm
                     */
                    var clearUploadUrlForm = function(uploadUrlData) {

                        // var uploadData = $scope.upload;
                        uploadUrlData.filename = "";
                        uploadUrlData.filenameValMsg = "";
                        uploadUrlData.value = "";
                        uploadUrlData.showFilenameInput = false;

                        if ($scope.formUpload && $scope.formUpload.$dirty) {
                            var valErrors = $scope.formUpload.profile_file_url.$error;
                            if (typeof valErrors !== "undefined") {
                                _.each(_.keys(valErrors), function(valKey) {
                                    $scope.formUpload.profile_file.$setValidity(valKey, true);
                                });
                            }
                            resetValidators($scope.formUpload.profile_file_url);
                            resetValidators($scope.formUpload.txtUploadUrlFilename);

                            // mark the form pristine
                            $scope.formUpload.$setPristine();
                        }
                    };

                    /**
                     * Validates the profile content to
                     * check if it contains name & at least
                     * one package.
                     *
                     * @method validateProfile
                     */
                    var validateProfile = function(fileContent) {
                        var valid = true;
                        if (_.isEmpty(fileContent.name) ||
                            _.isEmpty(fileContent.pkgs)) {
                            valid = false;
                        }
                        return valid;
                    };

                    /**
                     * Validate the uploaded filename to see if it contains
                     * restricted characters.
                     *
                     * @method validateFilename
                     */
                    var validateFilename = function(filename) {
                        var valid = true;
                        if (/(?:\.\.|\\|\/)/.test(filename)) {
                            valid = false;
                        }
                        return valid;
                    };

                    /**
                     * Reads the uploaded file to validate it.
                     *
                     * @method getAndValidateUploadData
                     */
                    var getAndValidateUploadData = function() {

                        // Destroy all growls before attempting to submit something.
                        growlMessages.destroyAllMessages();

                        var fileData = $scope.upload.profile;
                        if (!validateFilename(fileData.name)) {
                            $scope.$apply($scope.formUpload.profile_file.$setValidity("invalidfilename", false));
                            return;
                        } else {
                            $scope.$apply($scope.formUpload.profile_file.$setValidity("invalidfilename", true));
                        }
                        var reader = new FileReader();
                        reader.readAsText(fileData);
                        reader.onloadend = function() {
                            if (reader.readyState && !reader.error) {

                                // Check if the file has the required data.
                                var upContent = validateUploadContent(reader.result);
                                _.each(_.keys(upContent.val_results), function(val_key) {
                                    $scope.$apply($scope.formUpload.profile_file.$setValidity(val_key, upContent.val_results[val_key]));
                                });
                                if ($scope.formUpload.profile_file_url.$valid) {
                                    $scope.upload.content = upContent.content;
                                }
                            }
                        };
                    };

                    /**
                     * This validates the given content
                     * and updates the validators accordingly.
                     *
                     * @method validateUploadContent
                     */
                    var validateUploadContent = function(uploadContent) {

                        // Check if the file has the required data.
                        var content = "";
                        var valResults = {};
                        try {
                            content = JSON.parse(uploadContent);
                            valResults["invalidformat"] = true;
                            if (!validateProfile(content)) {
                                valResults["content"] = false;
                            } else {
                                valResults["content"] = true;
                            }
                        } catch (e) {
                            valResults["invalidformat"] = false;
                            console.log(e);
                        }
                        return { "content": content, "val_results": valResults };
                    };

                    /**
                     * Cancels the upload action for local section.
                     *
                     * @method cancelUpload
                     */
                    $scope.cancelUpload = function() {
                        $scope.upload.show = false;
                        clearUploadPopover();
                    };

                    /**
                     * Cancels the upload action for url section.
                     *
                     * @method resetUploadUrl
                     */
                    $scope.resetUploadUrl = function() {
                        clearUploadUrlForm($scope.upload.url);
                    };

                    /**
                     * Gets the content from the provided url and performs
                     * validation checks to make sure it is a valid JSON
                     * content with valid profile data.
                     *
                     * @method getAndValidateUploadDataFromURL
                     */
                    $scope.getAndValidateUploadDataFromURL = function() {

                        // Destroy all growls before attempting to submit something.
                        growlMessages.destroyAllMessages();

                        return ea4Data.getUploadContentFromUrl($scope.upload.url.value)
                            .then(function(data) {
                                if (typeof data !== "undefined" && data.status === "200") {
                                    var contentType = data.headers["content-type"];
                                    var validType = /^(application|text)\/json/.test(contentType);
                                    if (!validType) {
                                        $scope.formUpload.profile_file_url.$setValidity("filetype", false);
                                        return;
                                    }  else {
                                        $scope.formUpload.profile_file_url.$setValidity("filetype", true);
                                    }

                                    // Check if the file has the required data.
                                    var upContent = validateUploadContent(data.content);
                                    _.each(_.keys(upContent.val_results), function(val_key) {
                                        $scope.formUpload.profile_file_url.$setValidity(val_key, upContent.val_results[val_key]);
                                    });
                                    if ($scope.formUpload.profile_file_url.$valid) {
                                        $scope.upload.content = upContent.content;
                                        $scope.upload.url.showFilenameInput = true;
                                    } else {
                                        $scope.upload.url.showFilenameInput = false;
                                    }
                                } else {
                                    var errorMsg = LOCALE.maketext("Status: “[output,strong,_1]”. Reason: “[output,em,_2]”.", _.escape(data.status), _.escape(data.reason));
                                    growl.error(errorMsg);
                                }
                            }, function(error) {
                                growl.error(_.escape(error));
                            });
                    };

                    /**
                     * Scope method that calls ea4Util service's validateFilename method and
                     * sets the validation message accordingly.
                     *
                     * @method validateFilenameInput
                     */
                    $scope.validateFilenameInput = function() {
                        var valData = ea4Util.validateFilename($scope.upload.url.filename);
                        $scope.upload.url.filenameValMsg = valData.valMsg;
                        $scope.formUpload.txtUploadUrlFilename.$setValidity("valFilename", valData.valid);
                    };

                    /**
                     * Uploads Profiles.
                     *
                     * @method uploadProfile
                     */
                    $scope.uploadProfile = function() {

                        // Destroy all growls before attempting to submit something.
                        growlMessages.destroyAllMessages();

                        if ($scope.formUpload.$valid) {

                            // upload profile
                            var overwrite = $scope.upload.overwrite ? 1 : 0;
                            var filenameWithExt = (typeof $scope.upload.profile.name !== "undefined") ? $scope.upload.profile.name : $scope.upload.url.filename + ".json";
                            return ea4Data.saveAsNewProfile($scope.upload.content, filenameWithExt, overwrite)
                                .then(function(data) {
                                    if (typeof data !== "undefined" && !_.isEmpty(data.path)) {
                                        $scope.loadProfiles();
                                        growl.success(LOCALE.maketext("The system successfully uploaded your profile."));
                                        $scope.cancelUpload();
                                    }
                                }, function(response) {
                                    if (!_.isEmpty(response.data) && response.data.already_exists) {
                                        $scope.upload.highlightOverwrite = true;
                                    }
                                    growl.error(_.escape(response.error));
                                });
                        }
                    };

                    /**
                     * This toggle function handles enabling/disabling sections
                     * so that at least one upload section is always open.
                     *
                     * @method handleAccordionToggle
                     */
                    $scope.handleAccordionToggle = function() {
                        clearUploadLocalForm($scope.upload);
                        clearUploadUrlForm($scope.upload.url);
                        if ($scope.upload.urlSecIsOpen) {
                            $scope.upload.disableLocalSec = false;
                            $scope.upload.disableUrlSec = true;
                        } else {
                            $scope.upload.disableUrlSec = false;
                            $scope.upload.disableLocalSec = true;
                        }
                    };

                    /**
                     * Shows the given popover with their initialization logic.
                     *
                     * @method showPopover
                     */
                    $scope.showPopover = function(popoverName) {
                        $scope.convertProfile.cancel();
                        switch (popoverName) {
                            case "upload":
                                $scope.upload.show = true;
                                document.querySelector("#profile_file").onchange = getAndValidateUploadData;

                                var accordionLinkEls = document.querySelectorAll(".panel-heading a");
                                _.each(accordionLinkEls, function(el) {
                                    el.onclick = $scope.handleAccordionToggle;
                                });
                                break;
                            case "convert":
                                $scope.convertProfile.show = true;
                                break;
                        }
                    };

                    /**
                     * This method sets all the profile data including recommendations.
                     *
                     * @method setProfileData
                     */
                    var setProfileData = function(data, recommendations) {
                        var profileTypes = _.sortBy(_.keys(data));
                        _.each(profileTypes, function(type) {
                            if (typeof data[type] !== "undefined") {
                                _.each(data[type], function(profile) {
                                    profile.profileType = type;
                                    profile.tagsAsString = LOCALE.list_and(profile.tags);

                                    // Initialize with a valid flag.
                                    profile.isValid = true;
                                    profile.showValidationWarning = false;
                                    if (!profile.active) {     // Active profile is shown separately.
                                        profile.isValid = _.isEmpty(profile.validation_data.not_on_server);
                                        if (!profile.isValid) {
                                            profile.validation_data.not_on_server_without_prefix = ea4Util.getFormattedPackageList(profile.validation_data.not_on_server);
                                        }
                                        profile.id = type + "_" + profile.path.replace(/\.json/, "");

                                        // If the type is other than cPanel Or Custom, it should be a vendor in which case the
                                        // path changes a bit.
                                        var pathByType = ( type !== "cpanel" && type !== "custom" ) ? "vendor/" + type : type;
                                        profile.downloadUrl = "ea4_profile_download/" + pathByType + "?filename=" + profile.path;
                                        $scope.profileList.push(profile);
                                    } else {
                                        $scope.activeProfile = profile;

                                        // need active profile packages in customize scope so can run packages updates
                                        $scope.customize.activeProfilePkgs = profile.pkgs;

                                        var recos = recommendationsOfActiveProfile($scope.activeProfile, recommendations);
                                        if (!_.isEmpty(_.keys(recos))) {
                                            $scope.activeProfile.showRecommendations = false;

                                            var actual_recos = _.pickBy(recos, function(value, key) {
                                                return recos[key].show;
                                            });
                                            var recoCnt = 0;
                                            _.each(_.keys(actual_recos), function(key) {
                                                recoCnt += _.filter(actual_recos[key].recosList, ["show", true]).length;
                                            } );
                                            $scope.activeProfile.recommendations = actual_recos;
                                            $scope.activeProfile.recommendationLabel = LOCALE.maketext("[quant,_1,Recommendation,Recommendations]", recoCnt);
                                            $scope.activeProfile.recommendationsExist = recoCnt ? true : false;
                                        } else {
                                            $scope.activeProfile.recommendations = {};
                                        }
                                    }
                                });
                            }
                        });

                        // Check if there are any profiles.
                        $scope.noProfiles = ($scope.profileList.length <= 0);

                        // Active Profile. At present active profile will always be 'Currently Installed Packages'
                        // This may change in future.
                        // TODO: Add this method to ea4Util
                        var tags = ea4Util.createTagsForActiveProfile($scope.activeProfile.pkgs);
                        $scope.activeProfile.tags = tags;
                        $scope.activeProfile.tagsAsString = LOCALE.list_and(tags);
                    };

                    /**
                     * Error handling method for profile load failures.
                     *
                     * @method showProfileErrors
                     */
                    var showProfileErrors = function(error) {
                        $scope.errorOccurred = true;
                        alertService.add({
                            type: "danger",
                            message: error,
                            id: "alertMessages",
                            closeable: false,
                        });
                    };
                },
            ]
        );

        app.controller("ModalInstanceCtrl",
            ["$scope", "$uibModalInstance", "data", "ea4Util",
                function($scope, $uibModalInstance, data, ea4Util) {
                    $scope.modalData = {};
                    var profileInfo = data;
                    profileInfo.pkgs = ea4Util.getProfilePackagesByCategories(profileInfo.pkgs);
                    $scope.modalData = profileInfo;

                    $scope.closeModal = function() {
                        $uibModalInstance.close();
                    };
                },
            ]
        );
    }
);
