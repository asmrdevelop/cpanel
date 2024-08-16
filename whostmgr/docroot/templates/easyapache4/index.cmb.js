/*
# cpanel - whostmgr/docroot/templates/easyapache4/services/ea4Util.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/ea4Util',[
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

/*
# cpanel - whostmgr/docroot/templates/easyapache4/services/ea4Data.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/ea4Data',[
        "angular",
        "lodash",

        // CJT
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",

        // Angular components
        "cjt/services/APIService",

        // App components
        "app/services/ea4Util",
    ],
    function(angular, _, API, APIREQUEST) {
        "use strict";

        var app = angular.module("whm.easyapache4.ea4Data", []);

        app.factory("ea4Data", ["$q", "$location", "ea4Util", "APIService", function($q, $location, ea4Util, APIService) {
            var oData = {
                isReadyForProvision: false,
                mpmRegex: /ea-apache24-mod[_-]mpm.*/i,
                modulesRegex: /ea-apache24-mod.*/i,
                phpRegex: /^ea-php\d{2}$/i,
                phpExtRegex: /ea-php\d{2}-.*/i,
                rubyRegex: /ea-ruby\d{2}-.*/i,
            };

            /**
             * Sets or gets the provision value
             *
             * @method provisionReady
             * @param {Boolean} value
             * @return {Boolean}
             */
            oData.provisionReady = function(value) {
                if (typeof value === "boolean") {
                    oData.isReadyForProvision = value;
                } else {
                    return oData.isReadyForProvision;
                }
            };

            /**
             * @method getProfiles
             * @return {Promise}
             */
            oData.getProfiles = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "ea4_list_profiles");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {

                            // Keep the promise

                            // CJT2 whm-v1.js has parsedResponse wrapper
                            // which is returning wrong data when only 1 key exists
                            // in this response's data.
                            // i.e. when only 'cpanel' key exists in the response,
                            // whm-v1.js -> _reduce_list_data is removing it and returning
                            // and returning data differently.
                            // That is reason 'response.raw.data' is being used here
                            // to have a consistent return always.
                            // the above whm-v1.js method needs to be fixed.
                            deferred.resolve(response.raw.data);
                        } else {

                            // Pass the error along
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            /**
             * @method getVhostsByPhpVersion
             * @param {String} - php version
             * @return {Promise}
             */
            oData.getVhostsByPhpVersion = function(version) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "php_get_vhosts_by_version");
                apiCall.addArgument("version", version);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {

                            // Keep the promise
                            deferred.resolve(response.data);
                        } else {

                            // Pass the error along
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            /**
             * TODO: this method needs to handle API failure
             *
             * @method ea4GetCurrentPkgList
             * @return {Promise}
             */
            oData.ea4GetCurrentPkgList = function() {
                var apiCall = new APIREQUEST.Class();
                var apiService = new APIService();

                apiCall.initialize("", "ea4_get_currently_installed_packages");

                var deferred = apiService.deferred(apiCall);
                return deferred.promise;
            };

            /**
             * Returns ea4 meta info from the ea4_metainfo.json
             * It currently contains information about additional pacakges,
             * default PHP handler & default PHP package used.
             *
             * @method getEA4MetaInfo
             * @return {Promise}
             */
            oData.getEA4MetaInfo = function() {
                var apiCall = new APIREQUEST.Class();
                var apiService = new APIService();

                apiCall.initialize("", "ea4_metainfo");

                var deferred = apiService.deferred(apiCall);
                return deferred.promise;
            };

            /**
             * Returns pkgInfoList for additional pacakges.
             *
             * @method getPkgInfoForAdditionalPackages
             * @argument {Object} pkgInfoList
             * @return {Object}
             */
            oData.getPkgInfoForAdditionalPackages = function(pkgInfoList) {
                var list = {};

                _.each(ea4Util.additionalPkgList, function(pkg) {
                    var pkgInfo = pkgInfoList[pkg];
                    if (typeof pkgInfo !== "undefined") {
                        list[pkg] = pkgInfo;
                    }
                });
                return list;
            };

            /**
             * Returns pkgInfoList filtered by type.
             *
             * @method getPkgInfoSubset
             * @argument {String} type
             * @argument {Object} pkgInfoList
             * @return {Object}
             */
            oData.getPkgInfoSubset = function(type, pkgInfoList) {
                var regex;
                if (type === "additional") {
                    return oData.getPkgInfoForAdditionalPackages(pkgInfoList);
                }

                switch (type) {
                    case "mpm":
                        regex = oData.mpmRegex;
                        break;
                    case "modules":
                        regex = oData.modulesRegex;
                        break;
                    case "php":
                        regex = oData.phpRegex;
                        break;
                    case "extensions":
                        regex = oData.phpExtRegex;
                        break;
                    case "ruby":
                        regex = oData.rubyRegex;
                        break;
                }
                return oData.filterByRegex(regex, pkgInfoList);
            };

            /**
             * @method filterByRegex
             * @argument {Regex} regex
             * @argument {Object} pkgInfoList
             * @return {Promise}
             */
            oData.filterByRegex = function(regex, pkgInfoList) {
                var list = {};
                if (typeof regex === "undefined") {
                    return pkgInfoList;
                }

                var filterPkgs =
                    _.filter(_.keys(pkgInfoList), function(pkg) {
                        return regex.test(pkg);
                    });
                filterPkgs.sort();
                _.each(filterPkgs, function(pkg) {
                    list[pkg] = pkgInfoList[pkg];
                });
                return list;
            };

            /**
             * @method resolvePackages
             * @argument {Array} packages - Array of string names
             * @return {Promise}
             */
            oData.resolvePackages = function(packages) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "package_manager_resolve_actions");
                apiCall.addArgument("ns", "ea");
                _.each(packages, function(pkg, index) {
                    apiCall.addArgument("package-" + index, pkg );
                });

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.raw.data);
                        } else {
                            deferred.reject(response.raw.metadata.reason);
                        }
                    });

                return deferred.promise;
            };

            /**
             * @method doProvision
             * @argument {Array} installPackages - Array of string names
             * @argument {Array} uninstallPackages - Array of string names
             * @argument {Array} upgradePackages - Array of string names
             * @argument {String} profileID
             * @return {Promise}
             */
            oData.doProvision = function(installPackages, uninstallPackages, upgradePackages, profileID) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "package_manager_submit_actions");

                // apiCall.addArgument("profileID", profileID);

                // Prepare the package list
                _.each(installPackages, function(pkg, index) {
                    apiCall.addArgument("install-" + index, pkg );
                });
                _.each(uninstallPackages, function(pkg, index) {
                    apiCall.addArgument("uninstall-" + index, pkg );
                });
                _.each(upgradePackages, function(pkg, index) {
                    apiCall.addArgument("upgrade-" + index, pkg );
                });
                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        deferred.resolve(response.raw.data);
                    });

                return deferred.promise;
            };

            /**
             * @method tailingLog
             * @argument {Number} buildID
             * @argument {Number} offset
             * @return {Promise}
             */
            oData.tailingLog = function(buildID, offset) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "package_manager_get_build_log");

                // Send the pid
                apiCall.addArgument("build", buildID);
                apiCall.addArgument("offset", offset);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        deferred.resolve(response.raw.data);
                    });

                return deferred.promise;
            };

            /**
             * @method getPkgInfoList
             * @return {Promise}
             */
            oData.getPkgInfoList = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "package_manager_get_package_info");
                apiCall.addArgument("ns", "ea");
                apiCall.addArgument("disable-excludes", "1");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.data);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            /**
             * @method cancelOperation
             */
            oData.cancelOperation = function() {
                oData.clearEA4LocalStorageItems();
                $location.path("profile");
            };

            /**
             * @method clearEA4LocalStorageItems
             */
            oData.clearEA4LocalStorageItems = function() {
                localStorage.removeItem("pkgInfoList");
                localStorage.removeItem("selectedProfile");
                localStorage.removeItem("selectedPkgs");
                localStorage.removeItem("provisionActions");
                localStorage.removeItem("customize");
                localStorage.removeItem("ea4Recommendations");
                localStorage.removeItem("ea4RawPkgList");
                localStorage.removeItem("ea4Update");

                ea4Util.hideFooter();
            };

            /**
             * Saves data in Local Storage
             *
             * @method setData
             * @argument {Object} dataItems
             */
            oData.setData = function(dataItems) {
                _.each(_.keys(dataItems), function(item) {
                    var stringifyItem = JSON.stringify(dataItems[item]);
                    localStorage.setItem(item, stringifyItem);
                });
            };

            /**
             * Gets data from Local Storage
             *
             * @method getData
             * @argument {String} item
             */
            oData.getData = function(item) {
                return JSON.parse(localStorage.getItem(item));
            };

            /**
             * Adds new properties to the packages object
             *
             * @method initPkgUIProps
             * @argument {Object} pkgData
             * @return {Object}
             */
            oData.initPkgUIProps = function(pkgData) {
                pkgData["actions"] = ea4Util.pkgActions;
                pkgData["recommendations"] = [];
                pkgData["multiRequirements"] = ea4Util.multiRequirements;
                pkgData["vhostWarning"] = ea4Util.vhostWarning;
                pkgData["mpmMissing"] = false;
                pkgData["mpmMissingMsg"] = "";
                pkgData["autoSelectExt"] = [];

                // TODO:: Add more as you come across. It's easy to know and track all the properties
                // if they are initialized at one place.
                return pkgData;
            };

            // move to ea4Util
            var setPkgSelections = function(selPkgs, pkgInfoList) {
                var allSelectedPkgs = ea4Util.gatherAllRequirementsOfPkgs(selPkgs, pkgInfoList);

                // Select all packages that are installed.
                _.each(allSelectedPkgs, function(pkg) {
                    if (typeof pkgInfoList[pkg] !== "undefined") {
                        pkgInfoList[pkg].selectedPackage = true;
                    }
                });
                return pkgInfoList;
            };

            /**
             * @method buildPkgInfoList
             * @argument {Array} selPkgs - Array of Strings
             * @argument {Array} packagesInfo - Array of Objects
             * @argument {Object} ea4Recommendations - The key is the pkg name, the value an Array of recommendations
             * @return {Object}
             */
            oData.buildPkgInfoList = function(selPkgs, packagesInfo, ea4Recommendations) {

                // Set all packages info.
                var pkgInfoList = {};

                // Ignore any debug packages
                packagesInfo = _.filter(packagesInfo, function(pkg) {
                    return (!/.*\-debuginfo/.test(pkg.package));
                });

                _.each(packagesInfo, function(pkg) {
                    var pkgName = pkg.package;

                    // Start adding UI specific attributes to each package data.
                    pkg = oData.initPkgUIProps(pkg);
                    if (!_.isEmpty(ea4Recommendations[pkgName])) {
                        pkg.recommendations = ea4Recommendations[pkgName];
                    }
                    pkg.selectedPackage = false;
                    pkg.displayName = ea4Util.getFormattedPackageName(pkgName);
                    pkgInfoList[pkgName] = pkg;
                });

                pkgInfoList = setPkgSelections(selPkgs, pkgInfoList);
                return pkgInfoList;
            };

            /**
             * @method fixYumCache
             * @return {Promise}
             */
            oData.fixYumCache = function() {
                var apiCall = new APIREQUEST.Class();
                var apiService = new APIService();
                apiCall.addArgument("ns", "ea");
                apiCall.initialize("", "package_manager_fixcache");

                var deferred = apiService.deferred(apiCall);
                return deferred.promise;
            };

            /**
             * @method saveAsNewProfile
             * @argument {Object} content
             * @argument {String} filename
             * @argument {Number} overwrite
             * @return {Promise}
             */
            oData.saveAsNewProfile = function(content, filename, overwrite) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "ea4_save_profile");
                apiCall.addArgument("filename", filename);
                apiCall.addArgument("name", content.name);
                apiCall.addArgument("overwrite", overwrite);
                apiCall.addArgument("desc", content.desc || "");
                apiCall.addArgument("version", content.version || "");
                _.each(content.pkgs, function(pkg, index) {
                    apiCall.addArgument("pkg-" + index, pkg );
                });

                _.each(content.tags, function(tag, index) {
                    apiCall.addArgument("tag-" + index, tag );
                });

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.data);
                        } else {
                            deferred.reject(response);
                        }
                    });
                return deferred.promise;
            };

            /**
             * @method getEA4Recommendations
             * @return {Promise}
             */
            oData.getEA4Recommendations = function() {
                var apiCall = new APIREQUEST.Class();
                var apiService = new APIService();
                apiCall.initialize("", "ea4_recommendations");

                var deferred = apiService.deferred(apiCall);
                return deferred.promise;
            };

            /**
             * @method getUploadContentFromUrl
             * @argument {Object} uploadUrl
             * @return {Promise}
             */
            oData.getUploadContentFromUrl = function(uploadUrl) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "cors_proxy_get");
                apiCall.addArgument("url", uploadUrl);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.data);
                        } else {
                            deferred.reject(response.error);
                        }
                    });
                return deferred.promise;
            };

            /**
             * @method dataIsAvailable
             * @return {Boolean}
             */
            oData.dataIsAvailable = function() {
                if (oData.getData("pkgInfoList")) {
                    return true;
                } else {
                    return false;
                }
            };

            /**
             * @method getPkgInfoByType
             * @argument {String} type
             * @argument {Object} pkgInfoList
             * @return {Object}
             */
            oData.getPkgInfoByType = function(type, pkgInfoList) {
                var subsetPkgInfoList = [];
                if (type) {
                    subsetPkgInfoList = oData.getPkgInfoSubset(type, pkgInfoList);
                }
                return subsetPkgInfoList;
            };

            // Expose only required methods.
            return {
                provisionReady: oData.provisionReady,
                getProfiles: oData.getProfiles,
                ea4GetCurrentPkgList: oData.ea4GetCurrentPkgList,
                cancelOperation: oData.cancelOperation,
                getPkgInfoForAdditionalPackages: oData.getPkgInfoForAdditionalPackages,
                getPkgInfoSubset: oData.getPkgInfoSubset,
                filterByRegex: oData.filterByRegex,
                clearEA4LocalStorageItems: oData.clearEA4LocalStorageItems,
                resolvePackages: oData.resolvePackages,
                doProvision: oData.doProvision,
                tailingLog: oData.tailingLog,
                getPkgInfoList: oData.getPkgInfoList,
                setData: oData.setData,
                getData: oData.getData,
                initPkgUIProps: oData.initPkgUIProps,
                buildPkgInfoList: oData.buildPkgInfoList,
                getVhostsByPhpVersion: oData.getVhostsByPhpVersion,
                fixYumCache: oData.fixYumCache,
                saveAsNewProfile: oData.saveAsNewProfile,
                getEA4Recommendations: oData.getEA4Recommendations,
                getUploadContentFromUrl: oData.getUploadContentFromUrl,
                dataIsAvailable: oData.dataIsAvailable,
                getPkgInfoByType: oData.getPkgInfoByType,
                getEA4MetaInfo: oData.getEA4MetaInfo,
            };
        }]);
    }
);

