/* ***** BEGIN LICENSE BLOCK *****

# cpanel12 - interfacereset.js                  Copyright(c) 1997-2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

 * ***** END LICENSE BLOCK *****
  * ***** BEGIN APPLICABLE CODE BLOCK ***** */


var interfaceConfigs = [];

function register_interfacecfg_nvdata(nvname) {
    interfaceConfigs.push(nvname);
}

var reset_all_interface_settings = function(securityToken) {

    var sFormData = "names=" + interfaceConfigs.join("|");
    for (var i = 0; i < interfaceConfigs.length; i++) {
        sFormData += "&" + interfaceConfigs[i] + "=";
        NVData[interfaceConfigs[i]] = "";
    }

    var successFunction = function() {
        window.location.reload();
    };
    var token = securityToken || CPANEL.security_token;
    var apiUrl = token + "/frontend/" + window.thisTheme + "/nvset.xml";

    fetch(apiUrl, {
        method: "POST",
        body: sFormData,
    })
        .then(function(res) {
            successFunction();
        })
        .catch(function(error) {
            console.error("Error:", error);
        });
};

register_interfacecfg_nvdata("ignorecharencoding");
