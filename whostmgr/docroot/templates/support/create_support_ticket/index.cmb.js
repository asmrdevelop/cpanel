/*
 * whostmgr/docroot/templates/support/create_support_ticket/service/wizardApi.js
 *                                                 Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    'app/services/wizardApi',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/services/viewNavigationApi"
    ],
    function(angular, _, LOCALE) {

        var app = angular.module("whm.createSupportTicket");

        app.factory("wizardApi", [
            "viewNavigationApi",
            "wizardState",
            function(viewNavigationApi, wizardState) {

                /**
                 * Get a suitable prefix for IDs associated with the wizard. This prefix is
                 * derived from the current view of the wizard. It basically just removes any
                 * leading or trailing forward slashes if they exist and converts any other
                 * forward slashes to dashes.
                 *
                 * @method  _getIdPrefix
                 * @private
                 * @return {String}   The ID prefix.
                 */
                function _getIdPrefix() {
                    var view = wizardState.view || "wizard";
                    return _.kebabCase(view);
                }

                return {

                    /**
                     * Configure the common wizard options. Generally this is called only once. To
                     * configure individual steps call wizardAPI.configureStep()
                     *
                     * @name  configureWizardStep
                     * @param {Object} [opts] Collection of customizations to the wizard process.
                     * @param {Function} [opts.resetFn]             Function to call when navigating to the first step
                     * @param {Function} [opts.nextFn]              Function to call when navigating to the next step
                     * @param {String}   [opts.nextButtonText]      Name to show on the next button.
                     * @param {String}   [opts.nextButtonTitle]     Title for the next button.
                     * @param {Function} [opts.previousFn]          Function to call when navigating to the previous step
                     * @param {String}   [opts.previousButtonText]  Name to show on the previous button.
                     * @param {String}   [opts.previousButtonTitle] Title for the previous button.
                     */
                    configure: function(opts) {
                        opts = opts || {};
                        wizardState.resetFn             = opts.resetFn || angular.noop;
                        wizardState.nextButtonTitle     = opts.nextButtonTitle || "";
                        wizardState.nextButtonText      = opts.nextButtonText || LOCALE.maketext("Next");
                        wizardState.nextFn              = opts.nextFn || angular.noop;
                        wizardState.previousButtonTitle = opts.nextButtonTitle || "";
                        wizardState.previousButtonText  = opts.previousButtonText || LOCALE.maketext("Previous");
                        wizardState.previousFn          = opts.previousFn || angular.noop;
                    },

                    /**
                     * Get the current step
                     *
                     * @return {Number} Current step number.
                     */
                    getStep: function() {
                        return wizardState.step;
                    },

                    /**
                     * Get the view the wizard thinks its on
                     * @return {String}
                     */
                    getView: function() {
                        return wizardState.view;
                    },

                    /**
                     * Reset the wizard to it initial state. It will forward any
                     * arguments passed into the call to the registered
                     * function.
                     *
                     * @name reset
                     */
                    reset: function() {
                        if (wizardState.resetFn.apply(wizardState, arguments) ||
                            wizardState.resetFn === angular.noop) {
                            wizardState.step = 1;
                        }
                    },

                    /**
                     * Navigate to the next step. It will forward any
                     * arguments passed into the call to the registered
                     * function.
                     *
                     * @name next
                     */
                    next: function() {
                        if (wizardState.nextFn.apply(wizardState, arguments) ||
                            wizardState.nextFn === angular.noop) {
                            wizardState.step++;
                        }

                        this.setButtonIds();

                        // Prevent overflow
                        if (wizardState.step > wizardState.maxSteps) {
                            wizardState.step = wizardState.maxSteps;
                        }
                    },

                    /**
                     * Navigate to the previous step. It will forward any
                     * arguments passed into the call to the registered
                     * function.
                     *
                     * @name previous
                     */
                    previous: function() {
                        if (wizardState.previousFn.apply(wizardState, arguments) ||
                            wizardState.previousFn === angular.noop) {
                            wizardState.step--;
                        }

                        this.setButtonIds();

                        // Prevent overflow
                        if (wizardState.step <= 0) {
                            wizardState.step = 1;
                        }
                    },

                    /**
                     * Hide the wizard control footer.
                     *
                     * @name  hideFooter
                     */
                    hideFooter: function() {
                        wizardState.footer = false;
                    },

                    /**
                     * Show the wizard control footer.
                     *
                     * @name  showFooter
                     */
                    showFooter: function() {
                        wizardState.footer = true;
                    },

                    /**
                     * Disable the Next button in the wizard. This may be used to stop the user from
                     * moving forward until they complete some task on the current step.
                     *
                     * @scope
                     * @name  disableNextButton
                     */
                    disableNextButton: function() {
                        wizardState.nextButtonDisabled = true;
                    },

                    /**
                     * Enable the Next button in the wizard.
                     *
                     * @scope
                     * @name  enableNextButton
                     */
                    enableNextButton: function() {
                        wizardState.nextButtonDisabled = false;
                    },

                    /**
                     * Sets IDs on the next and previous buttons based on the prefix that is passed in
                     * or the view name.
                     *
                     * @method setButtonIds
                     * @param {String} [prefix]   Optional prefix for the button IDs.
                     */
                    setButtonIds: function(prefix) {
                        prefix = prefix || _getIdPrefix();
                        wizardState.nextButtonId     = prefix + "-next-button";
                        wizardState.previousButtonId = prefix + "-previous-button";
                    },

                    /**
                     * Configure the current wizard step. During configuration the
                     * wizards next and previous action functions are registered along
                     * with other next/previous button configuration.
                     *
                     * @name  configureStep
                     * @param {Object} [opts] Collection of customizations to the wizard process.
                     * @param {Function} [opts.nextFn]              Function to call when navigating to the next step
                     * @param {String}   [opts.nextButtonText]      Name to show on the next button.
                     * @param {String}   [opts.nextButtonTitle]     Title for the next button.
                     * @param {Function} [opts.previousFn]          Function to call when navigating to the previous step
                     * @param {String}   [opts.previousButtonText]  Name to show on the previous button.
                     * @param {String}   [opts.previousButtonTitle] Title for the previous button.
                     * @return {Boolean} if true it initialized correctly. if false it reset the wizard.
                     */
                    configureStep: function(opts) {
                        opts = opts || {};

                        wizardState.nextButtonTitle     = opts.nextButtonTitle || "";
                        wizardState.nextButtonText      = opts.nextButtonText || LOCALE.maketext("Next");
                        wizardState.nextFn              = opts.nextFn || angular.noop;
                        wizardState.previousButtonTitle = opts.previousButtonTitle || "";
                        wizardState.previousButtonText  = opts.previousButtonText || LOCALE.maketext("Previous");
                        wizardState.previousFn          = opts.previousFn || angular.noop;

                        return true;
                    },

                    /**
                     * Loads the specified view
                     *
                     * @method loadView
                     * @param {String} path        The path to the view, relative to the docroot.
                     * @param {Object} [query]     Optional query string properties passed as a hash.
                     * @param {Object} [options]   Optional hash of options.
                     *     @param {Boolean} [options.clearAlerts]    If true, the default alert group in the alertService will be cleared.
                     *     @param {Boolean} [options.replaceState]   If true, the current history state will be replaced by the new view.
                     * @return {$location}         Angular's $location service.
                     * @see cjt2/services/viewNavigationApi.js
                     */
                    loadView: function(path, query, options) {
                        var location = viewNavigationApi.loadView(path, query, options);
                        wizardState.view = path;
                        return location;
                    },

                    /**
                     * Verify if the steps path is where we expected it to
                     * be for this controller.
                     *
                     * @method verifyStep
                     * @param {String|Regexp} expectedPath Path or pattern of path we expected.
                     * @param {Function}      [fn]         Optional callback function. If not provided, the wizardApi.reset()
                     *                                     is called, otherwise it calls the callback.
                     *                                     fn should have the following signature:
                     *                                         fn(current, expected)
                     *                                     where:
                     *                                        current  - String - current path
                     *                                        expected - String - expected path
                     * @return {Boolean}                    true if the path and expectedPath match, false otherwise.
                     */
                    verifyStep: function(expectedPath, fn) {
                        var expectedPathRegexp = angular.isString(expectedPath) ? new RegExp("^" + _.escapeRegExp(expectedPath) + "$") : expectedPath;
                        if (!expectedPathRegexp instanceof RegExp) {
                            throw "expectedPath is not a valid expression. It must be a string or a RegExp";
                        }

                        var currentPath = this.getView();
                        if (!expectedPathRegexp.test(currentPath)) {
                            if (fn && angular.isFunction(fn)) {
                                fn(currentPath, expectedPath);
                            } else {
                                this.reset();
                            }
                            return false;
                        }
                        return true;
                    },

                    /**
                     * Current number of steps. Works as a getter and setter.
                     *
                     * @property steps
                     * @param  {Number} [steps] Number of steps.
                     * @return {Number}         Number of steps.
                     */
                    steps: function(steps) {
                        if (!angular.isUndefined(steps)) {
                            wizardState.maxSteps = steps;
                        }
                        return wizardState.maxSteps;
                    }
                };
            }
        ]);
    }
);

