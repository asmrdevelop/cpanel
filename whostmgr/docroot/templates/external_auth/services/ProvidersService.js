/*
# templates/external_auth/services/ProvidersService.js   Copyright 2022 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

// Then load the application dependencies
define(
    [
        "angular",
        "lodash",
        "cjt/core",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/decorators/growlDecorator",
        "cjt/modules",
    ],
    function(angular, _, CJT, PARSE, API, APIREQUEST) {
        "use strict";

        var app = angular.module("App");

        function ProvidersServiceFactory($q, growl) {
            var providers = [];
            var ProvidersService = {};

            function _build_batch_command(call, params) {
                var command_str = call;

                if (params) {
                    var command_params = [];
                    angular.forEach(params, function(value, key) {
                        command_params.push(key + "=" + encodeURIComponent(value));
                    });

                    command_str += "?" + command_params.join("&");
                }

                return command_str;
            }

            ProvidersService.get_providers = function() {
                return providers;
            };
            ProvidersService.get_enabled_providers = function(service) {
                var enabled_providers = [];
                angular.forEach(providers, function(provider) {
                    if (provider[service + "_enabled"]) {
                        enabled_providers.push(provider);
                    }
                });
                return enabled_providers;
            };

            ProvidersService.fetch_providers = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_available_authentication_providers");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                deferred.promise.then(function(result) {
                    providers = [];
                    angular.forEach(result.data, function(provider) {
                        provider = angular.extend(provider, {
                            enable: function(service) {
                                return ProvidersService.enable_provider(service, provider).then(function() {
                                    growl.success(LOCALE.maketext("The system has successfully enabled the “[_1]” provider in “[_2]”.", provider.display_name, service));
                                }, function(error) {
                                    growl.error(LOCALE.maketext("The system could not enable the “[_1]” provider in “[_2]”. The following error occurred: [_3]", provider.display_name, service, error));
                                });
                            },
                            disable: function(service) {
                                return ProvidersService.disable_provider(service, provider).then(function() {
                                    growl.success(LOCALE.maketext("The system has successfully disabled the “[_1]” provider in “[_2]”.", provider.display_name, service));
                                }, function(error) {
                                    growl.error(LOCALE.maketext("The system could not disable the “[_1]” provider in “[_2]”. The following error occurred: [_3]", provider.display_name, service, error));
                                });
                            },
                            toggle_status: function(service) {
                                return provider[service + "_enabled"] ? provider.disable(service) : provider.enable(service);
                            }
                        });
                        this.push(provider);
                    }, providers);
                });

                return deferred.promise;
            };
            ProvidersService.enable_provider = function(service, item) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "enable_authentication_provider");
                apiCall.addArgument("provider_id", item.id);
                apiCall.addArgument("service_name", service);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                            item[service + "_enabled"] = true;
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };
            ProvidersService.disable_provider = function(service, item) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "disable_authentication_provider");
                apiCall.addArgument("provider_id", item.id);
                apiCall.addArgument("service_name", service);


                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                            item[service + "_enabled"] = false;
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };
            ProvidersService.set_provider_display_configurations = function(provider_id, configurations) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "set_provider_display_configurations");
                apiCall.addArgument("service_name", "cpaneld");
                apiCall.addArgument("provider_id", provider_id);
                apiCall.addArgument("configurations", JSON.stringify(configurations));

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };
            ProvidersService.set_provider_client_configurations = function(provider_id, configurations) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "set_provider_client_configurations");
                apiCall.addArgument("service_name", "cpaneld");
                apiCall.addArgument("provider_id", provider_id);
                apiCall.addArgument("configurations", JSON.stringify(configurations));

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };
            ProvidersService.get_provider_client_configurations = function(provider_id) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_provider_client_configurations");
                apiCall.addArgument("provider_id", provider_id);
                apiCall.addArgument("service_name", "cpaneld");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });


                return deferred.promise;
            };
            ProvidersService.get_provider_configuration_fields = function(provider_id) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_provider_configuration_fields");
                apiCall.addArgument("service_name", "cpaneld");
                apiCall.addArgument("provider_id", provider_id);
                apiCall.addSorting("display_order");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };
            ProvidersService.get_provider_by_id = function(provider_id) {
                for (var i = 0; i < providers.length; i++) {
                    var provider = providers[i];
                    if (provider.id === provider_id) {
                        return provider;
                    }
                }
            };

            ProvidersService.get_provider_display_configurations = function(provider_id) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_provider_display_configurations");
                apiCall.addArgument("provider_id", provider_id);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });


                return deferred.promise;
            };

            /*
                client_configs: object of hashed keys to update
            */
            ProvidersService.save_provider_configurations = function(provider_id, client_configs, display_configs) {

                // This gets added to in the foreach loop. Format is necessary for batching.
                var params = {
                    command: []
                };

                if (display_configs) {

                    angular.forEach(display_configs, function(config) {
                        params.command.push(_build_batch_command("set_provider_display_configurations", {
                            provider_id: provider_id,
                            service_name: config.service_name,
                            configurations: JSON.stringify(config.configs)
                        }));
                    });
                }

                params.command.push(_build_batch_command("set_provider_client_configurations", {
                    provider_id: provider_id,
                    service_name: "cpaneld",
                    configurations: JSON.stringify(client_configs)
                }));

                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "batch");
                apiCall.addArgument("command", params.command);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });


                return deferred.promise;

            };

            return ProvidersService;
        }
        ProvidersServiceFactory.$inject = ["$q", "growl"];
        return app.factory("ProvidersService", ProvidersServiceFactory);
    });