/*
# cpanel - whostmgr/docroot/templates/easyapache4/directives/eaWizard.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    'app/directives/eaWizard',[
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

/*
# templates/easyapache4/directives/saveAsProfile.js            Copyright 2022 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/directives/saveAsProfile',[
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

/*
# cpanel - whostmgr/docroot/templates/easyapache4/services/pkgResolution.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    'app/services/pkgResolution',[
        "angular",
        "lodash",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/services/APIService",
    ],
    function(angular, _) {
        "use strict";

        var app = angular.module("whm.easyapache4.pkgResolution", []);

        app.factory("pkgResolution", function() {
            var oData = {

                // Common variables used.
                eaRegex: /^ea-/,
                allConflicts: [],
                allRequires: [],
                resolvedRemoveList: [],
                requireStructure: {
                    "safe": [],     // This will have array of safe required packages.
                    "unsafe": {},    // This will have { 'unsafe_req_pkg': [ con_pkgs_for_this_unsafe_req_pkg, … ], … }
                },
                conflictStructure: {
                    "safe": [],     // This will have array of safe conflict packages.
                    "unsafe": {},    // This will have { 'unsafe_conflict_pkg': [ req_pkgs_for_this_unsafe_conflict_pkg, … ], … }
                },
                orListStructure: {
                    exist: false,
                    orLists: [],
                },
                resolvedPackages: {
                    addList: [],
                    removeList: [],
                    actionNeeded: false,
                },
            };

            /**
             * Resets all the common variables that are used during the conflict/requirement resolution.
             * @method resetCommonVariables
             */
            oData.resetCommonVariables = function() {

                // Reset the common variables to keep them ready to re-use for next select/unselect actions.
                oData.allConflicts = [];
                oData.allRequires = [];
                oData.resolvedRemoveList = [];
                oData.requireStructure = {
                    "safe": [],
                    "unsafe": {},
                };
                oData.conflictStructure = {
                    "safe": [],
                    "unsafe": {},
                };
                oData.orListStructure = {
                    exist: false,
                    orLists: [],
                };
                oData.resolvedPackages = {
                    addList: [],
                    removeList: [],
                    actionNeeded: false,
                };
            };

            /**
             * Returns multirequirement data.
             *
             * @method getOrListStructure
             * @returns {object}
             */
            oData.getOrListStructure = function() {
                return oData.orListStructure;
            };

            /**
             * Updates multirequirement related data.
             *
             * @method setOrListStructure
             * @param {object} data - New orListStructure data.
             */
            oData.setOrListStructure = function(data) {
                oData.orListStructure = data;
            };

            /**
             * Returns the resolved pacakge data.
             *
             * @method getResolvedData
             * @returns {object}
             */
            oData.getResolvedData = function() {
                return oData.resolvedPackages;
            };

            /**
             * Resolves the requirements and conflicts by going through all
             * nested levels of the current package dependencies.
             *
             * @method resolveDependenciesWhenSelected
             * @param {object} thisPackage - The selected package data.
             * @param {array} selectedPackages - Current list of selected packages.
             * @param {array} pkgInfoList - A detailed list of all packages data.
             * @returns {object} - Returns an object with information on more action needed and multirequirement status.
             */
            oData.resolveDependenciesWhenSelected = function(thisPackage, selectedPackages, pkgInfoList) {
                var retData = {
                    orListExist: false,
                    actionNeeded: false,
                };

                if (thisPackage) {

                    // Recurse through all requirements for this package
                    // and collect the requirements into 'allRequires'
                    // and the corresponding conflicts into 'allConflicts'
                    oData.recurseWhenSelected(thisPackage, thisPackage.package, pkgInfoList);

                    // Add this package too as it isn't added during the recursion.
                    oData.allRequires.push(thisPackage.package);

                    oData.orListStructure = oData.updateMultiRequirements(oData.orListStructure, selectedPackages, oData.allRequires, oData.allConflicts, pkgInfoList);

                    if (oData.orListStructure.exist) {
                        retData.orListExist = oData.orListStructure.exist;
                    } else {
                        var actionNeeded = oData.proceedToResolveRequirementsAndConflicts(thisPackage, selectedPackages, pkgInfoList);
                        retData.actionNeeded = actionNeeded;
                    }
                }
                return retData;
            };


            /**
             * Updates the multi requirement object.
             *
             * @method updateMultiRequirements
             * @param {object} multiReq - The multiRequirment object to be updated.
             * @param {array} selectedPackages - Current list of selected packages.
             * @param {array} allRequires - A list of all required packages in the current context.
             * @param {array} allConflicts - A list of all conflicts in the current context.
             * @param {object} pkgInfoList - A list containing package information of all the available packages in EA4 repo.
             * @returns {object} - Updated multiRequirement object.
             */
            oData.updateMultiRequirements = function(multiReq, selectedPackages, allRequires, allConflicts, pkgInfoList) {

                if (multiReq) {

                    // In multiRequirement data, check to see if the packages in orLists
                    // are already in selectedPackages or in allRequires. If yes then resolve them.
                    var orLists = _.clone(multiReq.orLists);
                    _.each(orLists, function(eachList) {
                        var removeThisList = false;
                        var filterList = _.filter(eachList, function(pkg) {

                            // Consider only EasyApache packages if they are present on the system.
                            return (oData.eaRegex.test(pkg) && (typeof pkgInfoList[pkg] !== "undefined"));
                        });
                        removeThisList = _.isEmpty(filterList);
                        var alreadyInRequires = [];
                        if (!removeThisList) {

                            // See if any package in this OR list instance is among
                            // selected packages.
                            alreadyInRequires = _.intersection(filterList, selectedPackages);

                            // If not, see if any package in this OR list instance is already
                            // a required package.
                            if (_.isEmpty(alreadyInRequires)) {
                                alreadyInRequires = _.intersection(filterList, allRequires);
                            }

                            if (!_.isEmpty(alreadyInRequires)) {
                                if (filterList.length === 1) {
                                    oData.allRequires = _.union(allRequires, filterList);
                                }
                                removeThisList = true;
                            } else {
                                var findConflicts = _.intersection(filterList, allConflicts);
                                filterList = _.difference(filterList, findConflicts);
                                if (filterList.length === 1) {
                                    oData.allRequires = _.union(allRequires, filterList);
                                    removeThisList = true;
                                }
                            }
                        }

                        // Look if this list can be removed now.
                        if (removeThisList) {
                            _.pull(multiReq.orLists, eachList);
                        } else if (!_.isEqual(eachList, filterList)) {

                            // In this case replace old list with new one.
                            _.pull(multiReq.orLists, eachList);
                            if (!_.isEmpty(filterList)) {
                                multiReq.orLists = _.concat(multiReq.orLists, [filterList]);
                            }
                        }
                    });

                    multiReq.exist = multiReq.orLists.length > 0;
                }
                return multiReq;
            };

            /**
             * Continues to resolve conflict/requirements from where it previously
             * left off. (i.e. If a multirequirement existence is detected, then it stops the resolution
             * operation and prompts the user to choose one from the multiple requirements. Then after that it continues
             * from this function.)
             *
             * @method continueResolvingDependencies
             * @param {object} thisPackage - The selected package data.
             * @param {object} chosenPkg - The chosen package data.
             * @param {string} chosenPkgName
             * @param {array} pkgInfoList - A detailed list of all packages data.
             * @param {array} selectedPackages - Current list of selected packages.
             * @returns {object} - Returns an object with information on more action needed and multirequirement status.
             */
            oData.continueResolvingDependencies = function(thisPackage, chosenPkg, chosenPkgName, pkgInfoList, selectedPackages) {
                var retData = {
                    orListExist: false,
                    actionNeeded: false,
                };

                // Recurse through all requirements for this package
                // and collect the requirements into 'allRequires'
                // and the corresponding conflicts into 'allConflicts'
                oData.recurseWhenSelected(chosenPkg, chosenPkgName, pkgInfoList);

                // Add this package too as it isn't added during the recursion.
                oData.allRequires.push(chosenPkgName);

                oData.orListStructure = oData.updateMultiRequirements(oData.orListStructure, selectedPackages, oData.allRequires, oData.allConflicts, pkgInfoList);
                if (oData.orListStructure.exist) {
                    retData.orListExist = oData.orListStructure.exist;
                } else {
                    var actionNeeded = oData.proceedToResolveRequirementsAndConflicts(thisPackage, selectedPackages, pkgInfoList);
                    retData.actionNeeded = actionNeeded;
                }
                return retData;
            };

            /**
             * Second part of the conflict/dependency process after all nested levels
             * of conflicts and requirements are collected through recursive process.
             *
             * @method proceedToResolveRequirementsAndConflicts
             * @param {object} thisPackage - The selected package data.
             * @param {array} selectedPackages - Current list of selected packages.
             * @param {array} pkgInfoList - A detailed list of all packages data.
             * @returns {Boolean} - Returns a flag if action needed or not.
             */
            oData.proceedToResolveRequirementsAndConflicts = function(thisPackage, selectedPackages, pkgInfoList) {

                // REFACTOR: thisPackage can be removed since it's not used in this method anywhere.
                // var selectedPackages = $scope.selectedProfile.pkgs;
                // var pkgInfoList = pkgInfoList;

                // Get the required packages that are not selected.
                var reqToConsider = _.difference(oData.allRequires, selectedPackages);
                if (reqToConsider.length > 0) {

                    // Constructs requireStructure by
                    // adding safe and unsafe requirements appropriately.
                    oData.requireStructure = oData.buildRequireStructure(reqToConsider, selectedPackages, pkgInfoList);
                }

                var consToConsider = _.intersection(oData.allConflicts, selectedPackages);
                if (consToConsider.length > 0) {

                    // Constructs conflictStructure by
                    // adding safe and unsafe conflicts appropriately.
                    oData.conflictStructure = oData.buildConflictStructure(consToConsider, selectedPackages, pkgInfoList);
                }

                // This step ensures all unsafe require are resolved
                // and moved to requireStructure.safe array.
                oData.requireStructure = oData.resolveUnsafeRequires(selectedPackages, oData.requireStructure, pkgInfoList);

                // This step ensures all unsafe conflicts are resolved
                // and moved to conflictStructure.safe array.
                oData.conflictStructure = oData.resolveUnsafeConflicts(selectedPackages, oData.conflictStructure, pkgInfoList);

                // At this point we have the following data:
                // * resolvedRemoveList - list of all conflicts resolved and ready to remove
                // * conflictStructure.safe - list of all safe conflicts to remove
                // * requireStructure.safe - list of all safe requires to add
                oData.resolvedPackages.removeList = _.union(oData.resolvedRemoveList, oData.conflictStructure.safe);
                oData.resolvedPackages.addList = oData.requireStructure.safe;
                oData.resolvedPackages.actionNeeded = oData.resolvedPackages.removeList.length > 0;
                return oData.resolvedPackages.actionNeeded;
            };

            /**
             * Builds a requirement structure which separates out the safe and unsafe requirements.
             * Safe requirement: If a particular required package is not conflicting with any installed packages.
             * Unsafe requirement: If it conflicts with any installed package.
             *
             * @method buildRequireStructure
             * @param {array} reqToConsider
             * @param {array} selectedPackages - Current list of selected packages.
             * @param {array} pkgInfoList - A detailed list of all packages data.
             * @returns {object} - Returns an object with safe and unsafe requirements.
             */
            oData.buildRequireStructure = function(reqToConsider, selectedPackages, pkgInfoList) {
                var reqStruct = oData.requireStructure;
                if (pkgInfoList) {
                    _.each(reqToConsider, function(req) {
                        var reqIsSafe = true;
                        _.each(selectedPackages, function(pkg) {
                            var pkgDetails = pkgInfoList[pkg];
                            if (typeof pkgDetails !== "undefined" &&
                                _.includes(pkgDetails.pkg_dep.conflicts, req)) {

                                // At this point this 'req' is unsafe since it conflicts with an existing package.
                                // initialize an array (if it's not already) to store this unsafe req's conflicts.
                                if (typeof reqStruct.unsafe[req] === "undefined") {
                                    reqStruct.unsafe[req] = [];
                                }
                                reqStruct.unsafe[req].push(pkg);
                                reqIsSafe = false;
                            }
                        });
                        if (reqIsSafe) {
                            reqStruct.safe.push(req);
                        }
                    });
                }
                return reqStruct;
            };

            /**
             * Builds a conflict structure which separates out the safe and unsafe conflicts.
             * Safe conflict: If a particular conflicting package is a not a requirement for any installed packages.
             * Unsafe conflict: If it is a requirement for any installed packages.
             *
             * @method buildConflictStructure
             * @param {array} consToConsider
             * @param {array} selectedPackages - Current list of selected packages.
             * @param {array} pkgInfoList - A detailed list of all packages data.
             * @returns {object} - Returns an object with safe and unsafe conflicts.
             */
            oData.buildConflictStructure = function(consToConsider, selectedPackages, pkgInfoList) {
                var conStruct = oData.conflictStructure;
                _.each(consToConsider, function(con) {
                    var conIsSafe = true;
                    _.each(selectedPackages, function(pkg) {
                        var pkgDetails = pkgInfoList[pkg];
                        if (typeof pkgDetails !== "undefined" &&
                            _.includes(pkgDetails.pkg_dep.requires, con)) {

                            // At this point this 'con' is unsafe since it is required by an existing package.
                            // initialize an array (if it's not already) to store this unsafe con's requirements.
                            if (typeof conStruct.unsafe[con] === "undefined") {
                                conStruct.unsafe[con] = [];
                            }
                            conStruct.unsafe[con].push(pkg);
                            conIsSafe = false;
                        }
                    });
                    if (conIsSafe) {
                        conStruct.safe.push(con);
                    }
                });
                return conStruct;
            };

            /**
             * Unsafe requirements are examined and resolved by adding them to the
             * remove list accordingly.
             *
             * @method resolveUnsafeRequires
             * @param {array} selectedPackages - Current list of selected packages.
             * @param {object} reqStruct
             * @param {array} pkgInfoList - A detailed list of all packages data.
             * @returns {object} - Updated reqStruct with resolved unsafe requirements.
             */
            oData.resolveUnsafeRequires = function(selectedPackages, reqStruct, pkgInfoList) {
                if (reqStruct) {
                    var oUnsafeRequires = reqStruct.unsafe;
                    var keys = _.keys(oUnsafeRequires);
                    _.each(keys, function(req) {
                        var conflictsToResolve = oUnsafeRequires[req];
                        conflictsToResolve = _.difference(conflictsToResolve, oData.resolvedRemoveList);
                        _.each(conflictsToResolve, function(con) {

                            // TODO: The includes if condition can be removed since resolvedRemoveList items
                            // are removed from conflictsToResolve list in line above using _.difference operation.
                            if (!_.includes(oData.resolvedRemoveList, con)) {
                                var selPkgsToConsider = _.difference(selectedPackages, oData.resolvedRemoveList);
                                oData.recurseConflictRequirements(pkgInfoList[con], con, selPkgsToConsider, pkgInfoList);
                                oData.resolvedRemoveList = _.union(oData.resolvedRemoveList, [con]);
                            }
                        });

                        // Move this 'req' from unsafe to safe.
                        reqStruct.safe.push(req);

                        // TODO: This line may not be needed since the unsafe object is reset at the end of this function.
                        _.unset(reqStruct.unsafe, req);
                    });

                    // At this point all unsafe requires are resolved. So remove unsafe from reqStruct.
                    reqStruct.unsafe = {};
                }
                return reqStruct;
            };

            /**
             * Unsafe conflict are examined and resolved by adding them to the
             * remove list accordingly.
             *
             * @method resolveUnsafeConflicts
             * @param {array} selectedPackages - Current list of selected packages.
             * @param {object} conStruct
             * @param {array} pkgInfoList - A detailed list of all packages data.
             * @returns {object} - Updated conStruct with resolved unsafe conflicts.
             */
            oData.resolveUnsafeConflicts = function(selectedPackages, conStruct, pkgInfoList) {
                if (conStruct) {

                    // Remove all conflict objects from conflictStructure.unsafe that are present in resolvedRemoveList.
                    // since they are already resolved.
                    var oUnsafeConflicts = _.omit(conStruct.unsafe, oData.resolvedRemoveList);
                    var keys = _.keys(oUnsafeConflicts);
                    _.each(keys, function(con) {
                        var reqsToResolve = _.difference(oUnsafeConflicts[con], oData.resolvedRemoveList);
                        _.each(reqsToResolve, function(req) {

                            // TODO: The includes if condition can be removed since resolvedRemoveList items
                            // are removed from conflictsToResolve list in line above using _.difference operation.
                            if (!_.includes(oData.resolvedRemoveList, req)) {
                                var selPkgsToConsider = _.difference(selectedPackages, oData.resolvedRemoveList);
                                oData.recurseConflictRequirements(pkgInfoList[req], req, selPkgsToConsider, pkgInfoList);
                                oData.resolvedRemoveList = _.union(oData.resolvedRemoveList, [req]);
                            }
                        });

                        // Move this 'con' from unsafe to safe.
                        conStruct.safe.push(con);

                        // TODO: This line may not be needed since the unsafe object is reset at the end of this function.
                        _.unset(conStruct.unsafe, con);
                    });

                    // At this point all unsafe conflicts are resolved. So remove unsafe from conStruct.
                    conStruct.unsafe = {};
                }
                return conStruct;
            };

            /**
             * Recursive method that recurses through all requirements of a package and
             * collect their corresponding conflicts.
             *
             * @method recurseConflictRequirements
             * @param {object} conPackage - conflict package data.
             * @param {string} origPkgName - The original package name of the package selected in the current context.
             * @param {array} selPkgsToConsider - Current list selected packages.
             * @param {array} pkgInfoList - A detailed list of all packages data.
             */
            oData.recurseConflictRequirements = function(conPackage, origPkgName, selPkgsToConsider, pkgInfoList) {
                var pkgName = conPackage.package;
                if (origPkgName !== pkgName) {
                    oData.resolvedRemoveList.push(pkgName);
                }

                var recurseArray = _.pull(selPkgsToConsider, pkgName);

                // Find all selected packages that require pkgName.
                recurseArray = _.filter(recurseArray, function(pkg) {
                    var pkgDetails = pkgInfoList[pkg];
                    return (typeof pkgDetails !== "undefined" && _.includes(pkgDetails.pkg_dep.requires, pkgName));
                });
                _.each(recurseArray, function(recurPkg) {
                    oData.recurseConflictRequirements(pkgInfoList[recurPkg], origPkgName, selPkgsToConsider, pkgInfoList);
                });
            };

            // TODO: Try to return data instead of changing global variable from within
            // this method.
            /**
             * This method takes the selected package (origPkgName)
             * and finds recursively requirements and conflicts down to all levels and store them in
             * 'allRequires' & 'allConflicts' variables respectively. It also identifies packages
             * which have multi requirement options and feed them into 'orListStructure' variable. They are handled
             * through other methods.
             *
             * @method recurseWhenSelected
             * @param {object} pkgInfo - The selected package data.
             * @param {string} origPkgName - The original package name of the package selected in the current context.
             * @param {array} pkgInfoList - A detailed list of all packages data.
             */
            oData.recurseWhenSelected = function(pkgInfo, origPkgName, pkgInfoList) {
                if (pkgInfo) {
                    var pkgName = pkgInfo.package;

                    // Proceed only if it is an EA package and not previously went through this recursion.
                    if (!oData.eaRegex.test(pkgName)) {
                        return;
                    }
                    if (_.includes(oData.allRequires, pkgName)) {
                        return;
                    }

                    // Add the package to oData.allRequires list unless it is the package selected in UI.
                    if (typeof origPkgName !== "undefined" && pkgName !== origPkgName) {
                        oData.allRequires.push(pkgName);
                    }

                    // Collect all 'ea' packages that are in conflict with current pkg.
                    oData.allConflicts = _.union(oData.allConflicts, _.filter(pkgInfo.pkg_dep.conflicts, function(pkg) {
                        return (oData.eaRegex.test(pkg));
                    }));

                    var recurseArray = [];
                    if (pkgInfo.pkg_dep.requires.length > 0) {
                        recurseArray = _.clone(pkgInfo.pkg_dep.requires);

                        // IDENTIFY multi-requirement arrays.
                        // A multi-requirement array means for example cgid requires either
                        // mpm-event OR mpm-worker
                        // so cgid will have a multi-requirement array:
                        // [ mpm-event, mpm-worker ]
                        // We identify such multi-requirement arrays, find if any one of them is selected,
                        // and use that. If not we collect such arrays in oData.orListStructure.orLists
                        // and show it to the user and let them choose.
                        var orLists = _.remove(recurseArray, function(pkg) {
                            return _.isArray(pkg);
                        });

                        if (orLists.length > 0) {
                            oData.orListStructure.orLists = _.unionWith(oData.orListStructure.orLists, orLists, _.isEqual);
                        }

                        recurseArray = _.filter(recurseArray, function(pkg) {
                            return (oData.eaRegex.test(pkg));
                        });
                        recurseArray = _.difference(recurseArray, oData.allRequires);
                    }
                    _.forEach(recurseArray, function(reqPkg) {
                        var reqPkgInfo = pkgInfoList[reqPkg];

                        if (typeof reqPkgInfo !== "undefined") {
                            oData.recurseWhenSelected(reqPkgInfo, origPkgName, pkgInfoList);
                        }
                    });
                }
            };

            /**
            * Get all dependencies(requires/conflicts) recursively for a given package when selected.
            *
            * @method getAllDepsRecursively
            * @param {Boolean} selected - given package selected state.
            * @param {Object} pkgInfo - Package information object.
            * @param {String} origPkgName - Package name.
            * @param {String} pkgInfoList - List of all package info objects.
            * @param {array} selectedPackages - Current list of selected packages.
            * @return {Object} -
            *   On package select action: { 'requiredPkgs': [...], conflictPkgs: [...] }
            *   On package unselect action: { 'removedList': [...] }
            */
            oData.getAllDepsRecursively = function(selected, pkgInfo, origPkgName, pkgInfoList, selectedPackages) {
                var deps = {};
                if (selected) {
                    oData.recurseWhenSelected(pkgInfo, origPkgName, pkgInfoList);
                    deps = {
                        requiredPkgs: oData.allRequires,
                        conflictPkgs: oData.allConflicts,
                    };
                } else {
                    oData.recurseWhenUnselected(pkgInfo, origPkgName, pkgInfoList, selectedPackages);
                    deps = {
                        removedList: oData.resolvedRemoveList,
                    };
                }
                return deps;
            };

            /**
             * Resolves the requirements and conflicts of an unselected package, by going through all
             * nested levels of the current package dependencies.
             * Updates the resolvePackages.removeList.
             *
             * @method resolveDependenciesWhenUnSelected
             * @param {object} thisPackage - The selected package data.
             * @param {array} selectedPackages - Current list of selected packages.
             * @param {array} pkgInfoList - A detailed list of all packages data.
             */
            oData.resolveDependenciesWhenUnSelected = function(thisPackage, selectedPackages, pkgInfoList) {
                if (thisPackage) {
                    var pkgName = thisPackage.package;

                    oData.resolvedRemoveList.push(pkgName);
                    oData.recurseWhenUnselected(thisPackage, pkgName, pkgInfoList, selectedPackages);   // Updates oData.resolvedRemoveList.
                    oData.resolvedPackages.removeList = _.uniq(oData.resolvedRemoveList);
                }
            };

            /**
             * This recursive method takes the unselected package (origPkgName)
             * and finds packages that depend on it and add it to the removedList.
             * The recursion gets applied to the removedList all the way up and find package dependencies
             * that need to be removed.
             *
             * @method recurseWhenUnselected
             * @param {object} pkgInfo - The selected package data.
             * @param {string} origPkgName - The selected package name.
             * @param {array} pkgInfoList - A detailed list of all packages data.
             * @param {array} selectedPkgsToUnselectFrom - Selected package list that is used as a reference to check what needs to be removed.
             */
            oData.recurseWhenUnselected = function(pkgInfo, origPkgName, pkgInfoList, selectedPkgsToUnselectFrom) {
                var pkgName = pkgInfo.package;

                // Proceed only if it is an EA package and not previously went through this recursion.
                if (!oData.eaRegex.test(pkgName)) {
                    return;
                }
                if (_.includes(oData.allRequires, pkgName)) {
                    return;
                }

                // Add the package to allRequires list unless it is the package selected in UI.
                if (typeof origPkgName !== "undefined" && pkgName !== origPkgName) {
                    oData.allRequires.push(pkgName);
                }

                /* NOTES:
                 * Pick the packages from the `selectedPackages` list which depend (require) on the package being unselected.
                 * Recurse back all the way until we find all packages that depend on the one's being unselected.
                **/
                var recurseArray = [];
                if (selectedPkgsToUnselectFrom.length > 0) {
                    _.each(selectedPkgsToUnselectFrom, function(pkg) {
                        if (_.includes(pkgInfoList && pkgInfoList[pkg] && pkgInfoList[pkg].pkg_dep.requires, pkgName)) {

                            // At this point, the package 'pkg' depends directly/indirectly on the original package. So,
                            // add this to the remove list.
                            oData.resolvedRemoveList.push(pkg);
                            recurseArray.push(pkg);
                        }
                    });
                    selectedPkgsToUnselectFrom = _.pullAll(selectedPkgsToUnselectFrom, recurseArray);

                    // IDENTIFY multi-requirement arrays.
                    // A multi-requirement array means for example cgid requires either
                    // mpm-event OR mpm-worker
                    // so cgid will have a multi-requirement array:
                    // [ mpm-event, mpm-worker ]
                    // We identify such multi-requirement arrays, find if any one of them is selected,
                    // and use that. If not we collect such arrays in orListStructure.orLists
                    // and show it to the user and let them choose.
                    var orLists = _.remove(recurseArray, function(pkg) {
                        return _.isArray(pkg);
                    });

                    // From each orList, add the one's that are currently selected.
                    _.each(orLists, function(orList) {
                        _.concat(recurseArray, _.filter(orList, function(pkg) {
                            return (typeof pkgInfoList[pkg] !== "undefined" && pkgInfoList[pkg].selectedPackage);
                        }));
                    });
                    recurseArray = _.filter(recurseArray, function(pkg) {
                        return (oData.eaRegex.test(pkg));
                    });
                    recurseArray = _.difference(recurseArray, oData.allRequires);
                }

                _.forEach(recurseArray, function(reqPkg) {
                    var reqPkgInfo = pkgInfoList[reqPkg];

                    if (typeof reqPkgInfo !== "undefined") {
                        oData.recurseWhenUnselected(reqPkgInfo, origPkgName, pkgInfoList, selectedPkgsToUnselectFrom);
                    }
                });
            };

            /**
            * Constructs multiRequirement object for a package's dependencies.
            *
            * @method setupMultiRequirementForUserInput
            * @param {object} pkgInfoList An package info object with key (package name) value (package object) pairs.
            */
            oData.setupMultiRequirementForUserInput = function(pkgInfoList) {
                var multiRequirements = {};

                // Check if orLists is empty. If empty,
                // Pull the first orList from multiReq.
                var orListStruct = oData.getOrListStructure();
                if (typeof orListStruct !== "undefined") {
                    var orList = orListStruct.orLists.shift();
                    if (typeof orList !== "undefined" && orList.length > 0) {
                        var orListWithPkgNames = _.map(orList, function(orPkg) {
                            if (typeof pkgInfoList[orPkg] !== "undefined") {
                                return { "package": orPkg, "displayName": pkgInfoList[orPkg].displayName };
                            }
                        });
                        multiRequirements = {
                            exist: orListStruct.exist,
                            orList: orListWithPkgNames,
                            chosenPackage: "",
                        };
                    }
                }
                return multiRequirements;
            };

            /**
             * Resets all common and package object variables that deal with
             * conflict/requirement resolving process.
             *
             * @method resetPkgResolveActions
             * @param {object} pkgInfo - Package object.
             * @returns {object} - package object.
             */
            oData.resetPkgResolveActions = function(pkgInfo) {
                oData.resetCommonVariables();

                // Reset the actions of this package to empty
                if (pkgInfo) {

                    // TODO: merge pkgInfo.actions & multirequirements into
                    // pkgInfo.resolveData = {
                    //     removeList: [], addList: [], actionNeeded: false,
                    //     multiRequirements: {}
                    // };
                    pkgInfo.actions = { removeList: [], addList: [], actionNeeded: false };
                    pkgInfo.mpmMissing = false;
                    pkgInfo.mpmMissingMsg = "";
                    pkgInfo.multiRequirements = {};
                }
                return pkgInfo;
            };

            /**
             * Prepares the callout to display the conflict requirements that are identified
             * during the resolving process.
             *
             * @method setupConDepCallout
             * @param {object} pkgInfo - The selected package data.
             * @param {array} pkgInfoList - A detailed list of all packages data.
             * @returns {object} - Selected package data with updated dependency resolution info for callout .
             */
            oData.setupConDepCallout = function(pkgInfo, pkgInfoList) {

                // get resolved package data.
                var resData = oData.getResolvedData();
                if (resData.actionNeeded) {
                    pkgInfo.actions.actionNeeded = resData.actionNeeded;
                    pkgInfo.actions.removeList = _.map(resData.removeList, function(pkg) {
                        return pkgInfoList[pkg].displayName;
                    });

                    pkgInfo.actions.addList = _.map(resData.addList, function(pkg) {
                        return pkgInfoList[pkg].displayName;
                    });
                }
                return pkgInfo;
            };

            return oData;
        });
    }
);

