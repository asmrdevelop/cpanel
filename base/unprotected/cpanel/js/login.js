/* global MESSAGES: false */

/* eslint-disable strict */
/* eslint-disable camelcase */

"use strict";

var FADE_DURATION = 0.45;
var FADE_DELAY = 20;
var AJAX_TIMEOUT = 30000;

var LOCALE_FADES = [];
var HAS_CSS_OPACITY = "opacity" in document.body.style;
var login_form = DOM.get("login_form");
var login_username_el = DOM.get("user");
var login_password_el = DOM.get("pass");
var login_submit_el   = DOM.get("login_submit");

// Possibly could have used getParameterByName from redirect.html?
window.get_goto = function(appOrUri) {
    let queryStr = window.location.search;
    queryStr = queryStr.substr(1); // Chop off ?
    let exploded = queryStr.split("&");
    exploded = exploded.flatMap( (kv) => kv.split("=") );

    // Unlike in perl, there is no method of "just" treating an even length
    // array as a object (hash in perl) *without iterating*.
    // You may be tempted to use a `new Map` over an array, but guess what,
    // you cannot access that by key, you have to iterate so no love.
    // As such, just iterate, as you will have to do this no matter what.
    // Even join to string of JSON then JSON.parse is iteration.
    let ret = "";
    for ( let i = 0; i < exploded.length; i++ ) {
        if ( exploded[i] === "goto_" + appOrUri ) {
            ret = exploded[i + 1];
            break;
        }
    }

    let alt = location.href.replace(location.origin, "");

    // Check length, because this can be '/'. In that case keep query string's.
    if ( appOrUri === "uri" && alt.length > 1 ) {
        alt = alt.substr(1);
        alt = alt.replace( new RegExp("^cpsess[0-9]+/"), "" );
        alt = alt.replace( new RegExp("\\?.*$"), "" );
        ret = alt;
    }

    // Discard nonsense gotos, add more here if we discover them
    if ( ret.indexOf("webmaillogout.cgi") >= 0 ) {
        ret = "";
    }

    return ret;
};
window.goto_app = window.get_goto("app");
window.goto_uri = window.get_goto("uri");

// Set up the caches.
var div_cache = {        // An object we'll use to do quick lookups of commonly accessed elements.
    "login-page": DOM.get("login-page") || false,
    "locale-container": DOM.get("locale-container") || false,
    "login-container": DOM.get("login-container") || false,
    "locale-footer": DOM.get("locale-footer") || false,
    "content-cell": DOM.get("content-container") || false,
    "invalid": DOM.get("invalid") || false,
};
var content_cell = div_cache["content-cell"];

if (div_cache["locale-footer"]) {
    div_cache["locale-footer"].style.display = "block";
}  // Enable the locale footer for people with javascript.

// eslint-disable-next-line no-unused-vars
var reset_form = DOM.get("reset_form");

var set_opacity;

if (HAS_CSS_OPACITY) {
    set_opacity = function setOpacity(el, opacity) {
        el.style.opacity = opacity;
    };
} else {
    var filter_regex = /(DXImageTransform\.Microsoft\.Alpha\()[^)]*\)/;
    set_opacity = function setOpacity(el, opacity) {
        var filter_text = el.currentStyle.filter;

        // Weird IE quirk: If you set an opacity in the element's style attribute, that will
        // override an opacity set via script. But, the only way to create a filter is to
        // do it in CSS. Yeah. :-p
        if (!filter_text) {
            el.style.filter = "progid:DXImageTransform.Microsoft.Alpha(enabled=true)";
        } else if ( !filter_regex.test(filter_text) ) {
            el.style.filter += " progid:DXImageTransform.Microsoft.Alpha(enabled=true)";
        } else {
            var new_filter = filter_text.replace(filter_regex, "$1enabled=true)");
            if (new_filter !== filter_text) {
                el.style.filter = new_filter;
            }
        }

        try {
            el.filters.item("DXImageTransform.Microsoft.Alpha").opacity = opacity * 100;
        } catch (e) {
            try {
                el.filters.item("alpha").opacity = opacity * 100;
            } catch (error) {

                // oops...This should't happen.
            }
        }
    };
}

