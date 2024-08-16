/*
# app/services/workerNodes.js                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    'app/services/workerNodes',[
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

/*
# templates/transfer_tool/controllers/AccountTableController.js     Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

/* jshint -W003 */
/* jshint -W098*/

define(
    'app/directives/accountExpandPanel',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/services/workerNodes",
    ],
    function(angular, _, LOCALE, WorkerNodesService) {

        "use strict";

        var MODULE_NAMESPACE = "whm.transfers.directives.accountExpandPanel";
        var MODULE_INJECTABLES = [WorkerNodesService.namespace];

        var DIRECTIVE_NAME = "accountExpandPanel";

        /* embedded in getacctlist.tmpl so relative pathing is not necessary */
        var DIRECTIVE_TEMPLATE = "directives/accountExpandPanel.ptt";

        var CONTROLLER_INJECTABLES = ["$scope", WorkerNodesService.serviceName ];
        var CONTROLLER = function AccountExpandPanelController($scope, $workerNodesService) {

            function _resetSkipOption(skipOption) {
                $scope.account[skipOption.modelKey] = skipOption.default;
                $scope.skipOptionChanged(skipOption);
            }

            function _resetWorkerType(workerDefaultValueObj) {
                var modelKey = workerDefaultValueObj.modelKey;
                var defaultValue = workerDefaultValueObj.value;
                var workerType = workerDefaultValueObj.workerType;

                $scope.account[modelKey] = defaultValue;
                $scope.workerNodeOption[workerType] = $scope.findWorkerOptionByValue(workerType, defaultValue);
                $scope.workerNodeOptionChanged(workerType);
            }

            /**
             * Function Called when reset button is clicked from the view
             *
             */
            $scope.resetToDefaultClicked = function resetToDefaultClicked() {
                if ($scope.account.proxyOption) {
                    $scope.account.proxyOption.value = $scope.account.proxyOption.default;
                }
                $scope.skipOptions.forEach(_resetSkipOption);
                $workerNodesService.getAccountWorkerDefaultValues($scope.account).forEach(_resetWorkerType);
            };

            /**
             * Function called when 'apply to all' button is clicked from the view
             *
             */
            $scope.applyToAllClicked = function allToAllClicked() {
                $scope.onApplyToAll({ updatedAccount: $scope.account, skipOptions: $scope.skipOptions, workerOptions: $scope.workerNodeOption, proxyOption: $scope.account.proxyOption });
            };

            /**
             * Function called on change of a specific option from the view
             *
             * @param {object} skipOption
             */
            $scope.skipOptionChanged = function skipOptionChanged(skipOption) {
                $scope.onChange({ updatedAccount: $scope.account, modelKey: skipOption.modelKey, value: $scope.account[skipOption.modelKey] });
            };

            /**
             * Function called on change of proxying option froom view
             * @param  {object} proxyOption
             */
            $scope.proxyOptionChanged = function proxyOptionChanged(proxyOption) {
                $scope.onChange({ updatedAccount: $scope.account, modelKey: proxyOption.modelKey, value: !proxyOption.value });
            };

            /**
             * Check if all options are set to default
             *
             * @returns {boolean} If all options match the default, this is true, else false
             */
            $scope.isSetToDefault = function isSetToDefault() {
                return !$scope._skipOptionsAltered() && !$scope._workerOptionsAltered() && !$scope._proxyOptionAltered();
            };

            /**
             * Determine the number of accounts selected based on whether this account is selected or not
             *
             * @returns {number} Number of accounts selected
             */
            $scope.getOtherSelectedAccountsCount = function getOtherSelectedAccountsCount() {
                var count = $scope.selectedAccountsCount;
                if ($scope.account.selected && count > 0) {
                    count--;
                }
                return count;
            };

            /**
             * Dispatches a close call to allow the closing of the expansion panel
             *
             */
            $scope.applyAndClose = function applyAndClose() {
                $scope.onClose({ updatedAccount: $scope.account });
            };

            /**
             * Check to see if any skip options are altered
             *
             * @returns {boolean} returns true if any are altered
             */
            $scope._skipOptionsAltered = function _skipOptionsAltered() {
                return $scope.skipOptions.some(function(skipOption) {
                    if ($scope.account[skipOption.modelKey] !== skipOption.default) {
                        return true;
                    }
                    return false;
                });
            };

            /**
             * Check to see if proxying option has been changed
             * @return {boolean}
             */
            $scope._proxyOptionAltered = function _proxyOptionAltered() {
                if ($scope.account.proxyOption) {
                    return $scope.account.proxyOption.value !== $scope.account.proxyOption.default;
                }
                return false;
            };

            /**
             * Check to see if any worker options are altered
             *
             * @returns {boolean} returns true if any are altered
             */
            $scope._workerOptionsAltered = function _workerOptionsAltered() {
                return $workerNodesService.checkWorkerOptionsAltered($scope.account);
            };

            /**
             * Get the label for a worker option menu
             *
             * @param {string} workerType string identifier of the node type (Mail)
             * @returns {string} localized label
             */
            $scope.getWorkerConfigLabel = function getWorkerConfigLabel(workerType) {
                switch (workerType.toLowerCase()) {
                    case "mail":
                        return LOCALE.maketext("Mail");
                }
            };

            /**
             * Called when a worker node option changes
             *
             * @param {string} workerType the worker type that changed
             */
            $scope.workerNodeOptionChanged = function workerNodeOptionChanged(workerType) {
                var worker = $workerNodesService.getDefaultWorkerOptions()[workerType];
                $scope.onChange({ updatedAccount: $scope.account, modelKey: worker.modelKey, value: $scope.workerNodeOption[workerType].value });
            };

            /**
             * Find a specific worker option (object) by the .value property
             *
             * @param {string} workerType the worker type to search
             * @param {string} value the specific value to look for
             * @returns {object|null} returns the object if found
             */
            $scope.findWorkerOptionByValue = function findWorkerOptionByValue(workerType, value) {
                return _.find($scope.workerNodeOptions[workerType], function(workerOption) {
                    if (workerOption.value === value) {
                        return true;
                    }
                    return false;
                });
            };

            /**
             * Set the current value of a worker type (done on intiation)
             *
             * @param {string} workerType worker type to set
             */
            $scope.setCurrentWorkerTypeValue = function setCurrentWorkerTypeValue(workerType) {
                var modelKey = $workerNodesService.getDefaultWorkerOptions()[workerType].modelKey;
                $scope.workerNodeOption[workerType] = $scope.findWorkerOptionByValue(workerType, $scope.account[modelKey]);
            };

            // Build Worker Option Sets
            $scope.workerNodeOptions = $workerNodesService.getAccountWorkerNodeOptions($scope.account);
            $scope.workerNodeOption = {};

            $workerNodesService.getWorkerOptionTypes().forEach(function(workerType) {
                $scope.setCurrentWorkerTypeValue(workerType);
                var modelKey = $workerNodesService.getDefaultWorkerOptions()[workerType].modelKey;

                // Watch changes on the account
                $scope.$watch(function() {
                    return $scope.account[modelKey];
                }, function() {
                    $scope.setCurrentWorkerTypeValue(workerType);
                });
            });

            // We should only show worker choices if there is greater than one thing to choose
            // because only one thing means that there is only .local
            $scope.showWorkerNodeOptions = $workerNodesService.getWorkerOptionTypes().some(function(typeKey) {
                if ($scope.workerNodeOptions[typeKey].length > 1) {
                    return true;
                }
                return false;
            });
        };
        var LINK = function AccountExpandPanelLink($scope, element, attrs) {
            if ( _.isUndefined($scope.parentID) ) {
                throw new Error("“id” must be set for " + DIRECTIVE_NAME);
            }

            if ( _.isUndefined($scope.account) ) {
                throw new Error("“account” must be set for " + DIRECTIVE_NAME);
            }

            if ( _.isUndefined($scope.selectedAccountsCount) ) {
                throw new Error("“selectedAccountsCount” must be set for " + DIRECTIVE_NAME);
            }

            if (!$scope.skipOptions) {
                $scope.skipOptions = [];
            }

            $scope.selectedAccountsCount = parseInt($scope.selectedAccountsCount, 10);

            $scope.skipOptions.forEach(function validateSkipOption(skipOption) {
                var requiredParameters = ["label", "id", "modelKey", "default"];
                requiredParameters.forEach(function(param) {
                    if ( _.isUndefined(skipOption[param]) ) {
                        throw new Error("[" + DIRECTIVE_NAME + "] all skip-options items must have the following parameters:\n" + requiredParameters.join(", ") + "\nInvalid item:\n" + JSON.stringify(skipOption));
                    }
                });

                skipOption.id = $scope.parentID + "_" + skipOption.id;
            });
        };
        var DIRECTIVE_FACTORY = function DirectiveFactory() {

            return {
                restrict: "E",
                transclude: true,
                scope: {
                    parentID: "@id",
                    skipOptions: "=",
                    proxyOption: "=",
                    account: "=",
                    selectedAccountsCount: "@",
                    onApplyToAll: "&onApplyToAll",
                    onChange: "&onChange",
                    onClose: "&onClose",
                },
                link: LINK,
                controller: CONTROLLER_INJECTABLES.concat(CONTROLLER),
                templateUrl: DIRECTIVE_TEMPLATE,

            };
        };

        var module = angular.module(MODULE_NAMESPACE, MODULE_INJECTABLES);
        module.directive(DIRECTIVE_NAME, DIRECTIVE_FACTORY);

        return {
            namespace: MODULE_NAMESPACE,
            class: CONTROLLER,
            factory: LINK,
            template: DIRECTIVE_TEMPLATE
        };

    }
);

define(
    'app/overwriteStates',[],
    function() {
        "use strict";

        var OVERWRITE_STATES = {
            NO_OVERWRITE: "noOverwrite",
            OVERWRITE: "overwrite",
            OVERWRITE_WITH_DELETE: "overwriteWithDelete",
        };

        return OVERWRITE_STATES;
    }
);

define(
    'app/overwriteOptions',[
        "app/overwriteStates",
        "cjt/util/locale",
    ],
    function(OVERWRITE_STATES, LOCALE) {
        "use strict";

        var OVERWRITE_OPTIONS = [
            { label: LOCALE.maketext("Do Not Overwrite"), value: OVERWRITE_STATES.NO_OVERWRITE  },
            { label: LOCALE.maketext("Overwrite"), value: OVERWRITE_STATES.OVERWRITE  },
            { label: LOCALE.maketext("Overwrite with Delete"), value: OVERWRITE_STATES.OVERWRITE_WITH_DELETE  },
        ];

        return OVERWRITE_OPTIONS;
    }
);

