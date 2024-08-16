/* jshint -W108 */
// check to be sure the CPANEL global object already exists
if (typeof CPANEL == "undefined" || !CPANEL) {
    alert("You must include the CPANEL global object before including password.js!");
} else {
    if (!window.LOCALE) {
        window.LOCALE = new CPANEL.Locale();
    }

    /**
        The password module contains methods used for random password generation, strength validation, etc
        @module password
*/

    /**
        The password class contains methods used for random password generation, strength validation, etc
        @class password
        @namespace CPANEL
        @extends CPANEL
*/
    CPANEL.password = {

        // this function
        setup: function(password1_el, password2_el, strength_bar_el, password_strength, create_strong_el, why_strong_link_el, why_strong_text_el, min_length) {

            // check that we have received enough arguments
            if (YAHOO.util.Dom.inDocument(password1_el) == false) {
                alert("CPANEL.password.setup error: password1_el argument does not exist in the DOM!");
            }
            if (YAHOO.util.Dom.inDocument(password2_el) == false) {
                alert("CPANEL.password.setup error: password2_el argument does not exist in the DOM!");
            }
            if (YAHOO.util.Dom.inDocument(strength_bar_el) == false) {
                alert("CPANEL.password.setup error: strength_bar_el argument does not exist in the DOM!");
            }
            if (CPANEL.validate.positive_integer(password_strength) == false && password_strength != -1) {
                alert("CPANEL.password.setup error: password strength is not a positive integer!");
            }

            // handle optional arguments and set default value
            if (typeof min_length == "undefined" || CPANEL.validate.integer(min_length) == false) {
                min_length = 5;
            }

            // create the strength bar
            var password_bar = new CPANEL.password.strength_bar(strength_bar_el);

            // function to verify password strength
            var verify_password_strength = function() {
                if (password_bar.current_strength >= password_strength) {
                    return true;
                }
                return false;
            };

            // update the strength bar when we type in the password field
            password_bar.attach(password1_el, function() {
                strength_validator.verify();
            });

            // create a validator for password strength
            var strength_validator = new CPANEL.validate.validator(LOCALE.maketext("Password Strength"));
            if (password_strength != -1) {
                strength_validator.add(password1_el, "min_length(%input%, 1)", LOCALE.maketext("Password cannot be empty."));
            }
            if (min_length > 0) {
                strength_validator.add(password1_el, "min_length(%input%," + min_length + ")", LOCALE.maketext("Passwords must be at least [quant,_1,character,characters] long.", min_length));
            }
            if (password_strength > 0) {
                strength_validator.add(password1_el, verify_password_strength, LOCALE.maketext("Password strength must be at least [numf,_1].", password_strength));
            }
            strength_validator.attach();

            // create a validator for the two passwords matching
            var matching_validator = new CPANEL.validate.validator(LOCALE.maketext("Passwords Match"));
            matching_validator.add(password2_el, "equals('" + password1_el + "', '" + password2_el + "')", LOCALE.maketext("Passwords do not match."));
            matching_validator.attach();

            // create strong password link
            if (YAHOO.util.Dom.inDocument(create_strong_el) == true) {

                // function that executes when a user clicks the "use" button on the strong password dialog
                var fill_in_strong_password = function(strong_pass) {

                    // fill in the two fields
                    YAHOO.util.Dom.get(password1_el).value = strong_pass;
                    YAHOO.util.Dom.get(password2_el).value = strong_pass;

                    // verify the matching validator
                    matching_validator.verify();

                    // update the strength bar
                    password_bar.check_strength(password1_el, function() {

                        // verify the password strength
                        strength_validator.verify();
                    });
                };

                // add an event handler for the "create strong password" link
                YAHOO.util.Event.on(create_strong_el, "click", function() {
                    CPANEL.password.generate_password(fill_in_strong_password);
                });
            }

            // add an event handler for the "why?" link
            if (YAHOO.util.Dom.inDocument(why_strong_link_el) == true && YAHOO.util.Dom.inDocument(why_strong_text_el) == true) {
                CPANEL.panels.create_help(why_strong_link_el, why_strong_text_el);
            }

            // return the two validator objects we created
            return [strength_validator, matching_validator];
        },

        strength_bar: function(el) {

            // save each request so that we can cancel the last one when we fire off a new one
            this.ajax_request;

            // get the password bar element
            if (YAHOO.util.Dom.inDocument(el) == false) {
                alert("Failed to initialize password strength bar." + "\n" + "Could not find " + el + " in the DOM.");
            }
            this.strength_bar_el = YAHOO.util.Dom.get(el);

            // initialize the password strength at 0
            this.current_strength = 0;
            CPANEL.password.show_strength_bar(this.strength_bar_el, 0);

            // attach the password bar to an input field
            this.attach = function(input_el, callback_function) {

                if (YAHOO.util.Dom.inDocument(input_el) == false) {
                    alert("Failed to attach strength bar object.\n Could not find " + input_el + "in the DOM.");
                } else {

                    // if no callback function was added create one that does nothing
                    if (typeof (callback_function) === "undefined") {
                        callback_function = function() {};
                    }

                    var callback_args = {
                        "input_el": input_el,
                        "func": callback_function
                    };

                    // add event handlers to the input field
                    if (CPANEL.dom.has_oninput) {
                        EVENT.on(input_el, "input", oninput_listener, callback_args);
                    } else {
                        EVENT.on(input_el, "keyup", oninput_listener, callback_args);
                        EVENT.on(input_el, "change", oninput_listener, callback_args);

                        // The delay seems to be necessary.
                        EVENT.on(input_el, "paste", function() {
                            var that = this,
                                args = arguments;
                            setTimeout(function() {
                                oninput_listener.apply(that, args);
                            }, 5);
                        }, callback_args);
                    }
                }
            };

            // reset the bar
            this.destroy = function() {
                this.strength_bar_el.innerHTML = "";
                this.current_strength = 0;
            };

            // public wrapper for the check strength function
            this.check_strength = function(input_el, callback_function) {
                _check_strength(null, {
                    "input_el": input_el,
                    "func": callback_function
                });
            };

            // PRIVATE METHODS
            var that = this;

            var pw_strength_timeout;
            var oninput_listener = function(e, o) {
                clearTimeout(pw_strength_timeout);

                // if a request is currently active cancel it
                if (YAHOO.util.Connect.isCallInProgress(that.ajax_request)) {
                    YAHOO.util.Connect.abort(that.ajax_request);
                }

                var password = DOM.get(o.input_el).value;

                if (password in cached_strengths) {
                    that.current_strength = cached_strengths[password];
                    _update_strength_bar(cached_strengths[password]);
                    o.func();
                } else {
                    pw_strength_timeout = setTimeout(function() {
                        _check_strength(e, o);
                    }, CPANEL.password.keyup_delay_ms);
                }
            };

            var cached_strengths = {
                "": 0
            };

            // check the strength of the password
            var _check_strength = function(e, o) {


                // show a loading indicator
                _update_strength_bar(null);

                // set the value
                var password = YAHOO.util.Dom.get(o.input_el).value;

                // create the callback functions
                var callback = {
                    success: function(o2) {

                        // the responseText should be JSON data
                        try {
                            var response = YAHOO.lang.JSON.parse(o2.responseText);
                        } catch (e) {

                            // TODO: write CPANEL.errors.json();
                            alert("JSON Parse Error: Please refresh the page and try again.");
                            return;
                        }

                        // make sure strength is an integer between 0 and 100
                        var strength = parseInt(response.strength);

                        if (strength < 0) {
                            strength = 0;
                        } else if (strength > 100) {
                            strength = 100;
                        }

                        cached_strengths[password] = strength;

                        that.current_strength = strength;

                        _update_strength_bar(strength);

                        // run the callback function
                        o.func();
                    },

                    failure: function(o2) {
                        var error = '<table style="width: 100%; height: 100%; padding: 0px; margin: 0px"><tr>';
                        error += '<td style="padding: 0px; margin: 0px; text-align: center" valign="middle">AJAX Error: Try Again</td>';
                        error += "</tr></table>";
                        YAHOO.util.Dom.get(that.strength_bar_el).innerHTML = error;
                    }
                };

                // if a request is currently active cancel it
                if (YAHOO.util.Connect.isCallInProgress(that.ajax_request)) {
                    YAHOO.util.Connect.abort(that.ajax_request);
                }

                // send the AJAX request
                var url = CPANEL.urls.password_strength();
                that.ajax_request = YAHOO.util.Connect.asyncRequest("POST", url, callback, "password=" + encodeURIComponent(password));
            };

            var _update_strength_bar = function(strength) {
                CPANEL.password.show_strength_bar(that.strength_bar_el, strength);
            };
        },

        /**
                Shows a password strength bar for a given strength.
                @method show_strength_bar
                @param {DOM element} el The DOM element to put the bar.  Should probably be a div.
                @param {integer, null} strength The strength of the bar, or null for "updating".
        */
        show_strength_bar: function(el, strength) {

            el = YAHOO.util.Dom.get(el);

            // NOTE: it would probably be more appropriate to move these colors into a CSS file, but I want the CJT to be self-contained.  this solution is fine for now
            var phrase, color;
            if (strength === null) {
                phrase = LOCALE.maketext("Loading …");
            } else if (strength >= 80) {
                phrase = LOCALE.maketext("Very Strong");
                color = "#8FFF00"; // lt green
            } else if (strength >= 60) {
                phrase = LOCALE.maketext("Strong");
                color = "#C5FF00"; // chartreuse
            } else if (strength >= 40) {
                phrase = LOCALE.maketext("OK");
                color = "#F1FF4D"; // yellow
            } else if (strength >= 20) {
                phrase = LOCALE.maketext("Weak");
                color = "#FF9837"; // orange
            } else if (strength >= 0) {
                phrase = LOCALE.maketext("Very Weak");
                color = "#FF0000"; // red
            }

            var html;

            // container div with relative positioning, height/width set to 100% to fit the container element
            html = '<div style="position: relative; width: 100%; height: 100%">';

            // phrase div fits the width and height of the container div and has its text vertically and horizontally centered; has a z-index of 1 to put it above the color bar div
            html += '<div style="position: absolute; left: 0px; width: 100%; height: 100%; text-align: center; z-index: 1; padding: 0px; margin: 0px' + (strength === null ? "; font-style:italic; color:graytext" : "") + '">';
            html += '<table style="width: 100%; height: 100%; padding: 0px; margin: 0px"><tr style="padding: 0px; margin: 0px"><td valign="middle" style="padding: 0px; margin: 0px">' + phrase + (strength !== null ? (" (" + strength + "/100)") : "") + "</td></tr></table>"; // use a table to vertically center for greatest compatibility
            html += "</div>";

            if (strength !== null) {

                // color bar div fits the width and height of the container div and width changes depending on the strength of the password
                html += '<div style="position: absolute; left: 0px; width: ' + strength + "%; height: 100%; background-color: " + color + ';"></div>';
            }

            // close the container div
            html += "</div>";

            el.innerHTML = html;
        },

        // Time in ms between last keyup and sending off the password strength CGI
        // AJAX call. Useful to prevent an excess of aborted CGI calls.
        keyup_delay_ms: 500,


        /**
                Creates a strong password
                @method create_password
                @param {object} options (optional) options to specify limitations on the password
                @return {string} a strong password
        */
        create_password: function(options) {

            // set the length
            var length;
            if (CPANEL.validate.positive_integer(options.length) === false) {
                length = 12;
            } else {
                length = options.length;
            }

            // possible password characters
            var uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
            var lowercase = "abcdefghijklmnopqrstuvwxyz";
            var numbers = "0123456789";
            var symbols = "!@#$%^&*()-_=+{}[];,.?~";

            var chars = "";
            if (options.uppercase == true) {
                chars += uppercase;
            }
            if (options.lowercase == true) {
                chars += lowercase;
            }
            if (options.numbers == true) {
                chars += numbers;
            }
            if (options.symbols == true) {
                chars += symbols;
            }

            // generate the thing
            var password = "";
            for (var i = 0; i < length; i++) {
                var rnum = Math.floor(Math.random() * chars.length);
                password += chars.substring(rnum, rnum + 1);
            }

            return password;
        },

        /**
                Pops up a modal dialog box containing a strong password.
                @method generate_password
                @param {function} use_password_function A function that gets executed when the user clicks the "Use Password" button on the modal box.  The function will have the password string sent to it as its first argument.
                @param {integer} length (optional) the length of the random password to generate.  defaults to 15
                launch_el - the element you clicked on to launch the password generator (it appears relative to this element)
        */
        generate_password: function(use_password_function, length) {

            // create the password
            var default_options = {
                length: 12,
                uppercase: true,
                lowercase: true,
                numbers: true,
                symbols: true
            };
            var password = this.create_password(default_options);

            // remove the panel if it already exists
            if (YAHOO.util.Dom.inDocument("generate_password_panel") == true) {
                var remove_me = YAHOO.util.Dom.get("generate_password_panel");
                YAHOO.util.Event.purgeElement(remove_me, true);
                remove_me.parentNode.removeChild(remove_me);
            }

            // create the panel
            var panel_options = {
                width: "380px",
                fixedcenter: true,
                close: true,
                draggable: false,
                zindex: 1000,
                visible: true,
                modal: true,
                postmethod: "manual",
                hideaftersubmit: false,
                strings: {
                    "close": LOCALE.maketext("Close")
                },
                buttons: [{
                    text: LOCALE.maketext("Use Password"),
                    handler: function() {
                        this.submit();
                    }
                }, {
                    text: LOCALE.maketext("Cancel"),
                    handler: function() {
                        this.cancel();
                    }
                }],
                effect: {
                    effect: CPANEL.animate.ContainerEffect.FADE_MODAL,
                    duration: 0.25
                }
            };
            var panel = new YAHOO.widget.Dialog("generate_password_panel", panel_options);

            panel.renderEvent.subscribe(function() {
                var buttons = this.getButtons();
                YAHOO.util.Dom.addClass(buttons[0], "input-button disabled");
                YAHOO.util.Dom.addClass(buttons[1], "input-button");
            });


            // header
            var header = '<div class="header"><div class="lt"></div>';
            header += "<span>" + LOCALE.maketext("Password Generator") + "</span>";
            header += '<div class="rt"></div></div>';
            panel.setHeader(header);

            // body
            var body = '<div id="generate_password_body_div">';

            body += '<table id="generate_password_table">';
            body += "<tr>";
            body += '<td><input id="generate_password_input_field" type="text" value="' + password + '" size="27"  /></td>';
            body += "</tr>";
            body += "<tr>";
            body += '<td><input type="button" class="input-button btn btn-primary" value="' + LOCALE.maketext("Generate Password") + '" id="generate_password_reload" /></td>';
            body += "</tr>";
            body += "<tr>";
            body += '<td><span class="action_link" id="generate_password_toggle_advanced_options">' + LOCALE.maketext("Advanced Options") + " &raquo;</span>";

            body += '<div id="generate_password_advanced_options" style="display: none"><table style="width: 100%">';
            body += "<tr>";
            body += '<td colspan="2">' + LOCALE.maketext("Length") + ': <input type="text" id="generate_password_length" size="2" maxlength="2" value="12" /> (10-18)</td>';
            body += "</tr>";
            body += "<tr>";
            body += '<td width="50%">' + LOCALE.maketext("Alpha Characters") + ":</td>";
            body += '<td width="50%">' + LOCALE.maketext("Non Alpha Characters") + ":</td>";
            body += "</tr><tr>";
            body += '<td><input type="radio" name="generate_password_alpha" id="generate_password_mixed_alpha" checked="checked" /> <label for="generate_password_mixed_alpha">' + LOCALE.maketext("Both") + " (aBcD)</label></td>";
            body += '<td><input type="radio" name="generate_password_nonalpha" id="generate_password_mixed_nonalpha" checked="checked" /> <label for="generate_password_mixed_nonalpha">' + LOCALE.maketext("Both") + " (1@3$)</label></td>";
            body += "</tr><tr>";
            body += '<td><input type="radio" name="generate_password_alpha" id="generate_password_lowercase" /> <label for="generate_password_lowercase">' + LOCALE.maketext("Lowercase") + " (abc)</label></td>";
            body += '<td><input type="radio" name="generate_password_nonalpha" id="generate_password_numbers" /> <label for="generate_password_numbers">' + LOCALE.maketext("Numbers") + " (123)</label></td>";
            body += "</tr><tr>";
            body += '<td><input type="radio" name="generate_password_alpha" id="generate_password_uppercase" /> <label for="generate_password_uppercase">' + LOCALE.maketext("Uppercase") + " (ABC)</label></td>";
            body += '<td><input type="radio" name="generate_password_nonalpha" id="generate_password_symbols" /> <label for="generate_password_symbols">' + LOCALE.maketext("Symbols") + " (@#$)</label></td>";
            body += "</tr>";
            body += "</table></div>";

            body += "</td></tr></table>";

            body += '<p><input type="checkbox" id="generate_password_confirm" /> <label for="generate_password_confirm">' + LOCALE.maketext("I have copied this password in a safe place.") + "</label></p>";

            body += "</div>";
            panel.setBody(body);

            // render the panel
            panel.render(document.body);

            if (CPANEL.password.fade_from) {
                CPANEL.password.fade_from.fade_to(panel);
            }

            // make sure the input button is not checked (defeat browser caching)
            YAHOO.util.Dom.get("generate_password_confirm").checked = false;


            panel.validate = function() {
                return DOM.get("generate_password_confirm").checked;
            };
            panel.submitEvent.subscribe(function() {
                use_password_function(YAHOO.util.Dom.get("generate_password_input_field").value);
                this.cancel();
            });
            panel.cancelEvent.subscribe(function() {
                if (CPANEL.password.fade_from) {
                    panel.fade_to(CPANEL.password.fade_from);
                }
            });
            panel.hideEvent.subscribe(panel.destroy, panel, true);


            YAHOO.util.Event.on("generate_password_confirm", "click", function() {
                this.checked ? YAHOO.util.Dom.removeClass(panel.getButtons()[0], "disabled") : YAHOO.util.Dom.addClass(panel.getButtons()[0], "disabled");
            });

            // select the input field when the user clicks on it
            YAHOO.util.Event.on("generate_password_input_field", "click", function() {
                YAHOO.util.Dom.get("generate_password_input_field").select();
            });

            YAHOO.util.Event.on("generate_password_toggle_advanced_options", "click", function() {
                CPANEL.animate.slide_toggle("generate_password_advanced_options");
            });

            // get the password options from the interface
            var get_password_options = function() {
                var options = {};

                var length_el = YAHOO.util.Dom.get("generate_password_length");
                var length = length_el.value;
                if (CPANEL.validate.positive_integer(length) == false) {
                    length = 12;
                } else if (length < 10) {
                    length = 10;
                } else if (length > 18) {
                    length = 18;
                }
                length_el.value = length;
                options.length = length;

                if (YAHOO.util.Dom.get("generate_password_mixed_alpha").checked == true) {
                    options.uppercase = true;
                    options.lowercase = true;
                } else {
                    options.uppercase = YAHOO.util.Dom.get("generate_password_uppercase").checked;
                    options.lowercase = YAHOO.util.Dom.get("generate_password_lowercase").checked;
                }

                if (YAHOO.util.Dom.get("generate_password_mixed_nonalpha").checked == true) {
                    options.numbers = true;
                    options.symbols = true;
                } else {
                    options.numbers = YAHOO.util.Dom.get("generate_password_numbers").checked;
                    options.symbols = YAHOO.util.Dom.get("generate_password_symbols").checked;
                }

                return options;
            };

            // generate a new password and select the input field text when the user clicks the refresh text
            var generate_new_password = function() {
                YAHOO.util.Dom.get("generate_password_input_field").value = CPANEL.password.create_password(get_password_options());
            };
            if (this.beforeExtendPanel) {
                this.beforeExtendPanel();
                YAHOO.util.Dom.get("generate_password_input_field").value = CPANEL.password.create_password(get_password_options());
            }

            YAHOO.util.Event.on("generate_password_reload", "click", generate_new_password);

            // watch the advanced options inputs
            var password_options = [
                "generate_password_mixed_alpha", "generate_password_uppercase", "generate_password_lowercase",
                "generate_password_mixed_nonalpha", "generate_password_numbers", "generate_password_symbols"
            ];
            YAHOO.util.Event.on(password_options, "change", generate_new_password);
        }

    }; // end password object
} // end else statement