// eslint-disable-next-line no-unused-vars
function toggle_locales(show_locales) {
    while ( LOCALE_FADES.length ) {
        clearInterval( LOCALE_FADES.shift() );
    }

    var newly_shown = div_cache[ show_locales ? "locale-container" : "login-container" ];
    set_opacity( newly_shown, 0 );
    if (HAS_CSS_OPACITY) {
        content_cell.replaceChild( newly_shown, content_cell.children[0] );
    } else {
        var old = content_cell.children[0];
        content_cell.insertBefore( newly_shown, old );
        newly_shown.style.display = "";
        old.style.display = "none";
    }

    LOCALE_FADES.push( fade_in(newly_shown) );
    LOCALE_FADES.push( (show_locales ? fade_out : fade_in)("locale-footer") );
}

function showIEBanner() {
    if (navigator.userAgent.indexOf("Trident") !== -1) {
        var ieBannerDiv = document.getElementById("IE-warning");
        if (ieBannerDiv) {
            ieBannerDiv.classList.remove("IE-warning-hide");
        }
    }
}

showIEBanner();

function fade_in(el, duration, _fade_out_instead) {
    el = div_cache[el] || DOM.get(el) || el;
    var style_obj = el.style;
    var interval;

    var cur_style = window.getComputedStyle ? getComputedStyle(el, null) : el.currentStyle;
    var visibility = cur_style.visibility;

    var start_opacity;
    if (el.offsetWidth && visibility !== "hidden") {
        if ( window.getComputedStyle ) {
            start_opacity = Number(cur_style.opacity);
        } else {
            try {
                start_opacity = el.filters.item("DXImageTransform.Microsoft.Alpha").opacity;
            } catch (e) {
                try {
                    start_opacity = el.filters("alpha").opacity;
                } catch (error) {
                    start_opacity = 100;
                }
            }
            start_opacity /= 100;
        }
        if ( !start_opacity ) {
            start_opacity = 0;
        }
    } else {
        start_opacity = 0;
        set_opacity( el, 0 );
    }

    if ( _fade_out_instead && start_opacity < 0.01 ) {
        if (start_opacity) {
            set_opacity( el, 0 );
        }
        return;
    }

    if (!duration) {
        duration = FADE_DURATION;
    }
    var duration_ms = duration * 1000;
    var start = new Date();
    var end;
    if ( _fade_out_instead ) {
        end = duration_ms + start.getTime();
    } else {
        style_obj.visibility = "visible";
    }

    var fader = function() {
        var opacity;
        if ( _fade_out_instead ) {
            opacity = start_opacity * ( end - new Date() ) / duration_ms;
            if (opacity <= 0) {
                opacity = 0;
                clearInterval(interval);
                style_obj.visibility = "hidden";
            }
        } else {
            opacity = start_opacity + (1 - start_opacity) * ( new Date() - start ) / duration_ms;
            if (opacity >= 1) {
                opacity = 1;
                clearInterval(interval);
            }
        }

        set_opacity(el, opacity);
    };

    fader();
    interval = setInterval( fader, FADE_DELAY );

    return interval;
}

function fade_out(el, timeout) {
    return fade_in(el, timeout, true);
}

function AjaxObject(url, callbackFunction) {
    this._url      = url;
    this._callback = callbackFunction || function() { };
}

AjaxObject.prototype.updating = false;
AjaxObject.prototype.abort = function() {
    if ( this.updating ) {
        this.AJAX.abort();
        delete this.AJAX;
    }
};
AjaxObject.prototype.update = function(passData, postMethod) {
    if (this.AJAX) {
        return false;
    }

    var ajax = null;

    if (window.XMLHttpRequest) {
        ajax = new XMLHttpRequest();
    } else if ( window.ActiveXObject ) {
        ajax = new window.ActiveXObject("Microsoft.XMLHTTP");
    } else {
        return false;
    }

    var timeout;

    var that = this;
    ajax.onreadystatechange = function() {
        if ( ajax.readyState == 4 ) {
            clearTimeout(timeout);
            that.updating = false;
            that._callback(ajax);
            delete that.AJAX;
        }
    };
    try {
        var uri;
        timeout = setTimeout( function() {
            that.abort();
            show_status( MESSAGES.ajax_timeout, "error" );
        }, AJAX_TIMEOUT );

        if (/post/i.test(postMethod)) {
            uri = this._url + "?login_only=1";
            ajax.open("POST", uri, true);
            ajax.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
            ajax.send(passData);
        } else {
            uri = this._url + "?" + passData + "&timestamp=" + (new Date()).getTime();
            ajax.open("GET", uri, true);
            ajax.send(null);
        }

        this.AJAX = ajax;
        this.updating = true;
    } catch (e) {
        login_form.submit();
    }

    return true;
};

