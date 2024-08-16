/*
 * services/setupService.js                           Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* eslint-env amd */

define('app/services/setupService',[
    "angular",
    "cjt/io/whm-v1-request",
    "cjt/io/whm-v1",
    "cjt/services/APIService",
    "cjt/services/whm/nvDataService",
], function(
    angular,
    WHMAPI1_REQUEST
) {

    "use strict";

    var module = angular.module("whm.initialSetup.setupService", [
        "cjt2.services.api",
        "cjt2.services.whm.nvdata"
    ]);

    module.factory("setupService", [
        "$q",
        "APIService",
        "nvDataService",
        function(
            $q,
            APIService,
            nvDataService
        ) {

            var NO_MODULE = "";

            var SetupService = function() {
                this.apiService = new APIService();
            };

            angular.extend(SetupService.prototype, {

                /**
                 * Stores if the box is eligible for trial
                 */
                isEligibleForTrial: false,

                /**
                 * Records the root user's acceptance of the current legal agreements.
                 *
                 * @method recordAcceptance
                 * @return {Promise}   When resolved, the server has successfully recorded the user's acceptance.
                 */
                recordAcceptance: function() {

                    var apiCall = new WHMAPI1_REQUEST.Class();
                    apiCall.initialize(NO_MODULE, "accept_eula");

                    return this.apiService.deferred(apiCall).promise;
                },

                /**
                 * Sets the contact email and default nameservers in wwwacct.conf
                 *
                 * @param {Object} args   An object containing values for the contact email and/or default nameservers.
                 * @param {String} [args.email]         The contact email for root.
                 * @param {String} [args.nameservers]   An array, containing the hostnames of the nameservers. Currently,
                 *                                      only the first two values in the array are used.
                 */


                /**
                 * Sets the contact_email in /etc/wwwacct.conf
                 *
                 * @param {String} email   The contact email for root.
                 * @return {Promise}       Resolves once the API call is complete.
                 */
                setEmail: function(email) {
                    if (!angular.isString(email)) {
                        throw new TypeError("Developer Error: Them email argument must be a string");
                    }

                    var apiCall = new WHMAPI1_REQUEST.Class();
                    apiCall.initialize(NO_MODULE, "update_contact_email");
                    apiCall.addArgument("contact_email", email);

                    return this.apiService.deferred(apiCall).promise;
                },

                /**
                 * Sets nameservers 1 and 2 in /etc/wwwacct.conf. This method
                 * does not currently support nameservers 3 and 4.
                 *
                 * @param  {String[]} nameservers   An array of nameserver hostnames.
                 * @return {Promise}                Resolves once the API call is complete.
                 */
                setNameservers: function(nameservers) {
                    if (!angular.isArray(nameservers)) {
                        throw new TypeError("Developer Error: The nameservers argument must be an array");
                    }

                    var apiCall = new WHMAPI1_REQUEST.Class();
                    apiCall.initialize(NO_MODULE, "update_nameservers_config");

                    [
                        "nameserver",
                        "nameserver2",
                    ].forEach(function(apiKey, index) {
                        apiCall.addArgument(apiKey, nameservers[index]);
                    });

                    return this.apiService.deferred(apiCall).promise;
                },

                /**
                 * Creates NVData entries for API failures that take place during
                 * the setup process so we can create additional notices inside
                 * the product to draw users' attention.
                 *
                 * @param  {String[]} errorKeys    An array of error keys to base the NVData names on.
                 * @return {Promise}               Resolves once the API call is complete.
                 */
                saveErrors: function(errorKeys) {
                    if (!angular.isArray(errorKeys)) {
                        throw new TypeError("Developer Error: The errorKeys argument must be an array");
                    }

                    if (!errorKeys.length) {
                        return $q.resolve();
                    }

                    var nvData = {};
                    errorKeys.forEach(function(key) {
                        key = "isa:" + key + "_save_error";
                        nvData[key] = 1;
                    });

                    return nvDataService.setObject(nvData);
                },

                /**
                 * Checks whether an initial website was requested.
                 *
                 * @return {Promise}     Resolves once the API call is complete.
                 */
                initialWebsiteRequested: function() {
                    var apiCall = new WHMAPI1_REQUEST.Class();
                    apiCall.initialize(NO_MODULE, "initialwebsite_requested");

                    return this.apiService.deferred(apiCall).promise;
                },

                /**
                 * Creates the initial website if specified in a config file.
                 *
                 * @return {Promise}     Resolves once the API call is complete.
                 */
                initialWebsite: function() {
                    var apiCall = new WHMAPI1_REQUEST.Class();
                    apiCall.initialize(NO_MODULE, "initialwebsite_create");

                    return this.apiService.deferred(apiCall).promise;
                },

            });

            return new SetupService();
        }
    ]);
});

/*
 * views/infoController.js                            Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* eslint-env amd */

