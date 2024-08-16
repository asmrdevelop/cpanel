/*
# app/services/workerNodes.js                      Copyright 2022 cPanel, L.L.C.
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
    ],
    function(angular, _, LOCALE) {

        "use strict";

        var MODULE_NAMESPACE = "whm.transfers.services.workerNodes";
        var SERVICE_NAME = "WorkerNodesService";
        var MODULE_REQUIREMENTS = [];
        var SERVICE_INJECTABLES = ["LOCAL_WORKER_NODES", "REMOTE_WORKER_NODES", "DEFAULT_WORKER_OPTIONS"];

        /**
         * Service for Handling Worker / Linked Nodes
         *
         * @param {object[]} LOCAL_WORKER_NODES local worker nodes possible to be used by accounts
         * @param {object[]} REMOTE_WORKER_NODES remote worker nodes that may or may not be used by individual accounts
         * @param {object} DEFAULT_WORKER_OPTIONS worker type keyed object representing the keys and defaults for the system
         * @returns instance of a workerNodesService
         */
        var SERVICE_FACTORY = function(LOCAL_WORKER_NODES, REMOTE_WORKER_NODES, DEFAULT_WORKER_OPTIONS) {

            var Service = function() {};

            Service.prototype = Object.create({});

            _.assign(Service.prototype, {

                _localWorkerNodes: null,
                _remoteWorkerNodes: null,
                _workerOptionTypes: null,
                _defaultWorkerOptions: null,
                _accountWorkerNodeOptions: {},
                _accountWorkerDefaultValues: {},

                /**
                 * Parse a raw worker node
                 *
                 * @private
                 *
                 * @param {object{alias:string,hostname:string,worker_capabilities:object}} rawWorkerNode raw worker node
                 * @returns {object} parsed worker node
                 */
                _parseWorkerNode: function _parseWorkerNode(rawWorkerNode) {
                    var workerNode = {
                        alias: rawWorkerNode["alias"],
                        hostname: rawWorkerNode["hostname"],
                        workerCapabilities: Object.keys(rawWorkerNode.worker_capabilities),
                    };
                    return workerNode;
                },

                /**
                 * Parse a set of raw worker nodes
                 *
                 * @private
                 *
                 * @param {object[]} rawWorkerNodes raw worker nodes to parse
                 * @returns {object[]} parsed worker nodes
                 */
                _parseWorkerNodes: function _parseWorkerNodes(rawWorkerNodes) {
                    return rawWorkerNodes.map(this._parseWorkerNode);
                },

                /**
                 * Get the listed of remote worker nodes
                 *
                 * @returns {object[]} parsed remote worker nodes
                 */
                getRemoteWorkerNodes: function getRemoteWorkerNodes() {
                    if (_.isNull(this._remoteWorkerNodes)) {
                        this._remoteWorkerNodes = this._parseWorkerNodes(REMOTE_WORKER_NODES);
                    }

                    return this._remoteWorkerNodes;
                },

                /**
                 * Get the list of local worker nodes
                 *
                 * @returns {object[]} parsed local worker nodes
                 */
                getLocalWorkerNodes: function getLocalWorkerNodes() {
                    if (_.isNull(this._localWorkerNodes)) {
                        this._localWorkerNodes = this._parseWorkerNodes(LOCAL_WORKER_NODES);
                    }

                    return this._localWorkerNodes;
                },

                /**
                 * Get the default worker options.
                 * These are the settings that determine which workers, what defaults, and what the modelKey is
                 *
                 * @returns {object} worker type keyed object
                 */
                getDefaultWorkerOptions: function getDefaultWorkerOptions() {
                    if ( _.isNull(this._defaultWorkerOptions) ) {
                        this._defaultWorkerOptions = DEFAULT_WORKER_OPTIONS;

                        // Check to ensure the default exists, if not, set it to local
                        Object.keys(this._defaultWorkerOptions).filter(function(workerType) {
                            return !this.getWorkerByAlias(this.getLocalWorkerNodes(), this._defaultWorkerOptions[workerType].value);
                        }, this).forEach(function(workerType) {

                            // These don't exist locally, so we should restore to controller
                            this._defaultWorkerOptions[workerType].value = ".local";
                        }, this);
                    }
                    return this._defaultWorkerOptions;
                },

                /**
                 * Get a list of worker options that are supported
                 *
                 * @returns {string[]} array of strings representing the worker types supported
                 *
                 * @example
                 * this.getWorkerOptionTypes(); // ['Mail', 'Web']
                 */
                getWorkerOptionTypes: function getWorkerOptionTypes() {
                    if (_.isNull(this._workerOptionTypes)) {
                        this._workerOptionTypes = Object.keys(this.getDefaultWorkerOptions());
                    }
                    return this._workerOptionTypes;
                },

                /**
                 * Look up a worker based on the hostname and type
                 *
                 * @param {object[]} workerList list of workers to search
                 * @param {string} hostname hostname of the worker 'host.name.com'
                 * @param {string} desiredWorkerType worker type 'Mail' etc
                 * @returns {object|null} worker type if it matches the hostname and type
                 */
                getWorkerByHostname: function getWorkerByHostname(workerList, hostname, desiredWorkerType) {
                    if (!workerList) {
                        return;
                    }

                    return _.find(workerList, function(worker) {
                        return worker.hostname === hostname && worker.workerCapabilities.indexOf(desiredWorkerType) > -1;
                    });
                },

                /**
                 * Get a worker from a worker list based on the alias
                 *
                 * @param {object[]} workerList list of workers to search
                 * @param {string} alias alias for which to search
                 * @returns {object|null} returns the worker object if it exists
                 */
                getWorkerByAlias: function getWorkerByAlias(workerList, alias) {
                    if (!workerList) {
                        return;
                    }

                    return _.find(workerList, function(worker) {
                        return worker.alias === alias;
                    });
                },

                /**
                 * Build an item for a worker list of a specific type
                 *
                 * @private
                 *
                 * @param {string} label descriptive label of the item
                 * @param {string} value specific key value for comparison
                 * @param {string} type type of worker (Mail, etc)
                 * @returns {object} worker item
                 */
                _createWorkerListTypeItem: function _createWorkerListTypeItem(label, value, type) {
                    var defaultWorkerOptions = this.getDefaultWorkerOptions();
                    var workerOption = {
                        label: label,
                        value: value,
                        modelKey: defaultWorkerOptions[type].modelKey,
                    };
                    return workerOption;
                },


                /**
                 * Build an options list for a specific type of worker for a specific account
                 *
                 * @private
                 *
                 * @param {object} account account to base to list from
                 * @param {string} workerType type of worker to build the list for
                 * @returns {object[]} list of worker options for the account
                 */
                _createAccountWorkerListType: function _createAccountWorkerListType(account, workerType) {
                    var defaultWorkerOptions = this.getDefaultWorkerOptions();
                    var remoteWorkerNodes = this.getRemoteWorkerNodes();
                    var localWorkerNodes = this.getLocalWorkerNodes();

                    var existingNodeFound;
                    var workerTypeList = [];

                    // Add local, should always be an option
                    workerTypeList.push( this._createWorkerListTypeItem( LOCALE.maketext("Use only this server. Transfer or restore locally."), ".local", workerType) );

                    // Check for a local alias that matches the hostname and workertype of the remote user type
                    if (account.workerNodes && account.workerNodes[workerType]) {
                        var remoteWorker = this.getWorkerByAlias(remoteWorkerNodes, account.workerNodes[workerType]);
                        var matchingLocalWorker = remoteWorker && this.getWorkerByHostname(localWorkerNodes, remoteWorker.hostname, workerType);
                        if (matchingLocalWorker) {
                            existingNodeFound = matchingLocalWorker.alias;
                            workerTypeList.push(this._createWorkerListTypeItem( LOCALE.maketext("Use the [asis,cPanel] account’s package configuration.") + " (" + matchingLocalWorker.hostname + ")", existingNodeFound, workerType) );
                        }
                    }

                    // Add the rest
                    localWorkerNodes.filter(function(workerNode) {
                        return workerNode.alias !== existingNodeFound;
                    }).forEach(function(workerNode) {
                        workerTypeList.push( this._createWorkerListTypeItem(workerNode.alias + " (" + workerNode.hostname + ")", workerNode.alias, workerType) );
                    }, this);

                    var defaultAlias = existingNodeFound ? existingNodeFound : defaultWorkerOptions[workerType].value;

                    workerTypeList.filter(function(workerItem) {
                        return workerItem.value === defaultAlias;
                    }).forEach(function(workerItem) {
                        workerItem.isDefault = true;
                    });

                    return workerTypeList;
                },

                /**
                 * See <getAccountWorkerNodeOptions>
                 *
                 * @private
                 */
                _createAccountWorkerLists: function _createAccountWorkerLists(account) {
                    var workerLists = {};
                    this.getWorkerOptionTypes().forEach(function(workerType) {
                        workerLists[workerType] = this._createAccountWorkerListType(account, workerType);
                    }, this);
                    return workerLists;
                },

                /**
                 * Build all the worker options for all supported types for an account
                 *
                 * @private
                 *
                 * @param {object} account
                 * @returns {object} object with lists based on specific type
                 *
                 * @example
                 * this.getAccountWorkerNodeOptions(acccount); // {'Mail':[{label:"",value,"",modelKey:"",isDefault:false},{},{},...], 'Web':[], ...}
                 */
                getAccountWorkerNodeOptions: function getAccountWorkerNodeOptions(account) {

                    var cacheKey = this._getAccountCacheKey(account);

                    if (_.isUndefined(this._accountWorkerNodeOptions[cacheKey])) {
                        this._accountWorkerNodeOptions[cacheKey] = this._createAccountWorkerLists(account);
                    }
                    return this._accountWorkerNodeOptions[cacheKey];
                },


                /**
                 * Determine if any of the worker options for an account have been altered from the default
                 *
                 * @param {object} account account to check
                 * @returns {boolean} has the account's worker options been altered
                 */
                checkWorkerOptionsAltered: function checkWorkerOptionsAltered(account) {
                    return this.getAccountWorkerDefaultValues(account).some(function(workerDefaultObj) {
                        var modelKey = workerDefaultObj.modelKey;
                        var defaultValue = workerDefaultObj.value;
                        if (account[modelKey] !== defaultValue) {
                            return true;
                        }
                        return false;
                    });
                },

                /**
                 * Get the default worker values for an account. Used to establish initial values
                 *
                 * @param {object} account account to build the list from
                 * @returns {object[]} returns a list of modelKey and values for an account
                 *
                 * @example
                 * this.getAccountWorkerDefaultValues(account); // [{modelKey:"mail_location", value:'the_default_value"},...]
                 */
                getAccountWorkerDefaultValues: function getAccountWorkerDefaultValues(account) {
                    var cacheKey = this._getAccountCacheKey(account);

                    if (_.isUndefined(this._accountWorkerDefaultValues[cacheKey])) {
                        var workerNodeOptions = this.getAccountWorkerNodeOptions(account);
                        var defaultWorkerOptions = this.getDefaultWorkerOptions();

                        var accountDefaults = [];

                        Object.keys(workerNodeOptions).forEach(function(workerType) {
                            var accountDefault = {
                                workerType: workerType,
                                modelKey: defaultWorkerOptions[workerType].modelKey
                            };

                            workerNodeOptions[workerType].forEach(function(workerOption) {
                                if (workerOption.isDefault) {
                                    accountDefault.value = workerOption.value;
                                }
                            });

                            if (!accountDefault.value) {
                                accountDefault.value = defaultWorkerOptions[workerType].value;
                            }

                            accountDefaults.push(accountDefault);
                        });

                        this._accountWorkerDefaultValues[cacheKey] = accountDefaults;
                    }

                    return this._accountWorkerDefaultValues[cacheKey];
                },

                /**
                 * Reset an account's worker settings to the defaults for that account
                 *
                 * @param {object} account
                 */
                resetAccountToDefaults: function resetAccountToDefaults(account) {

                    // Get Worker Node Default Values (this is specific to the individual account)
                    var defaultValues = this.getAccountWorkerDefaultValues(account);
                    defaultValues.forEach(function(defaultValueObj) {
                        account[defaultValueObj.modelKey] = defaultValueObj.value;
                    }, this);
                },

                /**
                 * Build a key to use for caching account lists
                 *
                 * @private
                 *
                 * @param {object} account account for which to build the key
                 * @returns {string} a string combination of the remote_user and domain, combined with a pipe
                 */
                _getAccountCacheKey: function _getAccountCacheKey(account) {

                    // This is probably over-safe. remote_user _shouldn't_ change
                    return account.remote_user + "|" + account.domain;
                }


            });

            return new Service();
        };

        SERVICE_INJECTABLES.push(SERVICE_FACTORY);

        var app = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);

        // This determines which options are revealed
        app.value("DEFAULT_WORKER_OPTIONS", {
            "Mail": {
                value: ".local",
                modelKey: "mail_location"
            }
        });

        app.factory(SERVICE_NAME, SERVICE_INJECTABLES);

        return {
            "class": SERVICE_FACTORY,
            "serviceName": SERVICE_NAME,
            "namespace": MODULE_NAMESPACE
        };
    }
);