var _text_content = ("textContent" in document.body) ? "textContent" : "innerText";

function _process_parsed_login_success(result) {
    var final_uri;
    var login_url_regex = /^\/(?:logout|login|openid_connect_callback)\/?/; // unprotected/cpanel/templates/external_auth.tmpl needs to use the same regex
    if (result.redirect && !login_url_regex.test(result.redirect)) {
        final_uri = result.redirect;
    }

    var location_obj_to_redirect;

    if ( /^(?:\/cpsess[^/]+)\/$/.test(final_uri) ) {

        // top.location.href = final_uri;
        location_obj_to_redirect = top.location;
    } else {

        // If we’re in a frameset, then set each of the frames
        // to the updated cpsess token.
        if (result.security_token && (top !== window)) {
            for (var f = 0; f < top.frames.length; f++) {
                if (top.frames[f] !== window) {
                    var href = top.frames[f].location.href.replace(/\/cpsess[.\d]+/, result.security_token);
                    top.frames[f].location.href = href;
                }
            }
        }

        // location.href = final_uri;
        location_obj_to_redirect = location;
    }

    var redirector = function() {

        // Include the URL fragment for the sake of AngularJS
        // and other frameworks that need this for in-page routing.
        location_obj_to_redirect.href = final_uri + location.hash;
    };

    if (result.notices && result.notices.length) {
        show_status( MESSAGES.read_below, "warn" );

        var click_form = DOM.get("clickthrough_form");
        var container = click_form.querySelector(".notices");

        for (var n = 0; n < result.notices.length; n++) {
            var new_p = document.createElement("p");
            new_p.textContent = result.notices[n].content;
            container.appendChild(new_p);
        }

        click_form.onsubmit = redirector;
        fade_out(login_form);
        fade_in(click_form);
    } else {
        show_status( MESSAGES.success, "success" );

        fade_out( "content-container", FADE_DURATION / 2 );
        redirector();
    }
}

var login_button = {
    button: login_submit_el,
    _suppressed_disabled: null,
    suppress: function() {
        if ( this._suppressed_disabled === null ) {
            this._suppressed_disabled = this.button.disabled;
            this.button.disabled = true;
        }
    },
    release: function() {
        if ( this._suppressed_disabled !== null ) {
            this.button.disabled = this._suppressed_disabled;
            this._suppressed_disabled = null;
        }
    },
    queue_disabled: function(state) {
        if ( this._suppressed_disabled === null ) {
            this.button.disabled = state;
        } else {
            this._suppressed_disabled = state;
        }
    },
};

function login_results(ajax_obj) {
    var result;
    try {
        result = JSON.parse(ajax_obj && ajax_obj.responseText);
    } catch (e) {
        result = null;
    }

    var response_status = ajax_obj.status;
    if ( response_status === 200 ) {
        if (result) {
            if (result.session) {
                window.SubmitPost.submit(
                    result.redirect,
                    {
                        session: result.session,
                        goto_uri: result.goto_uri,
                    }
                );
            } else {
                _process_parsed_login_success(result);
            }
        } else {
            login_form.submit();
        }
        return;
    } else {
        if ( parseInt(response_status / 100, 10) === 4 ) {
            var msg_code = result && result.message;
            show_status( MESSAGES[msg_code || "invalid_login"] || MESSAGES.invalid_login, "error");
            set_status_timeout();
        } else {
            show_status( MESSAGES.network_error, "error" );
        }

        document.body.classList.remove("logging-in");
        login_button.release();
        return;
    }
}

var level_classes = {
    info: "info-notice",
    error: "error-notice",
    success: "success-notice",
    warn: "warn-notice",
};
var levels_regex = "";
Object.keys(level_classes).forEach( function(lv) {
    levels_regex += "|" + level_classes[lv];
} );
levels_regex = new RegExp("\\b(?:" + levels_regex.slice(1) + ")\\b");