define('app/views/infoController',[
    "angular",
    "cjt/util/locale",
    "ngSanitize",
    "cjt/directives/validationContainerDirective",
    "cjt/directives/validationItemDirective",
    "cjt/validator/domain-validators",
    "cjt/validator/email-validator",
    "app/services/setupService",
], function(angular, LOCALE) {

    "use strict";

    function InfoController(PAGE, $location, setupService, $scope, $window, $q) {
        this.PAGE = PAGE;
        this.$location = $location;
        this.setupService = setupService;
        this.$scope = $scope;
        this.$window = $window;
        this.$q = $q;

        if (!PAGE.has_accepted_legal_agreements) {
            $location.path("/legal");
        }

        if (PAGE.has_completed_initial_setup || PAGE.is_dnsonly) {
            this.exit();
        }

        // Create copies of the initial data, for later comparisons
        this.email = PAGE.email;
        this.nameservers = PAGE.nameservers && PAGE.nameservers.slice() || [];
        this.finishButtonText = LOCALE.maketext("Finish");

        if (!PAGE.has_license && !this.setupService.isEligibleForTrial) {
            this.finishButtonText = LOCALE.maketext("Next");
        }
    }

    InfoController.$inject = [
        "PAGE",
        "$location",
        "setupService",
        "$scope",
        "$window",
        "$q",
    ];

    /**
     * Sets the provided values via the API and pushes forward to the next step.
     * @method submit
     */
    InfoController.prototype.submit = function() {
        var self = this;

        if (self.isSubmitting) {
            return;
        }

        if (self.$scope.infoForm.$invalid) {
            _validateControls(self.$scope.infoForm); // Recursively run $validate() on all ngModelControllers
            return;
        }

        self.isSubmitting = true;

        // Check whether or not anything has changed from the initial values to see if we should make an API call
        var emailHasChanged = _normalizeFalsyVals(self.PAGE.email) !== _normalizeFalsyVals(self.email);
        var nameserversHaveChanged = self.nameservers.some(function(nameserver, index) {
            return _normalizeFalsyVals(nameserver) !== _normalizeFalsyVals(self.PAGE.nameservers[index]);
        });

        // If nothing has changed, we can exit early
        if (!emailHasChanged && !nameserversHaveChanged) {
            self.exit();
            return;
        }

        // Otherwise, we need to wait on the API calls
        var promise = self.$q.resolve();
        var errorKeys = [];

        if ( emailHasChanged ) {
            promise = promise.then(function() {
                return self.setupService.setEmail(self.email);
            }).catch(function(error) {
                errorKeys.push("contact_email");
            });
        }

        if ( nameserversHaveChanged ) {
            promise = promise.then(function() {
                return self.setupService.setNameservers(self.nameservers);
            }).catch(function(error) {
                errorKeys.push("nameservers");
            });
        }

        promise.then(function() {
            if (errorKeys.length) {
                return self.setupService.saveErrors(errorKeys);
            }
        }).finally(function() {
            self.exit();
        });
    };

    /**
     * Runs $validate() on any NgModelController instances found. If the controller
     * passed in is an instance of FormController, then this function will process
     * the entire tree of FormController instances.
     *
     * @param  {Controller} controller   The FormController or NgModelController to process.
     */
    function _validateControls(controller) {
        if (controller.$validate) {
            controller.$setDirty();
            controller.$validate();
        } else {

            // Hack until we update AngularJS and get FormController.getControls()
            Object.keys(controller).forEach(function(key) {

                // Skip built-in keys
                if (key[0] === "$") {
                    return;
                }

                _validateControls( controller[key] );
            });
        }
    }

    /**
     * Sets the given nameserver index back to its initial value.
     *
     * @param  {Number} index   The index in this.nameservers/PAGE.nameservers
     */
    InfoController.prototype.resetNsInput = function(index) {
        this.nameservers[index] = this.PAGE.nameservers[index];
    };

    /**
     * Gives the text for the reset button title.
     *
     * @param  {Number} index   The index in this.nameservers
     * @return {String}         The title text.
     */
    InfoController.prototype.resetTitleText = function(index) {
        return LOCALE.maketext("Reset to the original value: [_1]", this.PAGE.nameservers[index]);
    };

    /**
     * Determines whether or not a reset button should be disabled.
     * @param  {Number} index   The index in this.nameservers
     * @return {Boolean}        True if it should be disabled. False otherwise
     */
    InfoController.prototype.shouldDisableReset = function(index) {
        return _normalizeFalsyVals( this.PAGE.nameservers[index] ) === _normalizeFalsyVals( this.nameservers[index] );
    };

    function _normalizeFalsyVals(str) {
        return !str ? "" : str;
    }

    /**
     * Exits the initial setup assistant and drops them to the next step.
     * @method exit
     */
    InfoController.prototype.exit = function() {
        if (this.PAGE.requested_initial_website) {
            this.$location.path("/initial-website");
        } else {
            this.$window.location.href = "../initial_setup_wizard1_do";
        }
    };

    angular
        .module("whm.initialSetup.infoController", [
            "ngSanitize",
            "cjt2.validate",
            "cjt2.directives.validationContainer",
            "cjt2.directives.validationItem",
            "whm.initialSetup.setupService",
        ])
        .controller("infoController", InfoController);

    return InfoController;

});