(function(root) {
define("jquery-chosen", ["jquery"], function() {
  return (function() {
/*!
Chosen, a Select Box Enhancer for jQuery and Prototype
by Patrick Filler for Harvest, http://getharvest.com

Version 1.5.1
Full source at https://github.com/harvesthq/chosen
Copyright (c) 2011-2016 Harvest http://getharvest.com

MIT License, https://github.com/harvesthq/chosen/blob/master/LICENSE.md
This file is generated by `grunt build`, do not edit it by hand.
*/

(function() {
  var $, AbstractChosen, Chosen, SelectParser, _ref,
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  SelectParser = (function() {
    function SelectParser() {
      this.options_index = 0;
      this.parsed = [];
    }

    SelectParser.prototype.add_node = function(child) {
      if (child.nodeName.toUpperCase() === "OPTGROUP") {
        return this.add_group(child);
      } else {
        return this.add_option(child);
      }
    };

    SelectParser.prototype.add_group = function(group) {
      var group_position, option, _i, _len, _ref, _results;
      group_position = this.parsed.length;
      this.parsed.push({
        array_index: group_position,
        group: true,
        label: this.escapeExpression(group.label),
        title: group.title ? group.title : void 0,
        children: 0,
        disabled: group.disabled,
        classes: group.className
      });
      _ref = group.childNodes;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        option = _ref[_i];
        _results.push(this.add_option(option, group_position, group.disabled));
      }
      return _results;
    };

    SelectParser.prototype.add_option = function(option, group_position, group_disabled) {
      if (option.nodeName.toUpperCase() === "OPTION") {
        if (option.text !== "") {
          if (group_position != null) {
            this.parsed[group_position].children += 1;
          }
          this.parsed.push({
            array_index: this.parsed.length,
            options_index: this.options_index,
            value: option.value,
            text: option.text,
            html: option.innerHTML,
            title: option.title ? option.title : void 0,
            selected: option.selected,
            disabled: group_disabled === true ? group_disabled : option.disabled,
            group_array_index: group_position,
            group_label: group_position != null ? this.parsed[group_position].label : null,
            classes: option.className,
            style: option.style.cssText
          });
        } else {
          this.parsed.push({
            array_index: this.parsed.length,
            options_index: this.options_index,
            empty: true
          });
        }
        return this.options_index += 1;
      }
    };

    SelectParser.prototype.escapeExpression = function(text) {
      var map, unsafe_chars;
      if ((text == null) || text === false) {
        return "";
      }
      if (!/[\&\<\>\"\'\`]/.test(text)) {
        return text;
      }
      map = {
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#x27;",
        "`": "&#x60;"
      };
      unsafe_chars = /&(?!\w+;)|[\<\>\"\'\`]/g;
      return text.replace(unsafe_chars, function(chr) {
        return map[chr] || "&amp;";
      });
    };

    return SelectParser;

  })();

  SelectParser.select_to_array = function(select) {
    var child, parser, _i, _len, _ref;
    parser = new SelectParser();
    _ref = select.childNodes;
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      child = _ref[_i];
      parser.add_node(child);
    }
    return parser.parsed;
  };

  AbstractChosen = (function() {
    function AbstractChosen(form_field, options) {
      this.form_field = form_field;
      this.options = options != null ? options : {};
      if (!AbstractChosen.browser_is_supported()) {
        return;
      }
      this.is_multiple = this.form_field.multiple;
      this.set_default_text();
      this.set_default_values();
      this.setup();
      this.set_up_html();
      this.register_observers();
      this.on_ready();
    }

    AbstractChosen.prototype.set_default_values = function() {
      var _this = this;
      this.click_test_action = function(evt) {
        return _this.test_active_click(evt);
      };
      this.activate_action = function(evt) {
        return _this.activate_field(evt);
      };
      this.active_field = false;
      this.mouse_on_container = false;
      this.results_showing = false;
      this.result_highlighted = null;
      this.allow_single_deselect = (this.options.allow_single_deselect != null) && (this.form_field.options[0] != null) && this.form_field.options[0].text === "" ? this.options.allow_single_deselect : false;
      this.disable_search_threshold = this.options.disable_search_threshold || 0;
      this.disable_search = this.options.disable_search || false;
      this.enable_split_word_search = this.options.enable_split_word_search != null ? this.options.enable_split_word_search : true;
      this.group_search = this.options.group_search != null ? this.options.group_search : true;
      this.search_contains = this.options.search_contains || false;
      this.single_backstroke_delete = this.options.single_backstroke_delete != null ? this.options.single_backstroke_delete : true;
      this.max_selected_options = this.options.max_selected_options || Infinity;
      this.inherit_select_classes = this.options.inherit_select_classes || false;
      this.display_selected_options = this.options.display_selected_options != null ? this.options.display_selected_options : true;
      this.display_disabled_options = this.options.display_disabled_options != null ? this.options.display_disabled_options : true;
      this.include_group_label_in_selected = this.options.include_group_label_in_selected || false;
      return this.max_shown_results = this.options.max_shown_results || Number.POSITIVE_INFINITY;
    };

    AbstractChosen.prototype.set_default_text = function() {
      if (this.form_field.getAttribute("data-placeholder")) {
        this.default_text = this.form_field.getAttribute("data-placeholder");
      } else if (this.is_multiple) {
        this.default_text = this.options.placeholder_text_multiple || this.options.placeholder_text || AbstractChosen.default_multiple_text;
      } else {
        this.default_text = this.options.placeholder_text_single || this.options.placeholder_text || AbstractChosen.default_single_text;
      }
      return this.results_none_found = this.form_field.getAttribute("data-no_results_text") || this.options.no_results_text || AbstractChosen.default_no_result_text;
    };

    AbstractChosen.prototype.choice_label = function(item) {
      if (this.include_group_label_in_selected && (item.group_label != null)) {
        return "<b class='group-name'>" + item.group_label + "</b>" + item.html;
      } else {
        return item.html;
      }
    };

    AbstractChosen.prototype.mouse_enter = function() {
      return this.mouse_on_container = true;
    };

    AbstractChosen.prototype.mouse_leave = function() {
      return this.mouse_on_container = false;
    };

    AbstractChosen.prototype.input_focus = function(evt) {
      var _this = this;
      if (this.is_multiple) {
        if (!this.active_field) {
          return setTimeout((function() {
            return _this.container_mousedown();
          }), 50);
        }
      } else {
        if (!this.active_field) {
          return this.activate_field();
        }
      }
    };

    AbstractChosen.prototype.input_blur = function(evt) {
      var _this = this;
      if (!this.mouse_on_container) {
        this.active_field = false;
        return setTimeout((function() {
          return _this.blur_test();
        }), 100);
      }
    };

    AbstractChosen.prototype.results_option_build = function(options) {
      var content, data, data_content, shown_results, _i, _len, _ref;
      content = '';
      shown_results = 0;
      _ref = this.results_data;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        data = _ref[_i];
        data_content = '';
        if (data.group) {
          data_content = this.result_add_group(data);
        } else {
          data_content = this.result_add_option(data);
        }
        if (data_content !== '') {
          shown_results++;
          content += data_content;
        }
        if (options != null ? options.first : void 0) {
          if (data.selected && this.is_multiple) {
            this.choice_build(data);
          } else if (data.selected && !this.is_multiple) {
            this.single_set_selected_text(this.choice_label(data));
          }
        }
        if (shown_results >= this.max_shown_results) {
          break;
        }
      }
      return content;
    };

    AbstractChosen.prototype.result_add_option = function(option) {
      var classes, option_el;
      if (!option.search_match) {
        return '';
      }
      if (!this.include_option_in_results(option)) {
        return '';
      }
      classes = [];
      if (!option.disabled && !(option.selected && this.is_multiple)) {
        classes.push("active-result");
      }
      if (option.disabled && !(option.selected && this.is_multiple)) {
        classes.push("disabled-result");
      }
      if (option.selected) {
        classes.push("result-selected");
      }
      if (option.group_array_index != null) {
        classes.push("group-option");
      }
      if (option.classes !== "") {
        classes.push(option.classes);
      }
      option_el = document.createElement("li");
      option_el.className = classes.join(" ");
      option_el.style.cssText = option.style;
      option_el.setAttribute("data-option-array-index", option.array_index);
      option_el.innerHTML = option.search_text;
      if (option.title) {
        option_el.title = option.title;
      }
      return this.outerHTML(option_el);
    };

    AbstractChosen.prototype.result_add_group = function(group) {
      var classes, group_el;
      if (!(group.search_match || group.group_match)) {
        return '';
      }
      if (!(group.active_options > 0)) {
        return '';
      }
      classes = [];
      classes.push("group-result");
      if (group.classes) {
        classes.push(group.classes);
      }
      group_el = document.createElement("li");
      group_el.className = classes.join(" ");
      group_el.innerHTML = group.search_text;
      if (group.title) {
        group_el.title = group.title;
      }
      return this.outerHTML(group_el);
    };

    AbstractChosen.prototype.results_update_field = function() {
      this.set_default_text();
      if (!this.is_multiple) {
        this.results_reset_cleanup();
      }
      this.result_clear_highlight();
      this.results_build();
      if (this.results_showing) {
        return this.winnow_results();
      }
    };

    AbstractChosen.prototype.reset_single_select_options = function() {
      var result, _i, _len, _ref, _results;
      _ref = this.results_data;
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        result = _ref[_i];
        if (result.selected) {
          _results.push(result.selected = false);
        } else {
          _results.push(void 0);
        }
      }
      return _results;
    };

    AbstractChosen.prototype.results_toggle = function() {
      if (this.results_showing) {
        return this.results_hide();
      } else {
        return this.results_show();
      }
    };

    AbstractChosen.prototype.results_search = function(evt) {
      if (this.results_showing) {
        return this.winnow_results();
      } else {
        return this.results_show();
      }
    };

    AbstractChosen.prototype.winnow_results = function() {
      var escapedSearchText, option, regex, results, results_group, searchText, startpos, text, zregex, _i, _len, _ref;
      this.no_results_clear();
      results = 0;
      searchText = this.get_search_text();
      escapedSearchText = searchText.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, "\\$&");
      zregex = new RegExp(escapedSearchText, 'i');
      regex = this.get_search_regex(escapedSearchText);
      _ref = this.results_data;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        option = _ref[_i];
        option.search_match = false;
        results_group = null;
        if (this.include_option_in_results(option)) {
          if (option.group) {
            option.group_match = false;
            option.active_options = 0;
          }
          if ((option.group_array_index != null) && this.results_data[option.group_array_index]) {
            results_group = this.results_data[option.group_array_index];
            if (results_group.active_options === 0 && results_group.search_match) {
              results += 1;
            }
            results_group.active_options += 1;
          }
          option.search_text = option.group ? option.label : option.html;
          if (!(option.group && !this.group_search)) {
            option.search_match = this.search_string_match(option.search_text, regex);
            if (option.search_match && !option.group) {
              results += 1;
            }
            if (option.search_match) {
              if (searchText.length) {
                startpos = option.search_text.search(zregex);
                text = option.search_text.substr(0, startpos + searchText.length) + '</em>' + option.search_text.substr(startpos + searchText.length);
                option.search_text = text.substr(0, startpos) + '<em>' + text.substr(startpos);
              }
              if (results_group != null) {
                results_group.group_match = true;
              }
            } else if ((option.group_array_index != null) && this.results_data[option.group_array_index].search_match) {
              option.search_match = true;
            }
          }
        }
      }
      this.result_clear_highlight();
      if (results < 1 && searchText.length) {
        this.update_results_content("");
        return this.no_results(searchText);
      } else {
        this.update_results_content(this.results_option_build());
        return this.winnow_results_set_highlight();
      }
    };

    AbstractChosen.prototype.get_search_regex = function(escaped_search_string) {
      var regex_anchor;
      regex_anchor = this.search_contains ? "" : "^";
      return new RegExp(regex_anchor + escaped_search_string, 'i');
    };

    AbstractChosen.prototype.search_string_match = function(search_string, regex) {
      var part, parts, _i, _len;
      if (regex.test(search_string)) {
        return true;
      } else if (this.enable_split_word_search && (search_string.indexOf(" ") >= 0 || search_string.indexOf("[") === 0)) {
        parts = search_string.replace(/\[|\]/g, "").split(" ");
        if (parts.length) {
          for (_i = 0, _len = parts.length; _i < _len; _i++) {
            part = parts[_i];
            if (regex.test(part)) {
              return true;
            }
          }
        }
      }
    };

    AbstractChosen.prototype.choices_count = function() {
      var option, _i, _len, _ref;
      if (this.selected_option_count != null) {
        return this.selected_option_count;
      }
      this.selected_option_count = 0;
      _ref = this.form_field.options;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        option = _ref[_i];
        if (option.selected) {
          this.selected_option_count += 1;
        }
      }
      return this.selected_option_count;
    };

    AbstractChosen.prototype.choices_click = function(evt) {
      evt.preventDefault();
      if (!(this.results_showing || this.is_disabled)) {
        return this.results_show();
      }
    };

    AbstractChosen.prototype.keyup_checker = function(evt) {
      var stroke, _ref;
      stroke = (_ref = evt.which) != null ? _ref : evt.keyCode;
      this.search_field_scale();
      switch (stroke) {
        case 8:
          if (this.is_multiple && this.backstroke_length < 1 && this.choices_count() > 0) {
            return this.keydown_backstroke();
          } else if (!this.pending_backstroke) {
            this.result_clear_highlight();
            return this.results_search();
          }
          break;
        case 13:
          evt.preventDefault();
          if (this.results_showing) {
            return this.result_select(evt);
          }
          break;
        case 27:
          if (this.results_showing) {
            this.results_hide();
          }
          return true;
        case 9:
        case 38:
        case 40:
        case 16:
        case 91:
        case 17:
        case 18:
          break;
        default:
          return this.results_search();
      }
    };

    AbstractChosen.prototype.clipboard_event_checker = function(evt) {
      var _this = this;
      return setTimeout((function() {
        return _this.results_search();
      }), 50);
    };

    AbstractChosen.prototype.container_width = function() {
      if (this.options.width != null) {
        return this.options.width;
      } else {
        return "" + this.form_field.offsetWidth + "px";
      }
    };

    AbstractChosen.prototype.include_option_in_results = function(option) {
      if (this.is_multiple && (!this.display_selected_options && option.selected)) {
        return false;
      }
      if (!this.display_disabled_options && option.disabled) {
        return false;
      }
      if (option.empty) {
        return false;
      }
      return true;
    };

    AbstractChosen.prototype.search_results_touchstart = function(evt) {
      this.touch_started = true;
      return this.search_results_mouseover(evt);
    };

    AbstractChosen.prototype.search_results_touchmove = function(evt) {
      this.touch_started = false;
      return this.search_results_mouseout(evt);
    };

    AbstractChosen.prototype.search_results_touchend = function(evt) {
      if (this.touch_started) {
        return this.search_results_mouseup(evt);
      }
    };

    AbstractChosen.prototype.outerHTML = function(element) {
      var tmp;
      if (element.outerHTML) {
        return element.outerHTML;
      }
      tmp = document.createElement("div");
      tmp.appendChild(element);
      return tmp.innerHTML;
    };

    AbstractChosen.browser_is_supported = function() {
      if (/iP(od|hone)/i.test(window.navigator.userAgent)) {
        return false;
      }
      if (/Android/i.test(window.navigator.userAgent)) {
        if (/Mobile/i.test(window.navigator.userAgent)) {
          return false;
        }
      }
      if (/IEMobile/i.test(window.navigator.userAgent)) {
        return false;
      }
      if (/Windows Phone/i.test(window.navigator.userAgent)) {
        return false;
      }
      if (/BlackBerry/i.test(window.navigator.userAgent)) {
        return false;
      }
      if (/BB10/i.test(window.navigator.userAgent)) {
        return false;
      }
      if (window.navigator.appName === "Microsoft Internet Explorer") {
        return document.documentMode >= 8;
      }
      return true;
    };

    AbstractChosen.default_multiple_text = "Select Some Options";

    AbstractChosen.default_single_text = "Select an Option";

    AbstractChosen.default_no_result_text = "No results match";

    return AbstractChosen;

  })();

  $ = jQuery;

  $.fn.extend({
    chosen: function(options) {
      if (!AbstractChosen.browser_is_supported()) {
        return this;
      }
      return this.each(function(input_field) {
        var $this, chosen;
        $this = $(this);
        chosen = $this.data('chosen');
        if (options === 'destroy') {
          if (chosen instanceof Chosen) {
            chosen.destroy();
          }
          return;
        }
        if (!(chosen instanceof Chosen)) {
          $this.data('chosen', new Chosen(this, options));
        }
      });
    }
  });

  Chosen = (function(_super) {
    __extends(Chosen, _super);

    function Chosen() {
      _ref = Chosen.__super__.constructor.apply(this, arguments);
      return _ref;
    }

    Chosen.prototype.setup = function() {
      this.form_field_jq = $(this.form_field);
      this.current_selectedIndex = this.form_field.selectedIndex;
      return this.is_rtl = this.form_field_jq.hasClass("chosen-rtl");
    };

    Chosen.prototype.set_up_html = function() {
      var container_classes, container_props;
      container_classes = ["chosen-container"];
      container_classes.push("chosen-container-" + (this.is_multiple ? "multi" : "single"));
      if (this.inherit_select_classes && this.form_field.className) {
        container_classes.push(this.form_field.className);
      }
      if (this.is_rtl) {
        container_classes.push("chosen-rtl");
      }
      container_props = {
        'class': container_classes.join(' '),
        'style': "width: " + (this.container_width()) + ";",
        'title': this.form_field.title
      };
      if (this.form_field.id.length) {
        container_props.id = this.form_field.id.replace(/[^\w]/g, '_') + "_chosen";
      }
      this.container = $("<div />", container_props);
      if (this.is_multiple) {
        this.container.html('<ul class="chosen-choices"><li class="search-field"><input type="text" value="' + this.default_text + '" class="default" autocomplete="off" style="width:25px;" /></li></ul><div class="chosen-drop"><ul class="chosen-results"></ul></div>');
      } else {
        this.container.html('<a class="chosen-single chosen-default"><span>' + this.default_text + '</span><div><b></b></div></a><div class="chosen-drop"><div class="chosen-search"><input type="text" autocomplete="off" /></div><ul class="chosen-results"></ul></div>');
      }
      this.form_field_jq.hide().after(this.container);
      this.dropdown = this.container.find('div.chosen-drop').first();
      this.search_field = this.container.find('input').first();
      this.search_results = this.container.find('ul.chosen-results').first();
      this.search_field_scale();
      this.search_no_results = this.container.find('li.no-results').first();
      if (this.is_multiple) {
        this.search_choices = this.container.find('ul.chosen-choices').first();
        this.search_container = this.container.find('li.search-field').first();
      } else {
        this.search_container = this.container.find('div.chosen-search').first();
        this.selected_item = this.container.find('.chosen-single').first();
      }
      this.results_build();
      this.set_tab_index();
      return this.set_label_behavior();
    };

    Chosen.prototype.on_ready = function() {
      return this.form_field_jq.trigger("chosen:ready", {
        chosen: this
      });
    };

    Chosen.prototype.register_observers = function() {
      var _this = this;
      this.container.bind('touchstart.chosen', function(evt) {
        _this.container_mousedown(evt);
        return evt.preventDefault();
      });
      this.container.bind('touchend.chosen', function(evt) {
        _this.container_mouseup(evt);
        return evt.preventDefault();
      });
      this.container.bind('mousedown.chosen', function(evt) {
        _this.container_mousedown(evt);
      });
      this.container.bind('mouseup.chosen', function(evt) {
        _this.container_mouseup(evt);
      });
      this.container.bind('mouseenter.chosen', function(evt) {
        _this.mouse_enter(evt);
      });
      this.container.bind('mouseleave.chosen', function(evt) {
        _this.mouse_leave(evt);
      });
      this.search_results.bind('mouseup.chosen', function(evt) {
        _this.search_results_mouseup(evt);
      });
      this.search_results.bind('mouseover.chosen', function(evt) {
        _this.search_results_mouseover(evt);
      });
      this.search_results.bind('mouseout.chosen', function(evt) {
        _this.search_results_mouseout(evt);
      });
      this.search_results.bind('mousewheel.chosen DOMMouseScroll.chosen', function(evt) {
        _this.search_results_mousewheel(evt);
      });
      this.search_results.bind('touchstart.chosen', function(evt) {
        _this.search_results_touchstart(evt);
      });
      this.search_results.bind('touchmove.chosen', function(evt) {
        _this.search_results_touchmove(evt);
      });
      this.search_results.bind('touchend.chosen', function(evt) {
        _this.search_results_touchend(evt);
      });
      this.form_field_jq.bind("chosen:updated.chosen", function(evt) {
        _this.results_update_field(evt);
      });
      this.form_field_jq.bind("chosen:activate.chosen", function(evt) {
        _this.activate_field(evt);
      });
      this.form_field_jq.bind("chosen:open.chosen", function(evt) {
        _this.container_mousedown(evt);
      });
      this.form_field_jq.bind("chosen:close.chosen", function(evt) {
        _this.input_blur(evt);
      });
      this.search_field.bind('blur.chosen', function(evt) {
        _this.input_blur(evt);
      });
      this.search_field.bind('keyup.chosen', function(evt) {
        _this.keyup_checker(evt);
      });
      this.search_field.bind('keydown.chosen', function(evt) {
        _this.keydown_checker(evt);
      });
      this.search_field.bind('focus.chosen', function(evt) {
        _this.input_focus(evt);
      });
      this.search_field.bind('cut.chosen', function(evt) {
        _this.clipboard_event_checker(evt);
      });
      this.search_field.bind('paste.chosen', function(evt) {
        _this.clipboard_event_checker(evt);
      });
      if (this.is_multiple) {
        return this.search_choices.bind('click.chosen', function(evt) {
          _this.choices_click(evt);
        });
      } else {
        return this.container.bind('click.chosen', function(evt) {
          evt.preventDefault();
        });
      }
    };

    Chosen.prototype.destroy = function() {
      $(this.container[0].ownerDocument).unbind("click.chosen", this.click_test_action);
      if (this.search_field[0].tabIndex) {
        this.form_field_jq[0].tabIndex = this.search_field[0].tabIndex;
      }
      this.container.remove();
      this.form_field_jq.removeData('chosen');
      return this.form_field_jq.show();
    };

    Chosen.prototype.search_field_disabled = function() {
      this.is_disabled = this.form_field_jq[0].disabled;
      if (this.is_disabled) {
        this.container.addClass('chosen-disabled');
        this.search_field[0].disabled = true;
        if (!this.is_multiple) {
          this.selected_item.unbind("focus.chosen", this.activate_action);
        }
        return this.close_field();
      } else {
        this.container.removeClass('chosen-disabled');
        this.search_field[0].disabled = false;
        if (!this.is_multiple) {
          return this.selected_item.bind("focus.chosen", this.activate_action);
        }
      }
    };

    Chosen.prototype.container_mousedown = function(evt) {
      if (!this.is_disabled) {
        if (evt && evt.type === "mousedown" && !this.results_showing) {
          evt.preventDefault();
        }
        if (!((evt != null) && ($(evt.target)).hasClass("search-choice-close"))) {
          if (!this.active_field) {
            if (this.is_multiple) {
              this.search_field.val("");
            }
            $(this.container[0].ownerDocument).bind('click.chosen', this.click_test_action);
            this.results_show();
          } else if (!this.is_multiple && evt && (($(evt.target)[0] === this.selected_item[0]) || $(evt.target).parents("a.chosen-single").length)) {
            evt.preventDefault();
            this.results_toggle();
          }
          return this.activate_field();
        }
      }
    };

    Chosen.prototype.container_mouseup = function(evt) {
      if (evt.target.nodeName === "ABBR" && !this.is_disabled) {
        return this.results_reset(evt);
      }
    };

    Chosen.prototype.search_results_mousewheel = function(evt) {
      var delta;
      if (evt.originalEvent) {
        delta = evt.originalEvent.deltaY || -evt.originalEvent.wheelDelta || evt.originalEvent.detail;
      }
      if (delta != null) {
        evt.preventDefault();
        if (evt.type === 'DOMMouseScroll') {
          delta = delta * 40;
        }
        return this.search_results.scrollTop(delta + this.search_results.scrollTop());
      }
    };

    Chosen.prototype.blur_test = function(evt) {
      if (!this.active_field && this.container.hasClass("chosen-container-active")) {
        return this.close_field();
      }
    };

    Chosen.prototype.close_field = function() {
      $(this.container[0].ownerDocument).unbind("click.chosen", this.click_test_action);
      this.active_field = false;
      this.results_hide();
      this.container.removeClass("chosen-container-active");
      this.clear_backstroke();
      this.show_search_field_default();
      return this.search_field_scale();
    };

    Chosen.prototype.activate_field = function() {
      this.container.addClass("chosen-container-active");
      this.active_field = true;
      this.search_field.val(this.search_field.val());
      return this.search_field.focus();
    };

    Chosen.prototype.test_active_click = function(evt) {
      var active_container;
      active_container = $(evt.target).closest('.chosen-container');
      if (active_container.length && this.container[0] === active_container[0]) {
        return this.active_field = true;
      } else {
        return this.close_field();
      }
    };

    Chosen.prototype.results_build = function() {
      this.parsing = true;
      this.selected_option_count = null;
      this.results_data = SelectParser.select_to_array(this.form_field);
      if (this.is_multiple) {
        this.search_choices.find("li.search-choice").remove();
      } else if (!this.is_multiple) {
        this.single_set_selected_text();
        if (this.disable_search || this.form_field.options.length <= this.disable_search_threshold) {
          this.search_field[0].readOnly = true;
          this.container.addClass("chosen-container-single-nosearch");
        } else {
          this.search_field[0].readOnly = false;
          this.container.removeClass("chosen-container-single-nosearch");
        }
      }
      this.update_results_content(this.results_option_build({
        first: true
      }));
      this.search_field_disabled();
      this.show_search_field_default();
      this.search_field_scale();
      return this.parsing = false;
    };

    Chosen.prototype.result_do_highlight = function(el) {
      var high_bottom, high_top, maxHeight, visible_bottom, visible_top;
      if (el.length) {
        this.result_clear_highlight();
        this.result_highlight = el;
        this.result_highlight.addClass("highlighted");
        maxHeight = parseInt(this.search_results.css("maxHeight"), 10);
        visible_top = this.search_results.scrollTop();
        visible_bottom = maxHeight + visible_top;
        high_top = this.result_highlight.position().top + this.search_results.scrollTop();
        high_bottom = high_top + this.result_highlight.outerHeight();
        if (high_bottom >= visible_bottom) {
          return this.search_results.scrollTop((high_bottom - maxHeight) > 0 ? high_bottom - maxHeight : 0);
        } else if (high_top < visible_top) {
          return this.search_results.scrollTop(high_top);
        }
      }
    };

    Chosen.prototype.result_clear_highlight = function() {
      if (this.result_highlight) {
        this.result_highlight.removeClass("highlighted");
      }
      return this.result_highlight = null;
    };

    Chosen.prototype.results_show = function() {
      if (this.is_multiple && this.max_selected_options <= this.choices_count()) {
        this.form_field_jq.trigger("chosen:maxselected", {
          chosen: this
        });
        return false;
      }
      this.container.addClass("chosen-with-drop");
      this.results_showing = true;
      this.search_field.focus();
      this.search_field.val(this.search_field.val());
      this.winnow_results();
      return this.form_field_jq.trigger("chosen:showing_dropdown", {
        chosen: this
      });
    };

    Chosen.prototype.update_results_content = function(content) {
      return this.search_results.html(content);
    };

    Chosen.prototype.results_hide = function() {
      if (this.results_showing) {
        this.result_clear_highlight();
        this.container.removeClass("chosen-with-drop");
        this.form_field_jq.trigger("chosen:hiding_dropdown", {
          chosen: this
        });
      }
      return this.results_showing = false;
    };

    Chosen.prototype.set_tab_index = function(el) {
      var ti;
      if (this.form_field.tabIndex) {
        ti = this.form_field.tabIndex;
        this.form_field.tabIndex = -1;
        return this.search_field[0].tabIndex = ti;
      }
    };

    Chosen.prototype.set_label_behavior = function() {
      var _this = this;
      this.form_field_label = this.form_field_jq.parents("label");
      if (!this.form_field_label.length && this.form_field.id.length) {
        this.form_field_label = $("label[for='" + this.form_field.id + "']");
      }
      if (this.form_field_label.length > 0) {
        return this.form_field_label.bind('click.chosen', function(evt) {
          if (_this.is_multiple) {
            return _this.container_mousedown(evt);
          } else {
            return _this.activate_field();
          }
        });
      }
    };

    Chosen.prototype.show_search_field_default = function() {
      if (this.is_multiple && this.choices_count() < 1 && !this.active_field) {
        this.search_field.val(this.default_text);
        return this.search_field.addClass("default");
      } else {
        this.search_field.val("");
        return this.search_field.removeClass("default");
      }
    };

    Chosen.prototype.search_results_mouseup = function(evt) {
      var target;
      target = $(evt.target).hasClass("active-result") ? $(evt.target) : $(evt.target).parents(".active-result").first();
      if (target.length) {
        this.result_highlight = target;
        this.result_select(evt);
        return this.search_field.focus();
      }
    };

    Chosen.prototype.search_results_mouseover = function(evt) {
      var target;
      target = $(evt.target).hasClass("active-result") ? $(evt.target) : $(evt.target).parents(".active-result").first();
      if (target) {
        return this.result_do_highlight(target);
      }
    };

    Chosen.prototype.search_results_mouseout = function(evt) {
      if ($(evt.target).hasClass("active-result" || $(evt.target).parents('.active-result').first())) {
        return this.result_clear_highlight();
      }
    };

    Chosen.prototype.choice_build = function(item) {
      var choice, close_link,
        _this = this;
      choice = $('<li />', {
        "class": "search-choice"
      }).html("<span>" + (this.choice_label(item)) + "</span>");
      if (item.disabled) {
        choice.addClass('search-choice-disabled');
      } else {
        close_link = $('<a />', {
          "class": 'search-choice-close',
          'data-option-array-index': item.array_index
        });
        close_link.bind('click.chosen', function(evt) {
          return _this.choice_destroy_link_click(evt);
        });
        choice.append(close_link);
      }
      return this.search_container.before(choice);
    };

    Chosen.prototype.choice_destroy_link_click = function(evt) {
      evt.preventDefault();
      evt.stopPropagation();
      if (!this.is_disabled) {
        return this.choice_destroy($(evt.target));
      }
    };

    Chosen.prototype.choice_destroy = function(link) {
      if (this.result_deselect(link[0].getAttribute("data-option-array-index"))) {
        this.show_search_field_default();
        if (this.is_multiple && this.choices_count() > 0 && this.search_field.val().length < 1) {
          this.results_hide();
        }
        link.parents('li').first().remove();
        return this.search_field_scale();
      }
    };

    Chosen.prototype.results_reset = function() {
      this.reset_single_select_options();
      this.form_field.options[0].selected = true;
      this.single_set_selected_text();
      this.show_search_field_default();
      this.results_reset_cleanup();
      this.form_field_jq.trigger("change");
      if (this.active_field) {
        return this.results_hide();
      }
    };

    Chosen.prototype.results_reset_cleanup = function() {
      this.current_selectedIndex = this.form_field.selectedIndex;
      return this.selected_item.find("abbr").remove();
    };

    Chosen.prototype.result_select = function(evt) {
      var high, item;
      if (this.result_highlight) {
        high = this.result_highlight;
        this.result_clear_highlight();
        if (this.is_multiple && this.max_selected_options <= this.choices_count()) {
          this.form_field_jq.trigger("chosen:maxselected", {
            chosen: this
          });
          return false;
        }
        if (this.is_multiple) {
          high.removeClass("active-result");
        } else {
          this.reset_single_select_options();
        }
        high.addClass("result-selected");
        item = this.results_data[high[0].getAttribute("data-option-array-index")];
        item.selected = true;
        this.form_field.options[item.options_index].selected = true;
        this.selected_option_count = null;
        if (this.is_multiple) {
          this.choice_build(item);
        } else {
          this.single_set_selected_text(this.choice_label(item));
        }
        if (!((evt.metaKey || evt.ctrlKey) && this.is_multiple)) {
          this.results_hide();
        }
        this.show_search_field_default();
        if (this.is_multiple || this.form_field.selectedIndex !== this.current_selectedIndex) {
          this.form_field_jq.trigger("change", {
            'selected': this.form_field.options[item.options_index].value
          });
        }
        this.current_selectedIndex = this.form_field.selectedIndex;
        evt.preventDefault();
        return this.search_field_scale();
      }
    };

    Chosen.prototype.single_set_selected_text = function(text) {
      if (text == null) {
        text = this.default_text;
      }
      if (text === this.default_text) {
        this.selected_item.addClass("chosen-default");
      } else {
        this.single_deselect_control_build();
        this.selected_item.removeClass("chosen-default");
      }
      return this.selected_item.find("span").html(text);
    };

    Chosen.prototype.result_deselect = function(pos) {
      var result_data;
      result_data = this.results_data[pos];
      if (!this.form_field.options[result_data.options_index].disabled) {
        result_data.selected = false;
        this.form_field.options[result_data.options_index].selected = false;
        this.selected_option_count = null;
        this.result_clear_highlight();
        if (this.results_showing) {
          this.winnow_results();
        }
        this.form_field_jq.trigger("change", {
          deselected: this.form_field.options[result_data.options_index].value
        });
        this.search_field_scale();
        return true;
      } else {
        return false;
      }
    };

    Chosen.prototype.single_deselect_control_build = function() {
      if (!this.allow_single_deselect) {
        return;
      }
      if (!this.selected_item.find("abbr").length) {
        this.selected_item.find("span").first().after("<abbr class=\"search-choice-close\"></abbr>");
      }
      return this.selected_item.addClass("chosen-single-with-deselect");
    };

    Chosen.prototype.get_search_text = function() {
      return $('<div/>').text($.trim(this.search_field.val())).html();
    };

    Chosen.prototype.winnow_results_set_highlight = function() {
      var do_high, selected_results;
      selected_results = !this.is_multiple ? this.search_results.find(".result-selected.active-result") : [];
      do_high = selected_results.length ? selected_results.first() : this.search_results.find(".active-result").first();
      if (do_high != null) {
        return this.result_do_highlight(do_high);
      }
    };

    Chosen.prototype.no_results = function(terms) {
      var no_results_html;
      no_results_html = $('<li class="no-results">' + this.results_none_found + ' "<span></span>"</li>');
      no_results_html.find("span").first().html(terms);
      this.search_results.append(no_results_html);
      return this.form_field_jq.trigger("chosen:no_results", {
        chosen: this
      });
    };

    Chosen.prototype.no_results_clear = function() {
      return this.search_results.find(".no-results").remove();
    };

    Chosen.prototype.keydown_arrow = function() {
      var next_sib;
      if (this.results_showing && this.result_highlight) {
        next_sib = this.result_highlight.nextAll("li.active-result").first();
        if (next_sib) {
          return this.result_do_highlight(next_sib);
        }
      } else {
        return this.results_show();
      }
    };

    Chosen.prototype.keyup_arrow = function() {
      var prev_sibs;
      if (!this.results_showing && !this.is_multiple) {
        return this.results_show();
      } else if (this.result_highlight) {
        prev_sibs = this.result_highlight.prevAll("li.active-result");
        if (prev_sibs.length) {
          return this.result_do_highlight(prev_sibs.first());
        } else {
          if (this.choices_count() > 0) {
            this.results_hide();
          }
          return this.result_clear_highlight();
        }
      }
    };

    Chosen.prototype.keydown_backstroke = function() {
      var next_available_destroy;
      if (this.pending_backstroke) {
        this.choice_destroy(this.pending_backstroke.find("a").first());
        return this.clear_backstroke();
      } else {
        next_available_destroy = this.search_container.siblings("li.search-choice").last();
        if (next_available_destroy.length && !next_available_destroy.hasClass("search-choice-disabled")) {
          this.pending_backstroke = next_available_destroy;
          if (this.single_backstroke_delete) {
            return this.keydown_backstroke();
          } else {
            return this.pending_backstroke.addClass("search-choice-focus");
          }
        }
      }
    };

    Chosen.prototype.clear_backstroke = function() {
      if (this.pending_backstroke) {
        this.pending_backstroke.removeClass("search-choice-focus");
      }
      return this.pending_backstroke = null;
    };

    Chosen.prototype.keydown_checker = function(evt) {
      var stroke, _ref1;
      stroke = (_ref1 = evt.which) != null ? _ref1 : evt.keyCode;
      this.search_field_scale();
      if (stroke !== 8 && this.pending_backstroke) {
        this.clear_backstroke();
      }
      switch (stroke) {
        case 8:
          this.backstroke_length = this.search_field.val().length;
          break;
        case 9:
          if (this.results_showing && !this.is_multiple) {
            this.result_select(evt);
          }
          this.mouse_on_container = false;
          break;
        case 13:
          if (this.results_showing) {
            evt.preventDefault();
          }
          break;
        case 32:
          if (this.disable_search) {
            evt.preventDefault();
          }
          break;
        case 38:
          evt.preventDefault();
          this.keyup_arrow();
          break;
        case 40:
          evt.preventDefault();
          this.keydown_arrow();
          break;
      }
    };

    Chosen.prototype.search_field_scale = function() {
      var div, f_width, h, style, style_block, styles, w, _i, _len;
      if (this.is_multiple) {
        h = 0;
        w = 0;
        style_block = "position:absolute; left: -1000px; top: -1000px; display:none;";
        styles = ['font-size', 'font-style', 'font-weight', 'font-family', 'line-height', 'text-transform', 'letter-spacing'];
        for (_i = 0, _len = styles.length; _i < _len; _i++) {
          style = styles[_i];
          style_block += style + ":" + this.search_field.css(style) + ";";
        }
        div = $('<div />', {
          'style': style_block
        });
        div.text(this.search_field.val());
        $('body').append(div);
        w = div.width() + 25;
        div.remove();
        f_width = this.container.outerWidth();
        if (w > f_width - 10) {
          w = f_width - 10;
        }
        return this.search_field.css({
          'width': w + 'px'
        });
      }
    };

    return Chosen;

  })(AbstractChosen);

}).call(this);


  }).apply(root, arguments);
});
}(this));