/*
# cpanel - whostmgr/docroot/templates/easyapache4/services/wizardApi.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/services/wizardApi',[
        "angular",
        "lodash",
        "cjt/util/locale",

        // CJT
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",

        // Angular components
        "cjt/services/APIService",

        // App components
    ],
    function(angular, _, LOCALE) {
        "use strict";

        var app = angular.module("whm.easyapache4.wizardApi", []);

        app.factory("wizardApi", ["$location", "wizardState", "ea4Data", "ea4Util", function($location, wizardState, ea4Data, ea4Util) {
            var oData = {
                defaultWizardState: {
                    showWizard: false,
                    showSearchAndPage: false,
                    currentStepIndex: 0,
                    showFooter: false,
                    currentStep: "",
                    lastStepName: "",
                    steps: {
                        "mpm": { name: "mpm", title: LOCALE.maketext("Apache [output,acronym,MPM,Multi-Processing Modules]"), path: "mpm", stepIndex: 1, nextStep: "modules" },
                        "modules": { name: "modules", title: LOCALE.maketext("Apache Modules"), path: "modules", stepIndex: 2, nextStep: "php" },
                        "php": { name: "php", title: LOCALE.maketext("[output,acronym,PHP,PHP Hypertext Preprocessor] Versions"), path: "php", stepIndex: 3, nextStep: "extensions" },
                        "extensions": { name: "extensions", title: LOCALE.maketext("[output,acronym,PHP,PHP Hypertext Preprocessor] Extensions"), path: "extensions", stepIndex: 4, nextStep: "ruby" },
                        "ruby": { name: "ruby", title: LOCALE.maketext("[asis,Ruby] via [asis,Passenger]"), path: "ruby", stepIndex: 5, nextStep: "additional" },
                        "additional": { name: "additional", title: LOCALE.maketext("Additional Packages"), path: "additional", stepIndex: 6, nextStep: "review" },
                        "review": { name: "review", title: LOCALE.maketext("Review"), path: "review", stepIndex: 7, nextStep: "" },
                    },
                },
            };

            oData.getDefaultWizardState = function() {
                return oData.defaultWizardState;
            };

            /**
             * Checks the existence of certain packages and keeps or removes certain steps. After
             * the evaluation it rebuilds the wizard steps accordingly.
             * @param {Object} wizardSteps Object containing wizard steps.
             * @param {Object} rebuildArgs
             * @return {Object} Returns the new rebuilt wizardSteps Object.
             */
            oData.rebuildWizardSteps = function(wizardSteps, rebuildArgs) {
                wizardSteps = wizardSteps || {};
                if (!rebuildArgs.rubyPkgsExist) {
                    delete wizardSteps["ruby"];
                }

                if (!rebuildArgs.additionalPkgsExist) {
                    delete wizardSteps["additional"];
                }

                // Sort the steps. orderby isn't working directly in the ng-repeat (shrug).
                var sortedSteps = _.orderBy(_.values(wizardSteps), ["stepIndex"], ["asc"]);
                wizardSteps = _.keyBy(sortedSteps, function(step) {
                    return step.name;
                });
                return wizardSteps;
            };

            oData.init = function() {
                wizardState.steps = oData.defaultWizardState.steps;
                var pkgList = ea4Data.getData("pkgInfoList");
                if (pkgList) {
                    var rebuildArgs = {
                        rubyPkgsExist: ea4Util.doRubyPkgsExist(pkgList),
                        additionalPkgsExist: ea4Data.getData("additionalPkgsExist"),
                    };
                    wizardState.steps = oData.rebuildWizardSteps(oData.defaultWizardState.steps, rebuildArgs);
                }

                wizardState.showWizard = false;
                wizardState.showSearchAndPage = false;
                wizardState.showFooter = false;
                wizardState.currentStepIndex = 1;
                wizardState.lastStepName = "review";
            };

            oData.updateWizard = function(config) {
                _.each(_.keys(config), function(key) {
                    wizardState[key] = config[key];
                });
            };

            oData.getStepByName = function(stepName) {
                return wizardState.steps[stepName];
            };

            oData.getStepNameByIndex = function(index) {
                var stepObj = _.find(wizardState.steps, ["stepIndex", index]);
                if (typeof stepObj !== "undefined") {
                    return stepObj.name;
                }
            };

            /**
             * Reset the wizard to it initial state. It will forward any
             * arguments passed into the call to the registered
             * function.
             *
             * @name reset
             */
            oData.reset = function() {
                wizardState = oData.getDefaultWizardState();
            };

            /**
             * This function auto updates wizardState to the next step index and go to that step
             * if no arguments are passed.
             * If stepName argument is passed, then it updates the wizardState to the given step,
             * and goes to the given step.
             *
             * @name next
             * @arg stepName [optional] If passed, this method will send to the given step's view.
             */
            oData.next = function(stepName) {
                if (stepName) {
                    wizardState.currentStepIndex = oData.getStepByName(stepName).stepIndex;
                    wizardState.currentStep = stepName;
                } else {
                    wizardState.currentStepIndex++;
                    stepName = oData.getNextStepNameByIndex(wizardState.currentStepIndex);
                    wizardState.currentStep = stepName;
                }
                $location.path(stepName);
            };

            oData.getNextStepNameByIndex = function(index) {
                var lastStepIndex = oData.getLastStep().stepIndex;

                var stepObj = _.find(wizardState.steps, ["stepIndex", index]);
                if (typeof stepObj === "undefined") {

                    // Find the next available step.
                    for (var i = index + 1; i <= lastStepIndex; i++) {
                        stepObj = _.find(wizardState.steps, ["stepIndex", i]);
                        if (stepObj === "undefined") {
                            continue;
                        }
                    }
                }
                return (stepObj) ? stepObj.name : "";
            };

            /**
             * Get the wizard's last step object.
             * @return {Object} Returns wizard step object.
             */
            oData.getLastStep = function() {
                return wizardState.steps[wizardState.lastStepName];
            };

            return {
                init: oData.init,
                getStepByName: oData.getStepByName,
                updateWizard: oData.updateWizard,
                next: oData.next,
                getDefaultWizardState: oData.getDefaultWizardState,
                reset: oData.reset,
                rebuildWizardSteps: oData.rebuildWizardSteps,
                getLastStep: oData.getLastStep,
                getNextStepNameByIndex: oData.getNextStepNameByIndex,
            };
        }]);
    }
);

