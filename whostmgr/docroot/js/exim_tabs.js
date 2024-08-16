/*
cpanel - whostmgr/docroot/js/exim_tabs.js       Copyright(c) 2020 cPanel, L.L.C.
                                                          All rights reserved.
copyright@cpanel.net                                         http://cpanel.net
This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
var actiontabindex = 5;

var taburis = [

    // tabid, url, has been loaded
    ["basic", CPANEL.security_token + "/scripts2/basic_exim_editor?in_tab=1", 1, "Basic Editor"],
    ["advanced", CPANEL.security_token + "/scripts2/advanced_exim_editor?in_tab=1", 0, "Advanced Editor"],
    ["backup-exim-config", CPANEL.security_token + "/scripts2/exim_config_backup?in_tab=1", 0, "Backup"],
    ["restore", CPANEL.security_token + "/scripts2/exim_config_restore?in_tab=1", 0, "Restore"],
    ["reset", CPANEL.security_token + "/scripts2/exim_config_reset?in_tab=1", 0, "Reset"]
];

function select_exim_backup(reload, query_data) {
    if (parent.selectTab) {
        parent.selectTab("backup", reload, query_data);
    } else {
        selectTab("backup", reload, query_data);
    }
}

function select_exim_basic(reload, query_data) {
    if (parent.selectTab) {
        parent.selectTab("basic", reload, query_data);
    } else {
        selectTab("basic", reload, query_data);
    }
}

function select_exim_advanced(reload, query_data) {
    if (parent.selectTab) {
        parent.selectTab("advanced", reload, query_data);
    } else {
        selectTab("advanced", reload, query_data);
    }
}

function select_exim_reset(reload, query_data) {
    if (parent.selectTab) {
        parent.selectTab("reset", reload, query_data);
    } else {
        selectTab("reset", reload, query_data);
    }
}

function getTabPrettyName(tabid) {
    if (taburis[tabid]) {
        return taburis[tabid][3];
    }

    for (var i = 0; i < taburis.length; i++) {
        if (taburis[i][0] == tabid) {
            return taburis[i][3];
        }
    }

    return tabid;

}

function selectTab(tabid, reload, query_data) {
    if (reload) {
        reload_tab(tabid, query_data, 1);
    }
    for (var i = 0; i < taburis.length; i++) {
        if (taburis[i][0] == tabid) {
            if (self["tabView"]) {
                tabView.selectTab(i);
            } else if (parent.tabView) {
                parent.tabView.selectTab(i);
            }
            break;
        }
    }
}

function reload_tab(tabid, query_data, show_loading) {
    if (!query_data) {
        query_data = {};
    }
    var in_tab = 1;
    var thisIframeEl = document.getElementById(tabid) || parent.frames[tabid] || frames[tabid];
    if (!thisIframeEl) {
        thisIframeEl = window;
        in_tab = 0;
    }
    var url;
    for (var i = 0; i < taburis.length; i++) {
        if (taburis[i][0] == tabid) {
            url = taburis[i][1];
            taburis[i][2] = 1; // hasbeenloaded
        }
    }
    if (!in_tab) {
        url = url.replace(/in_tab=1/, "in_tab=0");
    }
    if (!url.match(/\?/)) {
        url += "?";
    }
    if (url.match(/cache_fix=/)) {
        url = url.replace(/cache_fix=/, "cache_fix=1");
    } else {
        url += "&cache_fix=" + parseInt(Math.random() * 50000000);
    }
    if (show_loading && in_tab) {
        var new_uri = process_url_and_query_data(url, query_data);
        var redirect_function = 'function() { var load_window = function() {  window.location.href = "' + String(new_uri).replace('"', '\\"') + '"; };  window.setTimeout(load_window,500); }';
        set_iframe_content(thisIframeEl, "<div style='padding: 5px;'>" + CPANEL.icons.ajax + " Reloading " + getTabPrettyName(tabid) + "....</div></body>", redirect_function);
    } else {
        tab_redirect(thisIframeEl, url, query_data);
    }

}

function process_url_and_query_data(url, query_data) {
    var url_qs = url.split("?", 2);
    var query_string = url_qs[1] || "";
    if (query_string != null) {
        var pairs = query_string.split("&");
        for (var i = 0; i < pairs.length; i++) {
            var pair = pairs[i].split("=");
            if (pair[0] != null && !query_data[pair[0]]) {
                query_data[pair[0]] = pair[1];
            }
        }
    }
    if (query_data["reload"]) {
        query_data["reload"]++;
    } else {
        query_data["reload"] = 1;
    }
    var new_query_data = [];
    for (var i in query_data) {
        new_query_data.push(i + "=" + query_data[i]);
    }
    return url_qs[0] + "?" + new_query_data.join("&");
}

function tab_redirect(thisIframeEl, url, query_data) {
    var redirect_url = process_url_and_query_data(url, query_data);

    set_iframe_url(thisIframeEl, redirect_url);

}

function set_iframe_content(thisIframeEl, content, functionToInject) {
    if (thisIframeEl.contentWindow) {
        if (thisIframeEl.contentWindow.document.body) {
            thisIframeEl.contentWindow.document.body.innerHTML = content;
        } else {
            thisIframeEl.contentWindow.document.innerHTML = "<html>" + content + "</html>";
        }
        if (functionToInject) {
            var injecter = function() {
                var inject = thisIframeEl.contentWindow.document.createElement("script");
                inject.setAttribute("type", "text/javascript");
                var textNode = thisIframeEl.contentWindow.document.createTextNode("(" + functionToInject + ")();");
                try {
                    inject.appendChild(textNode);
                } catch (e) {
                    inject.type = "text/javascript";
                    inject.text = "(" + functionToInject + ")();";
                }
                thisIframeEl.contentWindow.document.body.appendChild(inject);
            };
            if (thisIframeEl.contentWindow.document && thisIframeEl.contentWindow.document.body) {
                injecter();
            } else {
                YAHOO.util.Event.onAvailable(thisIframeEl.contentWindow.document.body, injecter);
            }
        }

    } else if (thisIframeEl.window) {
        if (thisIframeEl.window.document.body) {
            thisIframeEl.window.document.body.innerHTML = content;
        } else {
            thisIframeEl.window.document.innerHTML = "<html>" + content + "</html>";
        }
        if (functionToInject) {
            var injecter = function() {
                var inject = thisIframeEl.window.document.createElement("script");
                inject.setAttribute("type", "text/javascript");
                var textNode = thisIframeEl.window.document.createTextNode("(" + functionToInject + ")();");
                try {
                    inject.appendChild(textNode);
                } catch (e) {
                    inject.type = "text/javascript";
                    inject.text = "(" + functionToInject + ")();";
                }
                thisIframeEl.window.document.body.appendChild(inject);
            };
            if (thisIframeEl.window.document && thisIframeEl.window.document.body) {
                injecter();
            } else {
                YAHOO.util.Event.onAvailable(thisIframeEl.window.document.body, injecter);
            }
        }
    } else {
        alert("Could not set Iframe content");
    }
}

function set_iframe_url(thisIframeEl, redirect_url) {
    if (get_relative_url(get_iframe_url(thisIframeEl)) == get_relative_url(redirect_url)) {
        return;
    }

    // location.replace() avoids adding to browser history.
    if (thisIframeEl.contentWindow) {
        thisIframeEl.contentWindow.location.replace(redirect_url);
    } else if (thisIframeEl.window) {
        thisIframeEl.window.location.replace(redirect_url);
    } else if (thisIframeEl.src) {
        thisIframeEl.src = redirect_url;
    } else {
        alert("Could not set Iframe URL");
    }
}

function get_iframe_url(thisIframeEl) {
    if (thisIframeEl.contentWindow) {
        return thisIframeEl.contentWindow.location.href;
    } else if (thisIframeEl.window) {
        return thisIframeEl.window.location.href;
    } else if (thisIframeEl.src) {
        return thisIframeEl.src;
    } else {
        alert("Could not get Iframe URL");
    }
}

function get_relative_url(url) {
    if (url.match(/^\//)) {
        return url;
    }
    var spliturl = url.split("/");
    spliturl.splice(0, 3);
    return "/" + spliturl.join("/");
}
