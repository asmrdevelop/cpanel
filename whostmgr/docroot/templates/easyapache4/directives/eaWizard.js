/*
# cpanel - whostmgr/docroot/templates/easyapache4/directives/eaWizard.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [
        "angular",
        "cjt/core",
        "lodash",
        "cjt/util/locale",
        "cjt/filters/qaSafeIDFilter",
        "app/services/ea4Data",
        "app/services/ea4Util",
    ],
    function(angular, CJT, _, LOCALE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        app.directive("eaWizard",
            [ "$timeout", "ea4Data", "ea4Util", "wizardApi", "pkgResolution",
                function($timeout, ea4Data, ea4Util, wizardApi, pkgResolution) {
                    var TEMPLATE_PATH = "directives/eaWizard.ptt";
                    var RELATIVE_PATH = "templates/easyapache4/" + TEMPLATE_PATH;

                    var ddo = {
                        replace: true,
                        restrict: "E",
                        templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,
                        scope: {
                            idPrefix: "@",
                            totalPackageInfoList: "=",
                            selectedPackages: "=",
                            metaData: "=",
                            stepName: "@",
                            stepIndex: "@",
                            stepTitle: "@",
                            stepPath: "@",
                            stepNext: "@",
                            onToggleFn: "&",
                            showSearch: "@",
                            showPagination: "@",
                        },
                        link: function postLink(scope, element, attrs) {
                            var continueResolvingDeps = function(thisPackage) {
                                thisPackage.multiRequirements.exist = false;
                                var chosenPkgName = thisPackage.multiRequirements.chosenPackage;
                                var data = pkgResolution.continueResolvingDependencies(thisPackage, scope.totalPackageInfoList[chosenPkgName], chosenPkgName, scope.totalPackageInfoList, scope.selectedPackages);

                                // Check if orListStructure exists. If yes - Do setup multireq view.
                                if (data.orListExist) {
                                    thisPackage.multiRequirements = pkgResolution.setupMultiRequirementForUserInput(scope.totalPackageInfoList);

                                    // return false since resolving dependencies is not yet complete.
                                    return false;
                                } else if (data.actionNeeded) {

                                    // If not orlist, check if action is needed. If yes - setup conflict/resolution alert view.

                                    thisPackage = pkgResolution.setupConDepCallout(thisPackage, scope.totalPackageInfoList);

                                    // return false since resolving dependencies is not yet complete.
                                    return false;
                                } else {  // If not orlist OR action needed, call apply dependency.

                                    // Since no action is needed it is simply assumed that there are no conflicts
                                    // and all dependencies can be added without any harm.
                                    return scope.applyDependency(thisPackage);
                                }
                            };

                            /**
                            * Get required PHP extensions for a currently selected PHP version.
                            *
                            * @method getAllRequiredPhpExtensions
                            * @param {string} pkgName - PHP version package name
                            * @return {Array} reqPkgs - A list of required extensions.
                            */
                            var getAllRequiredPhpExtensions = function(pkgName) {
                                var reqPkgs = [];
                                var allDeps = pkgResolution.getAllDepsRecursively(true, scope.totalPackageInfoList[pkgName], pkgName, scope.totalPackageInfoList, scope.selectedPackages);
                                if (allDeps) {
                                    reqPkgs = ea4Util.getExtensionsForPHPVersion(pkgName, allDeps.requiredPkgs);
                                }
                                return reqPkgs;
                            };

                            /**
                            * Get common PHP extensions that can be auto selected for a currently selected PHP version.
                            *
                            * @method getAutoSelectPhpExtensions
                            * @param {string} package - PHP version package name
                            * @return {Array} autoSelectExtList - A list of auto select extensions.
                            */
                            var getAutoSelectPhpExtensions = function(thisPackage) {
                                var autoSelectExtList = [];
                                var extList = scope.php.commonExtensions;
                                extList = _.map(extList, function(ext) {
                                    return thisPackage + "-" + ext;
                                });

                                var requiredExtensions = getAllRequiredPhpExtensions(thisPackage);

                                // Check if the common extensions are actually available for the newly selected PHP version.
                                // only returns the extensions that are NOT required.
                                extList = _.filter(extList, function(ext) {
                                    var extension = scope.totalPackageInfoList[ext];
                                    var notRequired = false;
                                    if (typeof extension !== "undefined" && !_.includes(requiredExtensions, ext)) {
                                        notRequired = true;
                                    }
                                    return notRequired;
                                });

                                // Load the common extensions into the view model.
                                autoSelectExtList = _.map(extList, function(ext) {
                                    var displayName = ea4Util.getFormattedPackageName(ext);

                                    return {
                                        package: ext,
                                        displayName: displayName,
                                        isSelected: true,
                                    };
                                });

                                return autoSelectExtList;
                            };

                            var formatPhpVersionForDisplay = function(ver) {
                                var phpMatch = ver.match(ea4Util.phpVerRegex);
                                var formatted = "";
                                if (phpMatch) {
                                    var phpVersion = phpMatch[1];
                                    formatted = "PHP " + phpVersion.replace(/(\d)(\d)$/, "$1.$2");
                                }
                                return formatted;
                            };

                            /**
                            * Updates PHP package accordingly when selected/unselected. Details below:
                            *   For PHP just calling eaWizard.checkDependency isn't enough when
                            *   a PHP version package is unselected. There are some PHP specific stuff
                            *   that are needed to be done.
                            *   1. Find if there are any vhosts that are using the PHP version being uninstalled
                            *      and warn the user about that.
                            *   2. If all dependencies are resolved and everything is ok, then just remove all
                            *      extensions of the PHP version being uninstalled as well.
                            *   This method takes care of that.
                            *
                            * @method updatePHP
                            * @param {object} thisPackage The package info object of PHP version.
                            */
                            var updatePHP = function(thisPackage) {

                                // The state of the selectedPackage is not toggled by default
                                // by the toggle-switch directive. That is for now explicitly
                                // done by common function eaWizard.checkDependency called by all EA4 templates.
                                // Since in this template we need to do some vhost checks even before calling that
                                // function the state is toggled temporarily. This is a nasty hack but will be there
                                // until toggle-switch directive is fixed to toggle the ng-model's state correctly
                                // before firing on-toggle event.
                                var selectedState = !thisPackage.selectedPackage;
                                var version = thisPackage.package;
                                if (!selectedState) {

                                    // Find vhosts if any that are using this PHP version.
                                    var vhostsCount = 0;
                                    ea4Data.getVhostsByPhpVersion(version).then(function(data) {
                                        if (typeof data !== "undefined") {
                                            vhostsCount = data.length;
                                        }

                                        if (vhostsCount > 0) {
                                            thisPackage = ea4Util.setupVhostWarning(thisPackage, vhostsCount);
                                            return;
                                        }

                                        var isComplete = scope.checkDependency(thisPackage);
                                        if (isComplete) {
                                            scope.php.updatePHPExtensionList(thisPackage);
                                        }
                                    }, function(error) {

                                        // Do nothing.
                                    });
                                    thisPackage.autoSelectExt = angular.copy(ea4Util.autoSelectExt);
                                } else {
                                    scope.checkDependency(thisPackage);
                                    if (thisPackage.selectedPackage) {
                                        thisPackage.autoSelectExt = angular.copy(ea4Util.autoSelectExt);
                                        thisPackage.autoSelectExt.list = getAutoSelectPhpExtensions(thisPackage.package);
                                        var extCount = thisPackage.autoSelectExt.list.length;
                                        thisPackage.autoSelectExt.text = LOCALE.maketext("In addition to the dependencies that this version of [asis,PHP] requires, the system detected [quant,_1,extension,extensions] of all other installed PHP versions that it will install for this version.", extCount);
                                        var displayVersion = formatPhpVersionForDisplay(version);
                                        thisPackage.autoSelectExt.okText = LOCALE.maketext("[_1][comment,package name] and Extensions[comment,action text]", displayVersion);
                                        thisPackage.autoSelectExt.cancelText = LOCALE.maketext("[_1][comment,package name] Only[comment,action text]", displayVersion);
                                        thisPackage.autoSelectExt.show = (extCount > 0 && !thisPackage.actions.actionNeeded) ? true : false;
                                    }
                                }
                            };

                            /**
                            * Final part of updating a PHP version select/unselect action.
                            *
                            * @method finishUpdatePHP
                            * @param {object} thisPackage The package info object of PHP version.
                            */
                            var finishUpdatePHP = function(thisPackage) {

                                // When uninstall make sure to remove all corresponding extensions.
                                if (!thisPackage.selectedPackage) {
                                    var isComplete = scope.applyDependency(thisPackage);
                                    if (isComplete) {
                                        scope.php.updatePHPExtensionList(thisPackage);
                                    }
                                } else {
                                    scope.applyDependency(thisPackage);
                                    scope.php.autoSelectExtList = getAutoSelectPhpExtensions(thisPackage.package);
                                    thisPackage.autoSelectExt.show = (thisPackage.autoSelectExt.list.length > 0 && !thisPackage.actions.actionNeeded) ? true : false;
                                }
                            };

                            /**
                            * Continues to resolve dependencies after the user decides to continue.
                            *
                            * @method continueResolvingDeps
                            * @param {object} thisPackage The package info object of PHP version.
                            */
                            var continueResolvingDepsForPhp = function(thisPackage) {

                                // When uninstall make sure to remove all corresponding extensions.
                                if (!thisPackage.selectedPackage) {
                                    var isComplete = continueResolvingDeps(thisPackage);
                                    if (isComplete) {
                                        scope.php.updatePHPExtensionList(thisPackage);
                                    }
                                } else {
                                    continueResolvingDeps(thisPackage);
                                }
                            };

                            /** ***************
                             * SCOPE STUFF
                             *****************/
                            scope.php = {
                                commonExtensions: [],

                                /**
                                * Updates PHP Extension list by removing all extensions of the PHP version
                                * that is being uninstalled.
                                *
                                * @method updatePHPExtensionList
                                * @param {object} thisPackage The package object of PHP version being uninstalled.
                                */
                                updatePHPExtensionList: function(thisPackage) {
                                    if (!thisPackage.selectedPackage) {
                                        var list = ea4Util.getExtensionsForPHPVersion(thisPackage.package, scope.selectedPackages);
                                        _.each(list, function(pkg) {
                                            if (typeof scope.totalPackageInfoList[pkg] !== "undefined") {
                                                scope.totalPackageInfoList[pkg].selectedPackage = false;
                                            }
                                            _.pull(scope.selectedPackages, pkg);
                                        });
                                    }
                                },

                                /**
                                * Continues to check for dependencies after the user acknowledges the vhost warning and
                                * continues to uninstall a PHP version.
                                *
                                * @method continueCheckDependency
                                * @param {object} thisPackage The package info object of PHP version.
                                */
                                continueCheckDependency: function(thisPackage) {

                                    // If you come to this point, the vhost warning is already acknowledged
                                    // by now and it is safe to assume that necessary steps are taken.
                                    ea4Util.resetVhostWarning(thisPackage);

                                    var isComplete = scope.checkDependency(thisPackage);
                                    if (!thisPackage.selectedPackage && isComplete) {
                                        scope.php.updatePHPExtensionList(thisPackage);
                                    }
                                },

                                /**
                                * Reset the vhost warning object when select/unselect of a PHP version is canceled
                                *
                                * @method resetVhostWarning
                                * @param {object} thisPackage The package info object of PHP version.
                                */
                                resetVhostWarning: function(thisPackage) {
                                    return ea4Util.resetVhostWarning(thisPackage);
                                },
                            };

                            scope.extensions = {
                                _extToConsider: [],
                                _extensionList: {},
                                noPHPSelected: false,
                                filterPHPExtensions: function() {
                                    var phpVersions = scope.phpVersions;
                                    var showList = [];
                                    _.each(phpVersions, function(ver) {
                                        if (ver.selected) {
                                            var testString = new RegExp(ver.version + ".*", "i");
                                            var list = _.filter(scope.extensions._extToConsider, function(name) {
                                                return testString.test(name);
                                            });
                                            showList = _.union(showList, list);
                                        }
                                    });
                                    scope.currPkgInfoList = _.pick(scope.extensions._extensionList, showList);
                                    scope.applyMetaData();
                                },
                                showPhpFilterTags: function() {
                                    return (scope.stepName === "extensions" && !_.isEmpty(scope.extensions._extensionList));
                                },
                            };

                            scope.toggleLabel = function(thisPackage) {
                                return ea4Util.getPackageLabel(thisPackage.selectedPackage, thisPackage.state);
                            };

                            scope.packageClass = function(thisPackage) {
                                return ea4Util.getPackageClass(thisPackage.selectedPackage, thisPackage.state);
                            };

                            scope.applyDependency = function(thisPackage) {
                                var pkgName = thisPackage.package;
                                var selectedPackages = scope.selectedPackages;
                                var resData = pkgResolution.getResolvedData();

                                // At least 1 MPM package should be in the selected list
                                // Check for it everytime an MPM package is removed/uninstalled.
                                // Show a callout if there is no MPM in selected pkgs.
                                thisPackage.mpmMissing = false;
                                thisPackage.mpmMissingMsg = "";
                                if (thisPackage.actions.actionNeeded) {
                                    thisPackage = ea4Util.checkMPMRequirement(thisPackage, resData, selectedPackages, thisPackage.selectedPackage);
                                    if (thisPackage.mpmMissing) {
                                        return false;
                                    }

                                }

                                // Apply the actions
                                // 1. removeList must be pulled out of selected package list.
                                _.each(resData.removeList, function(conflict) {
                                    _.pull(selectedPackages, conflict);
                                    if ( typeof scope.totalPackageInfoList[conflict] !== "undefined" ) {
                                        scope.totalPackageInfoList[conflict].selectedPackage = false;
                                    }
                                });

                                // 2. addList must be added into selected package list.
                                _.each(resData.addList, function(dep) {
                                    selectedPackages = _.concat(selectedPackages, dep);
                                    if ( typeof scope.totalPackageInfoList[dep] !== "undefined" ) {
                                        scope.totalPackageInfoList[dep].selectedPackage = true;
                                    }
                                });

                                if (!thisPackage.selectedPackage) {
                                    _.pull(selectedPackages, pkgName);
                                    if ( typeof scope.totalPackageInfoList[pkgName] !== "undefined" ) {
                                        scope.totalPackageInfoList[pkgName].selectedPackage = false;
                                    }
                                }

                                // Finally set the current profile's pkgs.
                                scope.selectedPackages = selectedPackages;
                                thisPackage = pkgResolution.resetPkgResolveActions(thisPackage);

                                ea4Data.setData( { "pkgInfoList": scope.totalPackageInfoList } );

                                // Return true if everything is complete.
                                return true;
                            };

                            scope.checkDependency = function(thisPackage) {
                                var selected = false;
                                var pkgName = thisPackage.package;
                                var selectedPackages = scope.selectedPackages;

                                // REFACTOR: This needs to be re arranged (please see the comment in ea4Data.resetcommonvariables method)
                                thisPackage.actions = { removeList: [], addList: [], actionNeeded: false };

                                // Toggle the status of the package selection.
                                thisPackage.selectedPackage = scope.totalPackageInfoList[pkgName].selectedPackage = selected = !thisPackage.selectedPackage;

                                thisPackage.recommendations = ea4Util.decideShowHideRecommendations(thisPackage.recommendations, scope.selectedPackages, selected, pkgName);
                                thisPackage.showRecommendations = !_.every(thisPackage.recommendations, [ "show", false ]);

                                if (selected) {
                                    var data = pkgResolution.resolveDependenciesWhenSelected(thisPackage, selectedPackages, scope.totalPackageInfoList);

                                    // Check if orListStructure exists. If yes - Do setup multireq view.
                                    if (data.orListExist) {
                                        thisPackage.multiRequirements = pkgResolution.setupMultiRequirementForUserInput(scope.totalPackageInfoList);

                                        // return false since resolving dependencies is not yet complete.
                                        return false;
                                    } else if (data.actionNeeded) {

                                        // If not orlist, check if action is needed. If yes - setup conflict/resolution alert view.
                                        thisPackage = pkgResolution.setupConDepCallout(thisPackage, scope.totalPackageInfoList);

                                        // return false since resolving dependencies is not yet complete.
                                        return false;
                                    } else {

                                        // If not orlist OR action needed, call apply dependency.
                                        if (thisPackage.showRecommendations) {
                                            thisPackage.actions.actionNeeded = true;
                                            return false;
                                        } else {

                                            // Since no action is needed it is simply assumed that there are no conflicts
                                            // and all dependencies can be added without any harm.
                                            return scope.applyDependency(thisPackage);
                                        }
                                    }
                                } else {
                                    pkgResolution.resolveDependenciesWhenUnSelected(thisPackage, selectedPackages, scope.totalPackageInfoList);
                                    if (thisPackage.showRecommendations) {
                                        thisPackage.actions.actionNeeded = true;
                                        return false;
                                    } else {
                                        thisPackage.mpmMissing = false;
                                        thisPackage.mpmMissingMsg = "";
                                        var resData = pkgResolution.getResolvedData();
                                        thisPackage = ea4Util.checkMPMRequirement(thisPackage, resData, selectedPackages, selected);
                                        if (thisPackage.mpmMissing) {
                                            return false;
                                        } else {
                                            return scope.applyDependency(thisPackage);
                                        }
                                    }
                                }
                            };

                            scope.applyMetaData = function() {
                                scope.metaData = ea4Util.getUpdatedMetaData(scope.currPkgInfoList, scope.metaData);
                            };

                            scope.getShowingText = function() {
                                return ea4Util.getPageShowingText(scope.metaData);
                            };

                            scope.showSearchPageSection = function() {
                                if (scope.stepName === "extensions") {
                                    return (scope.stepName === "extensions" && !scope.extensions.noPHPSelected);
                                } else {
                                    return true;
                                }
                            };

                            scope.showEmptyMessage = function() {
                                var show = false;
                                if (scope.stepName === "extensions") {
                                    show = (!scope.extensions.noPHPSelected && scope.metaData.isEmptyList);
                                } else {
                                    show = scope.metaData.isEmptyList;
                                }
                                return show;
                            };

                            scope.showToggleSwitch = function(pkgData) {
                                if (scope.stepName === "php") {
                                    return (!pkgData.actions.actionNeeded && !pkgData.multiRequirements.exist && !pkgData.mpmMissing && !pkgData.vhostWarning.exist);
                                } else {
                                    return (!pkgData.actions.actionNeeded && !pkgData.multiRequirements.exist && !pkgData.mpmMissing);
                                }
                            };

                            scope.initializeSelection = function(pkgData) {
                                if (scope.stepName === "php") {
                                    updatePHP(pkgData);
                                } else {
                                    scope.checkDependency(pkgData);
                                }
                            };

                            scope.php.resetAutoSelectExtensions = function(pkgData) {
                                pkgData.autoSelectExt = angular.copy(ea4Util.autoSelectExt);
                            };

                            scope.php.performAutoSelect = function(thisPackage) {
                                var extList = _.filter(thisPackage.autoSelectExt.list, ["isSelected", true]);
                                _.each(extList, function(oExt) {
                                    var pkgName = oExt.package;
                                    var selected = true;
                                    var selectedPackages = scope.selectedPackages;
                                    var pkgData = scope.totalPackageInfoList[pkgName];
                                    pkgResolution.resetCommonVariables();

                                    // Toggle the status of the package selection.
                                    pkgData.selectedPackage = selected;
                                    var data = pkgResolution.resolveDependenciesWhenSelected(pkgData, selectedPackages, scope.totalPackageInfoList);

                                    // Check if orListStructure exists. If yes - Do setup multireq view.
                                    if (data.orListExist || data.actionNeeded) {
                                        pkgData.selectedPackage = !selected;

                                        // Record conflicted packages
                                        thisPackage.autoSelectExt.errorList.push(pkgName);
                                    } else {

                                        // Since no action is needed it is simply assumed that there are no conflicts
                                        // and all dependencies can be added without any harm.
                                        return scope.applyDependency(pkgData);
                                    }

                                });

                                if (thisPackage.autoSelectExt.errorList.length > 0) {
                                    thisPackage.autoSelectExt.showError = true;
                                } else {
                                    scope.php.resetAutoSelectExtensions(thisPackage);
                                }
                            };

                            scope.continueProcess = function(pkgData) {
                                if (scope.stepName === "php") {
                                    return continueResolvingDepsForPhp(pkgData);
                                } else {
                                    return continueResolvingDeps(pkgData);
                                }
                            };

                            scope.finalizeSelection = function(pkgData) {
                                if (scope.stepName === "php") {
                                    finishUpdatePHP(pkgData);
                                } else {
                                    scope.applyDependency(pkgData);
                                }
                            };

                            // When user is shown with a compiled list of add/remove packages,
                            // if the user chose not to proceed with the change, this method ensures nothing
                            // is changed.
                            scope.resetSelection = function(thisPackage) {
                                thisPackage.selectedPackage = !thisPackage.selectedPackage;
                                thisPackage = pkgResolution.resetPkgResolveActions(thisPackage);
                            };

                            scope.proceed = function(step) {
                                ea4Data.setData(
                                    {
                                        "pkgInfoList": scope.totalPackageInfoList,
                                        "selectedPkgs": scope.selectedPackages,
                                    }
                                );
                                wizardApi.next(step);
                            };


                            var initWizard = function() {
                                scope.showSearch = false;
                                scope.showPagination = false;
                                var thisStep = wizardApi.getStepByName(scope.stepName);
                                if (typeof thisStep !== "undefined") {
                                    scope.stepIndex = thisStep.stepIndex || -1;
                                    scope.stepPath = thisStep.path || "";
                                    scope.stepTitle = thisStep.title || "";
                                    scope.idPrefix = thisStep.name || "eaWizard";
                                    scope.stepNext = thisStep.nextStep || "";
                                }

                                scope.currPkgInfoList = ea4Data.getPkgInfoByType(scope.stepName, scope.totalPackageInfoList);
                                scope.metaData = ea4Util.getDefaultMetaData();
                                scope.applyMetaData(scope.currPkgInfoList, scope.metaData);

                                /* Set initial focus to the wizard step title. Also reset
                                focus to the new step title every time user clicks "Next".
                                This improves usability when navigating by keyboard. */
                                $timeout(function() {
                                    element.find("#wizard-step-title").focus();
                                });

                                if (scope.stepName === "extensions") {
                                    var currentPkgInfoList = scope.currPkgInfoList;

                                    var phpVersionsAndExtensions = ea4Util.getExtensionsOfSelectedPHPVersions(scope.totalPackageInfoList, currentPkgInfoList, scope.selectedPackages);
                                    scope.extensions.noPHPSelected = phpVersionsAndExtensions.noPHPSelected;
                                    scope.phpVersions = _.map(phpVersionsAndExtensions.versions, function(ver) {
                                        if (typeof scope.totalPackageInfoList[ver] !== "undefined") {
                                            return {
                                                version: scope.totalPackageInfoList[ver].package,
                                                name: scope.totalPackageInfoList[ver].displayName,
                                                selected: true,
                                            };
                                        }
                                    });
                                    scope.extensions._extToConsider = phpVersionsAndExtensions.extensions;
                                    scope.extensions._extensionList = _.pick(currentPkgInfoList, scope.extensions._extToConsider);

                                    scope.currPkgInfoList = scope.extensions._extensionList;
                                    scope.applyMetaData();
                                } else if (scope.stepName === "php") {

                                    // Find Common extensions installed on all existing PHP versions.
                                    var allPhpExtensions = ea4Data.getPkgInfoByType("extensions", scope.totalPackageInfoList);
                                    var installedPhpVersions = _.map( _.filter( scope.currPkgInfoList, function(pkgInfo) {
                                        return (pkgInfo.state !== "not_installed");
                                    } ), "package" );
                                    scope.php.commonExtensions = ea4Util.getCommonlyInstalledExtensions(allPhpExtensions, installedPhpVersions);
                                }
                            };

                            initWizard();
                        },
                    };
                    return ddo;
                },
            ]
        );
    }
);