/*
# whostmgr/docroot/templates/easyapache4/directives/fileModel.js     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
define('app/directives/fileModel',[
    "angular"
], function(angular) {

    // This directive updates the $scope when an <input type="file"> changes.
    // AngularJS ng-model does not keep the state of <input type="file"> linked with $scope.
    angular.module("App")
        .directive("fileModel", ["$parse", function($parse) {
            return {
                restrict: "A",
                require: "ngModel",
                link: function link($scope, $element, $attrs, $ngModelCtrl) {
                    var model = $parse($attrs.fileModel);
                    $element.bind("change", function() {
                        var file = this.files[0];
                        if (file) {
                            $scope.$apply(function() {
                                model.assign($scope, file);

                                // Mark as dirty
                                $ngModelCtrl.$setViewValue($ngModelCtrl.$modelValue);
                                $ngModelCtrl.$setDirty();
                            });
                        }
                    });
                }
            };
        }]);
});

/*
# whostmgr/docroot/templates/cpanel_customization/directive/fileType.js     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global define: false */

define('app/directives/fileType',[
    "angular"
], function(angular) {

    // This directive validates an <input type="file"> based on the "type" property of a selected file.
    // The file-type attribute should contain an expression defining an array of valid types.
    angular.module("App")
        .directive("fileType", [function() {
            function checkType(file, types) {
                var valid = false;
                var fileType = file.type;

                // IE doesn't return file.type for some MIME types.
                // For example it doesn't for 'json' type.
                // FIX: For 'json' in IE browsers.
                // If (file.type is empty){
                //    match file extension with requested type.
                // }
                // NOTE: This is not a fix for all but will cover at least JSON.
                if (fileType === "") {
                    var matchArr = file.name.match(/\.((?:.(?!\.))+)$/);
                    fileType = (matchArr.length > 0) ? matchArr[1] : "";

                    // Hack for json type
                    if (fileType === "json") {
                        fileType = "application/" + fileType;
                    }
                }

                valid = types.some(function(type) {
                    return type === fileType;
                });
                return valid;
            }
            return {
                restrict: "A",
                require: "ngModel",
                link: function link($scope, $element, $attrs, $ngModelCtrl) {
                    $element.bind("change", function() {
                        var file = this.files[0];
                        if (file && !checkType(file, $scope.$eval($attrs.fileType))) {
                            $ngModelCtrl.$setValidity("filetype", false);
                        } else {
                            $ngModelCtrl.$setValidity("filetype", true);
                        }
                    });
                }
            };
        }]);
});

