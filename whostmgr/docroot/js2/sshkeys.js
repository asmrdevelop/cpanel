if (!("_key_texts" in CPANEL)) {
    CPANEL._key_texts = {};
}

var fade_effect = {
    effect: YAHOO.widget.ContainerEffect.FADE,
    duration: 0.25
};

var get_form_callback = function(throbber_panel) {
    return {
        success: function(o) {
            var response = YAHOO.lang.JSON.parse(o.responseText);

            var response_panel = new CPANEL.widgets.Modal("response_panel");
            response_panel.cfg.setProperty("effect", null);

            if (response.metadata.result == 1) {
                if ("warnings" in response.metadata) {
                    response_panel.setHeader("<div class='lt'></div><span>" + "WARNING" + "</span><div class='rt'></div>");
                    response_panel.setBody(response.metadata.warnings.join("<br /><br />"));
                    response_panel.beforeHideEvent.subscribe(function() {
                        var reload_panel = new CPANEL.widgets.Modal("reload_panel");
                        reload_panel.setFooter("");
                        reload_panel.setBody(CPANEL.icons.ajax + "&nbsp;Reloading page...");
                        reload_panel.cfg.setProperty("effect", null);
                        reload_panel.render(document.body);
                        response_panel.destroy();
                        reload_panel.show();
                        location.reload();
                    });
                } else {
                    response_panel.setFooter("");
                    response_panel.setBody("Success!<br /><br />" + CPANEL.icons.ajax + "&nbsp;Reloading page...");
                    response_panel.showEvent.subscribe(function() {
                        location.reload();
                    });
                }
            } else {
                response_panel.setHeader("<div class='lt'></div><span>" + "ERROR" + "</span><div class='rt'></div>");
                response_panel.setBody(response.metadata.reason || "");
                response_panel.cfg.setProperty("effect", fade_effect);
            }

            throbber_panel.destroy();
            response_panel.show();
        },
        failure: function(o) {
            throbber_panel.destroy();
            alert("AJAX request failed.");
            toggle_new_key_form();
        }
    };
};


// import public key form
// ----------------------------------------------------------------------
window.import_public_key_form = document.getElementById("import_public_key_form");

var public_key_text_validator = new CPANEL.validate.validator("Public key text");
var public_key_obj = document.getElementById("public_key_text");
var public_key_text_validator_function = function() {
    var key_text = public_key_obj.value.trim();
    return Boolean(key_text.match(CPANEL._regexes.public_ssh2) || key_text.match(CPANEL._regexes.public_rsa1));
};
public_key_text_validator.add(public_key_obj, public_key_text_validator_function, "Invalid public key.");
public_key_text_validator.attach();

import_public_key_form.validators = [public_key_text_validator];

YAHOO.util.Event.on("import_public_key_button", "click", function() {
    show_form(import_public_key_form);
});
import_public_key_form.parentNode.removeChild(import_public_key_form);
import_public_key_form.style.display = "block";
import_public_key_form.title = YAHOO.lang.trim(
    document.getElementById("import_public_key_button").textContent || document.getElementById("import_public_key_button").innerText
);
YAHOO.util.Event.on("import_public_key_form", "submit", function(e) {
    YAHOO.util.Event.stopEvent(e);
    document.getElementById("import_public_key_form_submit_button").click();
    return false;
});
import_public_key_form.validate = function() {
    var key_name_input = document.getElementById("public_key_name");
    var key_name = key_name_input.value.trim();
    if (key_name.match(CPANEL._regexes.invalid_filename)) {
        var invalid_warning_div = document.getElementById("invalid_public_key_filename_text");
        CPANEL.animate.slide_down(invalid_warning_div);
        key_name_input.onkeydown = function() {
            CPANEL.animate.slide_up(invalid_warning_div);
            delete key_name_input.onkeydown;
        };
        return false;
    }

    var key_text_input = document.getElementById("public_key_text");
    var key_text = key_text_input.value.trim();
    if (!key_text.match(CPANEL._regexes.public_ssh2) && !key_text.match(CPANEL._regexes.public_rsa1)) {
        var invalid_warning_div = document.getElementById("invalid_public_key_text");
        CPANEL.animate.slide_down(invalid_warning_div);
        key_text_input.onkeydown = function() {
            CPANEL.animate.slide_up(invalid_warning_div);
            delete key_text_input.onkeydown;
        };
        return false;
    }

    return true;
};
import_public_key_form.submit_function = function() {
    var throbber_panel = new YAHOO.widget.Panel("throbber_panel", {
        fixedcenter: true,
        modal: true,
        underlay: null,
        close: false,
        constraintoviewport: true
    });
    throbber_panel.setHeader("<div class='lt'></div><span>" + "&nbsp;" + "</span><div class='rt'></div>");
    throbber_panel.setBody(CPANEL.icons.ajax + "&nbsp;Importing...");
    throbber_panel.render(document.body);

    this.panel.destroy();
    throbber_panel.show();

    var form_data = get_data_from_form(this);
    if (!form_data.name.match(/\.pub$/)) {
        form_data.name += ".pub";
    }

    YAHOO.util.Connect.asyncRequest(
        "POST",
        CPANEL.urls.whm_api("importsshkey", {
            "api.version": 1
        }),
        get_form_callback(throbber_panel),
        make_query_string(form_data)
    );

    return true;
};