/*
 * whostmgr/docroot/templates/support/create_support_ticket/views/wizardController.js
 *                                                 Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    'app/views/wizardController',[
        "angular"
    ],
    function(angular) {

        var app = angular.module("whm.createSupportTicket");

        app.controller("wizardController", [
            "$scope",
            "wizardState",
            "wizardApi",
            function($scope, wizardState, wizardApi) {
                $scope.wizard = wizardState;
                $scope.wizardApi = wizardApi;
                wizardApi.configure({
                    resetFn: function(suppressViewLoading) {
                        wizardState.step = 0;
                        if (!suppressViewLoading) {
                            wizardApi.loadView("/start");
                        }
                        wizardApi.hideFooter();
                        return true;
                    }
                });
            }
        ]);
    }
);

/*
 * services/ticketService.js                       Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define('app/services/ticketService',[
    "angular",
    "lodash",
    "cjt/util/parse",
    "cjt/io/whm-v1-request",
    "cjt/io/whm-v1",
    "cjt/services/APIService",
    "cjt/services/whm/oauth2Service"
], function(
        angular,
        _,
        PARSE,
        APIREQUEST
    ) {

    var module = angular.module("whm.createSupportTicket");

    module.factory("ticketService", [
        "$q",
        "APIService",
        "oauth2Service",
        "pageState",
        function(
            $q,
            APIService,
            oauth2Service,
            pageState
        ) {

            // The state of the cPanel & WHM server's access to the Customer Portal
            // If true, then we have an OAuth token on the server
            var _authState = false;

            // Set up the service's constructor and parent
            var TicketService = function() {};
            TicketService.prototype = new APIService();

            // Extend the prototype with any class-specific functionality
            angular.extend(TicketService.prototype, {

                /**
                 * Exchanges an OAuth code from the Customer Portal for an OAuth token that will be stored
                 * in the server's session data.
                 *
                 * @method verifyCode
                 * @param  {String} code           The OAuth code received from the Customer Portal that we want to verify
                 *                                 and exchange for a token.
                 * @param  {String} redirect_uri   The redirect_uri that was provided with the initial authorization request.
                 * @return {Promise}               When resolved, the code was successfully exchanged for an OAuth token and
                 *                                 that token is stored in the server-side session data.
                 */
                verifyCode: function(code, redirect_uri) {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "ticket_validate_oauth2_code");
                    apiCall.addArgument("code", code);
                    apiCall.addArgument("redirect_uri", redirect_uri);

                    var self = this;
                    return this.deferred(apiCall).promise.then(function(data) {
                        self.setAuthState(true);
                        return data;
                    }).catch(function(error) {
                        self.setAuthState(false);
                        return $q.reject(error);
                    });
                },

                /**
                * Launches an API query to retrieve the Support Information about the license provider.
                *
                * @method fetchSupportInfo
                * @return {Promise}                      When resolved, either the agreement will be available or
                *                                        retrieval will have failed.
                */
                fetchSupportInfo: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "ticket_get_support_info");

                    return this.deferred(apiCall).promise.then(function(result) {
                        return result;
                    });
                },

                /**
                * Launches an API query to retrieve the Technical Support Agreement and related metadata.
                *
                * @method fetchTechnicalSupportAgreement
                * @return {Promise}                      When resolved, either the agreement will be available or
                *                                        retrieval will have failed.
                */
                fetchTechnicalSupportAgreement: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "ticket_get_support_agreement");

                    if (pageState.tos) {
                        return $q(function(resolve, reject) {
                            resolve(pageState.tos);
                        });
                    }

                    return this.deferred(apiCall).promise.then(function(result) {
                        pageState.tos = result.data; // only on success
                        pageState.tos.accepted = PARSE.parsePerlBoolean(pageState.tos.accepted);
                        return result;
                    });
                },

                /**
                * Update the ticket system to show that the currently OAuth2 user has seen
                * the support agreement.
                *
                * @method updateAgreementApproval
                * @return {Promise}                      When resolved, the current version of the agreement
                *                                        will be marked as seen.
                */
                updateAgreementApproval: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "ticket_update_service_agreement_approval");
                    apiCall.addArgument("version", pageState.tos.version);

                    return this.deferred(apiCall).promise.then(function() {
                        pageState.tos.accepted = true;
                    });
                },

                /**
                 * Create a stub ticket so we can initiate other requests that depend
                 * on there being a ticket already.
                 *
                 * @return {Number} The ticket id of the stub ticket.
                 */
                createStubTicket: function() {
                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "ticket_create_stub_ticket");

                    return this.deferred(apiCall).promise.then(function(result) {
                        var ticketId = result.data.ticket_id;
                        var secId = result.data.secure_id;
                        pageState.ticketId = ticketId;
                        pageState.secId = secId;
                        return ticketId;
                    });
                },

                grantAccess: function() {
                    if (!pageState.ticketId) {
                        throw "You do not have a ticket yet, so you can not grant access. Call createStubTicket() first.";
                    }

                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "ticket_grant");
                    apiCall.addArgument("ticket_id", pageState.ticketId);
                    apiCall.addArgument("secure_id", pageState.secId);
                    apiCall.addArgument("server_num", 1);
                    apiCall.addArgument("ssh_username", "root"); // TODO: Will be dynamic after we get wheel user creation

                    return this.deferred(apiCall).promise;
                },

                /**
                 * A simple getter for the authorization state.
                 *
                 * @method getAuthState
                 * @return {Boolean}   True if we have a token and the server is authorized.
                 */
                getAuthState: function() {
                    return _authState;
                },

                /**
                 * A simple setter for the authorization state.
                 *
                 * @method setAuthState
                 * @param {Boolean} state   The new authorization status.
                 */
                setAuthState: function(state) {
                    if (_.isBoolean(state)) {
                        _authState = state;
                    } else {
                        throw new TypeError("The new state must be a boolean value.");
                    }
                }

            });

            return new TicketService();
        }
    ]);
});