/*
# whostmgr/docroot/templates/cpanel_customization/directive/fileSize.js     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */
define('app/directives/fileSize',[
    "angular"
], function(angular) {

    // This directive validates an <input type="file"> based on the "type" property of a selected file.
    // The file-type attribute should contain an expression defining an array of valid types.
    angular.module("App")
        .directive("fileSize", [function() {

            return {
                restrict: "A",
                require: "ngModel",
                link: function link($scope, $element, $attrs, $ngModelCtrl) {
                    $element.bind("change", function() {
                        var file = this.files[0];
                        if (file) {

                        // Check for empty files being uploaded
                            if (file.size === 0) {
                                $ngModelCtrl.$setValidity("fileSize", false);
                            } else {
                                $ngModelCtrl.$setValidity("fileSize", true);
                            }
                        }
                    });
                }
            };
        }]);
});

/*
# templates/easyapache4/views/profile.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

/* eslint-disable no-console, no-use-before-define, camelcase, no-useless-escape */

define(
    'app/views/profile',[
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

/*
# templates/easyapache4/views/yumUpdate.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    'app/views/yumUpdate',[
        "angular",
        "cjt/util/locale",
        "lodash",
        "cjt/services/alertService",
        "cjt/directives/alertList",
        "app/services/ea4Data",
        "app/services/ea4Util",
        "app/services/pkgResolution"
    ],
    function(angular, LOCALE, _) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("yumUpdate",
            [ "$scope", "$location", "ea4Data", "ea4Util", "alertService", "growl", "growlMessages",
                function($scope, $location, ea4Data, ea4Util, alertService, growl, growlMessages) {
                    $scope.fixFailed = false;
                    var fixYumCache = function() {
                        $scope.fixingYum = true;
                        ea4Data.fixYumCache().then(function(result) {
                            if (result.status && result.data.cache_seems_ok_now) {
                                app.firstLoad = false;
                                ea4Data.setData( { "ea4ThrewError": false } );
                                $location.path("profile");
                            } else {
                                $scope.fixFailed = true;
                            }
                        }, function(error) {
                            $scope.fixFailed = true;
                        }).finally(function() {
                            $scope.fixingYum = false;
                        });
                    };
                    $scope.$on("$viewContentLoaded", function() {

                        // Destroy all old growls when view is loaded.
                        growlMessages.destroyAllMessages();
                        var error = ea4Data.getData("ea4ThrewError");
                        if (error) {
                            fixYumCache();
                        }
                    });
                }]);
    }
);

/*
# cpanel - whostmgr/docroot/templates/easyapache4/views/customize.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'app/views/customize',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/services/ea4Data",
        "app/services/pkgResolution",
    ],
    function(angular, _, LOCALE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("customize",
            [ "$scope", "ea4Data", "pkgResolution", "wizardState", "wizardApi", "$location", "ea4Util",
                function($scope, ea4Data, pkgResolution, wizardState, wizardApi, $location, ea4Util) {
                    $scope.customize = {
                        pkgInfoList: {},
                        selectedPkgs: [],

                        // This contains only the current step's package info.
                        currentPkgInfoList: {},
                        saveProfilePopup: {
                            position: "top",
                            showTop: false,
                            showBottom: false,
                        },

                        // this contains the packages to run the update
                        activeProfilePkgs: [],
                    };

                    $scope.customize.wizard = wizardState;
                    $scope.customize.wizardApi = wizardApi;

                    /* -------  Save As Profile ------- */
                    $scope.customize.showsaveProfilePopup = function(position) {
                        $scope.customize.saveProfilePopup.position = position;
                        if (position !== "top") {
                            $scope.customize.saveProfilePopup.showTop = false;
                            $scope.customize.saveProfilePopup.showBottom = true;
                        } else {
                            $scope.customize.saveProfilePopup.showTop = true;
                            $scope.customize.saveProfilePopup.showBottom = false;
                        }
                    };

                    $scope.customize.clearSaveProfilePopup = function(position) {
                        if (position !== "top") {
                            $scope.customize.saveProfilePopup.showTop = false;
                            $scope.customize.saveProfilePopup.showBottom = false;
                            $scope.customize.saveProfilePopup.position = "top";
                        } else {
                            $scope.customize.saveProfilePopup.showTop = false;
                            $scope.customize.saveProfilePopup.showBottom = false;
                        }
                    };

                    $scope.customize.loadData = function(type) {
                        pkgResolution.resetCommonVariables();
                        $scope.customize.pkgInfoList = ea4Data.getData("pkgInfoList");
                        var customizeMode = ea4Data.getData("customize");
                        if (_.keys($scope.customize.pkgInfoList).length <= 0) {
                            ea4Data.cancelOperation();
                        } else {
                            $scope.customize.selectedPkgs = ea4Data.getData("selectedPkgs");

                            // set showWizard flag
                            wizardApi.updateWizard(
                                {
                                    "showWizard": customizeMode,
                                    "currentStep": type,
                                }
                            );

                            if (type === "review") {
                                ea4Util.hideFooter();
                            } else {
                                ea4Util.showFooter();
                            }
                        }
                    };

                    $scope.customize.processPkgInfoList = function(data) {
                        if (typeof data !== "undefined") {
                            var recos = ea4Data.getData("ea4Recommendations");
                            $scope.customize.pkgInfoList = ea4Data.buildPkgInfoList($scope.customize.selectedPkgs, data, recos);
                            ea4Data.setData({ "pkgInfoList": $scope.customize.pkgInfoList });
                        }
                    };

                    $scope.customize.loadPkgInfoList = function() {
                        pkgResolution.resetCommonVariables();
                        $scope.customize.selectedPkgs = ea4Data.getData("selectedPkgs");

                        var promise = ea4Data.getPkgInfoList();
                        promise.then(function(data) {
                            $scope.customize.processPkgInfoList(data);
                        });
                        return promise;
                    };

                    $scope.customize.proceed = function(step) {
                        ea4Data.setData(
                            {
                                "pkgInfoList": $scope.customize.pkgInfoList,
                                "selectedPkgs": $scope.customize.selectedPkgs,
                            }
                        );
                        wizardApi.next(step);
                    };

                    $scope.customize.getStepClass = function(step) {
                        if (step === $scope.customize.wizard.currentStep) {
                            return "active";
                        }
                    };

                    $scope.customize.getViewWidthCss = function(isWizard) {
                        return (isWizard ? "col-xs-9" : "col-xs-12");
                    };

                    $scope.customize.provisionEA4Updates = function() {

                        // This cancels any previously customized packages.
                        ea4Data.clearEA4LocalStorageItems();
                        ea4Data.setData(
                            {
                                "selectedPkgs": $scope.customize.activeProfilePkgs,
                                "ea4Update": true,
                            });
                        $location.path("review");
                    };

                    $scope.customize.toggleUpdateButton = function() {
                        var updateCount = $scope.customize.checkUpdateInfo.pkgNumber;

                        if (updateCount > 0) {
                            $scope.customize.checkUpdateInfo.btnText = LOCALE.maketext("Update [asis,EasyApache 4]");
                            $scope.customize.checkUpdateInfo.btnTitle = LOCALE.maketext("Update [asis,EasyApache 4]");
                            $scope.customize.checkUpdateInfo.btnCss = "btn-primary";
                        } else {
                            $scope.customize.checkUpdateInfo.btnText = LOCALE.maketext("[asis,EasyApache 4] is up to date[comment,no punctuation due to usage]");
                            $scope.customize.checkUpdateInfo.btnTitle = LOCALE.maketext("[asis,EasyApache 4] is up to date[comment,no punctuation due to usage]");
                            $scope.customize.checkUpdateInfo.btnCss = "btn-primary disabled";
                        }
                    };
                },
            ]
        );
    }
);