(function(root) {
define("angular-chosen", ["angular","jquery-chosen"], function() {
  return (function() {
/**
 * angular-chosen-localytics - Angular Chosen directive is an AngularJS Directive that brings the Chosen jQuery in a Angular way
 * @version v1.3.0
 * @link http://github.com/leocaseiro/angular-chosen
 * @license MIT
 */
(function() {
  var indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

  angular.module('localytics.directives', []);

  angular.module('localytics.directives').directive('chosen', [
    '$timeout', function($timeout) {
      var CHOSEN_OPTION_WHITELIST, NG_OPTIONS_REGEXP, isEmpty, snakeCase;
      NG_OPTIONS_REGEXP = /^\s*([\s\S]+?)(?:\s+as\s+([\s\S]+?))?(?:\s+group\s+by\s+([\s\S]+?))?\s+for\s+(?:([\$\w][\$\w]*)|(?:\(\s*([\$\w][\$\w]*)\s*,\s*([\$\w][\$\w]*)\s*\)))\s+in\s+([\s\S]+?)(?:\s+track\s+by\s+([\s\S]+?))?$/;
      CHOSEN_OPTION_WHITELIST = ['persistentCreateOption', 'createOptionText', 'createOption', 'skipNoResults', 'noResultsText', 'allowSingleDeselect', 'disableSearchThreshold', 'disableSearch', 'enableSplitWordSearch', 'inheritSelectClasses', 'maxSelectedOptions', 'placeholderTextMultiple', 'placeholderTextSingle', 'searchContains', 'singleBackstrokeDelete', 'displayDisabledOptions', 'displaySelectedOptions', 'width', 'includeGroupLabelInSelected', 'maxShownResults'];
      snakeCase = function(input) {
        return input.replace(/[A-Z]/g, function($1) {
          return "_" + ($1.toLowerCase());
        });
      };
      isEmpty = function(value) {
        var key;
        if (angular.isArray(value)) {
          return value.length === 0;
        } else if (angular.isObject(value)) {
          for (key in value) {
            if (value.hasOwnProperty(key)) {
              return false;
            }
          }
        }
        return true;
      };
      return {
        restrict: 'A',
        require: '?ngModel',
        priority: 1,
        link: function(scope, element, attr, ngModel) {
          var chosen, empty, initOrUpdate, match, options, origRender, startLoading, stopLoading, updateMessage, valuesExpr, viewWatch;
          scope.disabledValuesHistory = scope.disabledValuesHistory ? scope.disabledValuesHistory : [];
          element = $(element);
          element.addClass('localytics-chosen');
          options = scope.$eval(attr.chosen) || {};
          angular.forEach(attr, function(value, key) {
            if (indexOf.call(CHOSEN_OPTION_WHITELIST, key) >= 0) {
              return attr.$observe(key, function(value) {
                options[snakeCase(key)] = String(element.attr(attr.$attr[key])).slice(0, 2) === '{{' ? value : scope.$eval(value);
                return updateMessage();
              });
            }
          });
          startLoading = function() {
            return element.addClass('loading').attr('disabled', true).trigger('chosen:updated');
          };
          stopLoading = function() {
            element.removeClass('loading');
            if (angular.isDefined(attr.disabled)) {
              element.attr('disabled', attr.disabled);
            } else {
              element.attr('disabled', false);
            }
            return element.trigger('chosen:updated');
          };
          chosen = null;
          empty = false;
          initOrUpdate = function() {
            var defaultText;
            if (chosen) {
              return element.trigger('chosen:updated');
            } else {
              $timeout(function() {
                chosen = element.chosen(options).data('chosen');
              });
              if (angular.isObject(chosen)) {
                return defaultText = chosen.default_text;
              }
            }
          };
          updateMessage = function() {
            if (empty) {
              element.attr('data-placeholder', chosen.results_none_found).attr('disabled', true);
            } else {
              element.removeAttr('data-placeholder');
            }
            return element.trigger('chosen:updated');
          };
          if (ngModel) {
            origRender = ngModel.$render;
            ngModel.$render = function() {
              origRender();
              return initOrUpdate();
            };
            element.on('chosen:hiding_dropdown', function() {
              return scope.$apply(function() {
                return ngModel.$setTouched();
              });
            });
            if (attr.multiple) {
              viewWatch = function() {
                return ngModel.$viewValue;
              };
              scope.$watch(viewWatch, ngModel.$render, true);
            }
          } else {
            initOrUpdate();
          }
          attr.$observe('disabled', function() {
            return element.trigger('chosen:updated');
          });
          if (attr.ngOptions && ngModel) {
            match = attr.ngOptions.match(NG_OPTIONS_REGEXP);
            valuesExpr = match[7];
            scope.$watchCollection(valuesExpr, function(newVal, oldVal) {
              var timer;
              return timer = $timeout(function() {
                if (angular.isUndefined(newVal)) {
                  return startLoading();
                } else {
                  empty = isEmpty(newVal);
                  stopLoading();
                  return updateMessage();
                }
              });
            });
            return scope.$on('$destroy', function(event) {
              if (typeof timer !== "undefined" && timer !== null) {
                return $timeout.cancel(timer);
              }
            });
          }
        }
      };
    }
  ]);

}).call(this);


  }).apply(root, arguments);
});
}(this));