/*
 * whostmgr/docroot/templates/support/create_support_ticket/services/ticketUrlService.js
 *                                                 Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    'app/services/ticketUrlService',[
        "angular"
    ],
    function(angular) {

        var app = angular.module("whm.createSupportTicket");

        app.service("ticketUrlService", [
            "$httpParamSerializer",
            "pageState",
            function($httpParamSerializer, pageState) {
                return {

                    /**
                     * Fetch a ticket system url for a specific support scenario.
                     *
                     * @service urlService
                     * @method getTicketUrl
                     * @param  {String} service  Name of the support scenario. @see whostmgr7::create_support_ticket for list of valid names.
                     * @param  {Object} [params] Optional additional query-string parameters as a JavaScript object.
                     * @return {String}          Url in the ticket system to use.
                     */
                    getTicketUrl: function(service, params) {
                        var urls = pageState.new_ticket_urls;
                        var url = urls[service] || urls.generic;
                        var serializedParams = "";
                        if (params) {
                            serializedParams = $httpParamSerializer(params);
                        }
                        return url + (serializedParams ? "&" + serializedParams : "");
                    }
                };
            }
        ]);
    }
);

/*
 * support/create_support_ticket/services/oauthPopupService.js
 *                                                 Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    'app/services/oauth2PopupService',[
        "angular",
        "cjt/util/query",
        "cjt/services/windowMonitorService",
        "cjt/services/whm/oauth2Service",
        "cjt/services/alertService",
        "app/services/wizardApi"
    ],
    function(angular, QUERY) {

        var app = angular.module("whm.createSupportTicket");
        app.service("oauth2PopupService", [
            "pageState",
            "alertService",
            "oauth2Service",
            "popupService",
            "ticketService",
            "windowMonitorService",
            "wizardApi",
            function(
                pageState,
                alertService,
                oauth2Service,
                popupService,
                ticketService,
                windowMonitorService,
                wizardApi) {

                /**
                 * Gets the OAuth endpoint from the oauth2Service, opens the pop-up to that endpoing,
                 * and sets up a callback for the redirect, which exchanges the code for the OAuth
                 * token.
                 *
                 * @method _createAuthPopup
                 * @return {Window}   A reference to the pop-up window created
                 */
                function _createAuthPopup($scope, errorCb) {
                    var popup;
                    var oauth2 = pageState.oauth2;

                    oauth2Service.initialize(oauth2.endpoint, oauth2.params);
                    oauth2Service.setCallback(function oauth2Success(queryString) {

                        // We no longer need to monitor the pop-up for a premature close and we don't
                        // want the monitor to think that something went wrong, so clear it.
                        windowMonitorService.stop(popup);

                        // Send the client to the verification spinner.
                        wizardApi.loadView("/authorize-customer-portal/verifying", null, {
                            replaceState: true
                        });

                        // Exchange the code for a token. The token is saved in the session data on the
                        // server and not on the client.
                        var parsed = QUERY.parse_query_string(queryString);
                        ticketService.verifyCode(parsed.code, parsed.redirect_uri).then(function() {

                            // All went well...
                            // Lookup support info if the license is not from cPanel, otherwise go to the TOS.
                            if (!pageState.is_cpanel_direct) {
                                wizardApi.loadView("/supportinfo", null, {
                                    clearAlerts: true,
                                    replaceState: true
                                });
                            } else {
                                wizardApi.loadView("/tos", null, {
                                    clearAlerts: true,
                                    replaceState: true
                                });
                            }
                            wizardApi.showFooter();
                            wizardApi.next();

                        }).catch(function(error) {
                            alertService.add({
                                message: error,
                                type: "danger",
                                replace: false
                            });

                            if (errorCb) {
                                errorCb(error);
                            }
                        });
                    });

                    popup = popupService.openPopupWindow(oauth2Service.getAuthUri(), "authorize_customer_portal", {
                        autoCenter: true,
                        height: 415,
                        width: 450
                    });

                    return popup;
                }

                return {

                    /**
                     * Popup the oauth2 dialog and setup the callback and monitor.
                     *
                     * @param  {Scope}   $scope    Scope for the controller calling this. Note it must be
                     *                             passed since it can not be injected in a service like it
                     *                             can in a controller.
                     * @param  {Function} closedCb Callback to call when the monitor notices the dialog is closed.
                     * @param  {Function} errorCb  Callback to call if the verification step errors out.
                     * @return {Window}            The window handle for the popup window.
                     */
                    show: function($scope, closedCb, errorCb) {
                        var popup = _createAuthPopup($scope, errorCb);
                        windowMonitorService.start(popup, closedCb);
                        return popup;
                    }
                };
            }
        ]);


    }
);