/*
# cpanel - whostmgr/docroot/templates/easyapache4/views/loadPackages.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/loadPackages',[
        "angular",
        "lodash",
        "cjt/services/alertService",
    ],
    function(angular, _) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("loadPackages",
            ["$scope", "alertService", "wizardApi", "wizardState", "ea4Data", "ea4Util", "pkgResolution",
                function($scope, alertService, wizardApi, wizardState, ea4Data, ea4Util, pkgResolution) {
                    var loadPkgInfoData = function() {
                        var rawPkgList = ea4Data.getData("ea4RawPkgList");
                        if (rawPkgList === null) {
                            var promise = $scope.customize.loadPkgInfoList();

                            // REFACTOR: ERROR returns should be handled correctly.
                            promise.then(function() {
                                ea4Data.getEA4MetaInfo().then(function(response) {
                                    if (response.data) {
                                        ea4Util.additionalPkgList = response.data.additional_packages;

                                        // Find if additional packages don't exist in the system.
                                        var additionalPkgsExist = ea4Util.doAdditionalPkgsExist(ea4Util.additionalPkgList, $scope.customize.pkgInfoList);
                                        ea4Data.setData({ "additionalPkgsExist": additionalPkgsExist });
                                        var rebuildArgs = {
                                            rubyPkgsExist: ea4Util.doRubyPkgsExist($scope.customize.pkgInfoList),
                                            additionalPkgsExist: additionalPkgsExist,
                                        };
                                        wizardState.steps = wizardApi.rebuildWizardSteps(wizardState.steps, rebuildArgs);
                                        $scope.customize.proceed("mpm");
                                    }
                                }, function(error) {
                                    alertService.add({
                                        type: "danger",
                                        message: error,
                                        id: "alertMessages",
                                        closeable: false,
                                    });
                                });
                            }, function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: error,
                                    id: "alertMessages",
                                    closeable: false,
                                });
                            });
                        } else {
                            pkgResolution.resetCommonVariables();
                            $scope.customize.selectedPkgs = ea4Data.getData("selectedPkgs");
                            $scope.customize.processPkgInfoList(rawPkgList);
                            wizardApi.init();
                            $scope.customize.proceed("mpm");
                        }
                    };

                    $scope.$on("$viewContentLoaded", function() {
                        loadPkgInfoData();
                    });
                },
            ]
        );
    }
);

/*
# templates/easyapache4/views/mpm.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/mpm',[
        "angular",
    ],
    function(angular) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("mpm",
            ["$scope",
                function($scope) {
                    $scope.$on("$viewContentLoaded", function() {
                        $scope.customize.loadData("mpm");
                    });
                }
            ]
        );
    }
);

/*
# templates/easyapache4/views/modules.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/modules',[
        "angular",
    ],
    function(angular) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("modules",
            ["$scope",
                function($scope) {
                    $scope.$on("$viewContentLoaded", function() {
                        $scope.customize.loadData("modules");
                    });
                }
            ]
        );
    }
);

/*
# templates/easyapache4/views/php.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    'app/views/php',[
        "angular",
        "cjt/util/locale"
    ],
    function(angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("php",
            ["$scope", "PAGE",
                function($scope, PAGE) {

                    /**
                    * Builds the CloudLinux promotion banner and shows it off.
                    *
                    * @method setClBanner
                    */
                    var setClBanner = function() {
                        var clData = PAGE.cl_data;
                        var clLicensed = PAGE.cl_licensed;
                        $scope.linkTarget = "_blank";
                        $scope.purchaseLink = "";
                        $scope.clActionText = "";
                        $scope.hasCustomUrl = clData.purchase_cl_data.is_url;

                        if ( typeof clData !== "undefined" ) {
                            var purchaseCLData = clData.purchase_cl_data;
                            if (clData.cl_is_supported && !clData.cl_is_installed && !purchaseCLData.disable_upgrade) {
                                $scope.showCLBanner = true;
                                if (
                                    purchaseCLData.server_timeout ||
                                    purchaseCLData.error_msg && purchaseCLData.error_msg !== "") {
                                    $scope.hideUpgradeOption = true;
                                } else {
                                    $scope.hideUpgradeOption = false;
                                    if (clLicensed) {
                                        $scope.purchaseLink = "scripts13/install_cloudlinux_EA4";
                                        $scope.clActionText = LOCALE.maketext("Install [asis,CloudLinux]");
                                        $scope.linkTarget = "_self"; // No need for popup if staying in WHM
                                    } else {
                                        $scope.purchaseLink = clData.purchase_cl_data.url;
                                        $scope.clActionText = LOCALE.maketext("Upgrade to [asis,CloudLinux]");
                                    }
                                }
                            } else {
                                $scope.showCLBanner = false;
                            }
                            $scope.purchaseClData = purchaseCLData;
                        }
                    };

                    $scope.$on("$viewContentLoaded", function() {
                        $scope.customize.loadData("php");
                        setClBanner();
                    });
                }
            ]
        );
    }
);