/*
# license_purchase/services/storeService.js        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
define(
    'shared/js/license_purchase/services/storeService',[
        "angular",
        "lodash",

        // CJT
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",

        // Angular components
        "cjt/services/APIService"
    ],
    function(
        angular,
        _,
        LOCALE,
        PARSE,
        API,
        APIREQUEST
    ) {

        "use strict";

        // Constants
        var NO_MODULE = "";
        var USE_JSON = { json: true };

        var module = angular.module("whm.storeService", [
            "cjt2.services.api"
        ]);

        function storeServiceFactory($q, APIService) {

            // Set up the service's constructor and parent
            var StoreService = function() {
                this.accessToken = "";
            };
            StoreService.prototype = new APIService();

            var isEligibleForTrialPromise;

            // Extend the prototype with any class-specific functionality
            angular.extend(StoreService.prototype, {

                /**
                 * Checks to see whether the current server is eligible for a trial license.
                 *
                 * @param {Object} args - Object containing options
                 * @param {Boolean} args.noCache - By default, this method will return a promise from any previous
                 *                                 requests. Pass true to this argument to fetch a new response.
                 * @returns {Promise<Boolean>} - When resolved, it will contain a boolean response as to whether
                 *                               the current server is eligible for trial or not.
                 */
                isEligibleForTrial: function(args) {
                    args = args || {};

                    if (isEligibleForTrialPromise && !args.noCache) {
                        return isEligibleForTrialPromise;
                    } else {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize(NO_MODULE, "is_eligible_for_trial");

                        isEligibleForTrialPromise = this.deferred(apiCall).promise
                            .then(function(response) {
                                if (!response || !response.data || !response.data.hasOwnProperty("is_eligible")) {
                                    return $q.reject(
                                        LOCALE.maketext("The system failed to parse the response from the API: [_1]", "is_eligible_for_trial")
                                    );
                                }

                                return PARSE.parsePerlBoolean( response.data.is_eligible );
                            });

                        return isEligibleForTrialPromise;
                    }
                },

                /**
                 * Returns the cPanel store login link
                 * @method getLoginURL
                 * @param  {String} url The url to redirect the user to after successful store login
                 * @return {Promise} Promise that will fulfill the request.
                 */
                getLoginURL: function(url) {
                    var self = this;
                    return this._getLoginURL(url).catch(function(error) {

                        // There's no point in saving an error response. Let it retry every time
                        self._getLoginURL.cache.delete(url);
                        return $q.reject(error);
                    });
                },

                _getLoginURL: _.memoize(function(url) {

                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "get_login_url");
                    apiCall.addArgument("provider", "cPStore");
                    apiCall.addArgument("url_after_login", url);

                    var deferred = this.deferred(apiCall);

                    // pass the promise back to the controller
                    return deferred.promise;
                }),

                /**
                 * Validates if the returned token from the store is valid
                 * @method validateLoginToken
                 * @param {String} url The url to redirect the user to after successful store login
                 * @param {String} token The token returned from cPStore
                 * @return {Promise} Promise that will fulfill the request.
                 */
                validateLoginToken: function(token, url) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "validate_login_token");
                    apiCall.addArgument("provider", "cPStore");
                    apiCall.addArgument("url_after_login", url);
                    apiCall.addArgument("login_token", token);

                    var deferred = this.deferred(apiCall);

                    return deferred.promise;
                },

                /**
                 * Takes an authorization code and the redirect URI from the original authorization
                 * request and requests an access token from the cPStore.
                 *
                 * @async
                 * @param {string} authCode - The authorization code returned from the cPStore.
                 * @param {string} redirectUri - The URI provided to the original authorization request.
                 * @returns {Promise<string>} - Resolves with the access token.
                 * @throws {Promise<string>} - Rejects with an error message if the API indicates success but is missing the access token.
                 * @throws {Promise<string>} - Rejects with an error message from the API if there is an error.
                 */
                getAccessToken: function(authCode, redirectUri) {
                    return this.validateLoginToken(authCode, redirectUri).then(function(result) {
                        var accessToken = result && result.data && result.data[0] && result.data[0].access_token;
                        if (accessToken) {
                            return accessToken;
                        } else {
                            return $q.reject("The system failed to authenticate. Please try again");
                        }
                    });
                },

                /**
                 * Generated the order to purchase license
                 * @method generateLicenseOrder
                 * @param {String} token The token returned from cPStore
                 * @param {String} url The url to redirect the user to after checkout
                 * @return {Promise} Promise that will fulfill the request.
                 */
                generateLicenseOrder: function(token, url, isUpgrade) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "purchase_a_license");
                    apiCall.addArgument("provider", "cPStore");
                    apiCall.addArgument("login_token", token);
                    apiCall.addArgument("url_after_checkout", url);

                    if (isUpgrade) {
                        apiCall.addArgument("upgrade", "1");
                    }

                    var deferred = this.deferred(apiCall);

                    return deferred.promise;
                },

                /**
                 * Creates and completes an order for a new trial license for the server.
                 *
                 * @async
                 * @param {Object} args
                 * @param {string} args.token - An access token used to interface with the cPStore.
                 * @param {string} args.verificationCode - The verification code that will validate the user
                 *                                         for a trial license.
                 * @param {boolean} args.sendVerification - If true and the order is rejected due to missing
                 *                                          verification, a new verification code will be sent.
                 * @returns {Promise<*>} - When resolved, a new trial license has been secured.
                 */
                acquireTrialLicense: function(args) {
                    var apiArgs = {
                        provider: "cPStore",
                        login_token: args.token,
                        checkout_args: {},
                    };

                    if (args.sendVerification) {
                        apiArgs.checkout_args.send_verification = 1;
                    }
                    if (args.verificationCode) {
                        apiArgs.checkout_args.verification_code = args.verificationCode;
                    }

                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "purchase_a_trial", apiArgs, null, USE_JSON);

                    var deferred = this.deferred(apiCall, this._getTransformAPIFailureOverride());
                    return deferred.promise;
                },

                /**
                 * Thrown when an operation is taking place that expects the server not to be licensed, but it already is.
                 *
                 * @typedef {Object} ServerIsLicensedError
                 * @property {boolean} serverIsLicensed - True if the server is licensed.
                 */

                /**
                 * Thrown when there is additional type information available about an API error.
                 * @typedef {Object} TypedApiError
                 * @param {boolean} isVerificationFailure - True if the error is a result of the account not being verified.
                 * @param {string} type - The type of underlying error.
                 * @param {string} email - The associated email. Only populated for verification failures.
                 * @param {string} message - The API error string.
                 */

                /**
                 * Sends a verification code to the user.
                 *
                 * @async
                 * @param {string} token - An access token used to interface with the cPStore.
                 * @returns {Promise<string>} - Resolves with the email address that the verification code has been sent to.
                 * @throws {Promise<TypedApiError>} - Rejects with a typed error object when there is an error during checkout.
                 * @throws {Promise<string>} - Rejects with an error string when there is any other API error.
                 * @throws {Promise<ServerIsLicensedError>} - Rejects with an error object when the server is already licensed.
                 */
                sendVerificationCode: function(token) {
                    var self = this;
                    return this.acquireTrialLicense({
                        token: token,
                        sendVerification: true,
                    }).then(function() {

                        /**
                         * This means that the purchase actually went through. This should not usually happen unless
                         * the user is using multiple windows to complete the initial setup. We will throw to signal
                         * to the consumer that this unintentional purchase has occurred.
                         */
                        return $q.reject({
                            serverIsLicensed: true,
                        });
                    }).catch(function(error) {
                        if (error.type === self._verificationSentErrorCode) {

                            // A new code has been sent, so we won't rethrow the error
                            return error.email;
                        } else {

                            // We have some other failure, so rethrow
                            return $q.reject(error);
                        }
                    });
                },

                _verificationSentErrorCode: "X::EmailNotVerified::EmailSent",

                /**
                 * Calls the API to run cpkeyclt to check for a valid license
                 * @method updateLicense
                 * @return {Promise} Promise that will fulfill the request.
                 */
                updateLicense: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "run_cpkeyclt");

                    // force is undocumented by design to prevent users from locking out their system
                    apiCall.addArgument("force", "1");

                    var deferred = this.deferred(apiCall);

                    return deferred.promise;
                },

                /**
                 * Override for the default transformAPIFailure() handler in APIService so we
                 * can get the data object (that contains the error type information) as well.
                 */
                _getTransformAPIFailureOverride: function() {
                    var self = this;
                    return {

                        /**
                         * Transforms an API error into a typed error with additional information.
                         * @param {Object} resp - The API response object.
                         * @returns {TypedApiError}
                         */
                        transformAPIFailure: function(resp) {
                            if (!resp) {
                                return {};
                            }

                            var errorType = resp.data && resp.data.type;
                            return {
                                isVerificationFailure: errorType && self._isVerificationFailure(errorType),
                                type: errorType,
                                email: resp.data && resp.data.detail && resp.data.detail.data && resp.data.detail.data.email,
                                message: resp.error,
                            };
                        }
                    };
                },

                _verificationFailureRegex: /^X::EmailNotVerified/,
                _isVerificationFailure: function(errorType) {
                    return this._verificationFailureRegex.test(errorType);
                },
            });

            return new StoreService();
        }

        storeServiceFactory.$inject = ["$q", "APIService"];
        return module.factory("storeService", storeServiceFactory);
    });

