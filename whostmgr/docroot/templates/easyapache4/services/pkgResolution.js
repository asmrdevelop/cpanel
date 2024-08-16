/*
# cpanel - whostmgr/docroot/templates/easyapache4/services/pkgResolution.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [
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