/*
# templates/easyapache4/views/extensions.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/extensions',[
        "angular"
    ],
    function(angular) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("extensions",
            ["$scope",
                function($scope) {
                    $scope.$on("$viewContentLoaded", function() {
                        $scope.customize.loadData("extensions");
                    });
                }
            ]
        );
    }
);

/*
# templates/easyapache4/views/additionalPackages.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/additionalPackages',[
        "angular",
    ],
    function(angular) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("additionalPackages",
            ["$scope",
                function($scope) {
                    $scope.$on("$viewContentLoaded", function() {
                        $scope.customize.loadData("additional");
                    });
                }
            ]
        );
    }
);

/*
# templates/easyapache4/views/review.js                   Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/review',[
        "angular",
        "lodash",
        "app/services/ea4Data",
        "app/services/ea4Util"
    ],
    function(angular, _) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("review",
            [ "$scope", "$location", "ea4Data", "ea4Util", "growlMessages",
                function($scope, $location, ea4Data, ea4Util, growlMessages) {
                    $scope.readyToProvision = false;
                    $scope.gettingResults = true;

                    /**
                    * We can send packages from external apps directly to this view.
                    * The data should be sent as querystring params.
                    * 'queryStr' variable will track those params.
                    *
                    * querystring param: 'install': to install a package (can be multiple).
                    * querystring param: 'uninstall': to uninstall a package (can be multiple).
                    * Example:
                    * <url>/<cpsesskey>/scripts7/EasyApache4/review?install=mpm-prefork&install=cgi&uninstall=mpm-worker&uninstall=cgid
                    */
                    var queryStr = {};

                    /**
                    * Prepares the selected packages to be installed and does an
                    * API call to resolve those packages.
                    *
                    * @method prepareForReview
                    * @param {Array} A list of packages to be installed.
                    * @param {String} [Optional] profile id(usually path of a profile).
                    */
                    var prepareForReview = function(packageListForReview, profileId) {

                        // Get status of each package in the package list
                        ea4Data.resolvePackages(packageListForReview).then(function(data) {

                            // Get the packages display format
                            $scope.installList = ea4Util.getFormattedPackageList(data.install);
                            $scope.uninstallList = ea4Util.getFormattedPackageList(data.uninstall);
                            $scope.upgradeList = ea4Util.getFormattedPackageList(data.upgrade);
                            $scope.existingList = ea4Util.getFormattedPackageList(data.unaffected);

                            if (!$scope.installList.length && !$scope.upgradeList.length && !$scope.uninstallList.length) {
                                $scope.noActionRequired = true;
                                return;
                            }

                            // Put all lists into Web Storage
                            ea4Data.setData(
                                {
                                    "provisionActions":
                                    {
                                        profileId: profileId,
                                        install: data.install,
                                        uninstall: data.uninstall,
                                        upgrade: data.upgrade
                                    }
                                });

                            // Enable the Provision button
                            $scope.readyToProvision = true;

                            // Allow provision to run
                            ea4Data.provisionReady(true);
                        }, function(error) {
                            $scope.apiError = true;
                            $scope.yumErrorMessage = error;
                        }).finally(function() {
                            $scope.gettingResults = false;
                        });
                    };

                    /**
                    * update selectedPackages with new install and/or uninstall
                    * packages sent through querystring from directly called from
                    * an external application.
                    * This helps in by-passing customize steps when we need to install
                    * few packages required in other applications.
                    *
                    * @method updateSelPackagesAndReview
                    * @param {Object} angular query string object
                    */
                    var updateSelPackagesAndReview = function(qs) {

                        // 1. Get the current package list.
                        // 2. Add packages that need to be installed to 'selPkgs'
                        // 3. Remove packages that need to be uninstalled from 'selPkgs'.
                        var selPkgs = [];
                        ea4Data.ea4GetCurrentPkgList().then(function(result) {
                            if (result.status) {
                                selPkgs = result.data;

                                // qs["install"] may have a single string or an array of strings.
                                var installList = (_.isArray(qs["install"])) ? qs["install"] : [ qs["install"] ];
                                selPkgs = _.union(selPkgs, installList);

                                // qs["uninstall"] may have a single string or an array of strings.
                                var uninstallList = (_.isArray(qs["uninstall"])) ? qs["uninstall"] : [ qs["uninstall"] ];
                                selPkgs = _.difference(selPkgs, uninstallList);
                                prepareForReview(selPkgs);
                            }
                        });
                    };

                    $scope.$on("$viewContentLoaded", function() {

                        // A list of install/uninstall package set sent through querystring from an external location.
                        queryStr = $location.search();
                        if (!_.isEmpty(queryStr) &&
                        (!_.isEmpty(queryStr["install"]) || !_.isEmpty(queryStr["uninstall"]))) {
                            updateSelPackagesAndReview(queryStr);
                        } else {
                            var customize = ea4Data.getData("customize");
                            var ea4Update = ea4Data.getData("ea4Update");
                            if (customize) {
                                $scope.customize.loadData("review");
                                prepareForReview(ea4Data.getData("selectedPkgs"));
                            } else if (ea4Update) {
                                prepareForReview(ea4Data.getData("selectedPkgs"));
                            } else {
                                var selectedProfile = ea4Data.getData("selectedProfile");
                                if (!selectedProfile) {
                                    ea4Data.cancelOperation();
                                }
                                prepareForReview(selectedProfile.pkgs, selectedProfile.fullPath);
                            }
                        }
                    });

                    $scope.cancel = function() {
                        ea4Data.cancelOperation();
                    };
                }]);
    }
);

