/*
# htaccess/index.js                                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require:false, define:false, SetNvData:false, cpanel_jsonapi2:false */

define(
    [
        "jquery",
        "bootstrap"
    ], function($) {

        $("#btnSettingsSave").click(function() {
            var dirSelectionOption = $("input[name=dirselect]:checked").val();
            var domain = $("#ddlDomainSelect").val();
            var alwaysOpenDir = $("#settings_saved").is(":checked") ? "1" : "0";

            if (alwaysOpenDir === "1") {
                SetNvData("optionselect_password-protect", dirSelectionOption + ":" + domain + ":" + alwaysOpenDir, nvdataCallback);
            } else {
                if (dirSelectionOption === "webroot") {
                    reloadPage("public_html");
                } else {
                    cpanel_jsonapi2(docrootcallback, "DomainLookup", "getdocroot", "domain", domain);
                }
            }
        });

        function nvdataCallback(result) {
            if (result) {
                window.location.href = window.location.href.split("?")[0];
            }
        }

        function docrootcallback(result) {
            if (result) {
                reloadPage(result[0].docroot);
            }
        }

        function reloadPage(path) {
            var encoded_path = encodeURIComponent(path);
            window.location.href = updateQueryStringParameter(window.location.href, "dir", encoded_path);
        }

        function updateQueryStringParameter(uri, key, value) {
            var re = new RegExp("([?&])" + key + "=.*?(&|$)", "i");
            var separator = uri.indexOf("?") !== -1 ? "&" : "?";

            if (uri.match(re)) {
                return uri.replace(re, "$1" + key + "=" + value + "$2");
            } else {
                return uri + separator + key + "=" + value;
            }
        }

        $("#dirselect_webroot").change(function() {
            if ($("#dirselect_webroot").is(":checked")) {
                $("#ddlDomainSelect").prop( "disabled", true );
            } else {
                $("#ddlDomainSelect").prop( "disabled", false );
            }
        });

        $("#optionselect_domainrootselect_radio").change(function() {
            if ($("#optionselect_domainrootselect_radio").is(":checked")) {
                $("#ddlDomainSelect").prop( "disabled", false );
            } else {
                $("#ddlDomainSelect").prop( "disabled", true );
            }
        });

    });