/*
 * views/startController.js                        Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define('app/views/startController',[
    "angular",
    "cjt/util/query",
    "cjt/services/popupService",
    "cjt/services/alertService",
    "app/services/ticketService",
    "app/services/ticketUrlService",
    "app/services/oauth2PopupService",
    "app/services/wizardApi"
], function(
        angular,
        QUERY_STRING_UTILS
    ) {

    var app = angular.module("whm.createSupportTicket");

    return app.controller("startController", [
        "$scope",
        "pageState",
        "alertService",
        "popupService",
        "ticketService",
        "ticketUrlService",
        "oauth2PopupService",
        "wizardApi",
        "wizardState",
        function(
            $scope,
            pageState,
            alertService,
            popupService,
            ticketService,
            ticketUrlService,
            oauth2PopupService,
            wizardApi,
            wizardState
        ) {
            angular.extend($scope, {
                show: {
                    hackQuestion: false
                },
                hacked: "unspecified",
                hasCloudLinux: pageState.has_cloud_linux ? true : false,
                hasLiteSpeed: pageState.has_lite_speed ? true : false
            });

            if (ticketService.getAuthState()) {
                if (pageState.tos && pageState.tos.accepted) {

                    // For resets only
                    wizardState.maxSteps = 3;
                } else {
                    wizardState.maxSteps = 4;
                }
            } else {
                if (pageState.tos && pageState.tos.accepted) {

                    // For resets only
                    wizardState.maxSteps = 6;
                } else {
                    wizardState.maxSteps = 7;
                }
            }

            if (!pageState.is_cpanel_direct) {
                wizardState.maxSteps++;
            }

            wizardApi.configureStep();
            wizardApi.reset(true);
            alertService.clear();

            /**
             * The user has determined that he or she wants to get support for this server.
             * If it's DNS only, we will send them to the ticket system. Otherwise, we find
             * out if they've been compromised.
             *
             * @method selectThisServer
             */
            $scope.selectThisServer = function() {
                if (pageState.is_dns_only) {

                    // Navigate to the ticket system for dns only tickets
                    var url = $scope.getTicketUrl("dnsonly");
                    popupService.openPopupWindow(url, "tickets", { newTab: true }).focus();
                } else if ( ticketService.getAuthState() ) {
                    if (!pageState.is_cpanel_direct) {
                        wizardApi.loadView("/supportinfo", null, { clearAlerts: true });
                    } else if (pageState.tos && pageState.tos.accepted) {
                        wizardApi.loadView("/grant", null, { clearAlerts: true });
                    } else {
                        wizardApi.loadView("/tos", null, { clearAlerts: true });
                    }
                    wizardApi.showFooter();
                    wizardApi.next();
                } else {
                    $scope.show.hackQuestion = true;
                    wizardApi.next();
                }
            };

            /**
             * This gets the appropriate URL for creating a particular type of ticket.
             *
             * @method getTicketUrl
             * @type {String}     The type of ticket being created
             * @return {String}   The URL for creating that type of ticket
             */
            $scope.getTicketUrl = ticketUrlService.getTicketUrl;

            /**
             * Move back from the get started state.
             *
             * @method moveBack
             */
            $scope.moveBack = function() {
                $scope.show.hackQuestion = false;
                wizardApi.previous();
            };

            /**
             * We've determined at this point that the ticket is for this server and the
             * server isn't compromised. If they are already authenticated against the
             * customer portal, we dive right into the TOS. Otherwise, we need to open
             * the OAuth pop-up.
             *
             * @method startTicket
             */
            $scope.startTicket = function() {
                if (ticketService.getAuthState()) {

                    // Navigate to next view
                    wizardApi.loadView("/tos", null, { clearAlerts: true });
                    wizardApi.showFooter();
                    wizardApi.next();
                } else {

                    // Show OAUTH window
                    var popup = oauth2PopupService.show(
                        $scope,
                        function(reason) {
                            if (reason !== "closed") {
                                return;
                            }

                            // If the pop-up is closed before we get the code back, we should take
                            // them to the error page.
                            wizardApi.loadView("/authorize-customer-portal/error", null, {
                                replaceState: true
                            });
                        },
                        function(apiError) {
                            wizardApi.loadView("/authorize-customer-portal/error", null, {
                                replaceState: true
                            });
                        }
                    );
                    popup.focus();

                    wizardApi.loadView("/authorize-customer-portal/authorizing", null, { clearAlerts: true });
                    wizardApi.next();
                }
            };
        }
    ]);
});