// generate key pair form
// ----------------------------------------------------------------------
window.generate_new_key_form = document.getElementById("generate_new_key_form");
generate_new_key_form.validators = CPANEL.password.setup(
    "passphrase",
    "passphrase2",
    "passphrase_strength",
    REQUIRED_PASSPHRASE_STRENGTH,
    "create_strong_passphrase",
    "why_strong_passphrases_link",
    "why_strong_passphrases_text"
);

var key_name_validator = new CPANEL.validate.validator("Key name");
var key_name_obj = document.getElementById("generate_key_name");
var key_name_validator_function = function() {
    return !key_name_obj.value.trim().match(CPANEL._regexes.invalid_filename);
};
key_name_validator.add(key_name_obj, key_name_validator_function, "Invalid filename.");
key_name_validator.attach();

var key_comment_validator = new CPANEL.validate.validator("Key comment");
key_comment_validator.add("generate_key_comment", "anything", "");
key_comment_validator.attach();

generate_new_key_form.validators.push(key_name_validator);
generate_new_key_form.validators.push(key_comment_validator);

YAHOO.util.Event.on("generate_new_key_button", "click", function() {
    show_form(generate_new_key_form);
});
generate_new_key_form.parentNode.removeChild(generate_new_key_form);
generate_new_key_form.style.display = "block";
generate_new_key_form.title = YAHOO.lang.trim(
    document.getElementById("generate_new_key_button").textContent || document.getElementById("generate_new_key_button").innerText
);
generate_new_key_form.submit_function = function() {
    var throbber_panel = new YAHOO.widget.Panel("throbber_panel", {
        fixedcenter: true,
        modal: true,
        underlay: null,
        close: false,
        constraintoviewport: true
    });
    throbber_panel.setHeader("<div class='lt'></div><span>" + "&nbsp;" + "</span><div class='rt'></div>");
    throbber_panel.setBody(CPANEL.icons.ajax + "&nbsp;Generating...");
    throbber_panel.render(document.body);

    this.panel.destroy();
    throbber_panel.show();

    YAHOO.util.Connect.asyncRequest(
        "POST",
        CPANEL.urls.whm_api("generatesshkeypair", {
            "api.version": 1
        }),
        get_form_callback(throbber_panel),
        get_query_string_from_form(this)
    );
};

// import from private key form
// ----------------------------------------------------------------------
window.import_from_private_key_form = document.getElementById("import_from_private_key_form");
var private_key_text_validator = new CPANEL.validate.validator("Private key text");
var private_key_obj = document.getElementById("private_key_text");
var private_key_text_validator_function = function() {
    var key_text = private_key_obj.value.trim();
    return Boolean(key_text.match(CPANEL._regexes.private_ssh2) || key_text.match(CPANEL._regexes.putty_ssh2));
};
private_key_text_validator.add(private_key_obj, private_key_text_validator_function, "Invalid private key.");
private_key_text_validator.attach();

var private_key_name_validator = new CPANEL.validate.validator("Key name");
var private_key_name_obj = document.getElementById("private_name");
var private_key_name_validator_function = function() {
    var key_name = private_key_name_obj.value.trim();
    return !key_name.match(CPANEL._regexes.invalid_filename);
};
private_key_name_validator.add(private_key_name_obj, private_key_name_validator_function, "Invalid key name.");
private_key_name_validator.attach();

import_from_private_key_form.validators = [private_key_name_validator, private_key_text_validator];

