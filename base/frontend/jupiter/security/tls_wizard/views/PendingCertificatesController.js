/*
 * base/frontend/jupiter/security/tls_wizard/views/PendingCertificatesController.js
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
        "cjt/util/locale",
        "app/views/Certificate",
        "cjt/modules",
        "cjt/directives/spinnerDirective",
        "app/services/CertificatesService",
        "app/services/LocationService",
        "cjt/directives/actionButtonDirective",
    ],
    function(_, angular, LOCALE) {
        "use strict";

        var app = angular.module("App");

        function PendingCertificatesController(
            $scope,
            $location,
            $routeParams,
            $anchorScroll,
            $timeout,
            $window,
            CertificatesService,
            LocationService,
            Certificate,
            alertService
        ) {

            var providerDisplayName = {};
            CPANEL.PAGE.products.forEach(function(p) {
                providerDisplayName[p.provider] = p.provider_display_name;
            });

            $scope.show_introduction_block = CertificatesService.show_introduction_block;

            $scope.get_provider_display_name = function(provider) {
                return providerDisplayName[provider] || provider;
            };

            $scope.html_escape = _.escape;

            $scope.get_time = function() {
                return parseInt(Date.now() / 1000, 10);
            };

            $scope.LOCALE = LOCALE;

            $scope.checking_pending_queue = false;

            // Needed pending fix of CPANEL-4645
            $scope.cjt1_LOCALE = window.LOCALE;

            $scope.pending_certificates = CertificatesService.get_pending_certificates();
            $scope.expanded_cert = null;

            $scope.get_product_by_id = function(providerName, providerID) {
                return CertificatesService.get_product_by_id(providerName, providerID);
            };

            $scope.get_cert_title = function(cert) {
                var sortedDomains = cert.domains.sort(function(a, b) {
                    if (a.length === b.length) {
                        return 0;
                    }
                    return a.length > b.length ? 1 : -1;
                });

                if (sortedDomains.length === 1) {
                    return sortedDomains[0];
                } else {
                    return LOCALE.maketext("“[_1]” and [quant,_2,other domain,other domains]", sortedDomains[0], sortedDomains.length - 1);
                }

            };

            $scope.check_pending_queue = function() {
                return CertificatesService.process_ssl_pending_queue().then(function(result) {

                    // ----------------------------------------
                    // The intent here is to show at least one notification, always:
                    //
                    //  - notify (info) for each canceled cert
                    //
                    //  - notify (success) for each installed cert
                    //
                    //  - If we canceled nor installed any certificates,
                    //    notify (info) about no-op.
                    // ----------------------------------------

                    var installed = [];
                    var deletedCount = 0;

                    result.data.forEach(function(oi) {
                        deletedCount += (1 * oi.deleted);

                        if (oi.installed) {
                            installed.push(oi);
                        } else {
                            var msg, alertType;

                            var domains = oi.domains;

                            var providerDisplayName = $scope.get_provider_display_name(oi.provider);
                            var providerNameHtml = _.escape(providerDisplayName);
                            var domain0Html = _.escape(domains[0]);
                            var xtraDomainsCount = domains.length - 1;

                            /* jshint indent: false */
                            switch (oi.last_status_code) {
                                case "OrderCanceled":
                                case "OrderItemCanceled":
                                    alertType = "info";

                                    if (xtraDomainsCount) {
                                        msg = LOCALE.maketext("“[_1]” reports that the certificate for “[_2]” and [quant,_3,other domain,other domains] has been canceled.", providerNameHtml, domain0Html, xtraDomainsCount);
                                    } else {
                                        msg = LOCALE.maketext("“[_1]” reports that the certificate for “[_2]” has been canceled.", providerNameHtml, domain0Html);
                                    }

                                    break;

                                case "CA:revoked":
                                    alertType = "danger";

                                    if (xtraDomainsCount) {
                                        msg = LOCALE.maketext("“[_1]” reports that the certificate authority issued but then revoked the certificate for “[_2]” and [quant,_3,other domain,other domains].", providerNameHtml, domain0Html, xtraDomainsCount);
                                    } else {
                                        msg = LOCALE.maketext("“[_1]” reports that the certificate authority issued but then revoked “[_2]”’s certificate.", providerNameHtml, domain0Html);
                                    }

                                    break;

                                case "CA:rejected":
                                    alertType = "danger";

                                    if (xtraDomainsCount) {
                                        msg = LOCALE.maketext("“[_1]” reports that the certificate authority rejected the request for a certificate for “[_2]” and [quant,_3,other domain,other domains].", providerNameHtml, domain0Html, xtraDomainsCount);
                                    } else {
                                        msg = LOCALE.maketext("“[_1]” reports that the certificate authority rejected the request for a certificate for “[_2]”.", providerNameHtml, domain0Html);
                                    }
                            }
                            /* jshint indent: 4 */

                            if (oi.last_status_message) {
                                msg += " (" + _.escape(oi.last_status_message) + ")";
                            }

                            alertService.add({
                                type: alertType,
                                message: msg,
                                closeable: true,
                                replace: false,
                                group: "tlsWizard",
                            });
                        }
                    });

                    if (installed.length) {
                        var vhosts = [];

                        angular.forEach(installed, function(orderItem) {
                            vhosts = vhosts.concat(orderItem.vhost_names);
                        });
                        alertService.add({
                            type: "success",
                            message: LOCALE.maketext("[numerate,_2,A certificate,Certificates] for the following [numerate,_2,website was,websites were] available, and the system has installed [numerate,_2,it,them]: [list_and_quoted,_1]", vhosts, installed.length),
                            closeable: true,
                            replace: false,
                            autoClose: 10000,
                            group: "tlsWizard",
                        });
                    } else if (!deletedCount) {

                        // We mentioned canceled and installed certificates earlier.
                        alertService.add({
                            type: "info",
                            message: LOCALE.maketext("The system processed the pending certificate queue successfully, but [numerate,_1,your pending certificate was not,none of your pending certificates were] available.", result.data.length),
                            closeable: true,
                            replace: false,
                            group: "tlsWizard",
                        });
                    }

                    return CertificatesService.fetch_pending_certificates().then(function() {
                        $scope.pending_certificates = CertificatesService.get_pending_certificates();
                        if ($scope.pending_certificates.length === 0) {
                            alertService.add({
                                type: "info",
                                message: LOCALE.maketext("You have no more pending [asis,SSL] certificates.") + " " + LOCALE.maketext("You will now return to the beginning of the wizard."),
                                closeable: true,
                                replace: false,
                                group: "tlsWizard",
                            });
                            CertificatesService.reset();

                            /* clear page-loaded domains and installed hosts to ensure we show the latests when we redirect to the purchase wizard */
                            CPANEL.PAGE.installed_hosts = null;
                            CPANEL.PAGE.domains = null;
                            $scope.get_new_certs();
                        } else {
                            $scope.prepare_pending_certificates();

                            // If one is expanded, recheck the details of it
                            if ($scope.expanded_cert) {
                                angular.forEach($scope.pending_certificates, function(cert) {
                                    if (cert.order_item_id === $scope.expanded_cert) {
                                        $scope.load_certificate_details(cert);
                                    }
                                });
                            }
                        }
                    });
                });

            };

            $scope.reset_and_create = function() {
                CertificatesService.hard_reset();
                $scope.get_new_certs();
            };

            $scope.get_new_certs = function() {
                LocationService.go_to_last_create_route().search("");
            };

            $scope.cancel_purchase = function(cert) {
                CertificatesService.cancel_pending_ssl_certificate_and_poll(cert.provider, cert.order_item_id).then(function(response) {
                    var payload = response.data[1].parsedResponse.data;

                    var certificatePEM = payload.certificate_pem;

                    var providerHTML = _.escape($scope.get_provider_display_name(cert.provider));

                    if (certificatePEM) {
                        alertService.add({
                            type: "info",
                            message: LOCALE.maketext("You have canceled this order, but “[_1]” already issued the certificate. The system will now install it. ([output,url,_2,Do you need help with this order?])", providerHTML, cert.support_uri),
                            closeable: true,
                            replace: false,
                            group: "tlsWizard",
                        });
                        CertificatesService.install_certificate(
                            certificatePEM,
                            cert.vhost_names
                        ).then(
                            function() {
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("The system has installed the new [asis,SSL] certificate on to the [numerate,_1,website,websites] [list_and_quoted,_2].", cert.vhost_names.length, cert.vhost_names),
                                    closeable: true,
                                    replace: false,
                                    autoClose: 10000,
                                    group: "tlsWizard",
                                });
                            },
                            function(errorHTML) {
                                alertService.add({
                                    type: "danger",
                                    message: LOCALE.maketext("The system failed to install the new [asis,SSL] certificate because of an error: [_1]", errorHTML),
                                    group: "tlsWizard",
                                });
                            }
                        );
                    } else if (payload.status_code === "RequiresApproval") {
                        alertService.add({
                            type: "info",
                            message: LOCALE.maketext("The system has canceled the request for this certificate; however, “[_1]” was already waiting on approval before processing your order. To ensure that this certificate order is canceled, you must [output,url,_2,contact support directly].", providerHTML, cert.support_uri),
                            closeable: true,
                            replace: false,
                            group: "tlsWizard",
                        });
                    } else if (payload.status_code === "OrderCanceled") {
                        alertService.add({
                            type: "info",
                            message: LOCALE.maketext("This certificate’s order (ID “[_1]”) was already canceled directly via “[_2]”.", _.escape(cert.order_id), providerHTML),
                            closeable: true,
                            replace: false,
                            group: "tlsWizard",
                        });
                    } else if (payload.status_code === "OrderItemCanceled") {
                        alertService.add({
                            type: "info",
                            message: LOCALE.maketext("This certificate (order item ID “[_1]”) was already canceled directly via “[_2]”.", _.escape(cert.order_item_id), providerHTML),
                            closeable: true,
                            replace: false,
                            group: "tlsWizard",
                        });
                    } else {
                        alertService.add({
                            type: "success",
                            message: LOCALE.maketext("The system has canceled this certificate. Your credit card should not be charged for this order."),
                            closeable: true,
                            replace: false,
                            autoClose: 10000,
                            group: "tlsWizard",
                        });
                    }

                    CPANEL.PAGE.pending_certificates = null;
                    return CertificatesService.fetch_pending_certificates().then(function() {

                        /* refresh existing list */
                        $scope.pending_certificates = CertificatesService.get_pending_certificates();
                        if ($scope.pending_certificates.length === 0) {
                            $scope.get_new_certs();
                        } else {
                            $scope.prepare_pending_certificates();
                        }
                    }, function(errorHTML) {
                        alertService.add({
                            type: "danger",
                            message: LOCALE.maketext("The system encountered an error as it attempted to refresh your pending certificates: [_1]", errorHTML),
                            group: "tlsWizard",
                        });
                    });
                }, function(errorHTML) {
                    alertService.add({
                        type: "danger",
                        message: LOCALE.maketext("The system encountered an error as it attempted to cancel your transaction: [_1]", errorHTML),
                        group: "tlsWizard",
                    });
                });
            };

            var _addOrderDetailsToDisplayedDomain = function(certificate, displayedDomain) {
                if (!certificate.domainDetails) {
                    return;
                }
                displayedDomain.orderDetails = certificate.domainDetails[displayedDomain.domain];
            };

            $scope.get_displayed_domains = function(pcert) {
                var domains = pcert.domains;

                var start = pcert.display_meta.items_per_page * (pcert.display_meta.current_page - 1);
                var limit = Math.min(domains.length, start + pcert.display_meta.items_per_page);

                // Domains displayed are the same domains that will be displayed.
                if (pcert.displayed_domains && pcert.display_meta.start === start && pcert.display_meta.limit === limit && pcert.displayed_domains.length) {
                    return pcert.displayed_domains;
                }

                pcert.display_meta.start = start;
                pcert.display_meta.limit = limit;

                var displayDomains = [];
                for (var i = pcert.display_meta.start; i < pcert.display_meta.limit; i++) {
                    var domainObject = {
                        domain: domains[i],
                    };
                    _addOrderDetailsToDisplayedDomain(pcert, domainObject);
                    displayDomains.push(domainObject);
                }

                pcert.displayed_domains = displayDomains;
                return pcert.displayed_domains;
            };

            function _getStringForStatusCode(statusCode, provider) {
                var str;

                if (statusCode === "RequiresApproval") {
                    var providerDisplayName = $scope.get_providerDisplayName(provider);
                    str = LOCALE.maketext("Waiting for “[_1]” to approve your order …", providerDisplayName);
                }

                return str;
            }

            $scope.get_cert_status = function(pendingCertificate) {
                var statusCodeStr = _getStringForStatusCode(pendingCertificate.last_status_code, pendingCertificate.provider);

                if (statusCodeStr) {
                    return statusCodeStr;
                }

                var status = pendingCertificate.status;
                if (status === "unconfirmed") {
                    return LOCALE.maketext("Pending Completion of Payment");
                } else if (status === "confirmed") {
                    if (pendingCertificate.statusDetails && pendingCertificate.statusDetails.loaded) {
                        var incompleteThings = pendingCertificate.statusDetails.details.filter(function(item) {
                            if (item.rawStatus === "not-completed") {
                                return true;
                            }

                            return false;
                        });
                        if (incompleteThings.length === 0) {
                            return LOCALE.maketext("Payment Completed.") + " " + LOCALE.maketext("Awaiting Validation …");
                        } else if (incompleteThings.length === 1) {
                            return LOCALE.maketext("Payment Completed.") + " " + incompleteThings[0].status;
                        } else {
                            return LOCALE.maketext("Payment Completed.") + " " + LOCALE.maketext("Multiple validation items pending …");
                        }
                    } else {
                        return LOCALE.maketext("Payment Completed.") + " " + LOCALE.maketext("Waiting for the provider to issue the certificate …");
                    }
                } else {
                    return LOCALE.maketext("Status Unknown");
                }
            };

            $scope.toggle_cert_collapse = function(cert) {
                if ($scope.expanded_cert === cert.order_item_id) {
                    $scope.collapse_cert(cert);
                } else {
                    $scope.expand_cert(cert);
                }
            };

            $scope.expand_cert = function(cert) {
                $location.search("orderItemID", cert.order_item_id);
                $scope.expanded_cert = cert.order_item_id;
                if (!cert.statusDetails) {
                    $scope.load_certificate_details(cert);
                }
                $anchorScroll($scope.expanded_cert);
            };

            $scope.load_certificate_details = function(certificate) {

                certificate.domainDetails = {};
                certificate.statusDetails = { loaded: false, loading: true, details: [] };

                function _succeed(details) {
                    certificate.statusDetails.loaded = true;
                    certificate.statusDetails.details = details.statusDetails;
                    certificate.domainDetails = {};

                    angular.forEach(certificate.statusDetails.details, function(detail) {
                        if (detail.rawStatus === "completed") {
                            detail.rowStatusClass = "success";

                            // Unset the url for completed things so we don't  get a button
                            delete detail.actionURL;
                        } else {
                            detail.rowStatusClass = "warning";
                        }
                    });

                    angular.forEach(certificate.domains, function(domain) {

                        var status = details.domainDetails[domain];

                        if (status) {
                            certificate.hasDomainDetails = true;
                        }

                        certificate.domainDetails[domain] = {};

                        if (status === "NOTVALIDATED") {
                            certificate.domainDetails[domain].rowStatusClass = "warning";
                            certificate.domainDetails[domain].rowStatusLabel = LOCALE.maketext("Not Validated");
                            certificate.domainDetails[domain].domainDetailDescription = LOCALE.maketext("The [output,abbr,CA,Certificate Authority] received the request but has not yet performed a [output,abbr,DCV,Domain Control Validation] check.");
                        } else if (status === "VALIDATED") {
                            certificate.domainDetails[domain].rowStatusClass = "success";
                            certificate.domainDetails[domain].rowStatusLabel = LOCALE.maketext("Validated");
                            certificate.domainDetails[domain].domainDetailDescription = LOCALE.maketext("The [output,abbr,CA,Certificate Authority] validated the certificate.");

                        } else if (status === "AWAITINGBRANDING") {
                            certificate.domainDetails[domain].rowStatusClass = "info";
                            certificate.domainDetails[domain].rowStatusLabel = LOCALE.maketext("Awaiting Branding …");
                            certificate.domainDetails[domain].domainDetailDescription = LOCALE.maketext("The [output,abbr,CA,Certificate Authority] received the request and must now process the brand verification approval.");
                        } else {
                            certificate.domainDetails[domain].rowStatusClass = "info";
                            certificate.domainDetails[domain].rowStatusLabel = LOCALE.maketext("Unknown");
                            certificate.domainDetails[domain].domainDetailDescription = LOCALE.maketext("Unknown.");
                        }

                    });


                    // Manually add details to currently displayed domain (since it's cached)
                    angular.forEach(certificate.displayed_domains, function(displayedDomain) {
                        _addOrderDetailsToDisplayedDomain(certificate, displayedDomain);
                    });
                }

                function _finally() {
                    certificate.statusDetails.loading = false;
                }

                CertificatesService.getCertificateStatusDetails(certificate.provider, certificate.order_item_id).then(_succeed).finally(_finally);
            };

            $scope.collapse_cert = function() {
                $location.search();
                $scope.expanded_cert = null;
            };

            $scope.continue_purchase = function(pcert) {
                var domains = CertificatesService.get_all_domains();

                // Ensure no other purchasing certs exist
                CertificatesService.reset_purchasing_certificates();

                // rebuild purchasing certificate
                var cert = new Certificate();
                var certificateDomains = [];
                var certificateProduct = CertificatesService.get_product_by_id(pcert.provider, pcert.product_id);
                var totalPrice = 0;

                cert.set_domains(certificateDomains);
                cert.set_virtual_hosts(pcert.vhost_names);
                cert.set_product(certificateProduct);

                angular.forEach(pcert.domains, function(certificateDomain) {
                    angular.forEach(domains, function(domain) {
                        if (domain.domain === certificateDomain) {
                            certificateDomains.push(domain);
                            totalPrice += domain.is_wildcard ? certificateProduct.wildcard_price : certificateProduct.price;
                        }
                    });
                });

                cert.set_price(totalPrice);

                CertificatesService.add_new_certificate(cert);

                // Removes purchasing certificates that might be saved in local storage.
                // These don't reappear until returning from logging in.
                CertificatesService.save();

                //
                $location.path("/purchase/" + pcert.provider + "/login/").search({
                    order_id: pcert.order_id,
                });
            };

            $scope.rebuild_local_storage = function() {

                // Repair Orders
                var orders = {};
                var domains = CertificatesService.get_all_domains();
                var virtualHosts = CertificatesService.get_virtual_hosts();

                angular.forEach($scope.pending_certificates, function(orderItem) {

                    // build new order
                    orders[orderItem.order_id] = orders[orderItem.order_id] || {
                        access_token: "",
                        certificates: [],
                        order_id: orderItem.order_id,
                        checkout_url: orderItem.checkout_url,
                    };
                    orders[orderItem.order_id].certificates.push(orderItem);

                    // re select the domains
                    angular.forEach(orderItem.domains, function(certificateDomain) {
                        angular.forEach(domains, function(domain) {
                            if (domain.domain === certificateDomain) {
                                domain.selected = true;
                            }
                        });
                    });

                    // re select a product
                    angular.forEach(orderItem.vhost_names, function(vHostName) {
                        var vHostID = CertificatesService.get_virtual_host_by_display_name(vHostName);
                        var vhost = virtualHosts[vHostID];
                        var product = CertificatesService.get_product_by_id(
                            orderItem.provider,
                            orderItem.product_id
                        );

                        /* in case someone deletes the vhost while the certificate is pending */
                        if (vhost) {
                            vhost.set_product(product);
                        }
                    });

                });

                // add each new order
                angular.forEach(orders, function(order) {
                    CertificatesService.add_order(order);
                });

                // Then Save
                CertificatesService.save();
            };

            $scope.restore_orders = function() {

                // Rebuild to prevent doubling up
                CertificatesService.clear_stored_settings();

                /*  add in missing orders
                    we need to always do this in case a
                    localStorage exists that doesn't
                    contain *this* set of orders */
                var fetRet = CertificatesService.fetch_domains();
                if (_.isFunction(fetRet["finally"])) {
                    fetRet.then($scope.rebuild_local_storage);
                } else if (fetRet) {
                    $scope.rebuild_local_storage();
                }
            };

            $scope.prepare_pending_certificates = function() {
                $scope.pending_certificates.forEach(function(cert) {
                    cert.support_uri_is_http = /^http/.test(cert.support_uri);

                    cert.display_meta = cert.display_meta || {
                        items_per_page: 10,
                        current_page: 1,
                    };
                });
            };

            $scope.init = function() {
                $scope.restore_orders();
                $scope.prepare_pending_certificates();

                if ($routeParams.orderItemID) {
                    $scope.expanded_cert = $routeParams.orderItemID;
                    angular.forEach($scope.pending_certificates, function(cert) {
                        if (cert.order_item_id === $scope.expanded_cert) {
                            $scope.load_certificate_details(cert);
                        }
                    });
                    $timeout(function() {
                        $anchorScroll($scope.expanded_cert);
                    }, 500);
                }
            };

            $scope.init();
        }

        app.controller(
            "PendingCertificatesController",
            [
                "$scope",
                "$location",
                "$routeParams",
                "$anchorScroll",
                "$timeout",
                "$window",
                "CertificatesService",
                "LocationService",
                "Certificate",
                "alertService",
                PendingCertificatesController,
            ]
        );

    }
);
