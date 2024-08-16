/*
 * views/processingController.js                      Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define([
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