/*
 * views/introController.js                           Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* eslint-env amd */

define('app/views/introController',[
    "angular",
    "cjt/util/locale",
    "ngSanitize",
    "cjt/directives/disableAnimations",
    "shared/js/license_purchase/services/storeService",
], function(angular, LOCALE) {

    "use strict";

    function IntroController(PAGE, $timeout, storeService) {
        this.PAGE = PAGE;
        this.$timeout = $timeout;

        this.isDone = false;

        $timeout(this.checkExpiration.bind(this));

        storeService.isEligibleForTrial();
    }

    IntroController.$inject = [
        "PAGE",
        "$timeout",
        "storeService"
    ];

    IntroController.prototype.checkExpiration = function() {
        var self = this;

        var msUntilExpiration = this.msUntilExpiration();
        self.isDone = msUntilExpiration < 0;

        if (!self.isDone) {

            // We need to wait some more
            self.$timeout(function() {
                self.isDone = true;
            }, msUntilExpiration);
        }
    };

    IntroController.prototype.msUntilExpiration = function() {
        var self = this;
        return self.PAGE.introEndTime - Date.now();
    };

    IntroController.prototype.skip = function() {
        this.isDone = true;
    };

    angular
        .module("whm.initialSetup.introController", [
            "ngSanitize",
            "cjt2.directives.disableAnimations",
            "whm.storeService"
        ])
        .controller("introController", IntroController);

    return IntroController;

});