/*
 * views/authorizeCustomerPortalController.js      Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define('app/views/authorizeCustomerPortalController',[
    "angular",
    "cjt/util/locale",
    "cjt/services/alertService",
    "cjt/directives/loadingPanel",
    "app/services/oauth2PopupService",
    "app/services/ticketUrlService",
    "app/services/wizardApi"
], function(
        angular,
        LOCALE
    ) {

    var app = angular.module("whm.createSupportTicket");

    return app.controller("authorizeCustomerPortalController", [
        "$scope",
        "$routeParams",
        "alertService",
        "wizardApi",
        "oauth2PopupService",
        "ticketUrlService",
        function(
            $scope,
            $routeParams,
            alertService,
            wizardApi,
            oauth2PopupService,
            ticketUrlService
        ) {

            if (!wizardApi.verifyStep(/authorize-customer-portal\/.*$/)) {
                return;
            }

            $scope.$watch(
                function() {
                    return $routeParams.status;
                },
                function() {
                    $scope.status = $routeParams.status;

                    if ($scope.status === "error") {

                        /* If there is already an error displayed (e.g., from an API failure),
                         * don't bother displaying this generic error. */
                        if (!alertService.getAlerts().length) {
                            alertService.add({
                                message: LOCALE.maketext("The [asis,cPanel Customer Portal] authorization window appears closed, but the server did not receive an authorization response."),
                                type: "danger",
                                replace: true,
                                id: "closed-auth-window"
                            });
                        }
                    } else if ($scope.status !== "authorizing" &&
                               $scope.status !== "verifying" ) {
                        wizardApi.reset();
                    } else if ($scope.status === "verifying") {
                        wizardApi.next();
                    }
                }
            );

            /**
             * Retry the oauth2 popup again.
             *
             * @name  retry
             * @scope
             */
            $scope.retry = function() {

                // Show OAUTH window
                var popup = oauth2PopupService.show($scope,
                    function onClose(reason) {
                        if (reason !== "closed") {
                            return;
                        }

                        // If the pop-up is closed before we get the code back, we should take
                        // them to the error page.
                        wizardApi.loadView("/authorize-customer-portal/error", null, {
                            replaceState: true
                        });
                    },
                    function onError(apiError) {
                        wizardApi.loadView("/authorize-customer-portal/error", null, {
                            replaceState: true
                        });
                    }
                );
                popup.focus();

                // Reload the instructions and information about the authorization process.
                wizardApi.loadView("/authorize-customer-portal/authorizing", null, {
                    clearAlerts: true,
                    replaceState: true
                });
            };

            /**
             * Cancel the whole wizard and go back to the start.
             *
             * @name  cancel
             * @scope
             */
            $scope.cancel = function() {
                wizardApi.loadView("/start", null, {
                    clearAlerts: true,
                    replaceState: true
                });
                wizardApi.reset(true);
            };

            /**
             * This gets the appropriate URL for creating a particular type of ticket.
             *
             * @method getTicketUrl
             * @type {String}     The type of ticket being created
             * @return {String}   The URL for creating that type of ticket
             */
            $scope.getTicketUrl = ticketUrlService.getTicketUrl;

        }
    ]);
});

/*
 * views/termsofserviceController.js               Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define('app/views/termsofserviceController',[
    "angular",
    "cjt/util/locale",
    "cjt/directives/loadingPanel"
], function(
        angular,
        LOCALE
    ) {

    var app = angular.module("whm.createSupportTicket");

    return app.controller("termsofserviceController", [
        "$scope",
        "$q",
        "pageState",
        "wizardApi",
        "ticketService",
        "ticketUrlService",
        function(
            $scope,
            $q,
            pageState,
            wizardApi,
            ticketService,
            ticketUrlService
        ) {

            if (!wizardApi.verifyStep(/tos$/)) {
                return;
            }

            $scope.tos = {};

            $scope.uiState = {
                loading: false,
                failed: false
            };

            $scope.alertDetailsMessage = "";
            $scope.alertDetailsVisible = false;
            $scope.toggleMore = function(show) {
                if ($scope.alertDetailsMessage) {
                    $scope.alertDetailsVisible = show;
                } else {
                    $scope.alertDetailsVisible = false;
                }
            };

            $scope.getTicketUrl = ticketUrlService.getTicketUrl;

            /**
             * Cancel the whole wizard and go back to the start.
             *
             * @name  cancel
             * @scope
             */
            $scope.cancel = function() {
                wizardApi.loadView("/start", null, {
                    clearAlerts: true,
                    replaceState: true
                });
                wizardApi.reset(true);
            };


            /**
             * Navigate to the previous view.
             *
             * @name previous
             * @scope
             */
            var previous = function() {
                wizardApi.reset();
                return false;
            };

            /**
             * Navigate to the next view.
             *
             * @name next
             * @scope
             */
            var next = function() {
                pageState.data.tos.accepted = true; // Accepted, but not yet saved
                wizardApi.loadView("/grant");
                return true;
            };


            wizardApi.configureStep({
                nextFn: next,
                previousFn: previous,
                nextButtonText: LOCALE.maketext("Agree to Terms")
            });

            /**
             * Load the technical support agreement if its not
             * already loaded.
             *
             * @method  loadTechnicalSupportAgreement
             * @scope
             */
            $scope.loadTechnicalSupportAgreement = function() {

                /* If we've already loaded it once before, use the cached copy */
                if (pageState.tos) {
                    if (pageState.tos.accepted) {

                        // Get out as quick as possible, nothing further to do.
                        return $q.resolve();
                    }

                    $scope.tos = pageState.tos;
                    $scope.uiState = {
                        loading: false,
                        failed: false
                    };
                    return $q.resolve();
                }

                /* Otherwise, retrieve it via the API ... */

                $scope.uiState = {
                    loading: true,
                    failed: false
                };

                wizardApi.disableNextButton();

                return ticketService.fetchTechnicalSupportAgreement().then(function(result) {
                    $scope.tos = result.data;
                    wizardApi.enableNextButton();
                    $scope.uiState = {
                        loading: false,
                        failed: false
                    };
                })
                    .catch(function(error) {
                        $scope.uiState = {
                            loading: false,
                            failed: true
                        };
                        $scope.alertDetailsMessage = error;
                        return $q.reject(error);
                    });
            };

            $scope.loadTechnicalSupportAgreement().then(function() {
                if (pageState.tos.accepted) {

                    // We can skip further display of this step
                    wizardApi.loadView("/grant");
                    wizardApi.next();
                }
            });
        }
    ]);
});

/*
 * views/grantController.js                        Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define('app/views/grantController',[
    "angular",
    "cjt/util/locale",
    "cjt/directives/alert"
], function(
        angular,
        LOCALE
    ) {

    var app = angular.module("whm.createSupportTicket");

    return app.controller("grantController", [
        "$scope",
        "pageState",
        "wizardApi",
        function(
            $scope,
            pageState,
            wizardApi
        ) {

            if (!wizardApi.verifyStep(/grant$/)) {
                return;
            }

            // Load the grant from any previous trips through the
            // wizard or else make it true so we encourage people
            // to grant.
            $scope.allowGrant = !angular.isUndefined(pageState.data.grant.allow) ?
                pageState.data.grant.allow :
                true;

            // Only true while the grant checkbox hasn't been touched
            $scope.initGrant = true;

            /**
             * Toggles the state of the user's choice to allow access to his or her server
             * and sets the initGrant flag to false.
             *
             * @method toggleAllow
             */
            $scope.toggleAllow = function() {
                $scope.initGrant = false;
                $scope.allowGrant = !$scope.allowGrant;
            };

            /**
             * Stops propagation for a particular event.
             *
             * @method stopPropagation
             * @param  {Event} e   An event object.
             */
            $scope.stopPropagation = function(e) {
                $scope.initGrant = false;
                e.stopPropagation();
            };

            /**
             * Navigate to the previous view.
             *
             * @name previous
             * @scope
             */
            var previous = function() {
                if (pageState.tos.accepted) {
                    wizardApi.reset();
                    return false;
                } else {
                    wizardApi.loadView("/tos");
                    return true;
                }
            };

            /**
             * Navigate to the next view.
             *
             * @name next
             * @scope
             */
            var next = function() {
                pageState.data.grant.allow = $scope.allowGrant;
                wizardApi.loadView("/processing");
                return true;
            };

            wizardApi.configureStep({
                nextFn: next,
                previousFn: previous
            });

        }
    ]);
});