YAHOO.util.Event.on("import_from_private_key_button", "click", function() {
    show_form(import_from_private_key_form);
});
import_from_private_key_form.parentNode.removeChild(import_from_private_key_form);
import_from_private_key_form.style.display = "block";
import_from_private_key_form.title = YAHOO.lang.trim(
    document.getElementById("import_from_private_key_button").textContent || document.getElementById("import_from_private_key_button").innerText
);
import_from_private_key_form.check_for_encryption = function() {
    var passphrase_div = document.getElementById("passphrase_area");

    var key_text_input = document.getElementById("private_key_text");
    var key_text = key_text_input.value.trim();
    var check_key = check_private_key(key_text);

    if (check_key === null) {
        CPANEL.animate.slide_up(passphrase_div);
        return false;
    } else {
        var passphrase_is_displayed = YAHOO.util.Dom.getRegion(passphrase_div);

        if (check_key) {
            if (!passphrase_is_displayed) {
                CPANEL.animate.slide_down(passphrase_div, function() {
                    document.getElementById("private_passphrase").focus();
                });
            }
        } else if (passphrase_is_displayed) {
            CPANEL.animate.slide_up(passphrase_div);
        }
    }

    return true;
};
import_from_private_key_form.submit_function = function() {
    var throbber_panel = new YAHOO.widget.Panel("throbber_panel", {
        fixedcenter: true,
        modal: true,
        underlay: null,
        close: false,
        constraintoviewport: true
    });
    throbber_panel.setHeader("<div class='lt'></div><span>" + "&nbsp;" + "</span><div class='rt'></div>");
    throbber_panel.setBody(CPANEL.icons.ajax + "&nbsp;Importing...");
    throbber_panel.render(document.body);

    this.panel.destroy();
    throbber_panel.show();

    var form_data = get_data_from_form(this);
    var api_data = {
        name: form_data.name,
        key: form_data.key
    };
    if ("passphrase" in form_data) {
        api_data.passphrase = form_data.passphrase;
    }
    if (form_data.extract_public) {
        api_data.extract_public = 1;
    }
    if (form_data.extract_private) {
        api_data.extract_private = 1;
    }

    YAHOO.util.Connect.asyncRequest(
        "POST",
        CPANEL.urls.whm_api("importsshkey", {
            "api.version": 1
        }),
        get_form_callback(throbber_panel),
        make_query_string(api_data)
    );
};

var show_form = function(form) {
    var form_panel = new YAHOO.widget.Panel(form.id + "_container", {
        effect: fade_effect,
        visible: false,
        close: true,
        underlay: null,
        modal: false,
        draggable: true,
        fixedcenter: true,
    });

    form.panel = form_panel;

    var cancel_id = form.id + "_cancel";
    var submit_id = form.id + "_submit";

    form_panel.setFooter(
        '<span style="margin-right:30px" class="fake_link" id=\'' + cancel_id + "'>Cancel</span>" + '<button type="button" style="display:inline" id=\'' + submit_id + "'>Submit</button>"
    );

    form_panel.footer.form = form;
    form_panel.footer.yui_control = form_panel;

    if (form.parentNode) {
        form.parentNode.removeChild(form);
    }

    form_panel.setBody(form);
    form_panel.setHeader("<div class='lt'></div><span>" + form.title + "</span><div class='rt'></div>");
    form_panel.render(document.body);

    document.getElementById(cancel_id).onclick = function() {
        form_panel.hide();
    };
    document.getElementById(submit_id).onclick = function() {
        var form_is_valid = true;
        for (var v = 0; v < form.validators.length; v++) {
            var this_is_valid = form.validators[v].is_valid();
            form_is_valid = form_is_valid && this_is_valid;
        }

        return form_is_valid && form.submit_function();
    };

    form_panel.subscribe("hide", function() {
        form_panel.destroy();
    });
    form_panel.subscribe("beforeHide", function() {
        for (var v = 0; v < form.validators.length; v++) {
            form.validators[v].clear_messages();
        }
    });

    form_panel.show();

    for (var v = 0; v < form.validators.length; v++) {
        form.validators[v].verify();
    }

    return form_panel;
};

YAHOO.util.Event.on("dsa_button", "click", function() {
    document.getElementById("1024_button").checked = true;
    document.getElementById("2048_button").disabled = true;
    document.getElementById("4096_button").disabled = true;
});
YAHOO.util.Event.on("rsa_button", "click", function() {
    document.getElementById("2048_button").disabled = false;
    document.getElementById("4096_button").disabled = false;
});

var status_fade_panel = function(text) {
    var fade_panel = new YAHOO.widget.Panel("fade_panel", {
        underlay: "shadow",
        close: false,
        effect: fade_effect,
        visible: false,
        draggable: true,
        fixedcenter: true,
        constraintoviewport: true
    });
    fade_panel.setHeader("<div class='lt'></div><span>" + "&nbsp;" + "</span><div class='rt'></div>");
    fade_panel.setBody(text.html_encode());
    fade_panel.render(document.body);

    fade_panel.show();
    setTimeout(function() {
        fade_panel.hide();
    }, 1000);

    YAHOO.util.Event.purgeElement(fade_panel, true);
    fade_panel.parentNode.removeChild(fade_panel);
};