/*
 * views/legalController.js                           Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* eslint-env amd */

define('app/views/legalController',[
    "angular",
    "cjt/util/locale",
    "ngSanitize",
    "cjt/directives/actionButtonDirective",
    "cjt/services/alertService",
    "app/services/setupService",
    "shared/js/license_purchase/services/storeService",
], function(angular, LOCALE) {

    "use strict";

    function LegalController(PAGE, $anchorScroll, $location, $timeout, setupService, storeService, alertService, $window) {

        this.PAGE = PAGE;
        this.agreements = PAGE.agreements;
        this.$anchorScroll = $anchorScroll;
        this.$location = $location;
        this.$timeout = $timeout;
        this.setupService = setupService;
        this.alertService = alertService;
        this.$window = $window;
        this.storeService = storeService;

        if (PAGE.has_accepted_legal_agreements) {
            this.continueToNextStep();
            return;
        }

        this.setTopButtonMargin();
    }

    LegalController.$inject = [
        "PAGE",
        "$anchorScroll",
        "$location",
        "$timeout",
        "setupService",
        "storeService",
        "alertService",
        "$window",
    ];

    /**
     * Adds left and right margin to the floating "top" button to make sure
     * that it accounts for the scrollbar width, if any. We use left and right
     * margin so that it works for both LTR and RTL cases.
     *
     * @method setTopButtonMargin
     */
    LegalController.prototype.setTopButtonMargin = function() {
        this.$timeout(function() {
            var panelElem = angular.element(".panel-body").get(0);
            var topElem = angular.element("#top-link").get(0);

            if (!panelElem || !topElem) {
                return;
            }

            var scrollbarWidth = panelElem.offsetWidth - panelElem.clientWidth;
            topElem.style.opacity = 1;
            if (scrollbarWidth) {
                topElem.style.marginLeft = scrollbarWidth + "px";
                topElem.style.marginRight = scrollbarWidth + "px";
            }
        }, 1500);
    };

    /**
     * Prints the legal agreements.
     */
    LegalController.prototype.print = function() {
        window.print();
    };

    /**
     * Scrolls to the specified id using the location hash
     *
     * @method scrollTo
     * @param {String} id   The id of the anchor to scroll the view to
     */
    LegalController.prototype.scrollTo = function(id) {
        this.$location.hash(id);
        this.$anchorScroll();
    };

    /**
     * Records the user's acceptance of all of the legal agreements.
     *
     * @method acceptAll
     * @return {Promise}   When resolved, the server has successfully recorded the acceptance.
     */
    LegalController.prototype.acceptAll = function() {
        var self = this;
        self.isAccepting = true;
        self.alertService.clear();

        return this.setupService.recordAcceptance().then(function() {
            self.PAGE.has_accepted_legal_agreements = true;
            self.continueToNextStep();
        }).catch(function(error) {
            self.alertService.add({
                type: "danger",
                id: "eula-api-error-alert",
                message: LOCALE.maketext("The system could not process your agreement: [_1]", error),
                replace: true
            });
        }).finally(function() {
            self.isAccepting = false;
        });
    };

    LegalController.prototype.continueToNextStep = function() {
        var self = this;

        // TODO: Start using "cjt/services/viewNavigationApi" instead of $location.path() to propagate debug mode

        if (self.PAGE.has_license) {
            if (self.PAGE.has_completed_initial_setup || self.PAGE.is_dnsonly !== 0) {
                self.$window.location.href = "../initial_setup_wizard1_do";
            } else {
                self.$location.path("/info");
            }
        } else {
            self.storeService.isEligibleForTrial().then(function(isEligible) {
                if (isEligible) {
                    self.setupService.isEligibleForTrial = true;
                    self.$location.path("/trial-activation/login");
                } else {
                    if (self.PAGE.has_completed_initial_setup || self.PAGE.is_dnsonly !== 0) {
                        self.$window.location.href = "../initial_setup_wizard1_do";
                    } else {
                        self.setupService.isEligibleForTrial = false;
                        self.$location.path("/info");
                    }
                }
            }, function error() {
                if (self.PAGE.has_completed_initial_setup || self.PAGE.is_dnsonly !== 0) {
                    self.$window.location.href = "../initial_setup_wizard1_do";
                } else {
                    self.setupService.isEligibleForTrial = false;
                    self.$location.path("/info");
                }
            });
        }
    };

    angular
        .module("whm.initialSetup.legalController", [
            "ngSanitize",
            "cjt2.directives.actionButton",
            "cjt2.services.alert",
            "whm.initialSetup.setupService",
            "whm.storeService"
        ])
        .controller("legalController", LegalController);

    return LegalController;

});

