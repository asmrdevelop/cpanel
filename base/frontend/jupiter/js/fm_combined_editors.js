String.prototype.normalize_charset = function() {
    return this.toLowerCase().replace(/[_,.-]/, "");
};

function check_for_encoding_change(template, data) {
    var saved_charset = data[0].charset;
    if (saved_charset.normalize_charset() !== CHARSET.normalize_charset()) {
        var message = YAHOO.lang.substitute(
            template, {
                old_charset: CHARSET.toUpperCase(),
                new_charset: saved_charset.toUpperCase(),
            }
        );

        var enc_dialog = new CPANEL.ajax.Common_Dialog("enc_changed", {
            width: "500px",
            show_status: true,
            status_html: LEXICON.reloading,
        });

        enc_dialog.cfg.getProperty("buttons")[0].text = LOCALE.maketext("OK");

        // Omit the cancel button
        enc_dialog.cfg.getProperty("buttons").pop();

        DOM.addClass(enc_dialog.element, "cjt_notice_dialog cjt_info_dialog");

        enc_dialog.setHeader("<div class='lt'></div><span>" + LEXICON.charset_changed + "</span><div class='rt'></div>");

        enc_dialog.renderEvent.subscribe(function() {
            this.form.innerHTML = message;
            this.center();
        });

        enc_dialog.submitEvent.subscribe(function() {

            // so we catch file_charset as well as charset, the_charset, etc.
            var new_url = location.href.replace(/([^&?]*charset)=[^&]*/g, "$1=" + saved_charset);
            location.href = new_url;
        });

        this.fade_to(enc_dialog)[0].onComplete.subscribe(this.hide, this, true);

        return false;
    }
}

function check_file_edits() {
    var result = {
        isFileModified: false,
        changedContent: "",
    };

    if (USE_LEGACY_EDITOR) {
        result.changedContent = editAreaLoader.getValue(editAreaEl);
    } else {
        result.changedContent = ace_editor.getSession().getValue();
    }
    result.isFileModified = ( result.changedContent !== savedContent ) ? true : false;
    return result;
}

function confirm_close(clicked_el) {
    var res = check_file_edits();
    var isFileEdited = res.isFileModified;

    if (isFileEdited) {
        var confirmed = confirm(LEXICON.confirm_close);
        if (!confirmed) {
            return;
        } else {
            window.close();
        }
    }
    window.close();
}
var NativeJson = Object.prototype.toString.call(this.JSON) === "[object JSON]" && this.JSON;

function fastJsonParse(s, reviver) {
    return NativeJson ?
        NativeJson.parse(s, reviver) : YAHOO.lang.JSON.parse(s, reviver);
}
/* ***** BEGIN LICENSE BLOCK *****

# cpanel12 - CookieHelper.js                 Copyright(c) 1997-2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

 * ***** END LICENSE BLOCK *****
  * ***** BEGIN APPLICABLE CODE BLOCK ***** */

/* Double Include Protection

if (CookieHelper) {
    alert("Cookie Helper Included multiple times in " + window.location.href);
}

var CookieHelper = 1;
 */

var isWebMail = 0;
var NVData_pending = 0;

function DidSetNvData(jsonRef, myCallback) {
    NVData_pending = 0;
    if (!jsonRef) {
        alert("Invalid json response from json-api: " + o.responseText);
        return;
    }

    for (var i = 0; i < jsonRef.length; i++) {
        if (jsonRef[i].set == null) {
            alert("Invalid Data in response from json-api: " + o.responseText);
            continue;
        }
        if (myCallback != null) {
            myCallback(jsonRef[i].set);
        }
    }
}

function FailSetNvData(o) {

    // DEBUG    alert("Unable to setNvData in: " + window.location.href);
}

function SetNvData(name, Cvalue, myCallback, nocache) {
    var mycallback = function(xmlRef) {
        DidSetNvData(xmlRef, myCallback);
    };

    if (typeof (window["cpanel_jsonapi2"]) == "undefined") {
        alert("You must load jsonapi.js before using SetNvData into this page: " + window.location.href);
    }
    cpanel_jsonapi2(mycallback, "NVData", "set", "names", name, name, Cvalue, "__nvdata::nocache", (nocache ? 1 : 0));
    NVData_pending = 1;
    NVData[name] = Cvalue;
}

function GotNvData(jsonRef, myCallback) {

    if (!jsonRef) {
        alert("Invalid json response from json-api NVData get");
        return;
    }
    if (!myCallback) {
        alert("GetNvData call is missing a callback function on: " + window.location.href);
        return;
    }

    for (var i = 0; i < jsonRef.length; i++) {
        if (!jsonRef[i].name) {
            alert("Invalid Data in response from NVData get");
            continue;
        }
        var thisVal = "";
        if (jsonRef[i].value) {
            thisVal = jsonRef[i].value;
        }
        myCallback(jsonRef[i].name, unescape(thisVal));
    }
}