/*
# templates/transfer_tool/filters/startFromFilter.js                Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/filters/startFromFilter',[
        "angular"
    ],
    function(angular) {

        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        /**
         * Angular filter which returns array started at position defined by start
         * @return {array}
         */
        app.filter("startFrom", function() {
            return function(input, start) {
                if (input && angular.isArray(input)) {
                    start = Number(start); // parse to int
                    return input.slice(start);
                }
            };
        });
    }
);

/*
# templates/transfer_tool/filters/cpLimitToFilter.js                Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/filters/cpLimitToFilter',[
        "angular"
    ],
    function(angular) {

        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        // Main - reusable
        /**
         * Angular filter that limits arrays to a defined limit
         * @return {array}
         */
        app.filter("cpLimitTo", function() {
            return function(input, limit) {
                return limit ? input.slice(0, limit) : input;
            };
        });
    }
);

/*
# cpanel - templates/transfer_tool/controllers/MainController.js
#                                               Copyright(c) 2021 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */
/* jshint -W003 */
/**
 * @class Class constructor for the main controller
 * @param {object} $scope
 * @param {object} $filter
 */


define(
    'app/controllers/MainController',[
        "angular",
        "cjt/util/locale",
        "cjt/directives/pageSizeDirective",
        "../filters/startFromFilter",
        "../filters/cpLimitToFilter",
    ],
    function(angular, LOCALE) {

        "use strict";

        var CONTROLLER_INJECTABLES = ["$scope", "$log", "$filter", "PAGE", "OVERWRITE_OPTIONS", "OVERWRITE_STATES"];

        var MainController = function($scope, $log, $filter, PAGE, OVERWRITE_OPTIONS, OVERWRITE_STATES) {

            var _this = this;

            _this._log = $log;
            _this.PAGE = PAGE;
            _this.REMAINING_ACCOUNT_SLOTS = parseInt(PAGE.REMAINING_ACCOUNT_SLOTS, 10);
            _this.SERVER_MAX_USERS = parseInt(PAGE.SERVER_MAX_USERS, 10);
            _this.pkgTable = {
                currentPage: 1,
                pageSize: 10,
                reverse: false,
                order: "name",
            };

            _this.overwriteStates = OVERWRITE_STATES;

            // Determine if cPanel version is less than 11.55.
            _this.olderRemote = parseInt(_this.PAGE.remote.version.split(".")[1]) < 55;

            var serverType = LOCALE.maketext("Unknown");

            if (_this.PAGE.remote.server_type.match(/WHM/)) {
                serverType = "WHM " + _this.PAGE.remote.version;
            } else {
                serverType = _this.PAGE.remote.server_type + " " + _this.PAGE.remote.version;
            }
            var isCpanel = true;
            if ( !serverType.match(/WHM/) ) {
                isCpanel = false;
            }

            _this.meta = {
                server_type: serverType,
                is_cpanel: isCpanel,
                panel_name: _this.PAGE.remote.server_type,
            };

            _this.LOCALE = LOCALE;

            // Set default values - this checks them
            _this.control_bwdata = true;
            _this.control_homedir = true;
            _this.control_databases = true;
            _this.control_reseller_privs = true;

            // Packages / Main
            angular.forEach(_this.PAGE.items.packages, function(val, key) {
                _this.PAGE.items.packages[key].selected = 0;
            });

            _this.PAGE.domainsWithDedicatedIp = {};

            angular.forEach(_this.PAGE.local.dedicated_ips, function(value, key) {
                this[value] = true;
            }, _this.PAGE.domainsWithDedicatedIp);


            var startFrom = $filter("startFrom"),
                orderBy = $filter("orderBy"),
                limitTo = $filter("cpLimitTo"),
                filter = $filter("filter");

            _this.existingUsersFilter = $filter("existingUsers");

            _this.selectedAccounts = filter(_this.PAGE.items.accounts, {
                selected: 1,
            });

            _this.selectedPackages = filter(_this.PAGE.items.packages, {
                selected: 1,
            });

            // To better understand what these assignments are look at updateFilteredPackages and updateViewablePackages
            _this.filteredPackages = filter(_this.PAGE.items.packages, _this.pkgsFilter);
            _this.viewablePackages = limitTo(startFrom(orderBy(_this.filteredPackages, _this.pkgTable.order, _this.pkgTable.reverse), (_this.pkgTable.currentPage - 1) * _this.pkgTable.pageSize),
                _this.pkgTable.pageSize);

            /**
             * Updates the selectedPackages array based on what packages are selected
             */
            _this.updateSelectedPackages = function() {
                _this.selectedPackages = filter(this.PAGE.items.packages, {
                    selected: 1,
                });
            };

            _this.updateSelectedConfigurations = function() {
                _this.selectedConfigurations = [];
                angular.forEach(_this.PAGE.configuration_modules, function(value, key) {
                    if (value.selected) {
                        var config = {};
                        config[key + "_enabled"] = 1;
                        _this.selectedConfigurations.push( config );
                    }
                });
            };

            _this.updateSelectedConfigurations();

            /**
             * Dispatches Event to be caught by AccountTableController
             */
            _this.recheckUsers = function(dataset) {
                $scope.$broadcast("recheckUsersCalled", {
                    dataset: dataset,
                });
            };

            /**
             * Updates the selectedAccounts array based on what packages are selected
             */
            _this.updateSelectedAccounts = function() {
                _this.selectedAccounts = filter(this.PAGE.items.accounts, {
                    selected: 1,
                });
            };

            /**
             * Reapplies filters for the filteredPackages array
             * Array    ->    Filtered by pkgsFilter
             * packages | filter:pkgsFilter
             */
            _this.updateFilteredPackages = function() {
                _this.filteredPackages = filter(this.PAGE.items.packages, this.pkgsFilter);
            };

            /**
             * Reapplies filteres for the viewablePackages array.
             * FilteredPackages ->              Ordered by(reverse?)         ->          start at page# * pageSize                         ->    limit to page size
             * filteredPackages | orderBy: acctTable.order:acctTable.reverse | startFrom:(acctTable.currentPage - 1 ) * acctTable.pageSize | limitTo: acctTable.pageSize
             */
            _this.updateViewablePackages = function() {
                _this.viewablePackages = limitTo(startFrom(orderBy(_this.filteredPackages, _this.pkgTable.order, _this.pkgTable.reverse), (_this.pkgTable.currentPage - 1) * _this.pkgTable.pageSize),
                    _this.pkgTable.pageSize);
            };

            _this.getPossiblePageSizes = function() {
                return _this.PAGE.all_possible_page_sizes;
            };

            /**
             * Returns true if the source account is being assigned a new dedicated ip.
             * @param  {object} item Account object
             * @return {Boolean}
             */
            _this.newDedicatedIpFilter = function(item) {
                if (!item.dedicated_ip) {
                    return false;
                }

                return !_this.PAGE.domainsWithDedicatedIp[item.domain];
            };

            _this.toArray = function() {
                _this.configuration_modules = [];
                angular.forEach(_this.PAGE.configuration_modules, function(val, key) {
                    var analysis = [];
                    angular.forEach(val.analysis, function(analysisValue, analysisKey) {
                        analysis.push({ analysis: analysisValue, analysisKey: analysisKey });
                    });
                    val.analysis = analysis;
                    _this.configuration_modules.push({ key: key, value: val });
                });
            };

            _this.overwriteIsDefault = function overwriteIsDefault(item) {
                return item.overwrite_type.value === _this.overwriteStates.NO_OVERWRITE;
            };

            _this.overwriteOptions = OVERWRITE_OPTIONS;

            // If no viewable accounts are selected, make sure the checkbox is unchecked.
            $scope.$watch(function() {
                return _this.selectedAccounts.length;
            }, function(newVal) {
                if (!newVal) {
                    $scope.$broadcast("selectedAccountsEmptied", {});
                }
            });


            $scope.$watch(function() {
                return _this.pkgTable;
            }, function() {
                _this.updateViewablePackages();
            }, true);

            _this.toArray();

            return _this;
        };

        /**
         * Function that updates both filtered and viewable packages array results
         */
        MainController.prototype.updatePackages = function() {
            this.updateFilteredPackages();
            this.updateViewablePackages();
        };

        MainController.prototype.updateConfigurations = function() {
            this.updateSelectedConfigurations();
        };

        /**
         * Returns 'icon-arrow-up' or 'icon-arrow-down' if column is selected for ordering.  The result is based on what order.  Used to indicate sort order.
         * @param  {objec} tableOptionsObj
         * @param  {string} column
         * @return {string|Boolean}
         */
        MainController.prototype.selectedHeaderClass = function(tableOptionsObj, column) {
            var className = "icon-arrow-" + (tableOptionsObj.reverse ? "down" : "up");
            return column === tableOptionsObj.order && className;
        };

        /**
         * Returns 'active' if column is selected for ordering.  Used to highlight selected column.
         * @param  {object} tableOptionsObj
         * @param  {string} column
         * @return {string|Boolean}
         */
        MainController.prototype.selectedColClass = function(tableOptionsObj, column) {
            return column === tableOptionsObj.order && "active";
        };

        /**
         * Takes in an array of accounts and sets the attr of each account to a value of 1 or 0 corresponding to isChecked.  1 or 0 for Perl parsing after form submit.
         * @param  {array}  dataset
         * @param  {string}  attr
         * @param  {Boolean} isChecked
         */
        MainController.prototype.toggleCheckAll = function(dataset, attr, isChecked) {
            var newValue;
            if (attr === "overwrite_type") {
                newValue = isChecked;
            } else {
                newValue = isChecked ? 1 : 0;
            }
            angular.forEach(dataset, function(o) {
                o[attr] = newValue;
            });
        };

        MainController.prototype.toggleCheckAllAndReValidate = function(dataset, attr, isChecked) {
            var _this = this;
            _this.toggleCheckAll.apply(_this, arguments);

            /* selected accounts list must be updated before validation can occur */
            _this.updateSelectedAccounts();
            _this.recheckUsers(dataset);
        };

        /**
         * Sets the order and reverse attributes for tableOptions.  Used for column sorting.
         * @param  {object} tableOptionsObj
         * @param  {string} fieldName
         */
        MainController.prototype.toggleSort = function(tableOptionsObj, fieldName) {
            tableOptionsObj.reverse = (tableOptionsObj.order === fieldName ? !tableOptionsObj.reverse : 0);
            tableOptionsObj.order = fieldName;
        };


        /**
         * Returns true if the account is selected and has an invalid user
         * @param  {object} item
         * @return {Boolean}
         */
        MainController.prototype.invalidUserFilter = function(item) {
            return item.selected && item.invalidUser;
        };


        /**
         * Returns true if the account's local name has not changed from the remote name.
         * @param  {object} item
         * @return {Boolean}
         */
        MainController.prototype.noUsernameChange = function(item) {
            return item.localuser === item.remote_user;
        };


        /**
         * Returns true if the account matches a reserved account name on the file system
         * @param  {object} item
         * @return {Boolean}
         */
        MainController.prototype.reservedUserFilter = function(item) {
            return item.selected && item.invalidUser && item.userCheckStates.reserved;
        };

        /**
         * Returns true if the account username matches another name selected for importation
         * @param  {object} item
         * @return {Boolean}
         */
        MainController.prototype.duplicateUserFilter = function(item) {
            return item.selected && !!item.localuser && item.invalidUser && item.userCheckStates.duplicate;
        };

        /**
         * Returns true if the account does not match the system regular expression requirements
         * @param  {object} item
         * @return {Boolean}
         */
        MainController.prototype.invalidUsernameFilter = function(item) {
            return item.selected && item.invalidUser && item.userCheckStates.invalid;
        };


        /**
         * Returns true if the account is selected and has an invalid domain.
         * @param  {object} item
         * @return {Boolean}
         */
        MainController.prototype.invalidDomainFilter = function(item) {
            return item.selected && item.invalidDomain;
        };

        /**
         * Returns true if the account is selected, the user is a reseller on the source server,
         * and the reseller privileges are not being transferred.
         * @param  {object} item
         * @return {Boolean}
         */
        MainController.prototype.resellerNoCopyFilter = function(item) {
            return item.selected && item.is_reseller && !item.copy_reseller_privs;
        };

        /**
         * Revalidates all account usernames in provided array
         * @param  {array} array
         */
        MainController.prototype.reValidateDomainAndUsernameFor = function(array) {
            if (!array) {
                return;
            }
            for (var x = 0; x < array.length; x++) {
                var username = array[x].localuser || "";
                if (!username.length) {
                    username = array[x].remote_user;
                }

                array[x].invalidUser = this.PAGE.local.users[username] && !array[x].invalidDomain && array[x].overwrite_type === this.overwriteOptions[0] ? 1 : 0;
            }
        };

        /**
         * Returns message based on the way in which an account matches a local account.
         * @param  {object} acct
         * @return {String}
         */
        MainController.prototype.getExistingUserMessage = function(acct) {

            var incomingLocal = acct.localuser;
            var matchedLocal = acct.similarLocalUser;

            if (incomingLocal === matchedLocal) {
                return this.LOCALE.maketext("The remote account “[_1]” cannot transfer because an account with the same username exists on the local server.", incomingLocal);
            } else {
                return this.LOCALE.maketext("The remote account “[_1]” cannot transfer because the first [quant,_3,non-special character matches,non-special characters match] the local username “[_2]”.", incomingLocal, matchedLocal, this.PAGE.USERNAME_UNIQUE_LENGTH);
            }

        };

        MainController.prototype.existingAccountWarning = function(acctCount) {
            return LOCALE.maketext("[output,strong,Error]: You have selected [quant,_1,account transfer,account transfers] that will not complete properly because the [numerate,_1,username,usernames] already [numerate,_1,exists,exist] on the local server.", acctCount) + " " +
                LOCALE.maketext("To resolve this, you can overwrite the local [numerate,_1,account,accounts], rename the incoming [numerate,_1,account,accounts], or deselect the [numerate,_1,account,accounts].", acctCount);
        };

        MainController.prototype.existingDomainWarning = function(domainCount) {
            return LOCALE.maketext("[output,strong,Error]: You have selected [quant,_1,account transfer,account transfers] that will not complete properly because of [numerate,_1,a domain conflict,domain conflicts].", domainCount) + " " +
                LOCALE.maketext("This is due to [numerate,_1,an existing domain,existing domains] that [numerate,_1,matches an incoming domain,match incoming domains] but [numerate,_1,does,do] not match the local [numerate,_1,username,usernames].", domainCount) + " " +
                LOCALE.maketext("To resolve this, remove the matching [numerate,_1,domain,domains] from the local machine for any [numerate,_1,account,accounts] that you wish to transfer.", domainCount);
        };

        MainController.prototype.dedicatedIpAddrWarning = function(ipsToAdd, availableIps) {
            return LOCALE.maketext("[output,strong,Error]: You have selected [numf,_1] of [quant,_2,available IP address,available IP addresses]. Either deselect an account to transfer, or deselect its corresponding “[_3]” field.", ipsToAdd, availableIps, LOCALE.maketext("Dedicated IP Address"));
        };

        MainController.prototype.frontPageWarning = function(fpAccts) {
            return LOCALE.maketext("[output,strong,Warning]: You selected [quant,_1,account,accounts] that use [asis,Microsoft® FrontPage Extensions] on the source server. The local server does not support [asis,FrontPage]. To resolve this issue, disable [asis,FrontPage] for each account before you attempt the transfer.", fpAccts);
        };

        MainController.prototype.unusedDedicatedIpWarning = function(unusedDedIpAcctCount) {
            return LOCALE.maketext("[output,strong,Warning]: You have selected [quant,_1,account,accounts] which previously had a dedicated [asis,IP] address but you have chosen not to assign one after transfer.", unusedDedIpAcctCount);
        };

        MainController.prototype.packageFilterMessage = function() {
            return (this.pkgsFilter) ?
                LOCALE.maketext("Your search matched [numf,_1] of [quant,_2,record,records].", this.filteredPackages.length, this.PAGE.items.packages.length) :
                LOCALE.maketext("There [numerate,_1,is,are] [quant,_1,record,records].",  this.PAGE.items.packages.length);
        };

        MainController.prototype.packageSelectedMessage = function() {
            return LOCALE.maketext("[_1] selected", this.selectedPackages.length || 0);// this.PAGE.items.packages | filter:{selected: 1}).length);
        };

        MainController.prototype.accountFilterMessage = function(acctCount) {
            return (acctCount !== this.PAGE.items.accounts.length) ?
                LOCALE.maketext("Your search matched [numf,_1] of [quant,_2,record,records].", acctCount || 0, this.PAGE.items.accounts.length) :
                LOCALE.maketext("There [numerate,_1,is,are] [quant,_1,record,records].",  this.PAGE.items.accounts.length);
        };

        MainController.prototype.accountSelectedMessage = function(acctCount) {
            return LOCALE.maketext("[quant,_1,account,accounts] selected.", acctCount || 0);
        };

        MainController.prototype.accountConflictSelectedMessage = function(count) {
            return LOCALE.maketext("You have selected [quant,_1,account,accounts] that cannot transfer properly because [numerate,_1,its username conflicts,their usernames conflict] with [numerate,_1,a username,usernames] on the local server.", count);
        };

        MainController.prototype.licenseOverloadMessage = function() {
            if (this.REMAINING_ACCOUNT_SLOTS === 0) {
                return LOCALE.maketext("Because the destination server’s license is limited to [quant,_1,account,accounts], you can only overwrite existing accounts.", this.SERVER_MAX_USERS);
            } else {
                return LOCALE.maketext("Because the destination server’s license is limited to [quant,_1,account,accounts], you can only transfer [quant,_2,account,accounts].", this.SERVER_MAX_USERS, this.REMAINING_ACCOUNT_SLOTS);
            }
        };

        MainController.prototype.licenseOverloadCancelMessage = function(count) {
            return LOCALE.maketext("Deselect [quant,_1,account,accounts] to continue.", count);
        };

        MainController.prototype.accountOverwriteResolveMessage = function(count) {
            return LOCALE.maketext("To resolve this issue, you can overwrite the local [numerate,_1,account,accounts], rename the incoming [numerate,_1,account,accounts] so that the first [quant,_2,alphanumeric character,alphanumeric characters] do not match those of any local accounts, or deselect the [numerate,_1,account,accounts]. These options are mutually exclusive.",
                count, this.PAGE.USERNAME_UNIQUE_LENGTH);
        };

        MainController.prototype.accountOverwriteConfirmMessage = function(count) {
            return LOCALE.maketext("Overwrite conflicted [numerate,_1,account,accounts]", count);
        };

        MainController.prototype.accountConflictCancelMessage = function(count) {
            return LOCALE.maketext("Deselect conflicted [numerate,_1,account,accounts]", count);
        };

        MainController.prototype.accountConflictResolveMessage = function(count) {
            return LOCALE.maketext("To resolve this issue, you can rename the incoming [numerate,_1,account,accounts] so that the first [quant,_2,alphanumeric character,alphanumeric characters] do not match those of any local accounts, or deselect the [numerate,_1,account,accounts].",
                count, this.PAGE.USERNAME_UNIQUE_LENGTH);
        };

        MainController.prototype.accountConflictSelectedResolveMessage = function(count) {
            return LOCALE.maketext("You have selected [quant,_1,account transfer,account transfers] that will not complete properly because the [numerate,_1,username is,usernames are] reserved on the local server. To resolve this, you can either rename the incoming [numerate,_1,account,accounts] or deselect the [numerate,_1,account,accounts].", count);
        };

        MainController.prototype.accountConflictNameResolveMessage = function(count) {
            return LOCALE.maketext("The following [quant,_1,remote user is set,remote users are set] to migrate with [numerate,_1,a new name,new names] whose first [quant,_2,character conflicts,characters conflict] with one or more other proposed new usernames. To resolve this, you can either rename the incoming [numerate,_1,account,accounts] or deselect [numerate,_1,it,them].",
                count, this.PAGE.USERNAME_UNIQUE_LENGTH);
        };

        MainController.prototype.accountRenameMessage = function(to, from) {
            return LOCALE.maketext("“[_1]” is set to be renamed “[_2]”.", to, from);
        };

        MainController.prototype.usernameValidationTitle = function(count) {
            return LOCALE.maketext("You have entered [quant,_1,username that does,usernames that do] not meet this server’s username requirements:", count);
        };

        MainController.prototype.usernameValidationMessage = function(count) {
            return LOCALE.maketext("Usernames must be no longer than [quant,_1,character,characters] and must contain only lowercase letters and numerals. They may not begin with a numeral. To resolve this, you can either fix the [numerate,_2,username,usernames] or deselect the [numerate,_1,account,accounts].",
                this.PAGE.MAX_USERNAME_LENGTH, count);
        };

        MainController.prototype.usernameValidationAction = function(count) {
            return LOCALE.maketext("Deselect the [numerate,_1,account,accounts] with [numerate,_1,the invalid username,invalid usernames].", count);
        };

        MainController.prototype.dedicatedIPDeselectAction = function(count) {
            return LOCALE.maketext("Deselect “Dedicated IP Address” for conflicted [numerate,_1,account,accounts]", count);
        };

        MainController.prototype.dedicatedIPReselectAction = function(count) {
            return LOCALE.maketext("Reselect “[_1]” for [numerate,_2,account,accounts]", LOCALE.maketext("Dedicated IP Address"), count);
        };

        MainController.prototype.domainsWithFrontpageMessage = function(count) {
            return LOCALE.maketext("The following domains use [asis,FrontPage] on the source server:");
        };

        MainController.prototype.resellerNoCopyTitle = function(count) {
            return LOCALE.maketext("You have selected [quant,_1,user,users] that will be transferred with no reseller privileges.", count);
        };

        MainController.prototype.resellerNoCopyMessage = function(count) {
            if (this.PAGE.restricted_restore) {
                return LOCALE.maketext("[numerate,_1,This user is a reseller,These users are resellers] on the source server. Restricted Restore does not allow the transfer of reseller privileges. After the system restores the [numerate,_1,user,users], you can assign reseller privileges in WHM’s Reseller Center interface ([output,em,WHM » Home » Resellers » Reseller Center]).", count);
            } else {
                return LOCALE.maketext("[numerate,_1,This user is a reseller,These users are resellers] on the source server. To transfer an account’s reseller privileges from the source server, edit the [output,strong,Transfer Configuration] for the desired [numerate,_1,account,accounts] above. Be aware that reseller privileges can give users special permissions, including full root access, to your server.", count);
            }
        };

        MainController.prototype.resellerNoCopyFixMessage = function(count) {
            return LOCALE.maketext("Transfer reseller privileges for the selected [numerate,_1,account,accounts].", count);
        };

        MainController.prototype.canSubmitForm = function(warningLists, dedicatedIPAccounts, newSelectedUserList) {

            // Do warnings exists for any of these view lists
            for (var i = 0; i < warningLists.length; i++) {
                if (warningLists[i].length) {
                    return false;
                }
            }

            // Check for selected items
            if (!this.selectedPackages.length && !this.selectedAccounts.length && !this.selectedConfigurations.length) {
                return false;
            }

            // Check for dedicated IP overages
            if (dedicatedIPAccounts.length > this.PAGE.local.available_ips.length) {
                return false;
            }

            // Check for Empty Slots
            if (this.SERVER_MAX_USERS && newSelectedUserList.length > this.REMAINING_ACCOUNT_SLOTS) {
                return false;
            }

            return true;
        };

        MainController.prototype.getCopyButtonLabel = function getCopyButtonLabel() {
            return LOCALE.maketext("Copy");
        };

        MainController.prototype.submitSummaryMessage = function() {
            var summaryItems = [];
            if (this.selectedAccounts.length) {
                summaryItems.push(LOCALE.maketext("[quant,_1,Account,Accounts]", this.selectedAccounts.length));
            }
            if (this.selectedPackages.length) {
                summaryItems.push(LOCALE.maketext("[quant,_1,Package,Packages]", this.selectedPackages.length));
            }

            if (this.selectedConfigurations.length) {
                summaryItems.push(LOCALE.maketext("[quant,_1,Server Configuration,Server Configurations]", this.selectedConfigurations.length));
            }
            return LOCALE.maketext("When you click [output,em,_1], you will start the transfer process for the following: [list_and,_2]", this.getCopyButtonLabel(), summaryItems);
        };

        var app;
        try {
            app = angular.module("App"); // For runtime
            app.value("PAGE", PAGE);
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        /**
         * Returns true if the account does not exist locally on the server
         * @param  {object} item
         * @return {Boolean}
         */
        app.filter("existingUsers", function() {
            return function(items, exactMatchesOnly) {
                var matched = [];
                angular.forEach(items, function(item, index) {
                    if (exactMatchesOnly && item.localuser !== item.similarLocalUser) {

                        /* if exactMatchOnly is set, it will not return n character matches */
                        /* this is to allow filtering items to show only overwritable ones (exact matches) */
                        return false;
                    } else if (!exactMatchesOnly && item.localuser === item.similarLocalUser) {
                        return false;
                    }

                    /* will not return if user is also reserved because a reserved name overrides an existing name in transfers */
                    if (item.selected && item.invalidUser && item.userCheckStates.existing && !item.userCheckStates.reserved) {
                        matched.push(item);
                    }

                });
                return matched;
            };
        });

        MainController.$inject = CONTROLLER_INJECTABLES;
        var controller = app.controller("MainController", MainController);

        return controller;
    }
);

/*
# templates/transfer_tool/filters/accountFilter.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/filters/accountFilter',[
        "angular"
    ],
    function(angular) {

        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        /**
         * Filter that filters only on specific field based on $scope.acctsFilter.  Will return true if the account passes the filter.  Necessary for performance optimization.
         * @param  {onject} item
         * @return {array}
         */
        app.filter("accountFilter", function() {
            return function(accounts, filterText) {
                if (!filterText) {
                    return accounts;
                }
                var filteredAccounts = [];
                angular.forEach(accounts, function(account) {

                    /* isUser */
                    if (account.user.indexOf(filterText) !== -1) {
                        filteredAccounts.push(account);
                    } else if (account.domain.indexOf(filterText) !== -1) {

                        /* isDomain */
                        filteredAccounts.push(account);
                    } else if (account.owner.indexOf(filterText) !== -1) {

                        /* isOwner */
                        filteredAccounts.push(account);
                    }
                });

                return filteredAccounts;
            };
        });
    }
);