window.Warnings_panel = new YAHOO.widget.Panel("warnings_panel", {
    draggable: false,
    underlay: "none",
    close: true,

    //    width: '300px',
    effect: fade_effect,
    context: [document.body, "tr", "tr", ["windowScroll", "windowResize"]]
});
Warnings_panel.setHeader("<div class='lt'></div><span>" + "WARNINGS" + "</span><div class='rt'></div>");
if (CPANEL._warnings.length > 0) {
    Warnings_panel.setBody(CPANEL._warnings.join("<br /><br />"));
    Warnings_panel.render(document.body);
    Warnings_panel.show();
    Warnings_panel.cfg.setProperty("effect", fade_effect);
}

CPANEL.widgets.Info_panel = function(new_id) {
    this.constructor.superclass.constructor.call(this, new_id, {
        underlay: "shadow",
        close: true,
        effect: fade_effect,
        visible: false,
        draggable: true,
        width: "500px",
        height: "300px",
        constraintoviewport: true
    });
    this.setHeader("<div class='lt'></div><span>" + "&nbsp;" + "</span><div class='rt'></div>");
    this.setBody("");
    this.setFooter('<button name="q" onclick="this.parentNode.yui_control.hide()">Close</button>');
    this.footer.yui_control = this;

    var yui_control = this;
    this.footer.enter_listener = new YAHOO.util.KeyListener(
        document, {
            keys: 13
        }, {
            fn: this.hide,
            scope: this,
            correctScope: true
        }
    );
    this.subscribe("show", function() {
        this.footer.enter_listener.enable();
    });
    this.subscribe("hide", function() {
        this.footer.enter_listener.disable();
    });
    this.render(document.body);
};
YAHOO.extend(CPANEL.widgets.Info_panel, YAHOO.widget.Panel);

// for key deletion/authorization
CPANEL.widgets.Modal = function(new_id, overrides) {
    var options = {
        effect: fade_effect,
        visible: false,
        close: false,
        underlay: null,
        modal: true,
        draggable: false,
        fixedcenter: true,
        constraintoviewport: true
    };

    for (var opt in overrides) {
        options[opt] = overrides[opt];
    }

    this.constructor.superclass.constructor.call(this, new_id, options);

    this.setHeader("<div class='lt'></div><span>" + "&nbsp;" + "</span><div class='rt'></div>");
    this.setBody("");
    this.setFooter('<button onclick="this.parentNode.yui_control.hide()">Close</button>');
    this.footer.yui_control = this;

    this.footer.enter_listener = new YAHOO.util.KeyListener(
        document, {
            keys: 13
        }, {
            fn: this.hide,
            scope: this,
            correctScope: true
        }
    );
    this.subscribe("show", function() {
        this.footer.enter_listener.enable();
    });
    this.subscribe("hide", function() {
        this.footer.enter_listener.disable();
        this.destroy();
    });

    this.render(document.body);
    YAHOO.util.Dom.addClass(this.element, "modal-panel");
};
YAHOO.extend(CPANEL.widgets.Modal, YAHOO.widget.Panel);

if (typeof CPANEL._thispage == "undefined") {
    CPANEL._thispage = {};
}

CPANEL._putty_key_texts = {};

function download_putty_key(file, context, get_passphrase) {
    var view_div = document.getElementById(file + "-view");


    var background_color = get_background_color(document.getElementById(file + "-row").cells[0]);

    var throbber_div;
    var form_div;
    var passphrase;

    var submit_request = function() {
        var query_data = {
            "file": file
        };
        if (passphrase) {
            query_data.passphrase = passphrase;
        }

        var query_string = make_query_string(query_data);

        location.href = CPANEL.security_token + "/backend/puttykey.cgi?" + query_string;
    };

    var get_passphrase_and_submit = function() {
        form_div = document.createElement("div");

        form_div.innerHTML =
            "<form>" + '<label>Passphrase: <input type="password" name="passphrase" /></label>' + "<br />" + '<span class="fake_link">Cancel</span>&nbsp;&nbsp;<button type="submit">Submit</button>' + "</form>";
        view_div.appendChild(form_div);

        var passphrase_input = form_div.getElementsByTagName("input")[0];
        YAHOO.util.Event.on(form_div.getElementsByTagName("span")[0], "click", function(e) {
            CPANEL.animate.slide_up(view_div, function() {
                view_div.innerHTML = "";
            });
        });

        CPANEL.animate.slide_down(view_div, function() {
            passphrase_input.select();
        });

        YAHOO.util.Event.on(form_div.firstChild, "submit", function(e) {
            YAHOO.util.Event.stopEvent(e);
            passphrase = passphrase_input.value;

            CPANEL.animate.slide_up(view_div, function() {
                view_div.innerHTML = "";
            });

            submit_request();
        });
    };

    if (get_passphrase) {
        if (view_div.innerHTML) {
            CPANEL.animate.slide_up(view_div, function() {
                view_div.innerHTML = "";
                get_passphrase_and_submit();
            });
        } else {
            get_passphrase_and_submit();
        }
    } else {
        submit_request();
    }
}