function FailGetNvData(o) {

    // DEBUG    alert("Unable to getNvData in: " + window.location.href);
}

function GetNvData(name, myCallback) {
    var mycallback = function(xmlRef) {
        GotNvData(xmlRef, myCallback);
    };

    if (typeof (window["cpanel_jsonapi2"]) == "undefined") {
        alert("You must load jsonapi.js before using SetNvData into this page: " + window.location.href);
    }
    cpanel_jsonapi2(mycallback, "NVData", "get", "names", name);
}

function SetCookie(name, value, expires, path) {
    document.cookie = name + "=" + escape(value) +
        ((expires) ? ("; expires=" + expires.toGMTString()) : "") +
        ((path) ? ("; path=" + path) : "");
}

function GetCookie(name) {
    var dcookie = document.cookie;
    var cname = name + "=";
    var clen = dcookie.length;
    var cbegin = 0;
    while (cbegin < clen) {
        var vbegin = cbegin + cname.length;
        if (dcookie.substring(cbegin, vbegin) == cname) {
            var vend = dcookie.indexOf(";", vbegin);
            if (vend == -1) {
                vend = clen;
            }
            return unescape(dcookie.substring(vbegin, vend));
        }
        cbegin = dcookie.indexOf(" ", cbegin) + 1;
        if (cbegin == 0) {
            break;
        }
    }

    // alert("Cookie (Get):" + document.cookie);
    return null;
}

function include_dom(script_filename) {
    var html_doc = document.getElementsByTagName("head").item(0);
    var js = document.createElement("script");
    js.setAttribute("language", "javascript");
    js.setAttribute("type", "text/javascript");
    js.setAttribute("src", script_filename);
    html_doc.appendChild(js);
    return false;
}
/* ***** BEGIN LICENSE BLOCK *****

# cpanel12 - jsonapi.js                       Copyright(c) 1997-2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

 * ***** END LICENSE BLOCK *****
  * ***** BEGIN APPLICABLE CODE BLOCK ***** */

function cpanel_jsonapi1() {
    var argv = cpanel_jsonapi1.arguments;
    var mycallback = argv[0];
    var module = argv[1];
    var func = argv[2];
    var argc = argv.length;

    var callback = {
        success: cpanel_jsonapi1_parser,
        failure: mycallback,
        argument: mycallback
    };

    var sFormData = "cpanel_jsonapi_module=" + encodeURIComponent(module) + "&cpanel_jsonapi_func=" + encodeURIComponent(func) + "&cpanel_jsonapi_apiversion=1";
    var argnum = 0;
    for (var i = 3; i < argc; i++) {
        sFormData += "&arg-" + argnum + "=" + encodeURIComponent(argv[i]);
        argnum++;
    }
    if (sFormData.length < 2000) {
        YAHOO.util.Connect.asyncRequest("GET", CPANEL.security_token + "/json-api/cpanel?" + sFormData, callback);
    } else {
        YAHOO.util.Connect.asyncRequest("POST", CPANEL.security_token + "/json-api/cpanel", callback, sFormData);
    }
}

function cpanel_jsonapi1_parser(o) {
    var mycallback = o.argument;
    var jsonCode = fastJsonParse(o.responseText);
    if (mycallback) {
        mycallback(jsonCode.cpanelresult.data.result);
    }
}

function cpanel_jsonapi2() {
    var argv = cpanel_jsonapi2.arguments;
    var mycallback = argv[0];
    var module = argv[1];
    var func = argv[2];
    var argc = argv.length;

    var callback = {
        success: cpanel_jsonapi2_parser,
        failure: mycallback,
        argument: mycallback
    };

    var sFormData = "cpanel_jsonapi_module=" + encodeURIComponent(module) + "&cpanel_jsonapi_func=" + encodeURIComponent(func) + "&cpanel_jsonapi_apiversion=2";
    for (var i = 3; i < argc; i += 2) {
        sFormData += "&" + encodeURIComponent(argv[i]) + "=" + encodeURIComponent(argv[i + 1]);
    }
    if (sFormData.length < 2000) {
        YAHOO.util.Connect.asyncRequest("GET", CPANEL.security_token + "/json-api/cpanel?" + sFormData, callback);
    } else {
        YAHOO.util.Connect.asyncRequest("POST", CPANEL.security_token + "/json-api/cpanel", callback, sFormData);
    }
}

function cpanel_jsonapi2_parser(o) {
    var mycallback = o.argument;
    var jsonCode = fastJsonParse(o.responseText);
    if (mycallback) {
        mycallback(jsonCode.cpanelresult.data);
    }
}