/*
# templates/transfer_tool/filters/advanceAccountFilter.js           Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/filters/advanceAccountFilter',[
        "angular"
    ],
    function(angular) {

        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        /**
         * Filter that uses the options set in the advance filter form to further filter accounts.  Will return true if the account passes the filter.
         * @param  {object} item
         * @return {?array}
         */
        app.filter("advanceAccountFilter", function() {
            return function(accounts, advanceFilter) {
                if (!advanceFilter) {
                    return accounts;
                }
                var filteredAccounts = [];
                angular.forEach(accounts, function(account) {
                    if (account.remote_user.indexOf(advanceFilter.user) === -1) {
                        return;
                    }
                    if (account.domain.indexOf(advanceFilter.domain) === -1) {
                        return;
                    }
                    if (advanceFilter.owner && advanceFilter.owner.length && advanceFilter.owner.indexOf(account.owner) === -1) {
                        return;
                    }
                    if (advanceFilter.dedicated_ip >= 0 && account.dedicated_ip !== advanceFilter.dedicated_ip) {
                        return;
                    }

                    filteredAccounts.push(account);
                });

                return filteredAccounts;
            };
        });
    }
);

/*
# templates/transfer_tool/controllers/AccountTableController.js     Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

/* jshint -W003 */
/* jshint -W098*/