var _show_key = function(key_text, file, background_color) {
    var view_div = document.getElementById(file + "-view");

    var text_div = document.createElement("div");
    if (background_color) {
        YAHOO.util.Dom.setStyle(text_div, "background-color", background_color);
    }

    var textarea_width = view_div.parentNode.clientWidth - 12;

    text_div.innerHTML = '<textarea class="display_key" readonly="readonly" style="width:' + textarea_width + 'px" onfocus="this.select()">' + key_text.html_encode() + "</textarea>" + '<div style="text-align:center"><button>Close</button></div>';

    var throbber_div = view_div.firstChild;
    if (throbber_div) {
        text_div.style.display = "none";
        view_div.appendChild(text_div);
        CPANEL.animate.slide_down(text_div);

        CPANEL.animate.slide_up(throbber_div, function() {
            view_div.removeChild(throbber_div);
        });
    } else {
        view_div.appendChild(text_div);
        CPANEL.animate.slide_down(view_div);
    }

    var button = text_div.getElementsByTagName("button")[0];
    YAHOO.util.Event.addListener(button, "click", function() {
        CPANEL.animate.slide_up(view_div, function() {
            view_div.innerHTML = "";
        });
    });
};

function view_key(file, context) {
    var view_div = document.getElementById(file + "-view");
    if (view_div.innerHTML) {
        CPANEL.animate.slide_up(view_div, function() {
            view_div.innerHTML = "";
        });
        return;
    }

    var callback = {
        success: function(o) {
            var response = YAHOO.lang.JSON.parse(o.responseText);
            if (response.metadata.result == 1) {
                var key_text = response.data.keys[0].text;
                CPANEL._private_key_texts[file] = key_text;

                if ("warnings" in response.metadata) {
                    var response_panel = new CPANEL.widgets.Modal("response_panel");
                    response_panel.cfg.setProperty("effect", null);

                    response_panel.setHeader("<div class='lt'></div><span>" + "WARNINGS" + "</span><div class='rt'></div>");
                    response_panel.setBody(response.metadata.warnings.join("<br /><br />"));
                    response_panel.render(document.body);
                    response_panel.show();
                }

                _show_key(key_text, file, background_color);
            } else {
                CPANEL.animate.slide_up(throbber_div, function() {
                    view_div.innerHTML = "";
                });
                var response_panel = new CPANEL.widgets.Modal("modal_panel");
                response_panel.setHeader("<div class='lt'></div><span>" + "ERROR" + "</span><div class='rt'></div>");
                response_panel.setBody((response.metadata.reason || "").html_encode());
                response_panel.show();
            }
        },
        failure: function(o) {
            view_div.innerHTML = "";
            alert("AJAX request failed.");
        }
    };

    var background_color = get_background_color(document.getElementById(file + "-row").cells[0]);

    // if file is a Number, then this is a public key
    var cached_keys = YAHOO.lang.isNumber(file) ? CPANEL._public_key_texts : CPANEL._private_key_texts;

    if (cached_keys && (file in cached_keys)) {
        _show_key(cached_keys[file], file, background_color);
    } else {
        var throbber_div = document.createElement("div");
        YAHOO.util.Dom.setStyle(throbber_div, "background-color", background_color);
        throbber_div.innerHTML = CPANEL.icons.ajax + "&nbsp;Loading...";
        view_div.appendChild(throbber_div);

        CPANEL.animate.slide_down(view_div);

        YAHOO.util.Connect.asyncRequest(
            "GET",
            CPANEL.urls.whm_api(
                "listsshkeys", {
                    "files": file,
                    "public_texts": 1,
                    "private_texts": 1,
                    "api.version": 1
                }
            ),
            callback,
            ""
        );
    }
}

