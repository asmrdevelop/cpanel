/*
# email_accounts/services/emailAccountsService.js                                     Copyright 2022 cPanel, L.L.C.
#                                                                                            All rights reserved.
# copyright@cpanel.net                                                                          http://cpanel.net
# This code is subject to the cPanel license.                                  Unauthorized copying is prohibited
*/

/* global define: false, PAGE: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/util/query",
        "cjt/io/uapi-request",
        "cjt/io/batch-request",
        "cjt/io/uapi",
        "cjt/io/api",
        "cjt/services/APIService",
        "cjt/services/alertService",
    ],
    function(angular, _, LOCALE, PARSE, QUERY, APIREQUEST, BATCH) {
        "use strict";

        var HTML_INFINITY = "&infin;";
        var DEFAULT_ACCOUNT_LOGIN = "Main Account";

        var app = angular.module("cpanel.emailAccounts.service", [
            "cjt2.services.api",
            "cjt2.services.alert",
        ]);
        app.value("PAGE", PAGE);

        /**
         * Service wrapper for email accounts
         *
         * @module domains
         *
         * @param  {Object} $q angular $q object
         * @param  {Object} APIService cjt2 api service
         * @param  {Object} $timeout
         * @param  {Object} PAGE window.PAGE object
         */
        app.factory("emailAccountsService", [
            "$q",
            "APIService",
            "alertService",
            "$timeout",
            "PAGE",
            function($q, APIService, alertService, $timeout, PAGE) {

                // This class provides conveniences that allow an
                // alert with an automatically-created ID to be removed
                // or replaced easily. It mandates that each alert be
                // NON-replace.
                function AlertObject(args) {
                    this._init(args);
                }

                _.assign(
                    AlertObject.prototype,
                    {
                        _init: function(args) {
                            if (args.replace) {
                                throw "bad replace";
                            }

                            var localArgs = _.assign( {}, args );
                            localArgs.replace = false;

                            alertService.add(localArgs);

                            var alerts = alertService.getAlerts( args.group );
                            var theAlert = alerts.slice(-1)[0];
                            var alertID = theAlert.id;

                            this.id = alertID;
                            this.group = args.group;
                        },

                        remove: function remove() {
                            alertService.removeById( this.id, this.group );
                        },
                    }
                );

                // --------------------------------------------------

                // Set the default success transform on the prototype
                var servicePrototype = new APIService({
                    transformAPISuccess: function(response) {
                        return response.data;
                    },
                });

                var EmailAccountsService = function() {};
                EmailAccountsService.prototype = servicePrototype;

                var emailStats;

                /**
                 * Helps with the classes on the quota progress bar
                 *
                 * @method quotaProgressType
                 * @param {number} displayPercentage
                 * @returns {string} class for the quota progress bar
                 */
                function quotaProgressType(displayPercentage) {
                    if (displayPercentage >= 80) {
                        return "danger";
                    } else if (displayPercentage >= 60) {
                        return "warning";
                    } else if (displayPercentage < 60) {
                        return "success";
                    } else {
                        return "success";
                    }
                }

                /**
                 * Restructures Email account
                 *
                 * @method decorateEmailObj
                 * @param {Object} obj Email account object returned from API
                 * @returns {Object} returns modified email account
                 */
                function decorateEmailObj(obj) {
                    obj.diskused = parseInt(obj.diskused, 10);
                    obj.humandiskused = LOCALE.format_bytes( obj._diskused );
                    obj.id = obj.email;

                    if (obj._diskquota === 0 || obj.diskquota === 0 || obj.diskquota === "unlimited") {
                        obj.diskquota = 0;
                        obj.humandiskquota = HTML_INFINITY;
                        obj.diskusedpercent = 0;
                        obj.quotaType = "unlimited";
                        obj.quota = "";
                        obj.displayProgressbar = false;
                    } else {
                        obj.diskquota = parseInt(obj._diskquota, 10) / 1024 / 1024;
                        obj.humandiskquota = LOCALE.format_bytes(obj._diskquota);
                        obj.diskusedpercent = ((obj._diskused / obj._diskquota) * 100).toFixed(2);
                        obj.quotaProgressType = quotaProgressType(obj.diskusedpercent);
                        obj.quotaType = "userdefined";
                        obj.quota = obj.diskquota;
                        obj.quotaUnit = "MB";
                        obj.displayProgressbar = true;
                    }

                    obj.humandiskusedpercent = LOCALE.numf(obj.diskusedpercent) + "%";
                    obj.suspended_login = PARSE.parsePerlBoolean(obj.suspended_login);
                    obj.suspended_incoming = PARSE.parsePerlBoolean(obj.suspended_incoming);
                    obj.suspended_outgoing = PARSE.parsePerlBoolean(obj.suspended_outgoing);
                    obj.hold_outgoing = PARSE.parsePerlBoolean(obj.hold_outgoing);
                    obj.has_suspended = PARSE.parsePerlBoolean(obj.has_suspended);

                    obj.isDefault = obj.login === DEFAULT_ACCOUNT_LOGIN;

                    var webmailQuery = QUERY.make_query_string( {
                        user: obj.email,
                        return_request_uri: location.pathname,
                    } );

                    obj.webmailLink = "../mail/webmailform.html?" + webmailQuery;

                    return obj;
                }

                function _isNonClobberableUser(user) {

                    // See https://go.cpanel.net/UserManager-list_users for what “special” means.
                    if (user.special) {
                        return true;
                    }

                    return _.values(user.services).some( function(s) {
                        return PARSE.parsePerlBoolean(s.enabled);
                    } );
                }

                angular.extend(EmailAccountsService.prototype, {

                    /**
                     * Gets local storage values
                     * @method getStoredValue
                     * @param  {string}  key
                     * @return {string} returns the stored value
                     */
                    getStoredValue: function(key) {
                        var storageValue = localStorage.getItem(key);
                        if ( storageValue && (0 === storageValue.indexOf(PAGE.securityToken + ":")) ) {
                            storageValue = storageValue.substr( 1 + PAGE.securityToken.length );
                        } else {
                            storageValue = "";
                        }
                        return storageValue;
                    },

                    /**
                     * dataWrapper
                     * @method _dataWrapper
                     * @return {Promise} Returns a promise
                     */
                    _dataWrapper: function(apiCall) {
                        return this.deferred(apiCall).promise;
                    },

                    /**
                     * Gets upgrade url
                     * @method getUpgradeUrl
                     * @return {string} Returns upgarde url
                     */
                    getUpgradeUrl: function() {
                        return PAGE.upgradeUrl;
                    },

                    /**
                     * Gets email resource usage
                     * @method getEmailStats
                     * @return {Promise} Returns a promise
                     */
                    getEmailStats: function() {
                        if (emailStats) {
                            return $q.resolve(emailStats);
                        }

                        var apiCall = new APIREQUEST.Class();

                        apiCall.initialize("ResourceUsage", "get_usages");
                        apiCall.addFilter("id", "contains", "email_accounts");

                        return this.deferred(apiCall).promise
                            .then(function(response) {
                                emailStats = {};
                                var stats;
                                if (response && response.length) {
                                    stats = response[0];
                                    emailStats.maximum = parseInt(stats.maximum, 10);
                                    emailStats.used = parseInt(stats.usage, 10);
                                    if (!isNaN(emailStats.maximum) && emailStats.maximum) {
                                        emailStats.available = emailStats.maximum - emailStats.used;
                                    } else {
                                        emailStats.available = -1;
                                    }

                                } else {
                                    return $q.reject();
                                }
                                return emailStats;
                            });

                    },

                    /**
                     * Gets domains
                     * @method getMailDomains
                     * @return {Promise} Returns a promise
                     */
                    getMailDomains: function() {
                        var apiCall = new APIREQUEST.Class();

                        apiCall.initialize("Email", "list_mail_domains");

                        return this.deferred(apiCall).promise
                            .then(function(response) {
                                var domains = _.map(response, _.property("domain"));
                                return domains;
                            });
                    },

                    // Promise resolves truthy if the User Manager user
                    // is either nonexistent or has no services.
                    _isClobberableUserPromise: function _isClobberableUserPromise(emailAddressStr) {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("UserManager", "list_users");
                        apiCall.addFilter("full_username", "eq", emailAddressStr);

                        return this._dataWrapper(apiCall).then( function(users) {
                            return !users.some(_isNonClobberableUser) && users[0];
                        } );
                    },

                    /**
                     * Creates email account
                     *
                     * XXX: getEmailStats() must be called first.
                     *
                     * @method createEmail
                     * @param {Object} accountDetails Email account details
                     * @return {Promise} Returns a promise
                     */
                    createEmail: function(accountDetails) {
                        if (!emailStats) {
                            throw "Call getEmailStats() first.";
                        }

                        var apiCall = new APIREQUEST.Class();

                        var apiArgs, apiOverrides;

                        if (!accountDetails.setPassword) {

                            apiArgs = {
                                "username": accountDetails.userName,
                                "domain": accountDetails.domain,
                                "alternate_email": accountDetails.recoveryEmail,
                                "send_invite": 1,
                                "services.email.enabled": 1,
                                "services.email.quota": accountDetails.quota,
                                "services.email.send_welcome_email": accountDetails.sendWelcomeEmail ? 1 : 0,
                            };

                            // need to email reset link
                            apiCall.initialize("UserManager", "create_user", apiArgs);

                            // If this API call fails we want to examine the
                            // full response to see if there’s a typed error.
                            apiOverrides = {
                                transformAPIFailure: Object,
                            };
                        } else {
                            apiArgs = {
                                email: accountDetails.userName,
                                domain: accountDetails.domain,
                                password: accountDetails.password,
                                quota: accountDetails.quota,
                                send_welcome_email: accountDetails.sendWelcomeEmail ? 1 : 0,
                            };
                            apiCall.initialize("Email", "add_pop", apiArgs);
                        }

                        var self = this;

                        var realFailureXformer = this.presetDefaultHandlers.transformAPIFailure;

                        var emailAddressStr = accountDetails.userName + "@" + accountDetails.domain;

                        var ALERTGROUP = "emailAccounts";

                        var alertObj = new AlertObject( {
                            group: ALERTGROUP,
                            type: "info",
                            message: LOCALE.maketext("Creating email account …"),
                        } );

                        var apiPromise = this.deferred(apiCall, apiOverrides).promise;

                        return apiPromise
                            .then(function(response) {
                                emailStats.used = emailStats.used + 1;

                                if (emailStats.available !== -1) {
                                    emailStats.available = emailStats.available - 1;
                                }

                                // Plus Addressing to be sent to the Inbox
                                if (accountDetails.autoCreateSubaddressFolders !== true) {
                                    var subAddressingAPI = new APIREQUEST.Class();
                                    subAddressingAPI.initialize("Email", "disable_mailbox_autocreate", {
                                        email: emailAddressStr,
                                    });
                                    return self.deferred(subAddressingAPI).promise.then(function() {
                                        return response;
                                    });
                                }

                                return response;
                            }).catch( function(createResp) {

                                // If the call failed, check for
                                // “AlreadyExists”, which means a User
                                // Manager entry already exists for that
                                // email address.
                                if (createResp.data && createResp.data.type === "AlreadyExists") {
                                    var isLeftover = !_isNonClobberableUser(createResp.data && createResp.data.detail.entry);

                                    if (isLeftover) {
                                        var clobberableAcct = createResp.data.detail;

                                        var phrases = [
                                            LOCALE.maketext("“[_1]” already exists in the [asis,User Manager].", _.escape(emailAddressStr) ),
                                            LOCALE.maketext("This account appears to be left over from a previous subaccount.", _.escape(emailAddressStr)),
                                            LOCALE.maketext("Deleting …"),
                                        ];

                                        new AlertObject( {
                                            group: ALERTGROUP,
                                            type: "info",
                                            message: phrases.join(" "),
                                        } );

                                        var deleteArgs = {
                                            username: accountDetails.userName,
                                            domain: accountDetails.domain,
                                        };

                                        // We confirmed that User Manager’s
                                        // conflicting user is a “leftover”,
                                        // so let’s delete that user.
                                        var apiCall = new APIREQUEST.Class();
                                        apiCall.initialize("UserManager", "delete_user", deleteArgs);
                                        return self._dataWrapper(apiCall).then( function() {
                                            var msgHtml;

                                            if (clobberableAcct.alternate_email) {
                                                msgHtml = LOCALE.maketext("The system deleted [asis,User Manager]’s old leftover “[_1]” account (alternate email address: [_2]).", _.escape(emailAddressStr), _.escape(clobberableAcct.alternate_email));
                                            } else {
                                                msgHtml = LOCALE.maketext("The system deleted [asis,User Manager]’s old leftover “[_1]” account.", _.escape(emailAddressStr));
                                            }

                                            alertService.add( {
                                                group: ALERTGROUP,
                                                type: "info",
                                                message: msgHtml,
                                                replace: false,
                                            } );

                                            // Now that we’ve deleted the
                                            // empty User Manager account,
                                            // retry the original creation.
                                            return self.createEmail(accountDetails);
                                        } );
                                    }
                                }

                                return $q.reject(typeof createResp === "string" ? createResp : realFailureXformer(createResp));
                            }).finally( function() {
                                alertObj.remove();
                            });
                    },

                    /**
                     * Gets default account usage
                     * @method getDefaultAccountUsage
                     * @return {Promise} Returns a promise
                     */
                    getDefaultAccountUsage: function() {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("Email", "get_main_account_disk_usage");
                        return this._dataWrapper(apiCall);
                    },

                    /**
                     * Gets whether or not the shared address book is enabled
                     * @method isSharedAddressBookEnabled
                     * @return {Promise} Returns a promise that resolves to a boolean indicating whether or not the shared AB is enabled
                     */
                    isSharedAddressBookEnabled: function() {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("DAV", "has_shared_global_addressbook");
                        return this._dataWrapper(apiCall);
                    },

                    /**
                     * Enables the shared address book
                     * @method enableSharedAddressBook
                     * @return {Promise} Returns a promise that resolves to a boolean indicating whether or not the shared AB is enabled
                     */
                    enableSharedAddressBook: function() {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("DAV", "enable_shared_global_addressbook");
                        return this._dataWrapper(apiCall);
                    },

                    /**
                     * Disables the shared address book
                     * @method disableSharedAddressBook
                     * @return {Promise} Returns a promise that resolves to a boolean indicating whether or not the shared AB is enabled
                     */
                    disableSharedAddressBook: function() {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("DAV", "disable_shared_global_addressbook");
                        return this._dataWrapper(apiCall);
                    },

                    /**
                     * Gets whether or not UTF-8 Mailboxes names are enabled.
                     * @method isUTF8MailboxNamesEnabled
                     * @return {Promise} Returns a promise that resolves to a boolean indicating whether or not the call was successful.
                     */
                    isUTF8MailboxNamesEnabled: function() {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("Mailboxes", "has_utf8_mailbox_names");
                        return this._dataWrapper(apiCall);
                    },

                    /**
                     * Enables UTF-8 mailbox support
                     * @method enableUTF8MailboxNames
                     * @return {Promise} Returns a promise that resolves to a boolean indicating whether or not the call was successful.
                     */
                    enableUTF8MailboxNames: function() {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("Mailboxes", "set_utf8_mailbox_names");
                        apiCall.addArgument("enabled", 1);
                        return this._dataWrapper(apiCall);
                    },

                    /**
                     * Disables UTF-8 mailbox support
                     * @method disableUTF8MailboxNames
                     * @return {Promise} Returns a promise that resolves to a boolean indicating whether or not the call was successful.
                     */
                    disableUTF8MailboxNames: function() {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("Mailboxes", "set_utf8_mailbox_names");
                        apiCall.addArgument("enabled", 0);
                        return this._dataWrapper(apiCall);
                    },

                    /**
                     * Gets email account details
                     * @method getEmailAccountDetails
                     * @param {string} email email account
                     * @return {Promise} Returns a promise
                     */
                    getEmailAccountDetails: function(email) {
                        if (email) {

                            var apiCall = new APIREQUEST.Class();
                            apiCall.initialize("Email", "list_pops_with_disk");

                            apiCall.addFilter("email", "eq", email);
                            apiCall.addArgument("no_human_readable_keys", 1);
                            apiCall.addArgument("get_restrictions", 1);

                            var autoCreateApiCall = new APIREQUEST.Class();
                            autoCreateApiCall.initialize("Email", "get_mailbox_autocreate", {
                                "email": email,
                            });
                            var batchApiCall = new BATCH.Class([apiCall, autoCreateApiCall]);

                            var self = this;
                            return self.deferred(batchApiCall).promise
                                .then(function(responses) {

                                    responses = responses.map(function(response) {
                                        return response.data;
                                    });

                                    // Extract auto create setting
                                    var detailsResponse = responses[0];
                                    detailsResponse[0].autoCreateSubaddressFolders = responses[1];
                                    return detailsResponse;
                                })
                                .then(function(response) {
                                    if (_.isArray(response) && response.length === 0) {
                                        return $q.reject(LOCALE.maketext("You do not have an email account named “[_1]”.", _.escape(email)));
                                    }
                                    return decorateEmailObj(response[0]);
                                }, function(error) {
                                    return error;
                                });
                        }
                    },

                    /**
                     * Determine if Plus Address Folder Generation is Enabled
                     * @method isPlusAddressFolderCreationEnabled
                     * @param {string} email email account
                     * @return {Promise} Returns a promise
                     */
                    isPlusAddressFolderCreationEnabled: function(email) {
                        if (email) {
                            var apiCall = new APIREQUEST.Class();
                            apiCall.initialize("Email", "get_mailbox_autocreate", {
                                "email": email,
                            });

                            return this.deferred(apiCall).promise.then(function(response) {
                                return response;
                            });
                        }
                    },

                    /**
                     * Disable Plus Address Folder Generation
                     * @method disablePlusAddressFolderCreation
                     * @param {string} email email account
                     * @return {Promise} Returns a promise
                     */
                    disablePlusAddressFolderCreation: function(email) {
                        return this._createAPICall(
                            "disable_mailbox_autocreate",
                            {
                                email: email,
                                fullEmail: email,
                            },
                            {
                                success: LOCALE.translatable("You disabled automatic folder creation for “[_1]”."),
                                error: LOCALE.translatable("The system could not disable automatic folder creation for “[_1]”."),
                            }
                        );
                    },

                    /**
                     * Enable Plus Address Folder Generation
                     * @method enablePlusAddressFolderCreation
                     * @param {string} email email account
                     * @return {Promise} Returns a promise
                     */
                    enablePlusAddressFolderCreation: function(email) {
                        return this._createAPICall(
                            "enable_mailbox_autocreate",
                            {
                                email: email,
                                fullEmail: email,
                            },
                            {
                                success: LOCALE.translatable("You enabled automatic folder creation for “[_1]”."),
                                error: LOCALE.translatable("The system could not enable automatic folder creation for “[_1]”."),
                            }
                        );
                    },

                    /**
                     * Delete email account
                     * @method deleteEmail
                     * @param {string} email email account
                     * @return {Promise} Returns a promise
                     */
                    deleteEmail: function(email) {
                        if (email) {
                            var apiCall = new APIREQUEST.Class();
                            apiCall.initialize("Email", "delete_pop", { email: email });
                            return this.deferred(apiCall).promise
                                .then(function(response) {
                                    emailStats.used = emailStats.used - 1;

                                    if (emailStats.available !== -1) {
                                        emailStats.available = emailStats.available + 1;
                                    }

                                    return response;
                                });
                        }
                    },

                    /**
                     * Delete multiple emails
                     * @method deleteEmails
                     * @param {string[]} emails email accounts
                     * @return {Promise} Returns a promise
                     */
                    deleteEmails: function(emails) {
                        if (emails && emails.length > 0) {
                            var batchCalls = [];
                            for (var i = 0, len = emails.length; i < len; i++) {
                                var apiCall = new APIREQUEST.Class();
                                apiCall.initialize("Email", "delete_pop", { email: emails[i].email });
                                batchCalls.push(apiCall);
                            }

                            var batch = new BATCH.Class(batchCalls);

                            return this.deferred(batch).promise
                                .then(function(response) {
                                    emailStats.used = emailStats.used - emails.length;

                                    if (emailStats.available !== -1) {
                                        emailStats.available = emailStats.available + emails.length;
                                    }

                                    return response;
                                });
                        }
                    },

                    _createAPICall: function(method, attributes, messages) {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("Email", method, attributes);
                        return this._dataWrapper(apiCall).then(
                            function() {
                                return messages.success ? { method: method, type: "success", message: LOCALE.makevar(messages.success, _.escape(attributes.fullEmail)), autoClose: 10000 } : { method: method, type: "success" };
                            },
                            function(error) {
                                return messages.error ? { method: method, type: "danger", message: LOCALE.makevar(messages.error, _.escape(attributes.fullEmail), error) } : { method: method, type: "danger" };
                            }
                        );
                    },

                    /**
                     * Gets the number of currently held messages in the mail queue for the specified email account
                     * @method getHeldMessageCount
                     * @param {Object} emailAccount The email account to get the held message count for
                     * @return {Promise} Returns a promise that resolves to an integer count of the number of held messages
                     */
                    getHeldMessageCount: function(email) {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("Email", "get_held_message_count", {
                            email: email,
                        });
                        return this._dataWrapper(apiCall);
                    },

                    /**
                     * Deletes any held messages in the mail queue for the specified email account
                     * @method deleteHeldMessages
                     * @param {Object} emailAccount The email account to delete the held messages for
                     * @return {Promise} Returns a promise that resolves to an integer count of the number of deleted messages
                     */
                    deleteHeldMessages: function(email, releaseAfterDelete) {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("Email", "delete_held_messages", {
                            email: email,
                            release_after_delete: (releaseAfterDelete) ? 1 : 0,
                        });
                        return this._dataWrapper(apiCall);
                    },

                    _handleSuspensions: function(newSettings, currentSuspendedState, suspendOptions) {
                        var calls = [];
                        if (suspendOptions.incoming !== currentSuspendedState.incoming) {
                            if (!suspendOptions.incoming) {
                                calls.push(this._createAPICall(
                                    "unsuspend_incoming",
                                    {
                                        email: newSettings.email,
                                        fullEmail: newSettings.email,
                                    },
                                    {
                                        success: LOCALE.translatable("You unsuspended incoming mail for “[_1]”."),
                                        error: LOCALE.translatable("We can’t unsuspend incoming mail for “[_1]”:“[_2]”"),
                                    }
                                ));
                            } else {
                                calls.push(this._createAPICall(
                                    "suspend_incoming",
                                    {
                                        email: newSettings.email,
                                        fullEmail: newSettings.email,
                                    },
                                    {
                                        success: LOCALE.translatable("You suspended incoming mail for “[_1]”."),
                                        error: LOCALE.translatable("We can’t suspend incoming mail for “[_1]”:“[_2]”"),
                                    }
                                ));
                            }
                        }

                        if (suspendOptions.login !== currentSuspendedState.login) {
                            if (!suspendOptions.login) {
                                calls.push(this._createAPICall(
                                    "unsuspend_login",
                                    {
                                        email: newSettings.email,
                                        fullEmail: newSettings.email,
                                    },
                                    {
                                        success: LOCALE.translatable("You unsuspended logins for “[_1]”."),
                                        error: LOCALE.translatable("We can’t unsuspend logins for “[_1]”:“[_2]”"),
                                    }
                                ));
                            } else {
                                calls.push(this._createAPICall(
                                    "suspend_login",
                                    {
                                        email: newSettings.email,
                                        fullEmail: newSettings.email,
                                    },
                                    {
                                        success: LOCALE.translatable("You suspended logins for “[_1]”."),
                                        error: LOCALE.translatable("We can’t suspend logins for “[_1]”:“[_2]”"),
                                    }
                                ));
                            }
                        }

                        if (suspendOptions.outgoing !== currentSuspendedState.outgoing) {
                            if (suspendOptions.outgoing === "hold") {
                                calls.push(this._createAPICall(
                                    "hold_outgoing",
                                    {
                                        email: newSettings.email,
                                        fullEmail: newSettings.email,
                                    },
                                    {
                                        success: LOCALE.translatable("We’re holding outgoing mail for “[_1]”."),
                                        error: LOCALE.translatable("We can’t hold mail for “[_1]”:“[_2]”"),
                                    }
                                ));
                            } else if (suspendOptions.outgoing === "suspend") {
                                calls.push(this._createAPICall(
                                    "suspend_outgoing",
                                    {
                                        email: newSettings.email,
                                        fullEmail: newSettings.email,
                                    },
                                    {
                                        success: LOCALE.translatable("You suspended outgoing mail for “[_1]”."),
                                        error: LOCALE.translatable("We can’t suspend outgoing mail for “[_1]”:“[_2]”"),
                                    }
                                ));
                            }

                            if (currentSuspendedState.outgoing === "suspend") {
                                calls.push(this._createAPICall(
                                    "unsuspend_outgoing",
                                    {
                                        email: newSettings.email,
                                        fullEmail: newSettings.email,
                                    },
                                    {
                                        success: LOCALE.translatable("You unsuspended outgoing mail for “[_1]”."),
                                        error: LOCALE.translatable("We can’t unsuspend outgoing mail for “[_1]”:“[_2]”"),
                                    }
                                ));
                            }

                            if (currentSuspendedState.outgoing === "hold") {
                                calls.push(this._createAPICall(
                                    "release_outgoing",
                                    {
                                        email: newSettings.email,
                                        fullEmail: newSettings.email,
                                    },
                                    {
                                        success: LOCALE.translatable("You unsuspended outgoing mail for “[_1]”."),
                                        error: LOCALE.translatable("We can’t unsuspend outgoing mail for “[_1]”:“[_2]”"),
                                    }
                                ));
                            }
                        }

                        return calls;
                    },

                    /**
                     * Updates email account details
                     * @method updateEmail
                     * @param {Object} oldSettings old email account values
                     * @param {Object} newSettings new email account values
                     * @param {Object} currentSuspendedState current suspended state
                     * @param {Object} suspendOptions suspend options
                     * @return {Promise} Returns a promise
                     */
                    updateEmail: function(oldSettings, newSettings, currentSuspendedState, suspendOptions) {
                        var calls = [];

                        if (oldSettings && newSettings) {

                            if (oldSettings.autoCreateSubaddressFolders !== newSettings.autoCreateSubaddressFolders) {
                                if (newSettings.autoCreateSubaddressFolders) {
                                    calls.push(this.enablePlusAddressFolderCreation(newSettings.email));
                                } else {
                                    calls.push(this.disablePlusAddressFolderCreation(newSettings.email));
                                }
                            }

                            if (typeof newSettings.password !== "undefined" && newSettings.password) {
                                calls.push(this._createAPICall(
                                    "passwd_pop",
                                    {
                                        email: newSettings.email,
                                        password: newSettings.password,
                                        domain: newSettings.domain,
                                        fullEmail: newSettings.email,
                                    },
                                    {
                                        success: LOCALE.translatable("You updated the password for “[_1]”."),
                                        error: LOCALE.translatable("We can’t update the password for “[_1]”:“[_2]”"),
                                    }
                                ));
                            }

                            if (Number(oldSettings.diskquota).toFixed(2) !== newSettings.quota.toFixed(2)) {
                                calls.push(this._createAPICall(
                                    "edit_pop_quota",
                                    {
                                        email: newSettings.user,
                                        domain: newSettings.domain,
                                        quota: newSettings.quota,
                                        fullEmail: newSettings.email,
                                    },
                                    {
                                        success: LOCALE.translatable("You updated the storage space for “[_1]”."),
                                        error: LOCALE.translatable("We can’t update the storage space for “[_1]”:“[_2]”"),
                                    }
                                ));
                            }

                            if (suspendOptions && currentSuspendedState) {

                                // Handle deletion of queued email before processing the account suspensions
                                if (suspendOptions.deleteHeldMessages) {
                                    var releaseAfterDelete = currentSuspendedState.outgoing === "hold" && suspendOptions.outgoing === "allow";
                                    var self = this;
                                    return this.deleteHeldMessages(newSettings.email, releaseAfterDelete).then(
                                        function(deletedCount) {
                                            if (releaseAfterDelete) {
                                                suspendOptions.outgoing = "hold";
                                            }
                                            var additionalCalls = self._handleSuspensions(newSettings, currentSuspendedState, suspendOptions);
                                            var allCalls = calls.concat(additionalCalls);
                                            if ( allCalls.length > 0 ) {
                                                return $q.all(allCalls);
                                            } else {
                                                return $timeout( function() {
                                                    return $q.resolve(
                                                        [{
                                                            type: "success",
                                                            method: "delete_held_messages",
                                                            message: LOCALE.maketext("[quant,_1,message has,messages have] been queued for deletion from the outgoing mail queue.", deletedCount),
                                                        }]
                                                    );
                                                }, 0);
                                            }

                                        },
                                        function(error) {
                                            return $timeout( function() {
                                                return $q.resolve(
                                                    [{ type: "danger", message: error }]
                                                );
                                            }, 0);
                                        }
                                    );

                                } else {
                                    var additionalCalls = this._handleSuspensions(newSettings, currentSuspendedState, suspendOptions);
                                    calls = calls.concat(additionalCalls);
                                }
                            }

                            if ( calls.length > 0 ) {
                                return $q.all(calls);
                            } else {
                                return $timeout( function() {
                                    return $q.resolve(
                                        [{ type: "success", message: LOCALE.maketext("Email account “[_1]” is up to date.", newSettings.email), autoClose: 10000 }]
                                    );
                                }, 0);
                            }

                        }
                    },

                    /**
                     * Gets the list of email accounts
                     * @method getEmailAccounts
                     * @param  {Object}  apiParams An object providing the UAPI filter, paginate, and sort properties
                     * @return {Promise}           Returns a promise that resolves to the list of email accounts
                     */
                    getEmailAccounts: function(apiParams) {

                        if ( this.currentGetRequest && this.currentGetRequest.jqXHR ) {
                            this.currentGetRequest.jqXHR.abort();
                        }

                        var apiCall = new APIREQUEST.Class();

                        // We always format the data on the frontend so avoid doing it on the backend for non-displayed data
                        if (!apiParams) {
                            apiParams = {};
                        }
                        apiParams.no_human_readable_keys = 1;
                        apiParams.get_restrictions = 1;
                        apiParams.include_main = 1;
                        apiCall.initialize("Email", "list_pops_with_disk", apiParams);

                        var deferred = $q.defer();
                        var service = this;

                        // We want to be able to access the underlying jQuery XHR object here so that we can
                        // .abort() any in flight calls to list_pops_with_disk when a new one is submitted.
                        this.currentGetRequest = new APIService.AngularAPICall(apiCall, {
                            done: function(response) {

                                service.currentGetRequest = undefined;

                                if ( response.parsedResponse.error ) {
                                    deferred.reject(response.parsedResponse.error);
                                } else {

                                    var result = response.parsedResponse;

                                    var rdata = result.data;
                                    var rdatalen = rdata.length;
                                    for (var rd = 0; rd < rdatalen; rd++) {
                                        decorateEmailObj(rdata[rd]);
                                    }

                                    deferred.resolve(result);
                                }

                            },
                            fail: function() {
                                service.currentGetRequest = undefined;
                            },
                        });

                        return deferred.promise;
                    },

                });

                return new EmailAccountsService();
            },
        ]);
    }
);