/*
 * views/createAccountController.js                 Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* eslint-env amd */

define('app/views/createAccountController',[
    "angular",
    "cjt/util/locale",
    "app/services/setupService",
], function(angular, LOCALE) {

    "use strict";

    function CreateAccountController(PAGE, $location, setupService, $scope, $window, $q) {
        this.PAGE = PAGE;
        this.$location = $location;
        this.setupService = setupService;
        this.$scope = $scope;
        this.$window = $window;
        this.$q = $q;

        if (!PAGE.has_accepted_legal_agreements) {
            $location.path("/legal");
        }

        if (PAGE.has_completed_initial_setup || PAGE.is_dnsonly || !PAGE.requested_initial_website) {
            this.exit();
        }
    }

    CreateAccountController.$inject = [
        "PAGE",
        "$location",
        "setupService",
        "$scope",
        "$window",
        "$q",
    ];

    /**
     * Creates the account via the API.
     * @method submit
     */
    CreateAccountController.prototype.create = function() {
        var self = this;

        if (self.isSubmitting) {
            return;
        }

        if (!self.PAGE.requested_initial_website) {
            self.exit();
            return;
        }

        self.isSubmitting = true;

        var errorKeys = [];

        return self.setupService.initialWebsite(self.email)
            .catch(function(error) {
                errorKeys.push("initial_website");
            })
            .then(function() {
                if (errorKeys.length) {
                    return self.setupService.saveErrors(errorKeys);
                }
            }).finally(function() {
                self.exit();
            });
    };

    /**
     * Exits the initial setup assistant and drops them to the next step.
     * @method exit
     */
    CreateAccountController.prototype.exit = function() {
        this.$window.location.href = "../initial_setup_wizard1_do";
    };

    CreateAccountController.prototype.requested = function() {
        return this.PAGE.requested_initial_website;
    };

    angular
        .module("whm.initialSetup.createAccountController", [
            "whm.initialSetup.setupService",
        ])
        .controller("createAccountController", CreateAccountController);

    return CreateAccountController;
});

/*
 * views/trialActivationController.js               Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* eslint-env amd */