define(
    'app/controllers/AccountTableController',[
        "angular",
        "cjt/util/locale",
        "cjt/util/parse",
        "app/services/workerNodes",
        "app/filters/startFromFilter",
        "app/filters/cpLimitToFilter",
        "app/filters/accountFilter",
        "app/filters/advanceAccountFilter",
        "cjt/services/whm/nvDataService",
    ],
    function(angular, LOCALE, PARSE, WorkerNodesService) {

        "use strict";

        var DEFAULT_CUSTOMIZED_LABEL = LOCALE.maketext("Default");
        var CUSTOM_CUSTOMIZED_LABEL = LOCALE.maketext("Custom");

        var SKIP_FLAG_DEFAULTS = {
            "copy_homedir": 1,
            "copy_databases": 1,
            "copy_bwdata": 1,
            "copy_reseller_privs": 0
        };

        var CONTROLLER_INJECTABLES = ["$scope", "$rootScope", WorkerNodesService.serviceName, "$filter", "$uibModal", "PAGE", "nvDataService", "OVERWRITE_OPTIONS", "OVERWRITE_STATES", "OVERWRITE_DESCRIPTION_TEMPLATE"];

        /**
         * @class Controller class for the account table.  Used in the angular app with 'controller as'.  This contains most logic pertaining to accounts.
         * @param {object} $scope
         * @param {object} $filter
         */
        var AccountTableController = function($scope, $rootScope, $workerNodesService, $filter, $uibModal, PAGE, nvDataService, OVERWRITE_OPTIONS, OVERWRITE_STATES, OVERWRITE_DESCRIPTION_TEMPLATE) {
            var _this = this;

            _this.PAGE = PAGE;
            _this.disableLiveTransfers = _this.PAGE.disable_live_transfers;
            _this.isRestrictedRestore = _this.PAGE.restricted_restore;
            _this.isRTL = PAGE.locale_is_rtl.toString() === "1";

            _this.overwriteOptions = OVERWRITE_OPTIONS;

            _this.reservedUsernamePatterns = _this.PAGE.local.reserved_username_patterns;
            _this.localUserHash = Object.create(null);
            _this.reservedUsernames = {};
            _this.localPartialUsernames = {};

            _this.defaultWorkerOptions = $workerNodesService.getDefaultWorkerOptions();
            _this.workerOptionTypes = $workerNodesService.getWorkerOptionTypes();

            _this.control_overwrite = _this.overwriteOptions[0];
            _this.overwriteStates = OVERWRITE_STATES;

            _this.accountFilterText = "";
            _this.acctTable = {
                currentPage: 1,
                pageSize: 10,
                reverse: false,
                order: "remote_user",
                advSearchOptions: {
                    domain: "",
                    user: "",
                    owner: [],
                    dedicated_ip: -1
                },
                activeAdvFilter: null
            };

            _this.getDedicatedIPDomains = function() {
                return _this.PAGE.domainsWithDedicatedIp;
            };

            // This will require more logic as the banner messages that can reset dedicated
            // IP addresses so for now we are returning the status
            // quo of always displaying the column.
            _this.showDedicatedIPColumn = true;

            var supportsExpressTransfers = PAGE.remote ? PARSE.parsePerlBoolean(PAGE.remote.supports_express_transfers) : false;
            var supportsLiveTransfers = PAGE.remote ? PARSE.parsePerlBoolean(PAGE.remote.supports_live_transfers) : false;

            // If we support live transfers, it defaults to on
            // Unless it has been disabled
            var PROXY_FLAG_DEFAULT = supportsLiveTransfers && !_this.disableLiveTransfers;
            $scope.supportsLiveTransfers = supportsLiveTransfers;

            $scope.liveTransfersNoticeIsDismissed = PAGE.liveTransfersNoticeIsDismissed;
            $scope.liveTransfersPre90NoticeIsDismissed = PAGE.liveTransfersPre90NoticeIsDismissed;
            $scope.isAcctTabActive = true;

            // Overload the live transfer support. This gets set when the hostname is invalid.
            // We also need to overload and hide the notifications for live transfers
            if (_this.disableLiveTransfers) {
                $scope.liveTransfersNoticeIsDismissed = true;
            }

            $scope.dismissLiveTransfersNotice = function dismissLiveTransfersNotice() {
                $scope.liveTransfersNoticeIsDismissed = true;
                nvDataService.set("live_transfers_notice_is_dismissed", 1);
            };

            $scope.dismissLiveTransfersPre90Notice = function dismissLiveTransfersPre90Notice() {
                $scope.liveTransfersPre90NoticeIsDismissed = true;
                $scope.liveTransfersNoticeIsDismissed = true;

                nvDataService.set("live_transfers_pre_90_notice_is_dismissed", 1);
            };

            $rootScope.showTable = function showTable() {
                return !$scope.isAcctTabActive || (!$scope.supportsLiveTransfers || ($scope.supportsLiveTransfers && $scope.liveTransfersNoticeIsDismissed));
            };

            $rootScope.setAcctTabActive = function(isAcctTabActive) {
                $scope.isAcctTabActive = isAcctTabActive;
            };

            _this.createUser = function(obj, index) {
                obj.initialindex = index;
                obj.copy_homedir = SKIP_FLAG_DEFAULTS["copy_homedir"];
                obj.copy_databases = SKIP_FLAG_DEFAULTS["copy_databases"];
                obj.copy_bwdata = SKIP_FLAG_DEFAULTS["copy_bwdata"];
                obj.copy_reseller_privs  = SKIP_FLAG_DEFAULTS["copy_reseller_privs"];
                obj.copy_proxy_option = PROXY_FLAG_DEFAULT;
                obj.proxyOption = {
                    id: "proxy_option",
                    modelKey: "copy_proxy_option",
                    value: PROXY_FLAG_DEFAULT,
                    default: PROXY_FLAG_DEFAULT,
                    supports_live_transfers: PROXY_FLAG_DEFAULT,
                    supports_express_transfers: supportsExpressTransfers,
                };
                obj.selected = 0;
                obj.overwrite_type = _this.overwriteOptions[0];
                obj.overwrite_account = 0;
                obj.overwrite_with_delete = 0;
                obj.userCheckStates = {
                    duplicate: false,
                    reserved: false,
                    existing: false
                };
                obj.dedicated_ip = (obj.dedicated_ip || _this.getDedicatedIPDomains()[obj.domain]) ? 1 : 0;
                obj.existing_dedicated_ip = obj.dedicated_ip;
                obj.oldlocaluser = obj.user;
                obj.localuser = obj.user;
                obj.invalidDomain = _this.PAGE.local.domains[obj.domain] && _this.PAGE.local.domains[obj.domain] !== obj.user ? 1 : 0;
                obj.is_reseller = _this.PAGE.remote.resellers && _this.PAGE.remote.resellers[obj.remote_user] ? 1 : 0;
                obj.invalidUser = _this.PAGE.local.users[obj.remote_user] ? 1 : 0;
                obj.isCustomized = false;
                obj.workerNodes = obj.worker_nodes || {};

                // This is done in the service because it's done in multiple controllers
                $workerNodesService.resetAccountToDefaults(obj);
            };

            _this.expandedAccount = false;

            _this.PAGE.items.accounts.forEach(_this.createUser);

            var accountFilter = $filter("accountFilter"),
                advanceAccountFilter = $filter("advanceAccountFilter"),
                startFrom = $filter("startFrom"),
                orderBy = $filter("orderBy"),
                limitTo = $filter("cpLimitTo");


            // To better understand what these assignments are look at updateFilteredAccounts and updateViewableAccounts
            _this.filteredAccounts = accountFilter(advanceAccountFilter(this.PAGE.items.accounts, _this.acctTable.activeAdvFilter), _this.accountFilterText);
            _this.viewableAccounts = limitTo(startFrom(orderBy(_this.filteredAccounts, _this.acctTable.order, _this.acctTable.reverse), (_this.acctTable.currentPage - 1) * _this.acctTable.pageSize),
                _this.acctTable.pageSize);

            /**
            * Reapplies filters for the filteredAccounts array
            * Array    ->    Filtered by advanced             -> filtered by basic
            * accounts | advanceAccountFilter:activeAdvFilter | accountFilter:accountFilterText
            */
            _this.updateFilteredAccounts = function() {
                _this.filteredAccounts = accountFilter(
                    advanceAccountFilter(this.PAGE.items.accounts, _this.acctTable.activeAdvFilter), _this.accountFilterText);
            };

            /**
            * Reapplies filteres for the viewableAccounts array.
            * FilteredArray    ->              Ordered by(reverse?)         ->          start based on page #                             ->    limit to page size
            * filteredAccounts | orderBy: acctTable.order:acctTable.reverse | startFrom:(acctTable.currentPage - 1 ) * acctTable.pageSize | limitTo: acctTable.pageSize
            */
            _this.updateViewableAccounts = function() {
                var pageSize = _this.acctTable.pageSize;
                var accounts = orderBy(_this.filteredAccounts, _this.acctTable.order, _this.acctTable.reverse);
                accounts = limitTo(startFrom(accounts, (_this.acctTable.currentPage - 1) * pageSize), pageSize);
                _this.viewableAccounts = accounts;
            };

            _this.getUsernamePattern = function(key) {
                if (key === "TRIM_PATTERN") {
                    return new RegExp(_this.PAGE.UN_TRIM_REG_EXP);
                } else if (key === "TRANSFER_USER_RESTRICT") {
                    return new RegExp(_this.PAGE.USERNAME_TRANSFER_REGEXP);
                } else if (key === "NONTRANSFER_USER_RESTRICT") {
                    return new RegExp(_this.PAGE.USERNAME_REGEXP);
                } else {
                    return null;
                }
            };

            $scope.$on("recheckUsersCalled", function(eo, args) {
                angular.forEach(args.dataset, function(acct) {

                    // Always skip forcing selection, since "Select None" will cause this to just get re-selected
                    _this.updateOverwriteFlags(acct, false, true);
                    _this.updateUserCheckStates(acct);
                    _this.checkAccountForDuplicateLocals(acct);
                    _this.updateAccountsControlRow();
                });
            });

            $scope.$on("selectedAccountsEmptied", function() {
                _this.acct_checkbox_control = false;
                _this.updateAccountsControlRow();
            });

            $scope.$watch(function() {
                return _this.acctTable;
            }, function() {
                _this.updateViewableAccounts();
            }, true);

            $scope.$watch(function() {
                return _this.viewableAccounts;
            }, function() {
                _this.updateAccountsControlRow();
            }, true);

            for (var rUi = 0; rUi < _this.PAGE.local.reserved_usernames.length; rUi++) {
                var reservedUsername = _this.PAGE.local.reserved_usernames[rUi].toLowerCase();
                _this.reservedUsernames[reservedUsername] = 1;
            }

            /* used to check the eight v 16 restrictions of (no same first USERNAME_UNIQUE_LENGTH characters) */
            /* pre processed for big lists */

            angular.forEach(_this.PAGE.local.users, function(value, lUsername) {
                var plUsername = _this.makeUsernamePartial(lUsername, true);
                this[plUsername] = lUsername;
            }, _this.localPartialUsernames);

            angular.forEach(_this.PAGE.items.accounts, function(acct, key) {

                /* store local user hash */
                _this.storeLocalUserHash(acct.initialindex, acct.oldlocaluser, acct.localuser);
            });

            // Set the columnWidth

            _this.numberOfColumns = 9;
            ["bytesused", "owner", "dedicated_ip"].forEach(function(key) {
                if (!_this.showColumn(key)) {
                    _this.numberOfColumns--;
                }
            });

            _this.skipOptions = [
                { id: "copy_homedir_for", label: LOCALE.maketext("Home Directory"), modelKey: "copy_homedir", default: SKIP_FLAG_DEFAULTS["copy_homedir"] },

                // Disable reseller privileges skipOption for restricted restores
                { id: "reseller_privs_for", label: LOCALE.maketext("Reseller Privileges"), modelKey: "copy_reseller_privs", default: SKIP_FLAG_DEFAULTS["copy_reseller_privs"], disabled: _this.isRestrictedRestore },
                { id: "copy_acctdb_for", label: LOCALE.maketext("Databases"), modelKey: "copy_databases", default: SKIP_FLAG_DEFAULTS["copy_databases"] },
                { id: "copy_bwdata_for", label: LOCALE.maketext("Bandwidth Data"), modelKey: "copy_bwdata", default: SKIP_FLAG_DEFAULTS["copy_bwdata"] },
            ];

            _this.openModal = $uibModal.open.bind($uibModal);
            _this.overwriteDescriptionTemplate = OVERWRITE_DESCRIPTION_TEMPLATE;

            this._workerOptionAltered = $workerNodesService.checkWorkerOptionsAltered.bind($workerNodesService);

            return _this;
        };

        angular.extend(AccountTableController.prototype, {

            /**
            * Stores hashed usernames for duplication checks on large amounts of usernames
            */
            storeLocalUserHash: function storeLocalUserHash(index, oldValue, newValue) {

                var _this = this;
                var newValuePartial = this.makeUsernamePartial(newValue, true);
                var oldValuePartial = this.makeUsernamePartial(oldValue, true);

                _this.localUserHash[oldValuePartial] = _this.localUserHash[oldValuePartial] || [];
                angular.forEach(_this.localUserHash[oldValuePartial], function(value, key) {
                    if (value === index) {
                        _this.localUserHash[oldValuePartial].splice(key, 1);
                    }
                });

                _this.localUserHash[newValuePartial] = _this.localUserHash[newValuePartial] || [];
                _this.localUserHash[newValuePartial].push(index);
            },

            /**
            * Calls functions that update filtered and viewable accounts
            */
            updateAccounts: function updateAccounts() {
                this.updateFilteredAccounts();
                this.updateViewableAccounts();
            },

            /**
            * Returns class corresponding to glyph for account.  Account must be selected and not have a domain conflict.
            * @param  {object} acct
            * @return {?string}
            */
            getGlyphClass: function getGlyphClass(acct) {
                if (!acct.selected || acct.domainConflict) {
                    return;
                }
                if (acct.invalidUser) {
                    return "glyphicon-exclamation-sign";
                } else {
                    return "glyphicon-ok";
                }
            },

            /**
            * Returns class for button that corresponds to what choice for dedicated ip was selected.  Used in advance search form to indicate selection similar to radio button.
            * @param  {int} thisVal
            * @return {string|Boolean}
            */
            dedicatedIpClass: function dedicatedIpClass(thisVal) {
                return thisVal === this.acctTable.advSearchOptions.dedicated_ip ? "btn-primary" : "btn-default";
            },

            /**
             * Check the state of the various control columns
             *
             * @param {object[]} accounts list of accounts to build the value based on
             * @param {string} param parameter on account to check
             * @returns {*} current value of control column. Various values possible.
             */
            _getColumnControlState: function _getColumnControlState(accounts, param) {

                // If there are no accounts, return false
                if (!accounts.length) {
                    return false;
                }

                // If any are not checked, return false
                for (var i = 0; i < accounts.length; i++) {
                    var account = accounts[i];
                    if (!account[param]) {
                        return false;
                    }
                }

                // If all are checked, return true
                return true;
            },

            /**
             * Check the state of the overwrite control column
             *
             * @param {object[]} accounts list of accounts to build the value based on
             * @param {string} param parameter on account to check
             * @returns {object|null} value of the parameter for accounts if the same. Undefined otherwise.
             */
            _getOverwriteColumnControlState: function _getOverwriteColumnControlState(accounts, param) {

                // Update only based on selected accounts in list

                // If there are no accounts, return false
                if (!accounts.length) {
                    return this.overwriteOptions[0];
                }

                var currentValue;
                for (var i = 0; i < accounts.length; i++) {
                    var account = accounts[i];
                    if (!this.canNeedOverwrite(account)) {

                        // Only ones that might need overwrite should be considered
                        continue;
                    }

                    // Store the first value as a baseline
                    if (!currentValue) {
                        currentValue = account[param];
                    }

                    // If any are different from one another, default to undef (to allow setting it)
                    if (account[param].value !== currentValue.value) {
                        return;
                    }
                }

                // If all are one of the two overwrite values [1,2], use that value
                // If no value was determined, then no overwrite-capable items were found, use the zero option
                return currentValue ? currentValue : this.overwriteOptions[0];
            },

            /**
            * Called to check and adjust control row check boxes based on viewable account params
            */
            updateAccountsControlRow: function updateAccountsControlRow() {

                var checks = [{
                    param: "selected",
                    controlModel: "acct_checkbox_control",
                    checkFunction: this._getColumnControlState.bind(this)
                }, {
                    param: "dedicated_ip",
                    controlModel: "control_dedicated_ip",
                    onlySelected: true,
                    checkFunction: this._getColumnControlState.bind(this)
                }, {
                    param: "overwrite_type",
                    controlModel: "control_overwrite",
                    onlySelected: true,
                    checkFunction: this._getOverwriteColumnControlState.bind(this)
                }];

                var selectedAccounts = this.viewableAccounts.filter(function(account) {
                    return !!account.selected;
                });

                angular.forEach(checks, function(check) {

                    var accounts = check.onlySelected ? selectedAccounts : this.viewableAccounts;
                    this[check.controlModel] = check.checkFunction(accounts, check.param);

                }, this);

            },

            /**
            * Sets the advance search($scope.acctTable.advSearchOptions) to either be a copy of the object passed in or if no object, to the default value.  We set it this way
            * because otherwise Angular will bind the object directily causing any updates to be instantaneous, breaking the experience.
            * @param {object} obj
            */
            setAdvanceSearch: function setAdvanceSearch(obj) {
                this.acctTable.activeAdvFilter = angular.copy(obj);
                this.updateAccounts();

                if (!obj) {
                    this.acctTable.advSearchOptions = {
                        domain: "",
                        user: "",
                        owner: [],
                        dedicated_ip: -1
                    };
                }
            },

            /**
            * Goes over array of accounts and sets the dedicated_ip flag if the destination domain already has a dedicated ip.
            * @param  {array} dataset
            */
            handleDedicatedIpForArray: function handleDedicatedIpForArray(dataset) {
                var _self = this;
                angular.forEach(dataset, function(acct) {
                    if (_self.getDedicatedIPDomains()[acct.domain]) {
                        acct.dedicated_ip = 1;
                    }
                });
            },

            /**
            * Returns true if the account has a destination domain with a dedicated ip already or if there are no available IP addresses.
            * @param  {object}  acct
            * @return {Boolean}
            */
            isDedicatedIpDisabled: function isDedicatedIpDisabled(acct) {
                return this.getDedicatedIPDomains()[acct.domain] ? true : !this.PAGE.local.available_ips.length;
            },

            /**
            * Returns true for account that can be overwritten
            * @param  {object} item
            * @return {Boolean}
            */
            overwriteFilter: function overwriteFilter(item) {
                return this.PAGE.local.users[item.user] || this.PAGE.local.users[item.localuser] || (this.PAGE.local.domains[item.domain] === item.localuser);
            },

            /**
            * Updates account username checks and stores then on acct.userCheckStates
            * then updates calls updateLocalUserStatus() to reset acct.invalidUser
            *
            * @method validateAccount
            * @param acct {Object} angular user account object
            */
            validateAccount: function validateAccount(acct) {

                // update account localuser hash for duplicate validation
                /* which large accounts this was the only feasible option. */
                /* deep watch expressions were far too cumbersome.  */
                this.storeLocalUserHash(acct.initialindex, acct.oldlocaluser, acct.localuser);

                /* must be called before oldusername is reset to reset duplication on old set */
                this.checkAccountForDuplicateLocals(acct);
                acct.oldlocaluser = acct.localuser;
                this.updateUserCheckStates(acct);

            },

            /**
            * Seperate function allows independent updates to userCheckStates
            * used in ToggleCheckAll
            *
            * @method updateuserCheckStatus
            * @param acct {Object} angular user account object
            */
            updateUserCheckStates: function updateUserCheckStates(acct) {

                /* response is now in the form of false, or failure object */
                acct.userCheckStates.reserved = this.isReservedUsername(acct);
                acct.userCheckStates.existing = this.isExistingLocalUser(acct);

                /* refers to the specific makeup of the new username (does it match the regexp) */
                acct.userCheckStates.invalid = !this.isLocalUsernameValid(acct);
                acct.overwrite_type = acct.selected ? acct.overwrite_type : this.overwriteOptions[0];
                this.updateLocalUserStatus(acct);
            },

            /**
            * updates 'invalidUser' based on state check flags
            *
            * @method updateLocalUserStatus
            * @param acct {Object} angular user account object
            */
            updateLocalUserStatus: function updateLocalUserStatus(acct) {
                if ((acct.userCheckStates.existing !== false && acct.overwrite_type.value === this.overwriteStates.NO_OVERWRITE ) ||
                    acct.userCheckStates.duplicate !== false ||
                    acct.userCheckStates.invalid !== false ||
                    acct.userCheckStates.reserved !== false) {
                    acct.invalidUser = true;
                } else {
                    acct.invalidUser = false;
                }
            },

            /**
            * Returns the class to be used for input field highlighting.
            * @param  {object} acct
            * @return {?string}
            */
            getInputClass: function getInputClass(acct) {
                if (!acct.selected || acct.domainConflict) {
                    return;
                }

                if (acct.invalidUser) {
                    return "has-error";
                } else {
                    return "has-success";
                }
            },

            /**
            * Returns username converted from account as as string
            *
            * @method getUserNameFromAcct
            * @param acct {Object} angular user account object
            * @return {String} value of username
            */
            getUserNameFromAcct: function getUserNameFromAcct(acct) {
                var username = acct.localuser || "";
                if (!username.length) {
                    username = acct.remote_user;
                }
                return username;
            },

            /**
            * Returns Array of accounts that the username matches (can be partial match).
            *
            * @method findAccountsByUsername
            * @param username {String} angular user account object
            * @param matchFirstNChars {int} number of matching characters defaults to all
            *        passing -1 will be treated as a 'match all characters'
            * @param startingIndex {int} which account to begin the interation from (faster)
            * @return {Array} of acct indexes that match
            */
            findAccountsByUsername: function findAccountsByUsername(username, matchFirstNChars, startingIndex) {

                /* if matchFirstNChars > 0 use matchFirstNChars | else use -1 (interpretted as all) */
                matchFirstNChars = Number(matchFirstNChars) || -1;
                startingIndex = Number(startingIndex) || 0;

                if (matchFirstNChars !== -1) {
                    username = username.substr(0, matchFirstNChars);
                }

                var matchedAccounts = [];

                var otherAccount;
                for (var i = startingIndex; i < this.PAGE.items.accounts.length; i++) {

                    otherAccount = this.PAGE.items.accounts[i];

                    if (otherAccount.localuser.toLowerCase().indexOf(username) === 0) {

                        if (username.length < matchFirstNChars && otherAccount.localuser.length > username.length) {

                            /* this means that the otherAccount has additional characters in the NChars range
                                    so it is no longer enough matching characters */
                            continue;
                        }

                        /* username was found in it */
                        if (matchFirstNChars === -1 && username.length !== otherAccount.localuser.length) {

                            /* matchFirstNChars is set to default (match all), but lengths of the usernames */
                            continue;
                        }

                        /* good length, good first n chars */
                        matchedAccounts.push(i);
                    }

                }

                return matchedAccounts;
            },

            /**
            * finds accounts by username, then returns selected accounts
            *
            * @method findSelectedAccountsByUsername
            * see: findAccountsByUsername for @params
            */
            findSelectedAccountsByUsername: function findSelectedAccountsByUsername( /* inherit from findAccountsByUsername */ ) {

                var usernames = this.findAccountsByUsername.apply(this, arguments);
                var selected = [];

                if (usernames === false) {
                    return selected;
                }

                var uIndex;
                for (var i = 0; i < usernames.length; i++) {
                    uIndex = usernames[i];
                    if (this.PAGE.items.accounts[uIndex].selected) {
                        selected.push(uIndex);
                    }
                }

                return selected;

            },

            /**
            * Checks one local account for duplicates and marks userCheckStates.duplicate accordingly
            *
            * @method checkAccountForDuplicateLocals
            */
            checkAccountForDuplicateLocals: function checkAccountForDuplicateLocals(acct) {

                /* clear status flag */
                acct.userCheckStates.duplicate = false;

                /* get oldlocaluser and reset old duplicates */

                var oldUsernamePartial = this.makeUsernamePartial(acct.oldlocaluser, true);

                /* recheck old username set to update their duplicate flag */
                if (this.localUserHash[oldUsernamePartial] && this.localUserHash[oldUsernamePartial].length === 1) {
                    var previousDuplicateUser = this.localUserHash[oldUsernamePartial][0];
                    this.PAGE.items.accounts[previousDuplicateUser].userCheckStates.duplicate = false;
                    this.updateLocalUserStatus(this.PAGE.items.accounts[previousDuplicateUser]);
                }

                /* no local username entered? Ignore it! */
                if (!acct.localuser) {
                    return;
                }

                var username = acct.localuser;
                var trimmedUsername = this.makeUsernamePartial(username, true);
                var accountIndexOrObject;
                var accountIndex;
                var selectedOthers = [];

                /* reset all, store still selected items for next loop */
                for (var i = 0; i < this.localUserHash[trimmedUsername].length; i++) {
                    accountIndex = this.localUserHash[trimmedUsername][i];

                    accountIndexOrObject = this.PAGE.items.accounts[accountIndex];

                    accountIndexOrObject.userCheckStates.duplicate = false;
                    this.updateLocalUserStatus(accountIndexOrObject);

                    /* items that aren't selected are ignored */
                    if (!accountIndexOrObject.selected) {
                        continue;
                    }

                    selectedOthers.push(accountIndexOrObject);
                }

                /* if multiple items remain selected in this hash, set them as duplicates */

                if (selectedOthers.length > 1) {


                    for (i = 0; i < selectedOthers.length; i++) {
                        accountIndexOrObject = selectedOthers[i];

                        accountIndexOrObject.userCheckStates.duplicate = true;
                        this.updateLocalUserStatus(accountIndexOrObject);
                    }

                }

            },

            /**
            * Checks all local accounts for duplicates and marks userCheckStates.duplicate accordingly
            *
            * @method checkForDuplicateLocals
            */
            checkForDuplicateLocals: function checkForDuplicateLocals() {

                /* check this username against other usernames that have been checked for transfer */
                var i, otherAccount;

                /* reset all initially to allow faster parsing later in function*/
                for (i = 0; i < this.PAGE.items.accounts.length; i++) {
                    otherAccount = this.PAGE.items.accounts[i];
                    otherAccount.userCheckStates.duplicate = false;
                    this.updateLocalUserStatus(otherAccount);
                }

                /* iterate through all, skip already set duplicates, */
                for (i = 0; i < this.PAGE.items.accounts.length; i++) {
                    otherAccount = this.PAGE.items.accounts[i];
                    if (otherAccount.userCheckStates.duplicate) {

                        /* because of forward iteration nature of this, this
                                has been cleared and marked as a set for another item */
                        continue;
                    }
                    this.checkAccountForDuplicateLocals(otherAccount);
                }
            },

            /**
            * Returns Boolean defining whether account username is considered reserved.
            *
            * @method isReservedUsername
            * @param acct {Object} angular user account object
            * @return {Boolean} true if username is reserved
            */
            isReservedUsername: function isReservedUsername(acct) {
                var username = this.getUserNameFromAcct(acct);

                /* trim spaces from ends of username */
                var trimmedUsername = username.replace(/^\s*(.+)\s*$/i, "$1");

                /* check against reserved system names to see if this on exists */
                if (trimmedUsername in this.reservedUsernames) {
                    return true;
                }

                /* interim list of restricted partial names (reg ex patterns) */
                /* list cannot contain these specific parts */
                /*
                        matches names, or parts of names dependent on need
                        <[name]>$ matches a <[name]> at the end of a username
                        ^<[name]> matches a <[name]> at the beginning of the username
                        ^<[name]>$ matches exactly that <[name]> with no trailing or begining characters
                    */

                var currentRegExp, reservedNamePattern;
                for (var i = 0; i < this.reservedUsernamePatterns.length; i++) {
                    reservedNamePattern = this.reservedUsernamePatterns[i];

                    /* build dynamic regular expression */
                    currentRegExp = new RegExp(reservedNamePattern, "gi");
                    if (trimmedUsername.match(currentRegExp) !== null) {
                        return true;
                    }
                }

                return false;

            },

            /**
            * Returns Boolean representing whether acct.username exists on local machine
            * in part or fully (only first USERNAME_UNIQUE_LENGTH characters need to match)
            *
            * @method isExistingLocalUser
            * @param acct {Object} angular user account object
            * @return {Boolean} dependent on user existing on local server
            */
            isExistingLocalUser: function isExistingLocalUser(acct) {
                var username = this.getUserNameFromAcct(acct);
                var trimmedUsername = this.makeUsernamePartial(username, true);
                if (trimmedUsername in this.localPartialUsernames) {
                    acct.similarLocalUser = this.localPartialUsernames[trimmedUsername];
                    return true;
                }

                return false;
            },

            /**
            * Tests username against globally established regexp
            * uses the transfer specific regexp if remote_user === localuser
            * uses the non-transfer regexp otherwise
            *
            * @method isLocalUsernameValid
            * @param acct {Object} angular user account object
            * @return {Boolean} true or false based on regexp.test
            */
            isLocalUsernameValid: function isLocalUsernameValid(acct) {
                var re = this.getUsernamePattern("TRANSFER_USER_RESTRICT");
                var partial = this.makeUsernamePartial(acct.localuser, true);
                // eslint-disable-next-line no-useless-escape
                if (!partial.replace(/\-/gi, "").length) {
                    return false;
                }
                return re.test(acct.localuser);
            },

            makeUsernamePartial: function makeUsernamePartial(username, removeSpecialCharacters) {
                if (removeSpecialCharacters) {
                    // eslint-disable-next-line no-useless-escape
                    username = username.replace(/[\_\.]/gi, "");
                }
                return username.replace(this.getUsernamePattern("TRIM_PATTERN"), "$1").toLowerCase();
            },

            /**
             * Get the classes for each account row
             *
             * @param {object} account user account to check against
             * @returns {string} if the item is selected, and either the domain or user is invalid, else nothing
             */
            getAccountRowClasses: function getAccountRowClasses(account) {
                if (!account.selected) {
                    return "";
                }

                if (!account.invalidUser && !account.invalidDomain) {
                    return "success";
                }

                return "danger";
            },

            /**
             * Determine whether a column should show based on the key
             *
             * @param {string} columnName account key to check
             * @returns {boolean} qwhether to show the column
             *
             */
            showColumn: function showColumn(columnName) {
                switch (columnName) {
                    case "bytesused":
                        return !!this.PAGE.remote.has_disk_used;
                    case "owner":
                        return !!this.PAGE.remote.has_owners;
                    case "dedicated_ip":
                        return !!this.showDedicatedIPColumn;
                    default:
                        return true;
                }
            },

            /**
             * For Each account, determine the current chevron icon state
             *
             * @param {*} account account to check
             * @returns {string} if the account is expanded, 'fa-chevron-down', else a left or right based on the RTL settings of LOCALE
             */
            getChevronClasses: function getChevronClasses(account) {
                var collapsedClass = this.isRTL ? "fa-chevron-left" : "fa-chevron-right";
                return this.isAccountExpanded(account) ? "fa-chevron-down" : collapsedClass;
            },

            /**
             * Update the isCustomized value for an account based on skipOptions states
             *
             * @param {object} account account to check
             */
            updateCustomizedFlag: function updateCustomizedFlag(account) {
                account.isCustomized = this._skipOptionsAltered(account) || this._workerOptionAltered(account) || this._proxyOptionAltered(account);
            },

            _skipOptionsAltered: function _skipOptionsAltered(account) {
                var skipKeys = Object.keys(SKIP_FLAG_DEFAULTS);
                for (var i = 0; i < skipKeys.length; i++) {
                    var skipKey = skipKeys[i];
                    if (account[skipKey] !== SKIP_FLAG_DEFAULTS[skipKey]) {
                        return true;
                    }
                }
                return false;
            },

            /**
             * Check if Live Transfer option has be altered
             *
             * @param  {object} account account to check
             */
            _proxyOptionAltered: function _proxyOptionAltered(account) {
                if (account.proxyOption.value !== account.proxyOption.default) {
                    return true;
                }
                return false;
            },

            /**
             * Check if the account is expanded
             *
             * @param {object} account account to check
             * @returns {boolean} true|false state of account expansion
             */
            isAccountExpanded: function isAccountExpanded(account) {
                return this.expandedAccount === account;
            },

            /**
             * Expand the account
             *
             * @param {object} account account to expand
             */
            expandAccount: function expandAccount(account) {
                if (this.expandedAccount) {
                    this.collapseAccount(this.expandedAccount);
                }
                this.expandedAccount = account;
                this.accountSettingUpdated(account, true);
            },

            /**
             * Collapse the account
             *
             * @param {object} account account to collapse
             */
            collapseAccount: function collapseAccount(account) {
                this.expandedAccount = false;
            },

            /**
             * Toggle the expanded state of an account
             *
             * @param {object} account account to toggle
             */
            toggleAccountExpansion: function toggleAccountExpansion(account) {
                if ( this.isAccountExpanded(account) ) {
                    this.collapseAccount(account);
                } else {
                    this.expandAccount(account);
                }
            },

            /**
             * Get the label based on the isCustomized value of the account
             *
             * @param {object} account account to check
             */
            getCustomizeLabel: function getCustomizeLabel(account) {
                return account.isCustomized ? CUSTOM_CUSTOMIZED_LABEL : DEFAULT_CUSTOMIZED_LABEL;
            },

            /**
             * Called from the view when the expanded panel of an account change
             *
             * @param {object} account that changed
             * @param {string} key what option changed
             * @param {*} value what is the new value of that option
             */
            onExpandPanelOptionChanged: function onExpandPanelOptionChanged(account, key, value) {
                this.updateAccountSetting(account, key, value);
            },

            /**
             * Called from the view when "apply to all" is emmitted
             *
             * @param {object} fromAccount source account to copy from
             * @param {object[]} toAccounts destination accounts to copy to
             * @param {object[]} skipOptions which skip options to update
             * @param {object} workerOptions which worker options to update
             * @param {object} proxyOption proxy option to update
             */
            onExpandPanelApplyToAll: function onExpandPanelApplyToAll(fromAccount, toAccounts, skipOptions, workerOptions, proxyOption) {

                // Get Skip Model Keys Once
                var skipModelKeys = skipOptions.map(function(skipOption) {
                    return skipOption.modelKey;
                }, this);

                // Get Worker Model Keys Once
                var workerModelKeys = workerOptions && Object.keys(workerOptions).map(function(workerOptionType) {
                    return workerOptions[workerOptionType].modelKey;
                }, this) || [];

                // Include other options
                var modelKeys = ["dedicated_ip", "copy_proxy_option"].concat(skipModelKeys, workerModelKeys);

                var copyOverwrite = this.canNeedOverwrite(fromAccount);

                // Update extra items and validate
                toAccounts.filter(function(toAccount) {
                    if (toAccount === fromAccount) {
                        return false;
                    }
                    return true;
                }).forEach(function(toAccount) {
                    var myCopyOverwrite = copyOverwrite && this.canNeedOverwrite(toAccount);

                    var myModelKeys = modelKeys.slice();
                    if (myCopyOverwrite) {
                        myModelKeys.push("overwrite_type");
                    }

                    myModelKeys.forEach(function(modelKey) {
                        this.updateAccountSetting(toAccount, modelKey, fromAccount[modelKey], false);
                    }, this);

                    // If, but only if, both accounts are need-overwrite
                    // we should copy the overwrite setting.
                    if (myCopyOverwrite) {
                        this.updateOverwriteFlags(toAccount, false);
                    }

                    this.validateAccount(toAccount);
                }, this);
            },

            /**
             * Update an account setting and update settings based on it.
             *
             * @param {object} account account on which to update the setting
             * @param {string} key setting to update
             * @param {*} value new value
             * @param {boolean} validate validate after update
             */
            updateAccountSetting: function updateAccountSetting(account, key, value, validate) {
                if (!validate && key === "copy_proxy_option") {
                    account.proxyOption.value = value;
                }
                account[key] = value;
                this.accountSettingUpdated(account, validate);
            },

            /**
             * Called when any account setting is updated. Optionally validates the account based on state.
             *
             * @param {object} account account that had the update occur
             * @param {boolean} validate when true, validateAccount() will be called
             */
            accountSettingUpdated: function accountSettingUpdated(account, validate, skipForceSelect) {
                var callUpdate;
                if (!skipForceSelect && !account.selected) {
                    account.selected = 1;
                    callUpdate = true;
                }
                this.updateCustomizedFlag(account);
                if (validate) {
                    this.validateAccount(account);
                }
                if (callUpdate) {
                    this.updateSelectedAccounts();
                }
            },

            /**
             * Set a function to call when the selected accounts change
             *
             * @param {function} func function to call when the selected accounts change
             */
            setUpdateSelectedAccountsFunction: function setUpdateSelectedAccountsFunction(func) {
                this._updateSelectedAccounts = func;
            },

            /**
             * Called when selected accounts change, if set by setUpdateSelectedAccountsFunction() a callback function will be called too
             *
             */
            updateSelectedAccounts: function updateSelectedAccounts() {
                if (this._updateSelectedAccounts) {
                    this._updateSelectedAccounts();
                }
            },

            /**
             * Called by the view when an accounts selection changes
             *
             * @param {object} account the account that changed. Unused by the function.
             */
            accountSelectionUpdated: function accountSelectionUpdated(account) {
                this.updateSelectedAccounts();
            },

            /**
             * Check if an account is eligible for the overwrite dropdown
             *
             * @param {object} account account to be checked
             * @returns {boolean} whether or not the account could ever need overwriting
             */
            canNeedOverwrite: function canNeedOverwrite(account) {
                var localUsers = this.PAGE.local.users;
                var localDomains = this.PAGE.local.domains;
                return localUsers[account.user] || localUsers[account.localuser] || (localDomains[account.domain] === account.localuser);
            },

            /**
             * Update the specific overwrite flags based on the overwrite_type of the account
             * accountSettingUpdate is then called, passing along the validate value
             *
             * @param {object} account account to be updated
             * @param {boolean} validate whether to validate during the accountSettingUpdated phase
             */
            updateOverwriteFlags: function updateOverwriteFlags(account, validate, skipForceSelect) {
                account.overwrite_account = 0;
                account.overwrite_with_delete = 0;
                switch (account.overwrite_type.value) {
                    case this.overwriteStates.OVERWRITE_WITH_DELETE:
                        account.overwrite_with_delete = 1;

                    // fall through here is intentional as we want it to set overwrite_account as well when we set overwrite_with_delete
                    // eslint-disable-next-line no-fallthrough
                    case this.overwriteStates.OVERWRITE:
                        account.overwrite_account = 1;
                        break;
                }
                this.accountSettingUpdated(account, validate, skipForceSelect);
            },

            openOverwriteDescriptionModal: function openOverwriteDescriptionModal() {
                var self = this;
                self.overwriteModal = this.openModal({
                    templateUrl: this.overwriteDescriptionTemplate,
                    controller: ["$scope", function($scope) {
                        $scope.close = function() {
                            self.closeOverwriteDescriptionModal();
                        };
                    }]
                });
            },

            closeOverwriteDescriptionModal: function closeOverwriteDescriptionModal() {
                if (this.overwriteModal) {
                    this.overwriteModal.close();
                    this.overwriteModal = null;
                }
            }

        });

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
            app.value("PAGE", PAGE);
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        AccountTableController.$inject = CONTROLLER_INJECTABLES;
        var controller = app.controller("AccountTableController", AccountTableController);

        return controller;

    }
);