// maketext('Fake maketext call to ensure this file remains in .js_files_in_repo_with_mt_calls')
;
/*
 * views/supportInfoController.js                        Copyright(c) 2020 cPanel, L.L.C
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define('app/views/supportInfoController',[
    "angular",
    "cjt/util/locale",
    "cjt/directives/alert"
], function(
        angular,
        LOCALE
    ) {

    "use strict";
    var app = angular.module("whm.createSupportTicket");

    return app.controller("supportInfoController", [
        "$scope",
        "pageState",
        "wizardApi",
        "ticketService",
        function(
            $scope,
            pageState,
            wizardApi,
            ticketService
        ) {

            if (!wizardApi.verifyStep(/supportinfo$/)) {
                return;
            }

            $scope.supportinfo = {};
            $scope.uiState = {};

            $scope.uiState.loading = true;
            wizardApi.disableNextButton();

            /**
             * Goes to the next step in the wizard
             *
             * @method gotoNextStep
             */
            var gotoNextStep = function() {
                $scope.uiState.loading = false;
                wizardApi.enableNextButton();
                if ( pageState.tos && pageState.tos.accepted ) {
                    wizardApi.loadView("/grant", null, { clearAlerts: true });
                } else {
                    wizardApi.loadView("/tos", null, { clearAlerts: true });
                }
                return true;
            };

            /**
             * Navigate to the previous view.
             *
             * @name previous
             * @scope
             */
            var previous = function() {
                wizardApi.enableNextButton();
                wizardApi.reset();
                return false;
            };

            /**
             * Navigate to the next view.
             *
             * @name next
             * @scope
             */
            var next = function() {
                gotoNextStep();
                return true;
            };

            wizardApi.configureStep({
                nextFn: next,
                previousFn: previous
            });

            /**
             * Toggles the next button depending on the status of the checkbox.
             *
             * @method toggleNext
             */
            $scope.toggleNext = function() {
                if ( $scope.cpanelSupportWarning ) {
                    wizardApi.enableNextButton();
                } else {
                    wizardApi.disableNextButton();
                }
            };

            /**
             * Load the support information from the users license
             *
             * @method  loadSupportInformation
             * @scope
             */
            $scope.loadSupportInformation = function() {

                return ticketService.fetchSupportInfo().then(function(result) {
                    $scope.supportinfo = result.data;
                    $scope.uiState.loading = false;

                    // skip this step if the returned data does not have the information we are looking for.
                    if ( $scope.supportinfo.data.company_name === "" || $scope.supportinfo.data.pub_tech_contact === "" || $scope.supportinfo.data.pub_tech_contact.indexOf("tickets.cpanel.net") > -1 ) {
                        gotoNextStep();
                    }
                })
                    .catch(function(error) {

                        // If something fails, just skip this step and continue to the next.
                        return gotoNextStep();
                    });
            };

            // do the work!
            $scope.loadSupportInformation();
        }
    ]);
});

/*
 * services/sshTestService.js                      Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define('app/services/sshTestService',[
    "angular",
    "lodash",
    "cjt/util/parse",
    "cjt/io/whm-v1-request",
    "cjt/io/whm-v1",
    "cjt/services/APIService",
], function(
        angular,
        _,
        PARSE,
        APIREQUEST
    ) {

    var module = angular.module("whm.createSupportTicket");

    module.factory("sshTestService", [
        "$q",
        "APIService",
        function(
            $q,
            APIService
        ) {

            // Set up the service's constructor and parent
            var SshTestService = function() {};
            SshTestService.prototype = new APIService();

            // Extend the prototype with any class-specific functionality
            angular.extend(SshTestService.prototype, {

                /**
                 * Initiates an SSH test without waiting for the response.
                 *
                 * @method startTest
                 * @param  {Number} ticketId    The ticket ID that contains the server information you wish to test.
                 * @param  {Number} serverNum   The server number (as listed in the ticket) to test. Defaults to 1.
                 * @return {Promise}            When resolved, the SSH test initiated succesfully.
                 */
                startTest: function(ticketId, serverNum) {
                    if (angular.isUndefined(serverNum)) {
                        serverNum = 1;
                    }

                    if ( !angular.isNumber(ticketId) ) {
                        throw new TypeError("Developer Error: ticketId must be a number");
                    }
                    if ( !angular.isNumber(serverNum) ) {
                        throw new TypeError("Developer Error: serverNum must be a number");
                    }

                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize("", "ticket_ssh_test_start");
                    apiCall.addArgument("ticket_id", ticketId);
                    apiCall.addArgument("server_num", serverNum);

                    return this.deferred(apiCall).promise;
                },

            });

            return new SshTestService();
        }
    ]);
});

