/*
# cpanel - whostmgr/docroot/templates/easyapache4/services/ea4Util.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "lodash",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/services/APIService",
    ],
    function(angular, LOCALE, _) {
        "use strict";

        var app = angular.module("whm.easyapache4.ea4Util", []);

        app.factory("ea4Util", ["wizardState", function(wizardState) {
            var util = {
                eaRegex: /^ea-/i,
                phpVerRegex: /^ea-php(\d{2})$/i,
                phpExtRegex: /^ea-php(\d{2}-)/i,
                apacheVerRegex: /^ea-apache(\d{2})$/i,
                rubyVerRegex: /^ea-ruby(\d{2})/i,
                apacheModulesRegex: /^ea-apache(\d{2}-)/i,
                additionalPkgList: [],
                defaultMeta: {

                    // Search/Filter settings
                    filterList: {},
                    filterValue: "",
                    isEmptyList: false,

                    // Pager settings
                    showPager: true,
                    maxPages: 0,
                    totalItems: 0,
                    currentPage: 1,
                    pageSize: 10,
                    pageSizes: [10, 20, 50, 100],
                    start: 0,
                    limit: 10,
                },
                pkgActions: {
                    removeList: [],
                    addList: [],
                    actionNeeded: false,
                },
                vhostWarning: {
                    exist: false,
                    text: "",
                },
                multiRequirements: {
                    exist: false,
                    orList: [],
                    chosenPackage: "",
                },
                autoSelectExt: {
                    list: [],
                    text: "",
                    errorList: [],
                    show: false,
                    showError: false,
                    showCommonExtensions: false,
                },
                checkUpdateInfo: {
                    isLoading: true,
                    pkgNumber: 0,
                    btnText: LOCALE.maketext("Checking for updates …"),
                    btnTitle: LOCALE.maketext("Checking for updates …"),
                    btnCss: "btn-ea4-looking-updates disabled",
                },
            };

            util.gatherAllRequirementsOfPkgs = function(pkgsToConsider, packageListDetails) {
                var allRequires = [];
                _.each(pkgsToConsider, function(pkg) {
                    if (!_.includes(allRequires, pkg)) {
                        var pkgInfo = packageListDetails[pkg];
                        if (typeof pkgInfo !== "undefined") {
                            allRequires = util.recurseForRequires(pkgInfo, pkg, allRequires, packageListDetails);
                        }
                        allRequires.push(pkg);
                    }
                });
                return allRequires;
            };

            util.recurseForRequires = function(pkgInfo, origPkgName, allPkgList, packageListDetails) {
                var pkgName = pkgInfo.package;

                // Proceed only if it is an EA package and not previously went through this recursion.
                if (!util.eaRegex.test(pkgName)) {
                    return;
                }
                if (_.includes(allPkgList, pkgName)) {
                    return;
                }

                // Add the package to allPkgList list unless it is the package selected in UI.
                if (typeof origPkgName !== "undefined" && pkgName !== origPkgName) {
                    allPkgList.push(pkgName);
                }

                var recurseArray = [];
                if (pkgInfo.pkg_dep.requires.length > 0) {
                    recurseArray = _.clone(pkgInfo.pkg_dep.requires);
                    recurseArray = _.filter(recurseArray, function(pkg) {
                        return (util.eaRegex.test(pkg) && !_.isArray(pkg));
                    });
                    recurseArray = _.difference(recurseArray, allPkgList);
                }
                _.forEach(recurseArray, function(reqPkg) {
                    var reqPkgInfo = packageListDetails[reqPkg];

                    if (typeof reqPkgInfo !== "undefined") {
                        util.recurseForRequires(reqPkgInfo, origPkgName, allPkgList, packageListDetails);
                    }
                });
                return allPkgList;
            };

            /**
            * @method getFormattedPackageList
            * Takes an Array of packages names and returns a new sorted list
            * with formatted names.  By default takes out the "ea-" part of
            * the package name. Also takes a second optional regex param to change the default behavior.
            * @example getFormattedPackageList("ea-openssl"); // returns "openssl"
            * @param {Array} pkgList - Array contains a list of packages names.
            * @param {RegExp} regex - Optional
            * @return {Array} - New formatted and sorted list.
            */
            util.getFormattedPackageList = function(pkgList, regex) {
                var formattedList = [];
                formattedList = _.map(pkgList, function(pkg) {
                    return util._getReadableName(pkg, regex);
                });
                formattedList.sort();
                return formattedList;
            };

            util.getFormattedPackageName = function(pkg, regex) {
                return util._getReadableName(pkg, regex);
            };

            util._getReadableName = function(pkg, replaceRegex) {
                var strippedName = pkg;
                if (typeof replaceRegex !== "undefined" && replaceRegex !== "") {
                    strippedName = pkg.replace(replaceRegex, "");
                } else {
                    if (util.apacheModulesRegex.test(pkg)) {
                        strippedName = pkg.replace(util.apacheModulesRegex, "");
                    } else {
                        strippedName = pkg.replace(util.eaRegex, "");
                    }
                }
                if (strippedName === "php") {
                    strippedName = "php (DSO)";
                }
                return strippedName;
            };

            /**
             * @method getProfilePackagesByCategories
             * Takes an Array of packages names and groups them together in different categories.
             * The method will return an Object where the keys are the new categories.
             * @param {Array} pkgList - list of packages names.
             * @return {Object} - each keys equals a new category.
             */
            util.getProfilePackagesByCategories = function(pkgList) {
                var pkgCategories = util._pkgByCategory(pkgList);
                return pkgCategories;
            };

            util._pkgByCategory = function(pkgList) {
                var categories = {}, apacheList = [], phpExtList = [], others = [], phpVersions = [], apacheVersion = "";
                _.each(pkgList, function(pkg) {
                    if (util.apacheVerRegex.test(pkg)) {
                        apacheVersion = pkg;
                    } else if (util.apacheModulesRegex.test(pkg)) {
                        apacheList = _.concat(apacheList, pkg);
                    } else if (util.phpVerRegex.test(pkg)) {
                        phpVersions = _.concat(phpVersions, pkg);
                    } else if (util.phpExtRegex.test(pkg)) {
                        phpExtList = _.concat(phpExtList, pkg);
                    } else {
                        others = _.concat(others, pkg);
                    }
                });

                // Handle Apache version.
                if (apacheList.length > 0) {
                    apacheVersion = util._getReadableName(apacheVersion, util.eaRegex);
                    categories[apacheVersion] = {
                        "name": util.versionToString(apacheVersion),
                        "packages": util.getFormattedPackageList(apacheList, util.apacheModulesRegex),
                    };
                }

                // Handle PHP Versions.
                if (phpVersions.length > 0) {
                    _.each(phpVersions.sort(), function(version) {
                        var verRegex = new RegExp("^" + version);
                        var extensions = _.remove(phpExtList, function(pkg) {
                            return verRegex.test(pkg);
                        });
                        var phpversion = util._getReadableName(version, util.eaRegex);
                        categories[phpversion] = {
                            "name": util.versionToString(phpversion).replace("Php", "PHP"),
                            "packages": util.getFormattedPackageList(extensions, util.phpExtRegex),
                        };
                    });
                }

                // Handle Others.
                if (others.length > 0) {
                    categories["others"] = {
                        "name": LOCALE.maketext("Additional Packages"),
                        "packages": util.getFormattedPackageList(others, util.eaRegex),
                    };
                }
                return categories;
            };

            /**
             * @method versionToString
             * Returns a version in a user friendly format.
             * @example versionToString("apache24") // returns "Apache 2.4"
             * @param {String}
             * @return {String}
             */
            util.versionToString = function(version) {
                return version.replace(/^([a-z]+)(\d)(\d)$/, function(match, p1, p2, p3) {
                    return _.capitalize(p1) + " " + p2 + "." + p3;
                });
            };

            /**
             * @method getPackageLabel
             * Returns appropriate package label for a given package state.
             * @example getPackageLabel(true, "updatable"); // returns "Update"
             * @param {Boolean} selected
             * @param {String} state
             * @return {String}
             */
            util.getPackageLabel = function(selected, state) {
                var str = "";
                if (selected) {
                    if (state === "updatable") {
                        str = "Update";
                    } else if (state !== "installed" && state !== "updatable") {
                        str = "Install";
                    } else if (state === "installed") {
                        str = "Unaffected";
                    }
                } else if (state === "installed" || state === "updatable") {
                    str = "Uninstall";
                }
                return str;
            };

            /**
             * @method getPackageClass
             * Returns the proper css callout class for a given package state.
             * @param {Boolean} selected
             * @param {String} state
             * @return {String}
             */
            util.getPackageClass = function(selected, state) {
                var classString;
                if (selected) {
                    classString = "callout";
                    if (state === "updatable") {
                        classString += " callout-info";
                    } else {
                        classString += " callout-success";
                    }
                } else {
                    if (state === "installed" || state === "updatable") {
                        classString = "callout callout-warning";
                    } else {
                        classString = "no-callout";
                    }
                }

                return classString;
            };

            /**
             * @method getDefaultMetaData
             * Returns a deep copy of the Default Meta Data needed
             * to initialize the Wizard component
             * @return {Object}
             */
            util.getDefaultMetaData = function() {
                return _.clone(util.defaultMeta);
            };

            /**
             * @method getDefaultPageSizes
             * Returns an Array with the Default page size values
             * @return {Array}
             */
            util.getDefaultPageSizes = function() {
                return util.defaultMeta.pageSizes;
            };

            /**
             * @method getUpdatedMetaData
             * Returns updated meta data. While updating the metadata,
             * the package list may be filtered depending on the search criteria.
             * @param {Object} list - List of current packages
             * @param {Object} meta - Current meta data
             * @return {Object} updated meta data
             */
            util.getUpdatedMetaData = function(list, meta) {
                if (typeof list !== "undefined" && _.keys(list).length <= 0) {
                    meta.isEmptyList = true;
                    meta.totalItems = 0;
                    return meta;
                }

                // Filter settings.
                var searchStr = meta.filterValue;
                if (searchStr) {
                    var searchString = new RegExp(".*" + searchStr + ".*", "i");
                    list = _.pickBy(list, function(value, key) {
                        return (searchString.test(value.package) || searchString.test(value.short_description));
                    });
                }

                // Pager settings.
                var pkgKeys = _.keys(list);
                var pgSizes = util.getDefaultPageSizes();
                pgSizes = _.filter(pgSizes, function(size) {
                    return (size <= pkgKeys.length);
                });
                meta.pageSizes = pgSizes;
                var totalItems = pkgKeys.length;

                // filter list based on page size and pagination
                if (totalItems > _.min(pgSizes)) {
                    var startIdx = (meta.currentPage - 1) * meta.pageSize;
                    var endIdx = startIdx + meta.pageSize;
                    endIdx = endIdx > totalItems ? totalItems : endIdx;

                    list = _.pick(list, _.slice(pkgKeys, startIdx, endIdx));

                    // list statistics
                    meta.start = startIdx + 1;
                    meta.limit = endIdx;
                    meta.showPager = true;
                } else {
                    meta.showPager = false;
                    if (pkgKeys.length === 0) {
                        meta.start = 0;
                    } else {

                        // list statistics
                        meta.start = 1;
                    }
                    meta.limit = pkgKeys.length;
                }
                meta.totalItems = totalItems;
                meta.filterList = list;
                meta.isEmptyList = _.keys(meta.filterList).length <= 0;
                return meta;
            };

            /**
             * @method getPageShowingText
             * Returns a formated string message
             * @param {Object} meta - Current meta data
             * @return {String}
             */
            util.getPageShowingText = function(meta) {
                var newString = "";
                if (meta && typeof meta.start !== "undefined" && typeof meta.limit !== "undefined" && typeof meta.totalItems !== "undefined"  ) {
                    newString = LOCALE.maketext("[output,strong,Showing] [_1] - [_2] of [_3] items", meta.start, meta.limit, meta.totalItems);
                }
                return newString;
            };

            /**
             * @method getExtensionsForPHPVersion
             * Filters the package list and returns a new list
             * with only the packages associated to the PHP version provided
             * @param {String} version - PHP version (eg. ea-php71).
             * @param {Array} pkgList - Array of package names string
             * @return {Array}
             */
            util.getExtensionsForPHPVersion = function(version, pkgList) {
                var testString = new RegExp(version + ".*", "i");
                var list = _.filter(pkgList, function(name) {
                    return testString.test(name);
                });
                return list;
            };

            /**
             * @method decideShowHideRecommendations
             * Based on the current state of package selection (i.e. on select or unselect),
             * this method filters the recommendations and decides if the recommendation is to be shown or hidden.
             * @param {Array} recommendations - Array of recommendation Objects
             * @param {Array} pkgListToCheck - Package list to check if they match the recommendation criteria.
             * @param {Boolean} onSelect
             * @return {Array} - Array of filtered recommendation Objects
             */
            util.decideShowHideRecommendations = function(recommendations, pkgListToCheck, onSelect, pkg) {

                // Currently this recommendation system works strictly for DSO recommendation only. It can be modified to suit other
                // recommendations as they come.
                _.each(recommendations, function(reco) {
                    if (_.isUndefined(reco)) {
                        return;
                    }
                    if (typeof onSelect !== "undefined") {

                        // The display of a recommendation depends on when it should be
                        // shown (i.e. when installing a package or uninstalling a package)
                        if (onSelect) {
                            reco.show = (reco.on === "add");
                        } else {
                            reco.show = (reco.on === "remove");
                        }
                    } else {
                        reco.show = false;
                    }
                    if (reco.show) {
                        var pkgDisplayName = pkg;

                        // Show readable PHP version name if the pkg is PHP version.
                        if (util.phpVerRegex.test(pkg)) {
                            pkgDisplayName = util._getReadableName(pkg, util.eaRegex);
                            pkgDisplayName = util.versionToString(pkgDisplayName).replace("Php", "PHP");
                        }
                        var localizedName = LOCALE.makevar(reco.name); // The value of this variable is pulled in for translation via an ea4_recommendations TPDS
                        reco.displayName = LOCALE.maketext("Recommendations for “[_1]”: [_2]", pkgDisplayName, localizedName);
                        reco.desc = LOCALE.makevar(reco.desc); // The value of this variable is pulled in for translation via an ea4_recommendations TPDS
                        reco.showFootnote = false;

                        // 'showReco' flag is strictly used for the DSO recommendation.
                        var showReco = true;
                        _.each(reco.options, function(option) {
                            if (!_.isNil(option.recommended)) {
                                option.title = (option.recommended) ? LOCALE.maketext("Recommended") : LOCALE.maketext("Not Recommended");
                            }
                            option.text = LOCALE.makevar(option.text); // The value of this variable is pulled in for translation via an ea4_recommendations TPDS
                            option.show = true;
                            if (!_.isEmpty(option.items)) {
                                showReco = option.show = _.isEmpty(_.intersection(option.items, pkgListToCheck));

                                // If none of the options that include package recos need not be shown
                                // then we do not need to show the footnote.
                                if (!reco.showFootnote) {
                                    reco.showFootnote = option.show;
                                }
                            } else {

                                // In DSO recommendation, we are hiding the second option
                                // as well when the first option
                                option.show = showReco;
                            }
                        });
                        reco.show = !_.every(reco.options, ["show", false]);
                    }
                });
                return recommendations;
            };

            /**
             * @method getExtensionsOfSelectedPHPVersions
             * @param {Object} pkgInfoList
             * @param {Object} currPkgInfoList
             * @param {Array} selectedPkgs - Array of packages names
             * @return {Object}
             */
            util.getExtensionsOfSelectedPHPVersions = function(pkgInfoList, currPkgInfoList, selectedPkgs) {
                var extToConsider = [];
                var noPHPSelected = false;
                var allPhpVersions = _.filter(_.keys(pkgInfoList), function(pkg) {
                    return util.phpVerRegex.test(pkg);
                }).sort();
                var versionsToConsider = _.filter(selectedPkgs, function(pkg) {
                    return (util.phpVerRegex.test(pkg));
                }).sort();

                // Determine if all versions are selected or not. If selected,
                // we do not need to extract a subset, we can just show all extensions.
                if (!_.isEqual(allPhpVersions, versionsToConsider)) {
                    if (versionsToConsider.length > 0) {

                        // Extract only the extension packages of the versions to consider.
                        var workingExt = _.keys(currPkgInfoList);
                        _.each(versionsToConsider, function(ver) {
                            var testString = new RegExp(ver + ".*", "i");
                            var verExt = _.remove(workingExt, function(ext) {
                                return testString.test(ext);
                            });
                            extToConsider = _.concat(extToConsider, verExt);
                        });
                    } else {
                        noPHPSelected = true;
                    }
                } else {
                    versionsToConsider = allPhpVersions;
                    extToConsider = _.keys(currPkgInfoList);
                }
                return { versions: versionsToConsider, extensions: extToConsider, noPHPSelected: noPHPSelected };
            };

            /**
             * Following validations are done for filename:
             *  - It is invalid if the input is just . or ..
             *  - It is invalid if the filename contains / or NUL byte.
             *  - It is valid for all other cases.
             *
             * @method validateFilename
             */
            util.validateFilename = function(filename) {
                var valData = { valid: true, valMsg: "" };
                if (/^\.{1,2}$/.test(filename)) {
                    valData.valid = false;
                    valData.valMsg = LOCALE.maketext("Filename [output,strong,cannot] be “[output,strong,_1]”.", filename);
                } else if (/\/|\0/.test(filename)) {
                    valData.valid = false;
                    valData.valMsg = LOCALE.maketext("Filename [output,strong,cannot] include the following characters: [list_and,_1]", ["/", "NUL"]);
                }
                return valData;
            };

            util.setupVhostWarning = function(pkgInfo, vhostsCount) {

                // Show them as a warning.
                pkgInfo.vhostWarning.exist = true;
                var localizedText = LOCALE.maketext(
                    "[quant,_1,virtual host currently uses,virtual hosts currently use] this version of PHP. If you remove this PHP version, your virtual hosts may not work properly.",
                    vhostsCount);

                // This hack is to apply the right class to the number. This
                // is to overcome the limitation of locale system to take multiple output types for a string.
                localizedText = localizedText.replace(/^(\d+)/, "<span class='vhost-emphasis'>$1</span>");
                pkgInfo.vhostWarning.text = localizedText;
                return pkgInfo;
            };

            util.resetVhostWarning = function(pkgInfo) {
                pkgInfo.vhostWarning = angular.copy(util.vhostWarning);
            };

            /**
            * Creates tags based on the packages list provided.
            *
            * NOTE: [ Needs Improvement ]
            *   Until there is a better way to identify the important packages in a
            *   "Currently Installed Packages", we are going to use regex to extract
            *   Apache, and all PHP versions installed and add them as tags.
            *
            * @method createTagsForActiveProfile
            * @param {Array} packages A list of packages.
            */
            util.createTagsForActiveProfile = function(packages) {
                var tags = [];
                var skipRuby = false;

                _.each(packages, function(pkg) {
                    var newTag;
                    var apacheMatch = pkg.match(util.apacheVerRegex);
                    if (apacheMatch) {
                        var apacheVersion = apacheMatch[1];
                        newTag = "Apache " + apacheVersion.replace(/(\d)(\d)$/, "$1.$2");
                        tags = _.concat(tags, newTag);
                    } else {
                        var phpMatch = pkg.match(util.phpVerRegex);
                        if (phpMatch) {
                            var phpVersion = phpMatch[1];
                            newTag = "PHP " + phpVersion.replace(/(\d)(\d)$/, "$1.$2");
                            tags = _.concat(tags, newTag);
                        }
                        var rubyMatch = pkg.match(util.rubyVerRegex);
                        if (rubyMatch && !skipRuby) {
                            var rubyVersion = rubyMatch[1];
                            newTag = "Ruby " + rubyVersion.replace(/(\d)(\d)$/, "$1.$2");
                            tags = _.concat(tags, newTag);
                            skipRuby = true;
                        }
                    }
                });
                return tags;
            };

            /**
             * @method checkMPMRequirement
             * Checks if the user has any MPM packages (at least one needs to be installed).
             * Updates MPM callout feedback.
             * @param {Object} pkgData
             * @param {Object} resolvedData
             * @param {Array} selectedPkgs
             * @param {Boolean} whenSelected
             * @return {Object}
             */
            util.checkMPMRequirement = function(pkgData, resolvedData, selectedPkgs, whenSelected) {
                var mpmRegex = /mod[-_]mpm/;
                var mpmInRemoveList = _.filter(_.uniq(resolvedData.removeList), function(pkg) {
                    return mpmRegex.test(pkg);
                });
                if (!whenSelected && mpmRegex.test(pkgData.package)) {
                    mpmInRemoveList = _.union(mpmInRemoveList, [pkgData.package]);
                }
                var subList = _.difference(selectedPkgs, mpmInRemoveList);
                var mpmIndexInRemove = _.findIndex(subList, function(pkg) {
                    return mpmRegex.test(pkg);
                });
                var mpmIndexInAdd = _.findIndex(resolvedData.addList, function(pkg) {
                    return mpmRegex.test(pkg);
                });
                if (mpmIndexInRemove === -1 && mpmIndexInAdd === -1) {

                    // Show MPM callout;
                    pkgData.mpmMissing = true;
                    pkgData.mpmMissingMsg = LOCALE.maketext("Your selection removed [list_and,_1].", mpmInRemoveList) + " " + LOCALE.maketext("An [asis,MPM] package must exist on your system. Click “Continue” to select a new [asis,MPM] package.") + " " + LOCALE.maketext("Click “Cancel” to cancel this operation.");
                    pkgData.actions.actionNeeded = false;
                }
                return pkgData;
            };

            util.getCommonlyInstalledExtensions = function(allExtensions, installedPhpVersions) {

                // Filter only installed extensions.
                var installedExt = _.map(_.filter(allExtensions, ["selectedPackage", true]), "package");

                var extGroupByVersions = [];
                _.each(installedPhpVersions, function(version, index) {

                    // Group the extensions by PHP versions andn normalize them to
                    // a common name to make it easy to extract the
                    // common extensions across all installed versions.
                    // Example:
                    //  Trying to process the following array:
                    //  [
                    //      "ea-php54-libc-client", "ea-php54-build", "ea-php54-pear",
                    //      "ea-php54-php-bcmath", "ea-php55-libc-client", "ea-php55-build", "ea-php55-pear",
                    //      "ea-php70-libc-client", "ea-php70-build", "ea-php70-pear",
                    //      "ea-php70-php-calendar", "ea-php70-php-curl"
                    //  ]
                    //  To:
                    //  [
                    //      [ "libc-client", "build", "pear", "php-bcmath" ],
                    //      [ "libc-client", "build", "pear" ],
                    //      [ "libc-client", "build", "pear", "php-calendar", "php-curl" ]
                    //  ]
                    extGroupByVersions[index] = _.chain(installedExt)
                        .filter(function(ext) {
                            return _.startsWith(ext, version);
                        })
                        .map(function(ext) {
                            return _.replace(ext, util.phpExtRegex, "");
                        })
                        .value();
                });

                // Extract the common extensions.
                var commonExtensions = [];
                if (extGroupByVersions.length === 1) {
                    commonExtensions = extGroupByVersions[0];
                } else {
                    for (var i = 0, len = extGroupByVersions.length; i < len - 1; i++) {
                        if (commonExtensions.length > 0) {
                            commonExtensions = _.intersection(commonExtensions, extGroupByVersions[i + 1]);
                        } else {
                            commonExtensions = _.intersection(extGroupByVersions[i], extGroupByVersions[i + 1]);
                        }
                    }
                }

                // Only single PHP version can have DSO package installed at any instance. So
                // if a DSO package come up in the commonExtensions, pull it out to eliminate
                // having conflict issues while auto selecting common extensions.
                // Note: Generally a DSO package is 'ea-php##-php'. Since 'ea-php##-' is stripped above, we are comparing it with just php.
                var excludeList = ["php", "scldevel" ];
                _.pullAll(commonExtensions, excludeList);

                return commonExtensions;
            };

            /**
             * Looks for ea-ruby##-** packages and return true if they do exist.
             * @param {Object} pkgList Package information list,
             * @return {Boolean} True if at least one ruby package exists. False otherwise.
             */
            util.doRubyPkgsExist = function(pkgList) {
                return _.some(pkgList, function(pkg) {
                    return util.rubyVerRegex.test(pkg.package);
                });
            };

            /**
             * Looks for additional packages and return true if they do exist.
             * @param {Array} additionalPkgsList Array of additional package objects.
             * @param {Object} pkgList Package information list,
             * @return {Boolean} True if at least one additional package exists. False otherwise.
             */
            util.doAdditionalPkgsExist = function(additionalPkgsList, pkgList) {
                return _.some(additionalPkgsList, function(addlPkg) {
                    return _.includes(_.keys(pkgList), addlPkg);
                });
            };

            /**
             * Show Footer container of the wizard.
             */
            util.showFooter = function() {
                wizardState.showFooter = true;
            };

            /**
             * Hide Footer container of the wizard.
             */
            util.hideFooter = function() {
                wizardState.showFooter = false;
            };

            return util;
        }]);
    }
);