function show_status( message, level ) {
    DOM.get("login-status-message")[_text_content] = message;

    var container = DOM.get("login-status");
    var this_class = level && level_classes[level] || level_classes.info;
    var el_class = container.className.replace(levels_regex, this_class);
    container.className = el_class;

    fade_in(container);
    reset_status_timeout();
}

var STATUS_TIMEOUT = null;
function reset_status_timeout() {
    clearTimeout( STATUS_TIMEOUT );
    STATUS_TIMEOUT = null;
}
function set_status_timeout( delay ) {
    STATUS_TIMEOUT = setTimeout( function() {
        fade_out("login-status");
    }, delay || 8000 );
}

// LOGIN_SUBMIT_OK prevents rapid-fire login requests from holding ENTER.
var LOGIN_SUBMIT_OK = true;
document.body.onkeyup = function() {
    LOGIN_SUBMIT_OK = true;
};
document.body.onmousedown = function() {
    LOGIN_SUBMIT_OK = true;
};
function do_login() {
    if (LOGIN_SUBMIT_OK) {
        LOGIN_SUBMIT_OK = false;
        if (login_username_el.value.length === 0) {
            show_status( MESSAGES.no_username, "error" );
            return false;
        }
        document.body.classList.add("logging-in");
        login_button.suppress();
        show_status( MESSAGES.authenticating, "info" );
        var goto_app_query = window.goto_app && window.goto_app.value ? "&goto_app=" + encodeURIComponent(window.goto_app.value) : "";
        var goto_uri_query = window.goto_uri ? "&goto_uri=" + encodeURIComponent(window.goto_uri) : "";
        var ajax_login = new AjaxObject(login_form.action, login_results);
        ajax_login.update(
            "user=" + encodeURIComponent(login_username_el.value) +
            "&pass=" + encodeURIComponent(login_password_el.value) +
            goto_app_query +
            goto_uri_query,
            "POST"
        );
    }
    return false;
}

// eslint-disable-next-line no-unused-vars
function show_login() {
    var select_user_form = document.getElementById("select_user_form");
    select_user_form.style.display = "none";

    var login_form = document.getElementById("login_form");
    login_form.style.visibility = "";

    var select_users_option_block = document.getElementById("select_users_option_block");
    select_users_option_block.style.display = "block";

    var login_sub = document.getElementById("login-sub");
    login_sub.style.display = "block";
}

// eslint-disable-next-line no-unused-vars
function show_select_user() {
    var login_form = document.getElementById("login_form");
    login_form.style.visibility = "hidden";

    var select_users_option_block = document.getElementById("select_users_option_block");
    select_users_option_block.style.display = "none";

    var select_user_form = document.getElementById("select_user_form");
    select_user_form.style.display = "block";

    var login_sub = document.getElementById("login-sub");
    login_sub.style.display = "none";
}

if ( !window.JSON ) {
    login_button.suppress();
    var new_script = document.createElement("script");
    new_script.onreadystatechange = function() {
        if ( this.readyState === "loaded" || this.readyState === "complete" ) {
            this.onreadystatechange = null;
            window.JSON = { parse: window.jsonParse };
            window.jsonParse = undefined;  // IE can't delete window.*

            login_button.release();
        }
    };
    new_script.src = "/unprotected/json-minified.js";
    document.getElementsByTagName("head")[0].appendChild(new_script);
}

try {
    login_form.onsubmit = do_login;
    set_opacity( DOM.get("login-wrapper"), 0 );
    LOCALE_FADES.push( fade_in("login-wrapper") );

    var preload = document.createElement("div");
    preload.id = "preload_images";
    document.body.insertBefore(preload, document.body.firstChild);

    if ( window.IS_LOGOUT ) {
        set_status_timeout( 10000 );
    } else if (/(?:\?|&)locale=[^&]/.test(location.search)) {
        show_status( MESSAGES.session_locale );
    }

    // WebKit browsers sometimes need this delay.
    setTimeout( function() {
        login_username_el.focus();
    }, 100 );
} catch (e) {
    if (window.console) {

        // eslint-disable-next-line no-console
        console.warn(e);
    }
}
