/*
* base/frontend/jupiter/security/tls_wizard/views/CheckoutController.js
*                                                 Copyright(c) 2020 cPanel, L.L.C.
*                                                           All rights reserved.
* copyright@cpanel.net                                         http://cpanel.net
* This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

// Then load the application dependencies


define(
    [
        "lodash",
        "angular",
        "jquery",
        "cjt/util/locale",
        "cjt/util/query",
        "app/views/Certificate",
        "cjt/modules",
        "app/services/CertificatesService",
        "app/services/LocationService",
        "cjt/directives/spinnerDirective",
        "uiBootstrap",
    ],
    function(_, angular, $, LOCALE, QUERY) {
        "use strict";

        var app = angular.module("App");

        function CheckoutController(
            $scope,
            $controller,
            $location,
            $filter,
            $routeParams,
            $window,
            $timeout,
            CertificatesService,
            spinnerAPI,
            $q,
            $modal,
            $log,
            Certificate,
            LocationService,
            alertService) {

            var steps = {
                "cPStore": ["login", "send_cart_items", "checkout", "payment_callback", "checkout_complete"],
                "default": ["login", "send_cart_items", "checkout", "payment_callback", "checkout_complete"],
            };
            $scope.pending_certificates = CertificatesService.get_pending_certificates();
            $scope.LOCALE = LOCALE;
            $scope.purchase_steps = [];
            $scope.current_step = -1;
            $scope.start_step = null;
            $scope.providers = [];
            $scope.certificates_count = 0;
            $scope.steps = [];

            $scope.html_escape = _.escape.bind(_);

            $scope.get_step_classes = function(provider, step) {
                var steps = $scope.get_steps(provider.name).length;
                var stepIndex = $scope.get_step_index(provider.name, step);
                var cols = Math.floor(12 / steps);
                var classes = ["col-xs-12", "col-sm-12", "col-md-" + cols, "col-lg-" + cols, "checkout-step"];
                if ($scope.current_step_index === stepIndex) {
                    classes.push("checkout-step-current");
                    if ("checkout_complete" === step) {
                        classes.push("checkout-step-completed");
                    }
                } else if ($scope.current_step_index > stepIndex) {
                    classes.push("checkout-step-completed");
                }

                return classes;
            };

            $scope.cert_count_title = function() {
                return LOCALE.maketext("Purchasing [quant,_1,certificate,certificates] …", $scope.certificates_count);
            };

            $scope.get_purchases_title = function(provider) {
                return LOCALE.maketext("Completing [numerate,_2,purchase,purchases] for the “[_1]” provider …", $scope.html_escape(provider.display_name), provider.certificates.length);
            };

            $scope.sending_items_msg = function() {
                return LOCALE.maketext("Sending your [numerate,_1,item,items] to the store cart …", $scope.certificates_count);
            };

            $scope.starting_polling_msg = function() {
                return LOCALE.maketext("Starting background polling for the [numerate,_1,certificate,certificates]. The system will download and install the [numerate,_1,certificate,certificates] when available.", $scope.certificates_count);
            };

            $scope.get_provider_by_name = function(name) {
                for (var i = 0; i < $scope.providers.length; i++) {
                    if ($scope.providers[i].name === name) {
                        return $scope.providers[i];
                    }
                }
            };

            $scope.get_steps = function(providerName) {
                if (steps[providerName]) {
                    return steps[providerName];
                }
                return steps["default"];
            };

            $scope.get_current_step = function() {
                return $scope.steps[$scope.current_step_index];
            };

            $scope.get_step_index = function(providerName, step) {
                for (var i = 0; i < $scope.steps.length; i++) {
                    if ($scope.steps[i].provider === providerName && $scope.steps[i].step === step) {
                        return i;
                    }
                }
                return 0;
            };

            $scope.get_step_url = function(step) {
                return "/" + encodeURIComponent(step.provider) + "/" + encodeURIComponent(step.step);
            };

            $scope.get_next_step = function() {
                if ($scope.current_step_index + 1 < $scope.steps.length) {
                    return $scope.steps[$scope.current_step_index + 1];
                }
            };

            $scope.get_param = function(key) {
                return QUERY.parse_query_string(location.search.replace(/^\?/, ""))[key] || $routeParams[key];
            };

            $scope.require_params = function(keys) {
                var badKeys = [];
                var tooManyKeys = [];
                angular.forEach(keys, function(key) {
                    var value = $scope.get_param(key);
                    if (!value) {
                        badKeys.push(key);
                    } else if (value instanceof Array) {
                        tooManyKeys.push(key);
                    }
                });

                if (badKeys.length) {
                    alertService.add({
                        type: "danger",
                        message: LOCALE.maketext("The following [numerate,_1,parameter is,parameters are] required but [numerate,_1,does,do] not appear in the [asis,URL]: [list_and_quoted,_2]", badKeys.length, badKeys),
                        group: "tlsWizard",
                    });
                }

                if (tooManyKeys.length) {
                    alertService.add({
                        type: "danger",
                        message: LOCALE.maketext("The following [numerate,_1,parameter appears,parameters appear] more than once in the [asis,URL]: [list_and_quoted,_2]", tooManyKeys.length, tooManyKeys),
                        group: "tlsWizard",
                    });
                }

                return badKeys.length || tooManyKeys.length ? false : true;
            };

            $scope.in_debug_mode = false;

            $scope.get_route_url = function() {
                var routeURL = "";
                routeURL += $location.absUrl().replace(/tls_wizard\/.+/, "tls_wizard/#/purchase");
                return routeURL;
            };

            function _pemToBase64(pem) {
                return pem
                    .replace(/^\s*-\S+/, "")
                    .replace(/-\S+\s*$/, "")
                    .replace(/\s+/g, "");
            }

            // $q.all() will reject the “aggregate” promise with the
            // exact same value as the one that failed. That’s not good
            // enough; we also need to know which promise failed in addition
            // to why it failed.
            //
            // This transforms all failure callback payloads into 2-member
            // arrays:   [ <promise_index>, <payload> ]
            //
            // So, if you do:
            //  _qAllWithErrIndex( [ prA, prB, prC ] )
            //
            // ...and “prB” fails with the string "hahaha", the
            // failure callback will receive [ 1, "hahaha" ].
            //
            function _qAllWithErrIndex(promisesArray) {
                if (!(promisesArray instanceof Array)) {
                    throw "Only arrays here!";
                }

                return $q.all(promisesArray.map(function(p, i) {
                    return $q(function(resolve, reject) {
                        p.then(
                            resolve,
                            function(payload) {
                                reject([i, payload]);
                            }
                        );
                    });
                }));
            }

            $scope.dismiss_modal = function() {
                this.modal.dismiss();
            };

            $scope.go_to_purchase_page = LocationService.go_to_last_create_route;

            $scope.go_to_login = function() {
                this.go_step(this.get_current_step().provider, "login");
            };

            $scope.do_current_step = function() {
                var step = $scope.get_current_step();

                if (!step) {

                    // something is severely wrong
                    // maybe they hit the back button a lot for some random reason.
                    // let's send them back somewhere safe.
                    LocationService.go_to_last_create_route();
                    return;
                }

                var nextStep = $scope.get_next_step();
                var orderID = $scope.get_param("order_id");
                var loginCode = $scope.get_param("code");
                var order = CertificatesService.get_order_by_id(orderID);
                var orderStatus = $scope.get_param("order_status");
                var provider = $scope.get_provider_by_name(step.provider);
                var accessToken = $scope.get_param("access_token");
                var returnURL;

                if (step.step === "login") {
                    returnURL = $scope.get_route_url() + $scope.get_step_url(step);
                    if (order) {
                        returnURL += "?order_id=" + order.order_id;
                    }
                    if (loginCode) {

                        /* Back from Login, Verify It */
                        CertificatesService.verify_login_token(step.provider, loginCode, returnURL).then(function(result) {
                            if (order) {

                                /* there's an order, so don't create another one */
                                $scope.go_step(step.provider, "checkout", {
                                    order_id: order.order_id,
                                    access_token: result.data.access_token,
                                });
                            } else {

                                /* no order, so create one */
                                $scope.go_step(step.provider, "send_cart_items", {
                                    access_token: result.data.access_token,
                                });
                            }
                        }, function(errorHTML) {
                            $scope.return_to_wizard();
                            alertService.add({
                                type: "danger",
                                message: LOCALE.maketext("The system encountered an error as it attempted to verify the login token: [_1]", errorHTML) + " " + LOCALE.maketext("You will now return to the beginning of the wizard."),
                                closeable: true,
                                replace: false,
                                group: "tlsWizard",
                            });
                        });
                    } else {

                        /* There's no login code */
                        CertificatesService.get_store_login_url(step.provider, returnURL).then(function(result) {
                            $window.location.href = result.data;
                        }, function(errorHTML) {
                            $scope.return_to_wizard();
                            alertService.add({
                                type: "danger",
                                message: LOCALE.maketext("The system encountered an error as it attempted to get the store login [output,abbr,URL,Uniform Resource Location]: [_1]", errorHTML) + " " + LOCALE.maketext("You will now return to the beginning of the wizard."),
                                closeable: true,
                                replace: false,
                                group: "tlsWizard",
                            });
                        });
                    }
                } else if (step.step === "send_cart_items") {

                    /* create order / build cart */
                    if (!$scope.require_params(["access_token"])) {
                        return;
                    }
                    returnURL = $scope.get_route_url() + $scope.get_step_url(nextStep);
                    return CertificatesService.request_certificates(step.provider, accessToken, provider.certificates).then(function(result) {
                        var order = result.data;
                        order.order_id = order.order_id.toString();

                        CertificatesService.add_order(order);
                        CertificatesService.save();

                        $scope.go_step(step.provider, "checkout", {
                            order_id: order.order_id,
                            access_token: accessToken,
                        });
                    }, function(errorHTML) {
                        $scope.return_to_wizard();
                        alertService.add({
                            type: "danger",
                            message: LOCALE.maketext("The system encountered an error as it attempted to request the [asis,SSL] [numerate,_2,certificate,certificates]: [_1]", errorHTML, $scope.get_provider_by_name(step.provider).certificates.length) + " " + LOCALE.maketext("You will now return to the beginning of the wizard."),
                            closeable: true,
                            replace: false,
                            group: "tlsWizard",
                        });
                    });
                } else if (step.step === "checkout") {
                    if (!$scope.require_params(["order_id"])) {
                        return;
                    }
                    returnURL = $scope.get_route_url() + $scope.get_step_url(step);
                    if (orderStatus) {

                        /* are we back from checking out? */
                        $scope.go_step(step.provider, "payment_callback", {
                            order_id: order.order_id,
                            order_status: orderStatus,
                        });
                    } else {
                        if (!$scope.require_params(["access_token"])) {
                            return;
                        }

                        /* no? let's update the checkout url and head to checkout */
                        CertificatesService.set_url_after_checkout(step.provider, accessToken, order.order_id, returnURL).then(function() {
                            $window.location.href = order.checkout_url;
                        }, function(response) { // NB: the argument is *not* the error!
                            var isOtherUser = response.data && response.data.error_type === "OrderNotFound";

                            if (isOtherUser) {
                                $scope.order_id = order.order_id;
                                $scope.provider = $scope.get_provider_by_name(step.provider);

                                $scope.modal = $modal.open({
                                    template: document.getElementById("user-mismatch-modal").text,
                                    scope: $scope,
                                    backdrop: "static",
                                    animation: false,
                                    size: "sm",
                                });
                            } else {
                                LocationService.go_to_last_create_route();
                                alertService.add({
                                    type: "danger",
                                    message: LOCALE.maketext("The system encountered an error as it attempted to set the [asis,URL] after checkout: [_1]", _.escape(response.error)) + " " + LOCALE.maketext("You will now return to the beginning of the wizard."),
                                    closeable: true,
                                    replace: false,
                                    group: "tlsWizard",
                                });
                            }

                        });
                    }
                } else if (step.step === "payment_callback") {

                    /* post checkout processing */
                    CPANEL.PAGE.pending_certificates = null;
                    CPANEL.PAGE.installed_hosts = null;
                    if (orderStatus === "success") {
                        alertService.add({
                            type: "success",
                            message: LOCALE.maketext("You have successfully completed your certificate order (order ID “[_1]”). If you need help with this order, use the support [numerate,_2,link,links] below.", _.escape(orderID), order.certificates.length),
                            closeable: true,
                            replace: false,
                            autoClose: 10000,
                            group: "tlsWizard",
                        });
                        CertificatesService.set_confirmed_status_for_ssl_certificates(step.provider, order).then(function() {

                            // successful
                            $scope.go_step(step.provider, nextStep.step);
                        }, function(response) {

                            // This is here to accommodate cases where the certificate
                            // becomes available, and gets installed, prior to the
                            // browser’s being able to set the certificate to “confirmed”.
                            // When that happens, we get back a data structure that
                            // describes which vhosts’ pending queue entries didn’t exist;
                            // we then do what can be done to ensure that the cert(s)
                            // is/are installed where it/they should be.
                            //
                            if (response.data && response.data.error_type === "EntryDoesNotExist") {
                                var notFound = response.data.order_item_ids;

                                var msg = LOCALE.maketext("There are no pending certificates from “[_1]” with the following order item [numerate,_2,ID,IDs]: [join,~, ,_3]. The system will now verify that the [numerate,_2,certificate has,certificates have] been issued and installed.", _.escape(step.provider), notFound.length, notFound.map(_.escape.bind(_)));

                                alertService.add({
                                    type: "info",
                                    message: msg,
                                    closeable: true,
                                    replace: false,
                                    autoClose: 10000,
                                    group: "tlsWizard",
                                });

                                var certificates = provider.certificates;

                                notFound.forEach(function(oiid) {

                                    // Fetch the new SSL cert.
                                    var providerPromise = CertificatesService.get_ssl_certificate_if_available(step.provider, oiid);

                                    // There will only be one vhost
                                    // per certificate for now, but with
                                    // wildcard support that could change.
                                    certificates.forEach(function(cert) {

                                        cert.get_virtual_hosts().forEach(function(vhostName) {
                                            var domain = cert.get_domains().filter(function(domain) {
                                                return domain.virtual_host === vhostName;
                                            }).pop().domain;

                                            var bigP = _qAllWithErrIndex([
                                                CertificatesService.get_installed_ssl_for_domain(),
                                                providerPromise,
                                            ]);

                                            bigP.then(function yay(responses) {
                                                var installedPEM = responses[0].data.certificate.text;
                                                var installedB64;

                                                if (installedPEM) {
                                                    installedB64 = _pemToBase64(installedPEM);
                                                }

                                                var providerPEM = responses[1].data.certificate_pem;
                                                var providerB64;
                                                if (providerPEM) {
                                                    providerB64 = _pemToBase64(providerPEM);
                                                } else {
                                                    var apiResponse = responses[1].data;
                                                    var statusCode = apiResponse.status_code;
                                                    var statusMessage = apiResponse.status_message;

                                                    var alertMessage;

                                                    // There is ambiguity over the spelling of “canceled”.
                                                    if (/OrderCancell?ed/.test(statusCode)) {
                                                        alertMessage = LOCALE.maketext("“[_1]” indicated that the order with [asis,ID] “[_2]” has been canceled.", _.escape(step.provider), _.escape(orderID));
                                                    } else if (/OrderItemCancell?ed/.test(statusCode)) {
                                                        alertMessage = LOCALE.maketext("“[_1]” indicated that the certificate with order item [asis,ID] “[_2]” has been canceled.", _.escape(step.provider), _.escape(oiid));
                                                    } else {
                                                        alertMessage = LOCALE.maketext("“[_1]” has not issued a certificate for order item [asis,ID] “[_2]”. Contact them for further assistance.", _.escape(step.provider), _.escape(oiid));

                                                        // This yields one of:
                                                        //      statusCode
                                                        //      statusMessage
                                                        //      statusCode: statusMessage
                                                        // … depending on the two items’
                                                        // truthiness.
                                                        var statusStr = [statusCode, statusMessage].filter( function(s) {
                                                            return !!s;
                                                        } ).join(": ");

                                                        if (statusStr) {
                                                            alertMessage += " (" + statusStr + ")";
                                                        }
                                                    }

                                                    alertService.add({
                                                        type: "danger",
                                                        message: alertMessage,
                                                        closeable: true,
                                                        replace: false,
                                                        group: "tlsWizard",
                                                    });

                                                    // Since there’s no new certificate,
                                                    // there’s nothing more we can do.
                                                    LocationService.go_to_last_create_route();
                                                    return;
                                                }

                                                if (providerB64 === installedB64) {

                                                    // This is the most optimal outcome:
                                                    // we confirmed that the new cert is
                                                    // installed, as the user wanted.

                                                    alertService.add({
                                                        type: "success",
                                                        message: LOCALE.maketext("The system confirmed that the certificate for the website “[_1]” is installed.", _.escape(vhostName)),
                                                        closeable: true,
                                                        replace: false,
                                                        autoClose: 10000,
                                                        group: "tlsWizard",
                                                    });
                                                    if (installedB64) {
                                                        alertService.add({
                                                            type: "info",
                                                            message: LOCALE.maketext("“[_1]” has an [asis,SSL] certificate installed, but it is not the certificate that you just ordered (order item [asis,ID] “[_2]”). The system will now install this certificate.", _.escape(vhostName), _.escape(oiid)),
                                                            closeable: true,
                                                            replace: false,
                                                            autoClose: 10000,
                                                            group: "tlsWizard",
                                                        });
                                                    } else {
                                                        var noCertMessage;
                                                        noCertMessage = LOCALE.maketext("You do not have an [asis,SSL] certificate installed for the website “[_1]”.", _.escape(vhostName));

                                                        noCertMessage += LOCALE.maketext("The system will now install the new certificate.");

                                                        alertService.add({
                                                            type: "info",
                                                            message: noCertMessage,
                                                            closeable: true,
                                                            replace: false,
                                                            autoClose: 10000,
                                                            group: "tlsWizard",
                                                        });
                                                        CertificatesService.install_certificate(providerPEM, [domain]).then(
                                                            function yay() {
                                                                alertService.add({
                                                                    type: "success",
                                                                    message: LOCALE.maketext("The system installed the certificate onto the website “[_1]”.", _.escape(vhostName)),
                                                                    closeable: true,
                                                                    replace: false,
                                                                    autoClose: 10000,
                                                                    group: "tlsWizard",
                                                                });
                                                            },
                                                            function nay(errorHTML) {
                                                                alertService.add({
                                                                    type: "danger",
                                                                    message: LOCALE.maketext("The system failed to install the certificate onto the website “[_1]” because of the following error: [_2]", _.escape(vhostName), errorHTML),
                                                                    closeable: true,
                                                                    replace: false,
                                                                    group: "tlsWizard",
                                                                });
                                                            }
                                                        ).then(LocationService.go_to_last_create_route);
                                                    }
                                                }

                                            },
                                            function onerror(idxAndResponse) {

                                                // We’re here because we failed either
                                                // to fetch the new cert or to query
                                                // the current SSL state.

                                                var promiseI = idxAndResponse[0];
                                                var errorHTML = idxAndResponse[1];

                                                if (promiseI === 0) {
                                                    alertService.add({
                                                        type: "danger",
                                                        message: LOCALE.maketext("The system failed to locate the installed [asis,SSL] certificate for the website “[_1]” because of the following error: [_2]", _.escape(vhostName), errorHTML),
                                                        closeable: true,
                                                        replace: false,
                                                        group: "tlsWizard",
                                                    });
                                                } else if (promiseI === 1) {
                                                    alertService.add({
                                                        type: "danger",
                                                        message: LOCALE.maketext("The system failed to query “[_1]” for order item [asis,ID] “[_2]” ([_3]) because of the following error: [_4]", _.escape(step.provider), _.escape(oiid), _.escape(vhostName), errorHTML),
                                                        closeable: true,
                                                        replace: false,
                                                        group: "tlsWizard",
                                                    });
                                                } else {

                                                    // should never happen
                                                    alertService.add({
                                                        type: "danger",
                                                        message: "Unknown index: " + promiseI,
                                                        closeable: true,
                                                        replace: false,
                                                        group: "tlsWizard",
                                                    });
                                                }

                                                LocationService.go_to_last_create_route();
                                            }
                                            );
                                        });
                                    });
                                });
                            } else {
                                var errorHTML = response.error;
                                alertService.add({
                                    type: "danger",
                                    message: LOCALE.maketext("The system failed to begin polling for [quant,_2,new certificate,new certificates] because of an error: [_1]", errorHTML, $scope.certificates_count) + " " + LOCALE.maketext("You will now return to the beginning of the wizard."),
                                    closeable: true,
                                    replace: false,
                                    group: "tlsWizard",
                                });
                            }
                        });

                        // get info from local storage
                    } else {
                        if (orderStatus === "error") {
                            CertificatesService.reset();
                            CertificatesService.save();
                            $scope.return_to_wizard();
                            alertService.add({
                                type: "danger",
                                message: LOCALE.maketext("The system encountered an error as it attempted to complete your transaction.") + " " + LOCALE.maketext("You will now return to the beginning of the wizard."),
                                closeable: true,
                                replace: false,
                                group: "tlsWizard",
                            });
                        } else if (/^cancel?led$/.test(orderStatus)) { // cPStore gives two l’s
                            var orderItemIDs = [];
                            angular.forEach(order.certificates, function(cert) {
                                orderItemIDs.push(cert.order_item_id);
                            });
                            alertService.add({
                                type: "warn",
                                message: LOCALE.maketext("You seem to have canceled your transaction.") + " " + LOCALE.maketext("You will now return to the beginning of the wizard."),
                                closeable: true,
                                replace: false,
                                group: "tlsWizard",
                            });
                            $location.url($location.path()); // clear out the params so we do not get a cancel on subsequent orders
                            CertificatesService.cancel_pending_ssl_certificates(step.provider, orderItemIDs).then(function() {

                                /* need to clear old unused in page data to get a fresh load */
                                CertificatesService.reset();
                                CertificatesService.save();
                                $scope.return_to_wizard();
                            }, function(errorHTML) {
                                alertService.add({
                                    type: "danger",
                                    message: LOCALE.maketext("The system encountered an error as it attempted to cancel your transaction: [_1]", errorHTML) + " " + LOCALE.maketext("You will now return to the beginning of the wizard."),
                                    closeable: true,
                                    replace: false,
                                    group: "tlsWizard",
                                });
                            });
                        }
                        return false;
                    }
                } else if (step.step === "checkout_complete") {

                    // go next step or to done page
                    if (!nextStep) {
                        CertificatesService.reset();
                        CertificatesService.save();

                        // done
                        alertService.add({
                            type: "success",
                            message: LOCALE.maketext("The system has completed the [numerate,_1,purchase,purchases] and will begin to poll for your [numerate,_2,certificate,certificates].", $scope.providers.length, $scope.certificates_count),
                            closeable: true,
                            replace: false,
                            autoClose: 10000,
                            group: "tlsWizard",
                        });
                        $timeout($scope.go_to_pending, 1000);
                    }
                }
            };

            $scope.return_to_wizard = function() {
                var curURL = $location.absUrl();

                // force reset for specific cases, use path redirect otherwise;
                // this allows us to not clear growl notifications if we don't have to.
                // could be replaced with replaceState if we ever get to IE11
                if ($scope.get_param("code")) {
                    var newURL = curURL.replace(/([^#?]+\/).*/, "$1#" + LocationService.last_create_route());
                    $window.location.href = newURL;
                } else {
                    LocationService.go_to_last_create_route();
                }
            };

            $scope.check_step_success = function(stepIndex) {
                if (stepIndex < $scope.current_step_index) {
                    return true;
                }
            };

            $scope.go_step = function(provider, step, params) {
                $location.path("/purchase/" + provider + "/" + step + "/");

                if (params) {
                    $location.search(params);
                }
            };

            $scope.get_providers = function() {
                $scope.providers = [];

                var steps;
                $scope.purchasing_certs.forEach(function(cert) {
                    var product = cert.get_product();
                    var provider = $scope.get_provider_by_name(product.provider);
                    if (!provider) {
                        provider = {
                            name: product.provider,
                            display_name: product.provider_display_name || product.provider,
                            certificates: [],
                        };
                        $scope.providers.push(provider);
                        steps = $scope.get_steps(provider.name);
                        angular.forEach(steps, function(step) {
                            $scope.steps.push({
                                provider: provider.name,
                                step: step,
                            });
                        });
                    }
                    provider.certificates.push(cert);
                    $scope.certificates_count++;
                });

                return $scope.providers;
            };

            $scope.go_to_pending = function(orderItemID) {
                if (orderItemID) {
                    $location.path("/pending-certificates/").search("orderItemID", orderItemID);
                } else {
                    $location.path("/pending-certificates");
                }
            };

            $scope.pending_certificate = function(virtualHost) {
                var result = false;
                angular.forEach($scope.pending_certificates, function(pcert) {
                    angular.forEach(pcert.vhost_names, function(vhostName) {
                        if (vhostName === virtualHost.display_name) {
                            result = pcert.order_item_id;
                        }
                    });
                });
                return result;
            };

            $scope.view_pending_certificate = function(virtualHost) {
                var orderItemID = $scope.pending_certificate(virtualHost);
                $scope.go_to_pending(orderItemID);
            };

            $scope.begin = function() {

                // Only the “Simple” screen populates this.
                $scope.purchasing_certs = CertificatesService.get_purchasing_certs();

                if ($scope.purchasing_certs.length === 0) {

                    // The “Advanced” screen goes here, as does a resumed checkout.
                    CertificatesService.get_virtual_hosts().filter( function(vhost) {
                        if (!vhost.has_selected_domains()) {
                            return false;
                        }
                        var product = vhost.get_product();
                        if (!product) {
                            $log.warn("has selected, but no product?");
                            return false;
                        }
                        if (!CertificatesService.get_product_by_id(product.provider, product.id)) {
                            $log.warn("Unknown product!", product);
                            return false;
                        }
                        return true;
                    }).forEach(function(virtualHost) {
                        var product = virtualHost.get_product();
                        var cert = new Certificate();
                        cert.set_product(product);
                        cert.set_price(virtualHost.get_price());
                        cert.set_domains(virtualHost.get_selected_domains());
                        cert.set_virtual_hosts([virtualHost.display_name]);

                        if (product.x_identity_verification) {
                            var idVer = virtualHost.get_identity_verification();

                            // It’s ok if we don’t have the idver because
                            // that means we’re resuming a checkout, which
                            // means that the idver is already sent in, and
                            // the only reason we’re assembling cert/vhost/etc.
                            // is so that the controller can quantify the
                            // domains propertly in localization.
                            if (idVer) {
                                cert.set_identity_verification(idVer);
                            }
                        }

                        CertificatesService.add_new_certificate(cert);
                    });

                    $scope.purchasing_certs = CertificatesService.get_purchasing_certs();
                }

                $scope.get_providers();
                $scope.current_provider_name = $routeParams.provider;
                $scope.current_step_id = $routeParams.step;
                $scope.current_step_index = $scope.get_step_index($scope.current_provider_name, $scope.current_step_id);

                $scope.do_current_step();
                $timeout(function() {
                    _resizedWindow();
                }, 1);
            };

            $scope.init = function() {
                CertificatesService.restore();
                $scope.begin();
            };

            function _resizedWindow() {
                $(".checkout-step-inner").each(function(index, block) {
                    block = $(block);
                    var wrapper = block.find(".content-wrapper");
                    var padding = (block.height() - wrapper.height()) / 2;
                    wrapper.css("padding-top", padding);
                });
            }

            var window = angular.element($window);
            window.bind("resize", _resizedWindow);

            $scope.init();
        }

        app.controller("CheckoutController", [
            "$scope",
            "$controller",
            "$location",
            "$filter",
            "$routeParams",
            "$window",
            "$timeout",
            "CertificatesService",
            "spinnerAPI",
            "$q",
            "$uibModal",
            "$log",
            "Certificate",
            "LocationService",
            "alertService",
            CheckoutController]);
    }
);