define('app/views/trialLicenseActivationController',[
    "angular",
    "cjt/util/locale",
    "app/services/setupService",
    "shared/js/license_purchase/services/storeService",
    "cjt/services/alertService",
    "cjt/directives/actionButtonDirective",
    "cjt/directives/validationContainerDirective",
    "cjt/directives/validationItemDirective",
], function(angular, LOCALE) {

    "use strict";

    function trialActivationController(PAGE, $location, setupService, storeService, alertService, $scope, $window, $q, $timeout, $routeParams) {
        this.PAGE = PAGE;
        this.$location = $location;
        this.setupService = setupService;
        this.storeService = storeService;
        this.alertService = alertService;
        this.$scope = $scope;
        this.$window = $window;
        this.$q = $q;
        this.$timeout = $timeout;
        this.$routeParams = $routeParams;

        if (!PAGE.has_accepted_legal_agreements) {
            $location.path("/legal");
        }

        if (PAGE.has_license) {
            if (PAGE.has_completed_initial_setup || PAGE.is_dnsonly !== 0) {
                $window.location.href = "../initial_setup_wizard1_do";
            } else {
                $location.path("/info");
            }

            return;
        }

        var steps = ["login", "activation", "activation-status", "email-verification"];

        var currentStep = steps[0];

        if ($routeParams.nextStep &&
            steps.indexOf($routeParams.nextStep) !== -1) {
            currentStep = $routeParams.nextStep;
        }

        this.$scope.currentStep = currentStep;

        this.$scope.onActivationStatusView = this.$scope.currentStep === "activation-status";


        this.startTrialActivationProcess();

        // redirects to server setup page
        this.redirectToServerSetup = function() {
            $location.path("/info");
        };

        // Prefetch store URL if we haven't logged in yet.
        var queryArgs = $location.search();
        if (!queryArgs || !queryArgs.code) {
            this.prefetchLoginUrl();
        }
    }

    /**
    * Prefetches the login URL
    *
    * @method prefetchLoginUrl
    */
    trialActivationController.prototype.prefetchLoginUrl = function() {
        var returnUrl = this.getReturnURL("activation");
        this.storeService.getLoginURL(returnUrl);
    };

    /**
    * Generates return url thats passed to store
    *
    * @method getReturnURL
    * @param {string} step step key which is same as the route parameter.
    * @returns {string} return url that store will redirect to
    */
    trialActivationController.prototype.getReturnURL = function(step) {
        var self = this;
        var queryArgs = self.$location.search();

        var returnURL = self.PAGE.baseURL + self.PAGE.pageURL + "/trial-activation/" + step;
        if (queryArgs && queryArgs.debug) {
            returnURL += "?debug=1";
        }

        return returnURL;
    };

    /**
    * Redirect to the store login
    *
    * @method storeLoginRedirect
    * @returns {string} login url
    */
    trialActivationController.prototype.storeLoginRedirect = function() {
        var self = this;
        var returnURL = self.getReturnURL("activation");
        self.alertService.clear();

        return self.storeService.getLoginURL(returnURL).then(function(results) {
            if ( results.data && results.data.length ) {
                self.$window.location.href = results.data[0];
            }
        }, function(error) {
            self.alertService.add({
                type: "danger",
                id: "getLoginURL-api-error-alert",
                message: LOCALE.maketext("The system could not log in to the cPanel Store: [_1]", error),
                replace: true
            });
        });
    };

    /**
    * Switches routes and presentation and performs trial license activation
    *
    * @method startTrialActivationProcess
    */
    trialActivationController.prototype.startTrialActivationProcess = function() {

        var self = this;
        var authenticationCode = self.authenticationCode = self.$location.search().code;
        var nextStep = self.$routeParams.nextStep;

        self.activationInProgress = true;
        self.emailAddress = self.$routeParams.everythingelse;

        // Verify Login, Get Access Token and Generate Order
        if (authenticationCode && nextStep === "activation") {

            return _fetchAndStoreAccessToken(self).then(function(accessToken) {

                if (!accessToken) {

                    // _fetchAndStoreAccessToken() will already redirect them to /login on failure
                    return;
                }

                // Place the order and perform checkout
                return self.storeService.acquireTrialLicense({
                    token: accessToken,
                    sendVerification: true,
                }).then(
                    function() {
                        return self.storeService.updateLicense().then(
                            function(result) {
                                self.$location.path("/trial-activation/activation-status/");
                            },
                            function error(error) {
                                self.activationInProgress = false;
                                self.alertService.add({
                                    type: "danger",
                                    id: "updateLicense-api-error-alert",
                                    message: LOCALE.maketext("The system failed to update the license on your cPanel [output,amp] WHM server. [output,url,_1,Fix License File Errors]", "../../scripts10/license_error"),
                                    replace: true
                                });

                            }
                        );
                    }, function(error) {
                        self.activationInProgress = false;

                        if ( error.isVerificationFailure ) {
                            self.$location.path("/trial-activation/email-verification/" + error.email);
                        } else {
                            self.alertService.add({
                                type: "danger",
                                id: "purchase_a_trial-api-error-alert",
                                message: LOCALE.maketext("The system could not activate the trial license."),
                                replace: true
                            });
                        }
                    }
                );
            }, function(error) {
                self.activationInProgress = false;
                self.alertService.add({
                    type: "danger",
                    id: "validateLoginToken-api-error-alert",
                    message: LOCALE.maketext("The system failed to authenticate. Please try again"),
                    replace: true
                });

                self.$location.path("/trial-activation/login");
            });
        }

        // We need to get an access token
        if (nextStep !== "activation-status" && nextStep !== "email-verification") {
            self.$location.path("/trial-activation/login");
            return;
        }
    };

    trialActivationController.prototype.verifyEmail = function(form) {
        var self = this;

        if (form.$invalid) {
            return;
        }

        var verificationCode = self.verificationCode;
        var accessToken = self.storeService.accessToken;

        self.verificationInProgress = true;
        self.alertService.clear();

        // Place the order and perform checkout
        return self.storeService.acquireTrialLicense({
            token: accessToken,
            verificationCode: verificationCode,
        }).then(
            function() {
                return self.storeService.updateLicense().then(
                    function(result) {
                        self.alertService.clear();
                        self.$location.path("/trial-activation/activation-status/");
                    },
                    function error(error) {
                        self.activationInProgress = false;
                        self.alertService.add({
                            type: "danger",
                            id: "updateLicense-api-error-alert",
                            message: LOCALE.maketext("The system failed to update the license on your cPanel [output,amp] WHM server. [output,url,_1,Fix License File Errors]", "../../scripts10/license_error"),
                            replace: true
                        });

                    }
                );
            }, function(error) {
                self.activationInProgress = false;

                if ( error.isVerificationFailure ) {
                    self.alertService.add({
                        type: "danger",
                        id: "verify-email-api-error-alert",
                        message: LOCALE.maketext("The verification code was incorrect. Please try again."),
                        replace: true
                    });
                    return;
                }

                self.alertService.add({
                    type: "danger",
                    id: "purchase_a_trial-api-error-alert",
                    message: LOCALE.maketext("The system could not activate the trial license."),
                    replace: true
                });
            }
        ).finally(function() {
            self.verificationInProgress = false;
        });
    };

    trialActivationController.prototype.resendCode = function() {
        var self = this;
        var accessToken = self.storeService.accessToken;
        self.alertService.clear();

        return this.storeService.sendVerificationCode(accessToken).then(function(email) {
            self.alertService.add({
                type: "success",
                id: "resend-verification-api-success-alert",
                message: LOCALE.maketext("A new verification code has been sent to [_1].", email),
                replace: true
            });
        }).catch(function(error) {
            if (error.serverIsLicensed) {

                /**
                 * There service may determine that the server is already licensed, in which case we
                 * can send them to the success screen.
                 */
                self.$location.path("/trial-activation/activation-status/");
                self.activationInProgress = false;
                self.alertService.add({
                    type: "success",
                    id: "resend-verification-api-error-alert",
                    message: LOCALE.maketext("The system determined that your server is already licensed."),
                    replace: true
                });
                return;
            }

            self.alertService.add({
                type: "danger",
                id: "resend-verification-api-error-alert",
                message: LOCALE.maketext("The system failed to send a new verification code to [_1].", error.email),
                replace: true
            });
        });
    };

    /**
     * Fetches an access token for a controller instance and stores it to the storeService.
     * This method's promise return does not ever reject and relies on the resolved return
     * value instead.
     *
     * @private
     * @async
     * @param {Object} self - The controller instance. It must have an authenticationCode property
     *                        or the API call will fail.
     * @returns {Promise<string|undefined>} - The access token, if successful. Undefined, if not.
     */
    function _fetchAndStoreAccessToken(self) {
        var authenticationCode = self.authenticationCode;
        var returnUri = self.getReturnURL("activation");

        return self.storeService.getAccessToken(authenticationCode, returnUri).then(function(accessToken) {
            self.storeService.accessToken = accessToken;
            return accessToken;
        }).catch(function() {
            self.activationInProgress = false;
            self.alertService.add({
                type: "danger",
                id: "getAccessToken-api-error-alert",
                message: LOCALE.maketext("The system failed to authenticate. Please try again"),
                replace: true
            });

            self.$location.path("/trial-activation/login");

            return void 0;
        });
    }

    trialActivationController.$inject = [
        "PAGE",
        "$location",
        "setupService",
        "storeService",
        "alertService",
        "$scope",
        "$window",
        "$q",
        "$timeout",
        "$routeParams"
    ];


    angular
        .module("whm.initialSetup.trialActivationController", [
            "ngSanitize",
            "whm.initialSetup.setupService",
            "whm.storeService",
            "cjt2.services.alert"
        ])
        .controller("trialActivationController", trialActivationController);

    return trialActivationController;

});