/*
 * views/processingController.js                      Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define('app/views/processingController',[
    "angular",
    "cjt/util/locale",
    "cjt/services/alertService",
    "cjt/services/popupService",
    "cjt/directives/processingIconDirective",
    "app/services/ticketService",
    "app/services/sshTestService"
], function(
        angular,
        LOCALE
    ) {

    var app = angular.module("whm.createSupportTicket");

    return app.controller("processingController", [
        "$scope",
        "$interval",
        "$q",
        "alertService",
        "pageState",
        "wizardState",
        "wizardApi",
        "popupService",
        "ticketUrlService",
        "processingIconStates",
        "ticketService",
        "sshTestService",
        function(
            $scope,
            $interval,
            $q,
            alertService,
            pageState,
            wizardState,
            wizardApi,
            popupService,
            ticketUrlService,
            processingIconStates,
            ticketService,
            sshTestService
        ) {
            if (!/processing$/.test(wizardApi.getView()) ) {
                wizardApi.reset();
                return;
            }

            wizardApi.configureStep();
            wizardApi.hideFooter();

            var ticketData = {

                // ticketId
                // tsaRecorded
                // sshTestStarted
                // grantedAccess
            };

            $scope.work = {
                states: {
                    initializeRequest: processingIconStates.default,
                    logTsa: processingIconStates.default,
                    logAuthorizeSupport: processingIconStates.default,
                    startSshTest: processingIconStates.default,
                    updateRequest: processingIconStates.default,
                    transferring: processingIconStates.default
                }
            };

            $scope.ui = {
                showTsa: !pageState.tos.accepted,  // If it was not previously agreed to
                showAccess: pageState.data.grant.allow,
                processingError: null
            };

            $scope.isPopupBlocked = false;

            /**
             * Create the promise change the registers users agreement to
             * the Technical Services Agreement.
             *
             * @return {Promise} When fulfilled, it will have registered the
             * TSA that user agreed too in the tickets database.
             */
            function registerTsa() {
                $scope.work.states.logTsa = processingIconStates.run;
                return ticketService.updateAgreementApproval().then(function(result) {
                    delete pageState.data.tos.accepted;
                    pageState.tos.accepted = true;
                    ticketData.tsaRecorded = true;
                    $scope.work.states.logTsa = processingIconStates.done;
                }).catch(function(error) {
                    $scope.work.states.logTsa = processingIconStates.error;
                    return $q.reject({
                        error: error,
                        message: LOCALE.maketext("The system failed to log agreement to the Technical Support Agreement with the following error: [_1]", error),
                        id: "tsaSaveError"
                    });
                });
            }

            /**
             * Create the promise chain for creating a stub ticket.
             *
             * @return {Promise} When fulfilled, a stub ticket will exist on the
             * ticket system and other operations that depend on the tickets existence
             * will be able to run. The promise will return the ticketId to the next
             * promise success callback on success. On failure, the error string will be
             * returned to the failure handler.
             */
            function createStubTicket() {
                $scope.work.states.initializeRequest = processingIconStates.run;
                return ticketService.createStubTicket().then(function(ticketId) {
                    $scope.work.states.initializeRequest = processingIconStates.done;

                    // Record the ticket id for later
                    ticketData.ticketId = ticketId;

                    return ticketId; // For the next promise in the chain
                }).catch(function(error) {
                    $scope.work.states.initializeRequest = processingIconStates.error;
                    return $q.reject({
                        error: error,
                        message: LOCALE.maketext("The system failed to create a stub ticket with the following error: [_1]", error),
                        id: "stubTicketCreateError"
                    });
                });
            }

            /**
             * Setup the grant access promise and response handlers.
             *
             * @method grantAccess
             * @param  {Number} ticketId   The ID number of the ticket stub for which the server will be granting access.
             * @return {Promise}           Returns the ticketId when resolved or an error string when rejected.
             */
            function grantAccess(ticketId) {
                $scope.work.states.logAuthorizeSupport = processingIconStates.run;
                var SUB_SYSTEM = {
                    "chain_status": "iptables",
                    "hulk_wl_status": "cPHulk",
                    "csf_wl_status": "CSF",
                    "host_access_wl_status": LOCALE.maketext("Host Access Control") // We don't use [asis] for Host Access Control
                };

                return ticketService.grantAccess().catch(function(error) {
                    $scope.work.states.logAuthorizeSupport = processingIconStates.error;
                    return $q.reject({
                        error: error,
                        message: LOCALE.maketext("The system failed to authorize access to the server with following error: [_1]", error),
                        id: "grantAccessError"
                    });
                }).then(function(result) {

                    // Check for whitelist issues.
                    var hasIssues = false;
                    ["chain_status", "hulk_wl_status", "csf_wl_status", "host_access_wl_status"].forEach(function(key) {
                        if (result.data[key] && result.data[key] !== "ACTIVE") {
                            alertService.add({
                                message: LOCALE.maketext("The system failed to add whitelist rules for “[_1]” while configuring access for [asis,cPanel] support.", SUB_SYSTEM[key]),
                                type: "warning",
                                id: "grant-access-" + key.replace(/_status$/, "") + "-warning",
                                replace: false,
                            });
                            hasIssues = true;
                        }
                    });

                    // Add warning alerts for any non-fatal errors (botched ticket log or audit log entries).
                    if (result.data.non_fatals && result.data.non_fatals.length) {
                        alertService.add({
                            message: LOCALE.maketext("The following non-fatal [numerate,_1,error,errors] occurred while allowing [asis,cPanel] support access to this server:", result.data.non_fatals.length),
                            list: result.data.non_fatals,
                            type: "warning",
                            id: "grant-access-non-fatal-warning",
                            replace: false,
                        });
                    }
                    ticketData.grantedAccess = true;
                    $scope.work.states.logAuthorizeSupport = hasIssues ? processingIconStates.unknown : processingIconStates.done;
                    return ticketId; // For the next promise in the chain

                });
            }

            /**
             * Initiates an SSH connection test. The promise returned from this function will
             * always be resolved because our WHM interface does not yet support retrying the
             * request. The ticket system interface will handle those duties for now.
             *
             * @method startSshTest
             * @param  {Number} ticketId   The ID of the ticket stub that the SSH test will be run against.
             * @return {Promise}           This will always be resolved since failing to start an SSH test
             *                             should not prohibit users from submitting tickets. The resolution
             *                             data will always be the ticketId.
             */
            function startSshTest(ticketId) {
                $scope.work.states.startSshTest = processingIconStates.run;

                return sshTestService.startTest(ticketId, 1).then(function(result) {

                    // Record the test status for later
                    ticketData.sshTestStarted = true;

                    $scope.work.states.startSshTest = processingIconStates.done;
                    return ticketId;

                }).catch(function(error) {
                    alertService.add({
                        message: LOCALE.maketext("The system failed to initiate an [asis,SSH] connection test for this server: [_1]", error),
                        type: "warning",
                        id: "ssh-test-warning"
                    });

                    $scope.work.states.startSshTest = processingIconStates.error;

                    // We don't return a rejected promise because all SSH connection test results and
                    // retry attempts will be initiated on the ticket system side for now.
                    return ticketId;
                });
            }

            /**
             * Put the error information on the scope for our custom alert. This gives users a way out
             * of our flow if things break so that they can try again directly on the ticket system.
             *
             * @method handleFatalError
             * @param  {Object|String} error   The error string or an alert-style object.
             */
            function handleFatalError(error) {
                if (error && error.id) {

                    // This is our own error
                    $scope.processingError = error;
                } else {

                    // This is an unexpected error
                    $scope.processingError = {
                        message: LOCALE.maketext("The system failed to process your request because of an error: [_1]", error),
                        id: "unknown-error"
                    };
                }
            }

            /**
             * The main function of the controller that determines which operations
             * need to take place.
             *
             * @method processAll
             */
            function processAll() {

                var promise = $q.resolve();

                // Save the fact that the user has seen and acknowledged the
                // current Technical Support Agreement, if they hadn't done so
                // before
                if (!pageState.tos.accepted) {
                    promise = registerTsa();
                }

                // Create the stub ticket
                promise = promise.then(createStubTicket);

                // Grant access and start the SSH connection test if they have
                // allowed us access
                if (pageState.data.grant.allow) {
                    promise = promise.then(grantAccess)
                        .then(startSshTest);
                }

                // Finally, open the ticket system window
                promise = promise.then(function() {
                    openTicketWizard();
                });

                // If any complete failures happen, we should try and give
                // users a way forward
                promise.catch(handleFatalError);

            }

            /**
             * Navigate to the support window
             * @param  {Object} wizardState   The wizard state service.
             */
            function navigateToSupport(wizardState) {
                var params = {
                    "tsa-recorded": (ticketData.tsaRecorded || pageState.tos.accepted) ? 1 : 0,
                    "access-granted": ticketData.grantedAccess ? 1 : 0,
                    "ssh-test-started": ticketData.sshTestStarted ? 1 : 0,
                    "step": wizardState.step,
                    "max-steps": wizardState.maxSteps
                };

                if (ticketData.ticketId) {
                    params["ticket-id"] = ticketData.ticketId;
                }

                var url = ticketUrlService.getTicketUrl("cpanelnwf", params);
                var handle = popupService.openPopupWindow(url, "_blank", { newTab: true });
                if (!handle || handle.closed || angular.isUndefined(handle.closed)) {
                    $scope.isPopupBlocked = true;
                } else {
                    $scope.isPopupBlocked = false;
                    handle.focus();
                }

                // We shouldn't change the transferring status icon if we're using the button
                // associated with a fatal error
                if (!$scope.processingError) {
                    $scope.work.states.transferring = $scope.isPopupBlocked ?
                        processingIconStates.unknown : processingIconStates.done;
                }
            }

            /**
             * Open the ticket wizard in a new tab.
             *
             * @method openTicketWizard
             */
            function openTicketWizard() {
                navigateToSupport(wizardState);
            }

            $scope.openTicketWizard = openTicketWizard;
            processAll();

        }
    ]);
});