function authorize(file_index, context) {
    var view_div = document.getElementById(file_index + "-view");

    if (view_div.innerHTML != "") {
        CPANEL.animate.slide_up(view_div, function() {
            view_div.innerHTML = "";
        });
        return;
    }

    var background_color = get_background_color(document.getElementById(file_index + "-row").cells[0]);

    var options_div = document.createElement("div");
    YAHOO.util.Dom.setStyle(options_div, "background-color", background_color);
    options_div.innerHTML = '<label>Options:&nbsp;<input id="' + file_index + '-options-input" type="text" /></label>' + '<br /><button name="cancel" onclick="CPANEL._thispage.cancel()">Cancel</button>' + "&nbsp;&nbsp;" + '<button name="proceed" onclick="CPANEL._thispage.send_authorization()">Authorize</button>';

    CPANEL._thispage.cancel = function() {
        CPANEL.animate.slide_up(view_div, function() {
            view_div.innerHTML = "";
        });
    };
    CPANEL._thispage.send_authorization = function() {
        send_authorization(file_index, context, document.getElementById(file_index + "-options-input").value);
        CPANEL.animate.slide_up(options_div);
    };

    view_div.appendChild(options_div);
    CPANEL.animate.slide_down(view_div);

    options_div.getElementsByTagName("button")[1].focus();
}

function deauthorize(file_index, context) {
    send_authorization(file_index, context);
}

// arg 3: to_authorize

function send_authorization(file_index, context) {
    var to_authorize = arguments.length == 3;
    var auth_options = arguments[2];

    var action = (to_authorize ? "Authorizing" : "Deauthorizing") + "...";

    var background_color = get_background_color(document.getElementById(file_index + "-row").cells[0]);

    var view_div = document.getElementById(file_index + "-view");
    var throbber_div = document.createElement("div");
    throbber_div.innerHTML = CPANEL.icons.ajax + "&nbsp;" + action;
    YAHOO.util.Dom.setStyle(throbber_div, "background-color", background_color);

    if (view_div.innerHTML == "") {
        view_div.appendChild(throbber_div);
        CPANEL.animate.slide_down(view_div);
    } else { // sending an authorization; the view_div is already populated
        YAHOO.util.Dom.setStyle(throbber_div, "display", "none");
        view_div.appendChild(throbber_div);
        CPANEL.animate.slide_down(throbber_div);
    }

    var callback = {
        success: function(o) {
            var response = YAHOO.lang.JSON.parse(o.responseText);

            var info_panel;

            if (response.metadata.result == 1) {
                var success_div = document.createElement("div");
                YAHOO.util.Dom.setStyle(success_div, "background-color", background_color);
                success_div.style.display = "none";
                success_div.innerHTML = "This key has been " + (to_authorize ? "authorized" : "deauthorized") + ".";
                view_div.appendChild(success_div);
                CPANEL.animate.slide_up(throbber_div, function() {
                    view_div.removeChild(throbber_div);
                });
                CPANEL.animate.slide_down(success_div);
                setTimeout(function() {
                    CPANEL.animate.slide_up(view_div, function() {
                        view_div.innerHTML = "";
                    });
                }, 1000);

                context.replaceChild(document.createTextNode(to_authorize ? "Deauthorize" : "Authorize"), context.firstChild);
                var active_table_row = YAHOO.util.Dom.getAncestorByTagName(context, "tr");
                if (to_authorize) {
                    YAHOO.util.Dom.replaceClass(active_table_row, "not_authorized", "authorized");
                    context.onclick = function() {
                        deauthorize(file_index, context);
                    };

                    if (auth_options) {
                        document.getElementById(file_index + "-options").innerHTML = auth_options;
                        CPANEL.animate.slide_down(file_index + "-options-container");
                    }
                } else {
                    YAHOO.util.Dom.replaceClass(active_table_row, "authorized", "not_authorized");
                    context.onclick = function() {
                        authorize(file_index, context);
                    };
                    CPANEL.animate.slide_up(file_index + "-options-container"); // will do nothing if there are no options
                }

                background_color = get_background_color(document.getElementById(file_index + "-row").cells[0]);

                YAHOO.util.Dom.setStyle(throbber_div, "background-color", background_color);
                YAHOO.util.Dom.setStyle(success_div, "background-color", background_color);

                var authorized_span = active_table_row.cells[active_table_row.cells.length - 1].firstChild;
                authorized_span.innerHTML = to_authorize ? "Yes" : "No";
            } else {
                CPANEL.animate.slide_up(view_div, function() {
                    view_div.innerHTML = "";
                });

                info_panel = new CPANEL.widgets.Modal("auth_panel", {
                    "effect": null
                });
                info_panel.setBody(response.metadata.reason || "Request failed");

                info_panel.hideEvent.subscribe(info_panel.destroy);

                info_panel.setHeader("<div class='lt'></div><span>" + "&nbsp;" + "</span><div class='rt'></div>");
                info_panel.render(document.body);

                info_panel.show();

                info_panel.cfg.setProperty("effect", fade_effect);
            }
        },
        failure: function(o) {
            throbber_panel.destroy();
            alert("AJAX request failed.");
        }
    };

    YAHOO.util.Connect.asyncRequest(
        "GET",
        CPANEL.urls.whm_api(
            "authorizesshkey", {
                "text": CPANEL._public_key_texts[file_index],
                "authorize": to_authorize ? 1 : 0,
                "options": auth_options,
                "api.version": 1
            }
        ),
        callback,
        ""
    );
}