/*
# templates/transfer_tool/directives/boolToIntDirective.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/directives/boolToIntDirective',[
        "angular"
    ],
    function(angular) {

        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        // Main - reusable
        /**
         * Angular directive that when attached to an element with an ng-model will render that model as true or false
         * but ensure that any changing will result in 1 or 0 values.  Necessary because Perl cannot evaluate JavaScript
         * true/false when submitted in JSON.
         */
        app.directive("boolToInt", [

            function() {
                return {
                    restrict: "A",
                    require: "ngModel",
                    priority: 99,
                    link: function(scope, elem, attrs, controller) {
                        controller.$formatters.push(function(modelValue) {
                            return !!modelValue;
                        });

                        controller.$parsers.push(function(viewValue) {
                            return viewValue ? 1 : 0;
                        });
                    }
                };
            }
        ]);
    }
);

/*
# templates/transfer_tool/directives/preventBubblingDirective.js    Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/directives/ngDebounceDirective',[
        "angular"
    ],
    function(angular) {

        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        // Main - reusable
        // https://gist.github.com/tommaitland/7579618
        /**
         * Angular directive that prevents input from being processed.  Useful when paired with an input filter or ajax request
         * to prevent rapid calling of underlining functionality.
         */
        app.directive("ngDebounce", ["$timeout",
            function($timeout) {
                return {
                    restrict: "A",
                    require: "ngModel",
                    priority: 99,
                    link: function(scope, elm, attr, ngModelCtrl) {
                        if (attr.type === "radio" || attr.type === "checkbox") {
                            return;
                        }

                        elm.unbind("input");

                        var debounce;

                        elm.bind("input", function() {
                            $timeout.cancel(debounce);
                            debounce = $timeout(function() {
                                scope.$apply(function() {
                                    ngModelCtrl.$setViewValue(elm.val());
                                });
                            }, 250);
                        });

                        elm.bind("blur", function() {

                            // http://stackoverflow.com/questions/12729122/prevent-error-digest-already-in-progress-when-calling-scope-apply
                            $timeout(function() {
                                scope.$apply(function() {
                                    ngModelCtrl.$setViewValue(elm.val());
                                });
                            });
                        });
                    }
                };
            }
        ]);
    }
);