/*
# templates/easyapache4/views/provision.js                   Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/provision',[
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

/*
# templates/easyapache4/views/ruby.js                     Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/views/ruby',[
        "angular"
    ],
    function(angular) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("ruby",
            ["$scope",
                function($scope) {
                    $scope.$on("$viewContentLoaded", function() {
                        $scope.customize.loadData("ruby");
                    });
                }
            ]
        );
    }
);

/*
# cpanel - whostmgr/docroot/templates/easyapache4/index.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */

define(
    'app/index',[
        "angular",
        "cjt/core",
        "lodash",
        "cjt/modules",
    ],
    function(angular, CJT, _) {
        "use strict";

        return function() {

            // First create the application
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "cjt2.whm",
                "angular-growl",
                "whm.easyapache4.ea4Util",
                "whm.easyapache4.ea4Data",
                "whm.easyapache4.pkgResolution",
                "whm.easyapache4.wizardApi",
            ]);

            // Then load the application dependencies
            var appModule = require(
                [
                    "cjt/bootstrap",
                    "cjt/util/locale",

                    // Application Modules
                    "cjt/directives/toggleSwitchDirective",
                    "cjt/directives/searchDirective",
                    "app/directives/eaWizard",
                    "app/directives/saveAsProfile",
                    "app/services/ea4Data",
                    "app/services/ea4Util",
                    "app/services/pkgResolution",
                    "app/services/wizardApi",
                    "cjt/views/applicationController",
                    "app/views/profile",
                    "app/views/yumUpdate",
                    "app/views/customize",
                    "app/views/loadPackages",
                    "app/views/mpm",
                    "app/views/modules",
                    "app/views/php",
                    "app/views/extensions",
                    "app/views/additionalPackages",
                    "app/views/review",
                    "app/views/provision",
                    "app/views/ruby",
                ], function(BOOTSTRAP, LOCALE) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    // REFACTOR: This can be sent into ea4Data service.
                    app.firstLoad = true;

                    var wizardState = {};

                    app.value("wizardState", wizardState);

                    app.config(["$routeProvider", "$compileProvider",
                        function($routeProvider, $compileProvider) {

                            // Setup the routes
                            $routeProvider
                                .when("/profile", {
                                    controller: "profile",
                                    templateUrl: CJT.buildFullPath("easyapache4/views/profile.ptt"),
                                })
                                .when("/loadPackages", {
                                    controller: "loadPackages",
                                    templateUrl: CJT.buildFullPath("easyapache4/views/loadPackages.ptt"),
                                })
                                .when("/mpm", {
                                    controller: "mpm",
                                    templateUrl: CJT.buildFullPath("templates/easyapache4/views/mpm.phtml"),
                                })
                                .when("/modules", {
                                    controller: "modules",
                                    templateUrl: CJT.buildFullPath("templates/easyapache4/views/modules.phtml"),
                                })
                                .when("/php", {
                                    controller: "php",
                                    templateUrl: CJT.buildFullPath("easyapache4/views/php.ptt"),
                                })
                                .when("/extensions", {
                                    controller: "extensions",
                                    templateUrl: CJT.buildFullPath("templates/easyapache4/views/extensions.phtml"),
                                })
                                .when("/additional", {
                                    controller: "additionalPackages",
                                    templateUrl: CJT.buildFullPath("templates/easyapache4/views/additionalPackages.phtml"),
                                })
                                .when("/review", {
                                    controller: "review",
                                    templateUrl: CJT.buildFullPath("easyapache4/views/review.ptt"),
                                })
                                .when("/ruby", {
                                    controller: "ruby",
                                    templateUrl: CJT.buildFullPath("templates/easyapache4/views/ruby.phtml"),
                                })
                                .when("/provision", {
                                    controller: "provision",
                                    templateUrl: CJT.buildFullPath("easyapache4/views/provision.ptt"),
                                })
                                .when("/yumUpdate", {
                                    controller: "yumUpdate",
                                    templateUrl: CJT.buildFullPath("easyapache4/views/yumUpdate.ptt"),
                                })
                                .otherwise({
                                    "redirectTo": "/profile",
                                });

                            $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/);

                        },
                    ]);

                    app.run(["$rootScope", "$location", "ea4Util", "wizardApi", "wizardState", function($rootScope, $location, ea4Util, wizardApi, wizardState) {
                        if (_.isEmpty(wizardState)) {
                            wizardApi.init();
                            ea4Util.hideFooter();
                        }

                        // register listener to watch route changes
                        $rootScope.$on("$routeChangeStart", function() {
                            $rootScope.currentRoute = $location.path();
                        });
                    }]);
                    BOOTSTRAP(document);
                }
            );
            return appModule;
        };
    }
);