function delete_key(file, context) {
    var context_row = YAHOO.util.Dom.getAncestorByTagName(context, "tr");
    var is_authorized = YAHOO.util.Dom.hasClass(context_row, "authorized");

    var confirm_panel = new YAHOO.widget.Panel("confirm_panel", {
        fixedcenter: true,
        draggable: false,
        modal: true,
        underlay: null,
        close: false,
        effect: fade_effect,
        constraintoviewport: true
    });

    var panel_body_html = "Are you sure you want to delete “" + file + "”?" + "<br /><br />" + '<form onsubmit="return false;">';
    if (is_authorized) {
        panel_body_html +=
                "<label>" + '<input type="checkbox" id="leave_authorized_checkbox" value="1" />' + "&nbsp;Leave key authorized</label>" + "<br /><br />";
    }

    panel_body_html +=
            '<button name="cancel" onclick="CPANEL._thispage.cancel()">Cancel</button>' + "&nbsp;&nbsp;" + '<button name="proceed" id="proceed" onclick="CPANEL._thispage.do_delete_key()">Proceed</button>' + "</form>";

    confirm_panel.setFooter("");
    confirm_panel.setHeader("<div class='lt'></div><span>" + "&nbsp;" + "</span><div class='rt'></div>");
    confirm_panel.setBody(panel_body_html);
    confirm_panel.render(document.body);
    confirm_panel.subscribe("show", function() {
        document.getElementById("proceed").focus();
    });
    confirm_panel.show();

    CPANEL._thispage.cancel = function() {
        confirm_panel.hideEvent.subscribe(confirm_panel.destroy);
        confirm_panel.hide();

        delete CPANEL._thispage.do_delete_key;
        delete CPANEL._thispage.cancel;
    };

    CPANEL._thispage.do_delete_key = function() {
        var to_leave_authorized = is_authorized && document.getElementById("leave_authorized_checkbox") && document.getElementById("leave_authorized_checkbox").checked;

        var throbber_panel = new YAHOO.widget.Panel("throbber_panel", {
            fixedcenter: true,
            modal: true,
            underlay: null,
            close: false,
            effect: fade_effect,
            constraintoviewport: true
        });

        throbber_panel.setHeader("<div class='lt'></div><span>" + "&nbsp;" + "</span><div class='rt'></div>");
        throbber_panel.setBody(CPANEL.icons.ajax + "&nbsp;Deleting " + file + "...");
        throbber_panel.render(document.body);

        confirm_panel.destroy();
        throbber_panel.show();

        var callback = {
            success: function(o) {
                var response = YAHOO.lang.JSON.parse(o.responseText);

                if (response.metadata.result == 1) {
                    var action = to_leave_authorized ? "deleted;<br />however, this key is still authorized and will continue to allow access" : is_authorized ? "deauthorized and deleted" : "deleted";

                    var info_panel = new YAHOO.widget.Panel("delete_panel", {
                        fixedcenter: true,
                        modal: true,
                        underlay: null,
                        close: false,
                        constraintoviewport: true
                    });

                    info_panel.setBody(file.html_encode() + " has been " + action + ".");
                    info_panel.subscribe("show", function() {
                        setTimeout(function() {
                            info_panel.hide();
                        }, 1000);
                    });

                    if (to_leave_authorized) {
                        var key_index = context_row.id.match(/^\d+/)[0];
                        var filename_span = document.getElementById(key_index + "-filename");
                        filename_span.innerHTML = CPANEL._no_file_html;
                    } else {
                        var context_tbody = context_row.parentNode;
                        context_tbody.removeChild(context_row.nextSibling);
                        context_tbody.removeChild(context_row);

                        CPANEL.util.zebra(context_tbody);
                    }
                } else {
                    var info_panel = new CPANEL.widgets.Modal("delete_panel");
                    info_panel.setBody(response.metadata.reason || "Unknown error");
                    info_panel.cfg.setProperty("effect", null);
                }

                info_panel.subscribe("hide", function() {
                    info_panel.destroy();
                });

                info_panel.setHeader("<div class='lt'></div><span>" + "&nbsp;" + "</span><div class='rt'></div>");
                info_panel.render(document.body);

                throbber_panel.destroy();
                info_panel.show();

                info_panel.cfg.setProperty("effect", fade_effect);
            },
            failure: function(o) {
                throbber_panel.destroy();
                alert("AJAX request failed.");
            }
        };

        YAHOO.util.Connect.asyncRequest(
            "GET",
            CPANEL.urls.whm_api("deletesshkey", {
                "file": file,
                "leave_authorized": to_leave_authorized ? 1 : 0,
                "api.version": 1
            }),
            callback,
            ""
        );
    };
}

