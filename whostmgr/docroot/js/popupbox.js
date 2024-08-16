var popupboxcontainer;
var popupbox_current_title;
var default_iframe_height = 345;

function _isFunction(val) {
    return Object.prototype.toString.call(val) === "[object Function]";
}

function do_quick_popupbox(boxname, surl) {
    var argv = do_quick_popupbox.arguments;
    var argc = argv.length;

    var iframe = 0;
    var settings = {};
    var startarg = 2;

    if (boxname.title) {
        iframe = boxname.iframe;
        startarg = 1;
        settings = boxname;
    } else {
        settings.title = boxname;
        settings.url = surl;
    }

    var inner_container_height = default_iframe_height;

    if (boxname.height) {
        inner_container_height = boxname.height;
    }

    var height_style = "height:" + inner_container_height + "px";

    var displaycallback = {
        success: loadquickpopupbox,
        argument: {
            boxname: settings.title,
            callback: settings.callback,
            buttons: settings.buttons,
            processOutput: settings.processOutput

        }
    };
    var input_url = settings.url.split("?");


    var sFormData = input_url[1] + "&popupbox=1&";
    for (var i = startarg; i < argc; i += 2) {
        sFormData += argv[i] + "=" + encodeURIComponent(argv[i + 1]) + "&";
    }

    popupbox_current_title = settings.title;

    if (iframe) {
        display_quickpopupbox(settings.title, "<iframe id='popupboxiframe' style='" + height_style + "; border:0; width:100%;' src='" + CPANEL.icons.ajax_src + "'></iframe>", settings.buttons);
        window.setTimeout(function() {
            document.getElementById("popupboxiframe").src = input_url[0] + "?" + sFormData;
        }, 200);
    } else {
        if (settings.showloading && self["show_loading"]) {
            show_loading("Loading " + settings.title + "...");
        }
        YAHOO.util.Connect.asyncRequest("POST", input_url[0], displaycallback, sFormData);
    }

    return false;
}

function submit_quickpopupbox_callback(o) {
    if (self["clear_ui_status"]) {
        clear_ui_status();
    }
    display_quickpopupbox("Saved " + popupbox_current_title + " ...", o.responseText);
}


function display_quickpopupbox(boxname, html, buttonlist) {
    if (self["clear_ui_status"]) {
        clear_ui_status();
    }


    var buttons = [];
    if (!buttonlist || buttonlist["close_default"]) {
        buttons.push({
            text: "Close",
            handler: function() {
                popupboxcontainer.hide();
            },
            isDefault: true
        });
    }
    if (buttonlist) {
        if (buttonlist["close"]) {
            buttons.push({
                text: "Close",
                handler: function() {
                    popupboxcontainer.hide();
                }
            });
        }
        if (buttonlist["save"]) {
            buttons.push({
                text: "Save",
                handler: function() {
                    popupboxcontainer.submitform();
                    return false;
                },
                isDefault: true
            });
        }
        if (buttonlist["save-iframe"]) {
            buttons.push({
                text: "Save",
                handler: function() {
                    popupboxcontainer.submitiframeform();
                    return false;
                },
                isDefault: true
            });
        }


    }

    if (!popupboxcontainer) {
        popupboxcontainer = new YAHOO.widget.Dialog("popupboxcontainer", {
            width: "580px",
            height: "auto",
            fixedcenter: true,
            close: true,
            draggable: false,
            modal: true,
            "buttons": buttons,
            visible: false,
            zIndex: 2147483647,
        });
        var stop_popupboxcontainer_propagation = function(e) {
            var key_code = YAHOO.util.Event.getCharCode(e);
            if (key_code == 13) {
                YAHOO.util.Event.preventDefault(e);
            }
        };
        YAHOO.util.Event.addListener("popupboxcontainer", "keypress", stop_popupboxcontainer_propagation);
        YAHOO.util.Event.addListener("popupboxcontainer", "keydown", stop_popupboxcontainer_propagation);

        // must always recreate in case buttons change
        popupboxcontainer.submitiframeform = function() {
            var thisIframeEl = document.getElementById("popupboxiframe");
            try {
                if (thisIframeEl.contentWindow) {
                    thisIframeEl.contentWindow.submit_form();
                } else if (thisIframeEl.window) {
                    thisIframeEl.window.submit_form();
                }
            } catch (e) {

            };
        };

        // must always recreate in case buttons change
        popupboxcontainer.submitform = function() {
            if (CPANEL.validate && CPANEL.validate.form_checkers["submit_button"]) {
                CPANEL.validate.form_checkers["submit_button"]();
            }
            var popupEl = document.getElementById("popupboxcontainer");
            var formEl = (popupEl.getElementsByTagName("form"))[0];
            var formA = getFormData(formEl);
            var uriA = ["popupbox=1"];
            for (var i in formA) {
                if (i == "module" || i == "viz") {
                    continue;
                }
                if (formA[i] == true || formA[i] == false) {
                    uriA.push(i + "=" + (formA[i] ? 1 : 0));
                } else {
                    uriA.push(i + "=" + encodeURIComponent(formA[i]));
                }
            }
            var sFormData = uriA.join("&");
            if (self["show_loading"]) {
                show_loading("Saving " + popupbox_current_title + " ...");
            }
            YAHOO.util.Connect.asyncRequest("POST", formEl.action, {
                "success": submit_quickpopupbox_callback
            }, sFormData);
        };

    }
    popupboxcontainer.cfg.queueProperty("buttons", buttons);

    popupboxcontainer.setHeader("<div class='lt'></div><span>" + boxname + "</span><div class='rt'></div>");
    popupboxcontainer.setBody(html);
    popupboxcontainer.render(document.body);
    popupboxcontainer.show();
    popupboxcontainer.render(); /* Safari Fix */
}

function remove_popupbox_buttons() {
    popupboxcontainer.cfg.queueProperty("buttons", [{
        text: "Close",
        handler: function() {
            popupboxcontainer.hide();
        },
        isDefault: true
    }]);
    popupboxcontainer.show();
    popupboxcontainer.render(); /* Safari Fix */
}

function loadquickpopupbox(o) {
    var resp = o.responseText;
    if (o.argument.processOutput && _isFunction(o.argument.processOutput)) {
        resp = o.argument.processOutput(resp);
    }

    display_quickpopupbox(o.argument.boxname, resp, o.argument.buttons);
    if (o.argument.callback) {
        o.argument.callback();
    }
}