/*
# templates/transfer_tool/directives/preventBubblingDirective.js    Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/directives/preventBubblingDirective',[
        "angular"
    ],
    function(angular) {

        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        // Main - reusable
        /**
         * Angular directive which prevents event propogation.  Used in a Bootstrap dropdown menu with a form to prevent
         * accidental closure when interacting with the fields.
         */
        app.directive("preventBubbling", [

            function() {
                return {
                    restrict: "A",
                    link: function(scope, element) {
                        element.bind("click", function(event) {
                            event.preventDefault();
                            event.stopPropagation();
                        });
                    }
                };
            }
        ]);
    }
);

/*
# templates/transfer_tool/directives/clickOnceDirective.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/directives/clickOnceDirective',[
        "angular"
    ],
    function(angular) {

        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        // Main - reusable
        /**
         * Angular directive which disables a button on form submit.
         * Original work found here: http://stackoverflow.com/a/19825570
         */
        app.directive("clickOnce", ["$timeout",
            function($timeout) {
                return {
                    restrict: "A",
                    link: function(scope, element, attrs) {
                        var replacementText = attrs.clickOnce;
                        element.bind("click", function() {
                            $timeout(function() {
                                if (replacementText) {
                                    element.html(replacementText);
                                }
                                element.attr("disabled", true);
                            }, 0);
                        });
                    }
                };
            }
        ]);
    }
);

/*
# templates/transfer_tool/filters/overwriteFilter.js                Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    'app/filters/overwriteFilter',[
        "angular"
    ],
    function(angular) {

        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        /**
         * Returns true for account that can be overwritten
         * @param  {object} item
         * @return {array}
         */
        app.filter("overwriteFilter", function() {
            var localUsers = PAGE.local.users;
            var localDomains = PAGE.local.domains;
            return function(accounts) {
                var filteredAccounts = [];
                angular.forEach(accounts, function(account) {
                    if (localUsers[account.user] ||
                        localUsers[account.localuser] ||
                        localDomains[account.domain] === account.localuser) {
                        filteredAccounts.push(account);
                    }
                });
                return filteredAccounts;
            };
        });
    }
);

/*
# templates/transfer_tool/filters/bytesFilter.js                    Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/filters/bytesFilter',[
        "angular"
    ],
    function(angular) {

        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        // Main - reusable
        /**
         * Angular filter which returns a string localized with LOCALE.format_bytes
         * @return {string}
         */
        app.filter("bytes", function() {
            return function(bytes) {
                return LOCALE.format_bytes(bytes);
            };
        });
    }
);

/*
# cpanel - templates/transfer_tool/getacctlist.js  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require:false, define:false, confirm:false, alert:false, PAGE, EVENT:true */

(function(window) {
    "use strict";

    var enterSessionIfNotPending = function() {
        CPANEL.api({
            "func": "get_transfer_session_state",
            "data": {
                "transfer_session_id": PAGE.transfer_session_id
            },
            "callback": {
                success: function(o) {
                    var response = o.cpanel_data;
                    var statename = response.state_name;

                    if (o.cpanel_error) {
                        alert(LOCALE.maketext("Failed to retrieve the session state: [_1]", o.cpanel_error));
                    } else if (statename) {
                        if (statename !== "PENDING") {
                            if (confirm(LOCALE.maketext("The session has already started and cannot accept additional inputs. Would you like to view the transfer session?"))) {
                                window.location.href = "transfer_session?transfer_session_id=" + encodeURIComponent(PAGE.transfer_session_id);
                            } else {
                                window.history.go(-1);

                                /* Don't let them enter data on the screen as it will screen as it will just fail on the next screen since it the transfer sessions is already in progress */
                            }
                        }
                    }
                },
                failure: function() {
                    alert(LOCALE.maketext("Failed to retrieve the session state."));
                }
            }
        });
    };

    var reAnalyzeRemote = function() {
        var reAnalyzeRemoteButton = CPANEL.Y.one("#reAnalyzeRemoteButton"),
            preChangeText = reAnalyzeRemoteButton.innerHTML;

        reAnalyzeRemoteButton.disabled = true;
        reAnalyzeRemoteButton.innerHTML = "<i class='glyphicon glyphicon-refresh animate-spin'></i> " + LOCALE.maketext("Performing Analysis …");

        CPANEL.api({
            func: "analyze_transfer_session_remote",
            data: {
                "transfer_session_id": PAGE.transfer_session_id
            },
            callback: CPANEL.ajax.build_page_callback(function() {
                window.location.href = "transfer_selection?transfer_session_id=" + encodeURIComponent(PAGE.transfer_session_id);
            }, {
                pagenotice_container: "callback_block",
                on_error: function() {
                    reAnalyzeRemoteButton.disabled = false;
                    reAnalyzeRemoteButton.innerHTML = preChangeText;
                }
            })
        });
    };

    var init = function() {
        EVENT.on(CPANEL.Y.one("#reAnalyzeRemoteButton"), "click", reAnalyzeRemote);
        enterSessionIfNotPending();

        // Parse Blocker Data for Easy Apache
        if (PAGE.configuration_modules.Apache.analysis) {
            PAGE.EABlockers = PAGE.configuration_modules.Apache.analysis["Blocker Data"];

            // Loop through each item, look for Blocker level item
            for (var i = PAGE.EABlockers.length - 1; i >= 0; i--) {
                if (PAGE.EABlockers[i].vendor_id === "Cpanel" && PAGE.EABlockers[i].items) {
                    for (var j = PAGE.EABlockers[i].items.length - 1; j >= 0; j--) {
                        if (PAGE.EABlockers[i].items[j].status === 2) {
                            PAGE.blockerExists = true;
                        }
                    }
                }
            }
        }
    };

    EVENT.onDOMReady(init);


})(window);

/* angular portion */

define(
    'app/getacctlist',[
        "angular",
        "app/directives/accountExpandPanel",
        "cjt/util/locale",
        "app/overwriteStates",
        "app/overwriteOptions",
        "jquery",
        "ngRoute",
        "uiBootstrap",
        "angular-chosen",
        "ngSanitize",
        "cjt/modules",
        "cjt/directives/toggleLabelInfoDirective",
    ],
    function(angular, AccountExpandPanel, LOCALE, OVERWRITE_STATES, OVERWRITE_OPTIONS) {
        "use strict";

        return function() {
            var app = angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "cjt2.whm",
                "ngSanitize",
                "ui.bootstrap",
                AccountExpandPanel.namespace
            ]);

            app.value("OVERWRITE_DESCRIPTION_TEMPLATE", "overwriteWithDeleteDescription.ptt");
            app.value("OVERWRITE_STATES", OVERWRITE_STATES);
            app.value("OVERWRITE_OPTIONS", OVERWRITE_OPTIONS);

            app.value("LOCAL_WORKER_NODES", PAGE.local.linked_nodes);
            app.value("REMOTE_WORKER_NODES", PAGE.remote.linked_nodes);

            return require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/controllers/MainController",
                    "app/controllers/AccountTableController",
                    "app/directives/boolToIntDirective",
                    "app/directives/ngDebounceDirective",
                    "app/directives/preventBubblingDirective",
                    "cjt/directives/pageSizeDirective",
                    "app/directives/clickOnceDirective",
                    "app/filters/overwriteFilter",
                    "app/filters/bytesFilter"
                ], function(BOOTSTRAP) {

                    BOOTSTRAP(document);
                });
        };
    }
);