// ----------------------------------------------------------------------
// null: invalid key
// true/false: encrypted

function check_private_key(trimmed_key_text) {
    var key_match = trimmed_key_text.match(CPANEL._regexes.private_ssh2);
    var encrypted;
    if (key_match) {
        encrypted = key_match[2].match(/ENCRYPTED/) || !key_match[3].match(/^MII/);
    } else {
        key_match = trimmed_key_text.match(CPANEL._regexes.putty_ssh2);
        if (key_match) {
            encrypted = !key_match[2].match(/none/) || !key_match[5].match(/^AAAA/);
        }
    }

    if (!key_match) {
        return null;
    } else {
        return !!encrypted;
    }
}

// ----------------------------------------------------------------------

function make_query_string(data) {
    var query_string_parts = [];
    for (var key in data) {
        var value = data[key];
        var encoded_key = encodeURIComponent(key);
        if (YAHOO.lang.isArray(value)) {
            for (var cv = 0; cv < value.length; cv++) {
                query_string_parts.push(encoded_key + "=" + encodeURIComponent(value[cv]));
            }
        } else {
            query_string_parts.push(encoded_key + "=" + encodeURIComponent(value));
        }
    }

    return query_string_parts.join("&");
}

function get_query_string_from_form(form) {
    return get_data_from_form(form, true);
}
var TRIM_FORM_DATA = true;

function get_data_from_form(form, url_instead) {
    if (typeof form == "string") {
        form = document.getElementById(form);
    }

    if (url_instead) {
        var form_data = [];
        var _add_to_form_data = function(new_name, new_value) {
            if (TRIM_FORM_DATA) {
                new_value = new_value.trim();
            }
            form_data.push(encodeURIComponent(new_name) + "=" + encodeURIComponent(new_value));
        };
    } else {
        var form_data = {};
        var _add_to_form_data = function(new_name, new_value) {
            if (TRIM_FORM_DATA) {
                new_value = new_value.trim();
            }
            if (new_name in form_data) {
                if (YAHOO.lang.isArray(form_data[new_name])) {
                    form_data[new_name].push(new_value);
                } else {
                    form_data[new_name] = [form_data[new_name], new_value];
                }
            } else {
                form_data[new_name] = new_value;
            }
        };
    }

    var form_elements = form.elements;
    for (var fc = 0, cur_control; cur_control = form_elements[fc]; fc++) {
        if ("value" in cur_control && "name" in cur_control && cur_control.name && !cur_control.disabled) {
            var control_name = cur_control.nodeName.toLowerCase();
            if (control_name == "input") {
                var control_type = cur_control.type.toLowerCase();
                var control_form_name = cur_control.name;

                switch (control_type) {
                    case "radio":
                    case "checkbox":
                        if (cur_control.checked) {
                            _add_to_form_data(cur_control.name, cur_control.value);
                        }
                        break;
                    default:
                        _add_to_form_data(cur_control.name, cur_control.value);
                        break;
                }
            } else if (control_name == "select") {
                if (cur_control.multiple) {
                    var cur_options = cur_control.options;
                    for (var o = 0, cur_opt; cur_opt = cur_options[o]; o++) {
                        if (cur_opt.selected && !cur_opt.disabled) {
                            _add_to_form_data(cur_control.name, cur_control.value);
                        }
                    }
                } else {
                    _add_to_form_data(cur_control.name, cur_control.options[cur_control.selectedIndex].value);
                }
            } else if ((control_name == "button") || (control_name == "textarea")) {
                _add_to_form_data(cur_control.name, cur_control.value);
            }
        }
    }

    if (url_instead) {
        return form_data.join("&");
    } else {
        return form_data;
    }
}

var get_background_color = function(obj) {
    var cur_obj = obj;
    var cur_background;

    do {
        cur_background = YAHOO.util.Dom.getComputedStyle(cur_obj, "backgroundColor");
    } while (cur_background == "transparent" && (cur_obj = cur_obj.parentNode));

    return cur_background;
};

YAHOO.widget.Overlay.prototype.destroy = function() {
    var el = this.element;
    el.parentNode.removeChild(el);
};
