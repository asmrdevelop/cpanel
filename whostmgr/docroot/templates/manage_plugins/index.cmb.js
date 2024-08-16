/*
# cpanel - whostmgr/docroot/templates/manage_plugins/index.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, require, PAGE */
/* jshint -W100 */
/* eslint-disable camelcase */
define(
    'app/index',[
        "lodash",
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "cjt/io/whm-v1-request",
        "cjt/io/websocket",
        "cjt/util/query",
        "cjt/util/logMetaformat",
        "cjt/util/scrollSelect",
        "cjt/io/whm-v1",  // preload
        "cjt/util/parse",
        "cjt/modules",
        "cjt/decorators/growlAPIReporter",
        "uiBootstrap",
        "cjt/services/APICatcher",
        "cjt/directives/formWaiting",
        "cjt/directives/actionButtonDirective",
    ],
    function(_, angular, LOCALE, CJT, APIREQUEST, WS, QUERY, LOG_METAFORMAT, SCROLLSELECT) {
        "use strict";

        var PKGS = PAGE.plugins;

        if (!PKGS) {
            throw "plugins";
        }

        CJT.config.html5Mode = false;

        var plugin_metadata_skel = [
            [ LOCALE.maketext("Name"), "label" ],
            [ LOCALE.maketext("Description"), "description" ],
        ];

        var additional_changes = [];

        var plugin_lookup = {};
        var plugins = PKGS.map( function(pkg) {
            var metadata = [];

            var plugin = {
                metadata: metadata,
                label: pkg.label,
                logo: pkg.logo,
                enabled: !!pkg.installed_version,
                to_enable: !!pkg.installed_version,
                pkg_name: pkg.id,
                minimum_ram: pkg.minimum_ram,
                minimum_cpus: pkg.minimum_cpus,
                installed_by: pkg.installed_by,
                should_hide: pkg.should_hide ? true : false,
            };

            for (var p = 0; p < plugin_metadata_skel.length; p++) {
                var meta_key = plugin_metadata_skel[p][1];

                var cur_md = {
                    label: plugin_metadata_skel[p][0],
                    value: pkg[meta_key],
                };

                metadata.push(cur_md);
            }

            var ver_string = pkg.version;

            // versions should always contain a dash, so they’ll all be strings
            if ( pkg.installed_version && (pkg.installed_version !== ver_string) ) {
                ver_string += " (" + LOCALE.maketext("Installed: [_1]", pkg.installed_version) + ")";
            }

            metadata.push( {
                label: LOCALE.maketext("Version"),
                value: ver_string,
            } );

            plugin_lookup[ plugin.pkg_name ] = plugin;

            if (plugin.minimum_ram && PAGE.total_memory < plugin.minimum_ram) {
                plugin.alert = LOCALE.maketext("This plugin has a recommended minimum of [format_bytes,_1] of RAM, but your server only has [format_bytes,_2]. Your server may experience performance issues while using this plugin.", plugin.minimum_ram,  PAGE.total_memory);
            }

            if (plugin.minimum_cpus && PAGE.cpus < plugin.minimum_cpus) {
                plugin.alert = LOCALE.maketext("This plugin has a recommended minimum of [quant,_1,core,cores] but your server only has [quant,_2,core,cores]. Your server may experience performance issues while using this plugin.", plugin.minimum_cpus, PAGE.cpus);
            }

            if (plugin.minimum_ram && PAGE.total_memory < plugin.minimum_ram && plugin.minimum_cpus && PAGE.cpus < plugin.minimum_cpus) {
                plugin.alert = LOCALE.maketext("This plugin has a recommended minimum of [format_bytes,_1] of RAM and [quant,_2,core,cores] but your server only has [format_bytes,_3] of RAM and [quant,_4,core,cores]. Your server may experience performance issues while using this plugin.", plugin.minimum_ram, plugin.minimum_cpus, PAGE.total_memory, PAGE.cpus);
            }

            // If a hidden plugin has an alert, show the alert on the other plugin that triggers the install
            if (plugin.should_hide && plugin.installed_by && plugin.alert) {
                additional_changes.push(
                    function(to_change) {
                        if (to_change.pkg_name === plugin.installed_by) {
                            to_change.alert = plugin.alert;
                        }
                    }
                );
            }

            return plugin;
        } ).filter( function(pkg) {
            return !pkg.should_hide;
        } );

        plugins.forEach( function(to_change) {
            additional_changes.forEach( function(change) {
                change(to_change);
            } );
        } );

        function _make_installer(pkg_name) {
            return new APIREQUEST.Class().initialize(
                null,
                "install_rpm_plugin",
                { name: pkg_name }
            );
        }

        function _make_uninstaller(pkg_name) {
            return new APIREQUEST.Class().initialize(
                null,
                "uninstall_rpm_plugin",
                { name: pkg_name }
            );
        }

        function _gtime() {
            return LOCALE.local_datetime(new Date(), "time_format_medium");
        }

        function setPluginMessage(plugin, type, content) {
            plugin.last_status_notice_type = type;
            plugin.last_status_message = _gtime() + ": " + content;
        }

        function _clear_plugin_message(plugin) {
            delete plugin.last_status_message;
            delete plugin.last_status_notice_type;
        }

        function plugin_notice_is_dismissable(plugin) {
            plugin.last_status_dismissable = (plugin.last_status_notice_type !== "danger");

            return plugin.last_status_dismissable;
        }

        var TYPE_TO_ICON = {
            success: "ok",
            info: "info",
            warning: "exclamation",
            danger: "remove",
        };

        function plugin_notice_glyphicon(plugin) {
            return TYPE_TO_ICON[ plugin.last_status_notice_type ];
        }

        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load before any of its configured services are used.
                "ui.bootstrap",
                "cjt2.whm",
                "cjt2.decorators.growlAPIReporter",
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "uiBootstrap",
                ],
                function(BOOTSTRAP) {
                    var app = angular.module("App");

                    app.value("PAGE", PAGE);

                    app.controller("BaseController", [
                        "$rootScope",
                        "$scope",
                        "$q",
                        "APICatcher",
                        "APIService",
                        function($rootScope, $scope, $q, api, api_plain) {

                            if (/debug=1/.test(location.search)) {
                                window.SCOPE = $scope;
                            }

                            $scope.plugins = plugins;
                            $scope.total_memory     = PAGE.total_memory;            // This is sent along with plugin data from manage_plugins()

                            var _plugin_in_progress = {};

                            $scope.any_plugin_in_progress = function() {
                                return !!Object.keys(_plugin_in_progress).length;
                            };

                            $scope.toggle = function(plugin) {
                                plugin.to_enable = !plugin.to_enable;

                                var maker_func = plugin.to_enable ? _make_installer : _make_uninstaller;

                                var apicall = maker_func(plugin.pkg_name);

                                _plugin_in_progress[ plugin.pkg_name ] = true;

                                // We want to defer a resolution of the promise
                                // until the streaming is done, as a result
                                // of which we can’t just use the return of
                                // api.promise.
                                return $q( function( resolver, rejector ) {
                                    api.promise(apicall).then(
                                        function(resp) {
                                            _parse_install_uninstall_response(
                                                resp,
                                                plugin,
                                                resolver,
                                                rejector
                                            );
                                        },
                                        rejector
                                    );
                                } );
                            };

                            $scope.clear_plugin_message = _clear_plugin_message;
                            $scope.plugin_notice_glyphicon = plugin_notice_glyphicon;
                            $scope.plugin_notice_is_dismissable = plugin_notice_is_dismissable;

                            function _start_log_tailer(plugin, pid, resolver, rejector) {
                                var log_entry = plugin.log_entry;

                                // This isn’t quite the same as “in_progress”:
                                // we leave “in_progress” in place on
                                // non-success status, but we always remove
                                // “tailing_log”.
                                plugin.tailing_log = true;

                                var url = WS.getUrlBase();
                                url += "/websocket/PluginLog?";
                                url += QUERY.make_query_string( { log_entry: log_entry, pid: pid } );

                                var logEl;

                                var metadata = {};

                                var labelHtml = _.escape(plugin.label);

                                var ws = new WebSocket(url);

                                ws.onerror = function(e) {
                                    setPluginMessage(plugin, "danger", LOCALE.maketext("ERROR") + " (" + labelHtml + "): " + _.escape( e.data ) );
                                    rejector();
                                };

                                ws.onmessage = function(e) {
                                    if (!logEl) {
                                        logEl = document.getElementById(plugin.pkg_name + "-log");
                                        logEl.value = "";
                                    }

                                    var isAtEnd = SCROLLSELECT.isAtEnd(logEl);

                                    logEl.value += LOG_METAFORMAT.parse(e.data, metadata);

                                    if (isAtEnd) {
                                        SCROLLSELECT.scrollToEnd(logEl);
                                    }
                                };

                                ws.onclose = function(e) {
                                    delete plugin.tailing_log;

                                    if (e.code === WS.STATUS.SERVER_ERROR) {
                                        rejector();
                                        var whyHtml = _.escape( e.reason );

                                        if (plugin.to_enable) {
                                            setPluginMessage(plugin, "warning", LOCALE.maketext("The log follower for “[_1]” indicated an internal error ([_2]).", labelHtml, whyHtml) );
                                        } else {
                                            setPluginMessage(plugin, "warning", LOCALE.maketext("The log follower for “[_1]” indicated an internal error ([_2]).", labelHtml, whyHtml) );
                                        }
                                    }
                                    if ( metadata.CHILD_ERROR && (metadata.CHILD_ERROR !== "?") ) {
                                        var chld_err = "" + metadata.CHILD_ERROR;

                                        if (chld_err === "0") {
                                            resolver();

                                            // Only a complete success
                                            // re-enables the plugin controls;
                                            // Anything less stays frozen.
                                            plugin.in_progress = false;
                                            plugin.enabled = plugin.to_enable;
                                            delete _plugin_in_progress[ plugin.pkg_name ];

                                            if (plugin.to_enable) {
                                                setPluginMessage(plugin, "success", LOCALE.maketext("“[_1]” is now installed.", labelHtml) );
                                            } else {
                                                setPluginMessage(plugin, "success", LOCALE.maketext("“[_1]” is now uninstalled.", labelHtml ) );
                                            }
                                        } else {
                                            rejector();

                                            if (plugin.to_enable) {
                                                setPluginMessage(plugin, "warning", LOCALE.maketext("The log transmission for “[_1]” included a failure status ([_2]) for the installation.", labelHtml, _.escape(chld_err) ) );
                                            } else {
                                                setPluginMessage(plugin, "warning", LOCALE.maketext("The log transmission for “[_1]” included a failure status ([_2]) for the uninstallation.", labelHtml, _.escape(chld_err) ) );
                                            }
                                        }
                                    } else {
                                        rejector();

                                        var full_log_path = "/var/cpanel/logs/plugin/" + log_entry + "/txt";
                                        if (plugin.to_enable) {
                                            setPluginMessage(plugin, "warning", LOCALE.maketext("The log transmission for “[_1]” did not include a final status for the installation. This may indicate a failure. Check “[_2]” for more information.", labelHtml, _.escape(full_log_path) ) );
                                        } else {
                                            setPluginMessage(plugin, "warning", LOCALE.maketext("The log transmission for “[_1]” did not include a final status for the uninstallation. This may indicate a failure. Check “[_2]” for more information.", labelHtml, _.escape(full_log_path) ) );
                                        }
                                    }
                                };
                            }

                            function _parse_install_uninstall_response(api, plugin, resolver, rejector) {
                                var plabel_html = _.escape(plugin.label);

                                if (api.status) {
                                    plugin.in_progress = true;

                                    // plugin.enabled = plugin.to_enable;

                                    if (plugin.to_enable) {
                                        setPluginMessage(plugin, "info", LOCALE.maketext("Installation of “[_1]” is in progress.", plabel_html));
                                    } else {
                                        setPluginMessage(plugin, "info", LOCALE.maketext("Uninstallation of “[_1]” is in progress.", plabel_html));
                                    }

                                    plugin.log_entry = api.data.log_entry;

                                    _start_log_tailer(
                                        plugin,
                                        api.data.pid,
                                        resolver,
                                        rejector
                                    );
                                } else if (plugin.to_enable) {
                                    setPluginMessage(plugin, "danger", LOCALE.maketext("The system failed to start the installation for “[_1]” because of an error: [_2]", plabel_html, _.escape(api.error) ));
                                    rejector();
                                } else {
                                    setPluginMessage(plugin, "danger", LOCALE.maketext("The system failed to start the uninstallation for “[_1]” because of an error: [_2]", plabel_html, _.escape(api.error) ));
                                    rejector();
                                }
                            }
                        },
                    ]);

                    BOOTSTRAP();

                });

            return app;
        };
    }
);