/*
 * index.js                                           Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* eslint-env amd */

define(
    'app/index',[
        "angular",
        "cjt/modules",
        "ngRoute",
        "ngSanitize",

    ],
    function(angular, $) {

        "use strict";

        return function() {

            require(
                [
                    "cjt/bootstrap",
                    "cjt/directives/alertList",
                    "app/views/infoController",
                    "app/views/introController",
                    "app/views/legalController",
                    "app/views/createAccountController",
                    "app/views/trialLicenseActivationController"
                ], function(BOOTSTRAP) {

                    var app = angular.module("whm.initialSetup", [
                        "cjt2.config.whm.configProvider", // This needs to load before ngRoute
                        "ngRoute",
                        "cjt2.directives.alertList",
                        "whm.initialSetup.infoController",
                        "whm.initialSetup.introController",
                        "whm.initialSetup.legalController",
                        "whm.initialSetup.createAccountController",
                        "whm.initialSetup.trialActivationController"
                    ]);

                    app.config([
                        "$routeProvider",
                        function($routeProvider) {

                            $routeProvider.when("/legal", {
                                controller: "legalController",
                                controllerAs: "vm",
                                templateUrl: "gsw/initial_setup/views/legalView.ptt",
                            });

                            $routeProvider.when("/trial-activation/:nextStep?/:everythingelse?", {
                                controller: "trialActivationController",
                                controllerAs: "vm",
                                templateUrl: "gsw/initial_setup/views/trialLicenseActivationView.ptt",
                            });

                            $routeProvider.when("/info", {
                                controller: "infoController",
                                controllerAs: "vm",
                                templateUrl: "gsw/initial_setup/views/infoView.ptt",
                            });

                            $routeProvider.when("/initial-website", {
                                controller: "createAccountController",
                                controllerAs: "vm",
                                templateUrl: "gsw/initial_setup/views/createAccountView.ptt",
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/legal/"
                            });
                        }
                    ]);

                    app.value("PAGE", window.PAGE);

                    BOOTSTRAP("#content", "whm.initialSetup");

                });
        };
    }
);