/*
 * index.js                                        Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global require: false, define: false, PAGE: false */

define(
    'app/index',[
        "angular",
        "jquery",
        "cjt/modules",
        "ngRoute",
        "ngAnimate",
        "ngSanitize",
        "uiBootstrap",

    ],
    function(angular, $) {

        return function() {
            angular.module("whm.createSupportTicket", [
                "cjt2.config.whm.configProvider", // This needs to load before ngRoute
                "ngRoute",
                "ngAnimate",
                "ngSanitize",
                "ui.bootstrap",
                "cjt2.whm"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/util/parse",
                    "cjt/util/locale",

                    "cjt/views/applicationController",
                    "cjt/directives/alertList",
                    "cjt/services/autoTopService",
                    "cjt/services/whm/breadcrumbService",
                    "app/services/wizardApi",
                    "app/views/wizardController",
                    "app/views/startController",
                    "app/views/authorizeCustomerPortalController",
                    "app/views/termsofserviceController",
                    "app/views/grantController",
                    "app/views/supportInfoController",
                    "app/views/processingController",
                    "app/services/ticketService"
                ], function(BOOTSTRAP, PARSE, LOCALE) {

                    var app = angular.module("whm.createSupportTicket");

                    app.firstLoad = {};

                    // Normalize the data
                    PAGE.is_dns_only              = PARSE.parsePerlBoolean(PAGE.is_dns_only);
                    PAGE.is_tickets_authenticated = PARSE.parsePerlBoolean(PAGE.is_tickets_authenticated);
                    PAGE.is_cpanel_direct         = PARSE.parsePerlBoolean(PAGE.is_cpanel_direct);
                    PAGE.data = {
                        start: {},
                        tos: {},
                        grant: {},
                    };

                    // Inject the state in the application.
                    app.value("pageState", PAGE);
                    var wizardState = {
                        step: 0,
                        maxSteps: 7,
                        footer: false,
                        view: "/start"
                    };

                    if (PAGE.is_tickets_authenticated) {
                        wizardState.maxSteps -= 3;
                    }

                    app.value("wizardState", wizardState);

                    app.config([
                        "$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/start", {
                                controller: "startController",
                                templateUrl: "support/create_support_ticket/views/startView.ptt",
                                breadcrumb: LOCALE.maketext("Select Issue Type")
                            });

                            $routeProvider.when("/authorize-customer-portal/:status?", {
                                controller: "authorizeCustomerPortalController",
                                templateUrl: "support/create_support_ticket/views/authorizeCustomerPortalView.ptt",
                                breadcrumb: LOCALE.maketext("Authorize Customer Portal")
                            });

                            $routeProvider.when("/tos", {
                                controller: "termsofserviceController",
                                templateUrl: "support/create_support_ticket/views/termsofserviceView.ptt",
                                breadcrumb: LOCALE.maketext("Technical Support Agreement")
                            });

                            $routeProvider.when("/grant", {
                                controller: "grantController",
                                templateUrl: "support/create_support_ticket/views/grantView.ptt",
                                breadcrumb: LOCALE.maketext("Authorize Support Access")
                            });

                            $routeProvider.when("/processing", {
                                controller: "processingController",
                                templateUrl: "support/create_support_ticket/views/processingView.ptt",
                                breadcrumb: LOCALE.maketext("Processing")
                            });

                            $routeProvider.when("/supportinfo", {
                                controller: "supportInfoController",
                                templateUrl: "support/create_support_ticket/views/supportInfoView.ptt",
                                breadcrumb: LOCALE.maketext("Support Information")
                            });


                            $routeProvider.otherwise({
                                "redirectTo": "/start"
                            });
                        }
                    ]);

                    app.run([
                        "autoTopService",
                        "breadcrumbService",
                        "ticketService",
                        "wizardState",
                        function(autoTopService, breadcrumbService, ticketService) {
                            autoTopService.initialize();
                            breadcrumbService.initialize();
                            ticketService.setAuthState(PAGE.is_tickets_authenticated);
                            delete PAGE.is_tickets_authenticated;
                        }
                    ]);


                    BOOTSTRAP(document, "whm.createSupportTicket");

                });

            return app;
        };
    }
);

