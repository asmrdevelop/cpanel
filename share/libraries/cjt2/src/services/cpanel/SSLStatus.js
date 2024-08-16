/*
 * cjt/services/cpanel/sslStatus.js                 Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/** @namespace cjt.services.cpanel.sslStatus */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/io/uapi-request",
        "cjt/services/APICatcher",
        "cjt/modules"
    ],
    function(angular, _, LOCALE, APIRequest, APICatcher ) {

        "use strict";

        var CERT_TYPES = {
            EV: "ev",
            OV: "ov",
            DV: "dv",
            SELF_SIGNED: "self-signed",
        };

        var SSLCertificate = function() {
            this.certificateErrors = [];
            this.hasErrors = false;
        };
        SSLCertificate.prototype.getIconClasses = function getIconClasses() {
            switch (this.validationType) {
                case CERT_TYPES.DV:
                case CERT_TYPES.OV:
                case CERT_TYPES.EV:
                    return "fas fa-lock";
                case CERT_TYPES.SELF_SIGNED:
                default:
                    return "fas fa-unlock-alt";
            }
        };

        SSLCertificate.prototype.getStatusColorClass = function getStatusColorClass() {
            if (this.hasErrors) {
                return "text-danger";
            }

            switch (this.validationType) {
                case CERT_TYPES.DV:
                case CERT_TYPES.OV:
                case CERT_TYPES.EV:
                    return "text-success";
                case CERT_TYPES.SELF_SIGNED:
                default:
                    return "text-danger";
            }
        };

        SSLCertificate.prototype.getTypeName = function getSSLCertTypeName(options) {
            var isExpanded = options && options.stripMarkup;
            switch (this.validationType) {
                case CERT_TYPES.DV:
                    return isExpanded ? LOCALE.maketext("Domain Validated Certificate") : LOCALE.maketext("[output,abbr,DV,Domain Validated] Certificate");
                case CERT_TYPES.EV:
                    return isExpanded ? LOCALE.maketext("Extended Validation Certificate") : LOCALE.maketext("[output,abbr,EV,Extended Validation] Certificate");
                case CERT_TYPES.OV:
                    return isExpanded ? LOCALE.maketext("Organization Validated Certificate") : LOCALE.maketext("[output,abbr,OV,Organization Validated] Certificate");
                case CERT_TYPES.SELF_SIGNED:
                    return LOCALE.maketext("Self-signed Certificate");
                default:
                    return LOCALE.maketext("No Valid Certificate");
            }
        };

        SSLCertificate.prototype.addError = function addError(errorMessage) {
            this.certificateErrors.push(errorMessage);
            this.hasErrors = true;
            return this.certificateErrors;
        };

        SSLCertificate.prototype.getErrors = function getErrors(errorMessage) {
            return this.certificateErrors;
        };

        var SSLCertFactory = function() {
            this.make = function(certificate) {
                var sslCert = new SSLCertificate();
                sslCert.isSelfSigned = certificate.is_self_signed && certificate.is_self_signed.toString() === "1";
                sslCert.validationType = sslCert.isSelfSigned ? CERT_TYPES.SELF_SIGNED : certificate.validation_type;
                return sslCert;
            };
        };

        var _certFactory = new SSLCertFactory();

        var MODULE_NAMESPACE = "cjt2.services.cpanel.sslStatus";
        var SERVICE_NAME = "sslStatusService";
        var MODULE_REQUIREMENTS = [ ];
        var SERVICE_INJECTABLES = ["$log", "$q", "APICatcher"];

        var SERVICE_FACTORY = function($log, $q, APICatcher) {

            /**
             * service wrapper for domain related functions
             *
             * @module sslStatusService
             *
             * @param  {Object} APICatcher cjt2 APICatcher service
             *
             * @example
             * $sslStatusService.getDomainSSLCertificate("foo.com")
             *
             */

            var Service = function() {};

            Service.prototype = Object.create(APICatcher);

            _.assign(Service.prototype, {

                _domainsChecked: {},

                /**
                 * Wrapper for building an apiCall
                 *
                 * @private
                 *
                 * @param {String} module module name to call
                 * @param {String} func api function name to call
                 * @param {Object} args key value pairs to pass to the api
                 * @returns {UAPIRequest} returns the api call
                 *
                 * @example _apiCall( "Tokens", "rename", { name:"OLDNAME", new_name:"NEWNAME" } )
                 */
                _apiCall: function _createApiCall(module, func, args) {
                    var apiCall = new APIRequest.Class();
                    apiCall.initialize(module, func, args);
                    return apiCall;
                },

                _getDomainCertificate: function _getDomainCertificate(domain) {

                    if (!this._domainSSLMap) {
                        return;
                    }

                    var sslDomains = Object.keys(this._domainSSLMap);

                    for (var i = 0; i < sslDomains.length; i++) {
                        var sslDomain = sslDomains[i];

                        // THe domain is covered by a direct match
                        if (domain === sslDomain) {
                            return this._domainSSLMap[sslDomain];
                        }

                        // The domain is covered by a wildcard match foo.bar.com matches *.bar.com
                        var wildcardDomain = domain.replace(/^[^.]+\./, "*.");
                        if (wildcardDomain === sslDomain) {
                            return this._domainSSLMap[sslDomain];
                        }
                    }

                    // Return an "unsecured" certificate
                    var certificate =  _certFactory.make({});
                    certificate.addError(LOCALE.maketext("You have no valid [asis,SSL] certificate configured for this domain."));
                    return certificate;
                },

                _parseInstalledHost: function _parseInstalledHost(installedHost, retainInvalidCerts) {
                    var self = this;

                    if (!self._domainSSLMap) {
                        self._domainSSLMap = {};
                    }

                    var now = new Date();
                    now = now.getTime() / 1000;

                    if (!installedHost.certificate) {
                        $log.debug("Skipping installed host for lack of a certificate.", installedHost);
                        return;
                    }

                    var certificate = _certFactory.make(installedHost.certificate);

                    if (installedHost.verify_error) {
                        $log.debug("Certificate did not pass SSL Verification.", installedHost);
                        certificate.addError(_.escape(installedHost.verify_error));
                    }

                    var notValidAfter = parseInt(installedHost.certificate.not_after, 10);

                    if (notValidAfter < now) {
                        $log.debug("The certificate has expired.", installedHost);
                        certificate.addError(LOCALE.maketext("The certificate has expired."));
                    }

                    if (!retainInvalidCerts && certificate.hasErrors) {
                        $log.debug("Skipping certificate because of errors.");
                        return;
                    }

                    var domains = installedHost.certificate.domains || [];
                    domains.forEach(function(domain) {
                        self._domainSSLMap[domain] = certificate;
                    });
                },

                /**
                 * API Wrapper call to fetch installed hosts for the current user
                 *
                 * @method getValidSSLCertificates
                 *
                 * @param  {String} user username to use to check the domain status, this is required, but only used by WHM
                 *
                 * @return {Promise<Object>} returns the promise that returns a domain object map of ssl certs
                 *
                 */
                getValidSSLCertificates: function getValidSSLCertificates() {
                    var self = this;

                    if (self._domainSSLMap) {
                        return $q.resolve(self._domainSSLMap);
                    }

                    var apiCall = self._apiCall("SSL", "installed_hosts");

                    $log.debug("getValidSSLCertificates");

                    self._domainSSLMap = {};

                    return self._promise(apiCall).then(function(result) {
                        var data = result.data || [];

                        data.forEach(self._parseInstalledHost.bind(self), self);

                        return self._domainSSLMap;
                    });

                },

                /**
                 * API Wrapper call to get the SSL Status of a single domain
                 *
                 * @method getDomainSSLCertificate
                 *
                 * @param  {String} user username to use to check the domain status
                 * @param  {String} domain domain name to get the ssl status of
                 *
                 * @return {Promise<String>} returns the promise that returns the ssl status string
                 *
                 */
                getDomainSSLCertificate: function getDomainSSLCertificate(domain, includeInvalid) {
                    var self = this;

                    $log.debug("getDomainSSLCertificate", domain);

                    if (self._domainsChecked[domain]) {
                        return self._getDomainCertificate(domain);
                    }

                    var apiCall = self._apiCall("SSL", "installed_host", {
                        domain: domain,
                        verify_certificate: 1
                    });

                    return self._promise(apiCall).then(function(result) {

                        // Mark it checked
                        self._domainsChecked[domain] = true;

                        var data = result.data || {};
                        self._parseInstalledHost.call(self, data, includeInvalid);

                        return self._getDomainCertificate(domain);
                    });
                },

                /**
                 * Wrapper for .promise method from APICatcher
                 *
                 * @param {Object} apiCall api call to pass to .promise
                 * @returns {Promise}
                 *
                 * @example $service._promise( $service._apiCall( "Tokens", "rename", { name:"OLDNAME", new_name:"NEWNAME" } ) );
                 */
                _promise: function _promise() {

                    // Because nested inheritence is annoying
                    return APICatcher.promise.apply(this, arguments);
                }

            });

            return new Service();
        };


        var module = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);

        SERVICE_INJECTABLES.push(SERVICE_FACTORY);

        module.factory(SERVICE_NAME, SERVICE_INJECTABLES );

        return {
            "class": SERVICE_FACTORY,
            "serviceName": SERVICE_NAME,
            "namespace": MODULE_NAMESPACE,
            CERT_TYPES: CERT_TYPES,
            _certFactory: _certFactory,
            SSLCertificateClass: SSLCertificate
        };
    }
);
