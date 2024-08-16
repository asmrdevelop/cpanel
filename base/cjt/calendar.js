/*
calendar.js                                   Copyright(c) 2020 cPanel, L.L.C.
                                                          All rights reserved.
copyright@cpanel.net                                         http://cpanel.net
This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* eslint-disable camelcase, strict */

(function() {

    // class Calendar_With_Time
    // adds time input to a YUI 2 Calendar
    //
    // config options:
    //    cldr_time_format_short: default "h:mm a"
    //    time_template: default "{time_html} {timezone}"
    //    timezone: default auto-detect from Date toString()
    //    default_hours: default 0,  always in 24-hour time
    //    default_minutes: default 0 }
    //    ampm: default [ "AM", "PM" ]
    var CE = YAHOO.util.CustomEvent;

    var Calendar_With_Time = function(container, config) {
        if (!config) {
            config = {};
        }
        if (Calendar_With_Time.localization) {
            YAHOO.lang.augmentObject(config, Calendar_With_Time.localization);
        }

        Calendar_With_Time.superclass.constructor.apply(this, arguments);

        this.hours_change_event = new CE("hours_change", this);
        this.minutes_change_event = new CE("minutes_change", this);
        this.ampm_change_event = new CE("ampm_change", this);

        var cal = this;
        this.renderEvent.subscribe(function() {
            var default_hours = cal.cfg.getProperty("default_hours");
            var hours = cal._format_hours(default_hours);
            var minutes = cal._format_minutes(cal.cfg.getProperty("default_minutes"));

            var template_vals = {
                HOUR: "<input class='cjt_calendarwithtime_hours' size='2' maxlength='2' value='" + hours.html_encode() + "' />",
                MINUTE: "<input class='cjt_calendarwithtime_minutes' size='2' maxlength='2'  value='" + minutes.html_encode() + "' />"
            };

            var time_format_short = cal.cfg.getProperty("cldr_time_format_short");
            var has_ampm = time_format_short.indexOf("a") !== -1;

            var time_html;
            if (has_ampm) {
                var is_pm = (default_hours > 12);
                template_vals.AMPM = "<select class='cjt_calendarwithtime_ampm'>" +
                    "<option value='" + cal.cfg.getProperty("ampm")[0] + "'>" +
                    cal.cfg.getProperty("ampm")[0] +
                    "</option>" +
                    "<option " + (is_pm ? "selected='selected'" : "") +
                    " value='" + cal.cfg.getProperty("ampm")[1] + "'>" +
                    cal.cfg.getProperty("ampm")[1] + "</option>" +
                    "</select>";

                time_html = time_format_short
                    .replace(/h+/i, "{HOUR}")
                    .replace(/m+/, "{MINUTE}")
                    .replace(/a+/, "{AMPM}");
            } else {
                time_html = time_format_short
                    .replace(/h+/i, "{HOUR}")
                    .replace(/m+/, "{MINUTE}");
            }

            time_html = YAHOO.lang.substitute(time_html, template_vals);

            var timezone_html = "<span class='cjt_calendarwithtime_timezone'>" + cal.cfg.getProperty("timezone") + "</span>";

            time_html = YAHOO.lang.substitute(cal.cfg.getProperty("time_template"), {
                time_html: time_html,
                timezone_html: timezone_html
            });

            var time_div = document.createElement("div");
            time_div.className = "cjt_calendarwithtime";
            time_div.innerHTML = time_html;

            cal.time_div = time_div;
            cal.hours_input = DOM.getElementsByClassName("cjt_calendarwithtime_hours", "input", time_div)[0];
            cal.minutes_input = DOM.getElementsByClassName("cjt_calendarwithtime_minutes", "input", time_div)[0];

            YAHOO.util.Event.on(cal.hours_input, "change", function() {
                cal._hours = this.value.trim();
                cal.hours_change_event.fire(cal._hours);
            });
            YAHOO.util.Event.on(cal.minutes_input, "change", function() {
                cal._minutes = this.value.trim();
                cal.minutes_change_event.fire(cal._minutes);
            });

            if (has_ampm) {
                cal.ampm_input = DOM.getElementsByClassName("cjt_calendarwithtime_ampm", "select", time_div)[0];
                YAHOO.util.Event.on(cal.ampm_input, "change", function() {
                    cal._ampm = this.selectedIndex;
                    cal.ampm_change_event.fire(cal._ampm);
                });
            }

            var table = DOM.get(cal.id);
            cal.oDomContainer.insertBefore(time_div, table.nextSibling || undefined);
        });
    };

    var default_timezone;
    var now = new Date();
    var tz_match = now.toString().match(/\(([^\)]+)\)$/);
    if (tz_match) {
        default_timezone = tz_match[1];
    } else {
        var seconds_offset = now.getTimezoneOffset();
        var hours = String(Math.abs(Math.floor(seconds_offset / 60)));
        if (hours.length < 2) {
            hours = "0" + hours;
        }
        var minutes = String(seconds_offset % 60);
        if (minutes.length < 2) {
            minutes = "0" + minutes;
        }

        default_timezone = "GMT" + (seconds_offset > 0 ? "-" : "+") + hours + minutes;
    }

    Calendar_With_Time._config = {
        cldr_time_format_short: {
            value: "h:mm a"
        }, // English-US
        time_template: {
            value: "{time_html} {timezone_html}"
        },
        timezone: {
            value: default_timezone
        },
        default_hours: {
            value: 0
        }, // always in 24-hour time
        default_minutes: {
            value: 0
        },
        ampm: {
            value: ["AM", "PM"]
        }
    };

    YAHOO.lang.extend(Calendar_With_Time, YAHOO.widget.Calendar, {
        setupConfig: function() {
            Calendar_With_Time.superclass.setupConfig.apply(this, arguments);
            for (var key in Calendar_With_Time._config) {
                this.cfg.addProperty(key, Calendar_With_Time._config[key]);
            }
        },

        // returns hour
        _format_hours: function(hours) {
            var match = this.cfg.getProperty("cldr_time_format_short").match(/h+/i);
            var h = match[0];
            var hours_string = hours.toString();
            if (h === "h" || h === "hh") {
                if (hours > 12) {
                    hours -= 12;
                }

                if (hours === 0) {
                    hours_string = "12";
                } else if (h === "hh" && hours_string.length < 2) {
                    hours_string = "0" + hours_string;
                } else {
                    hours_string = hours.toString();
                }
            } else if (h === "HH" && hours < 10) {
                hours_string = "0" + hours;
            }

            return hours_string;
        },
        _format_minutes: function(minutes) {
            var match = this.cfg.getProperty("cldr_time_format_short").match(/m+/);
            var m = match[0];
            var minutes_string;
            if (m === "mm" && minutes < 10) {
                minutes_string = "0" + minutes;
            } else {
                minutes_string = minutes.toString();
            }

            return minutes_string;
        },
        set_hours: function(hours) {
            if (typeof hours !== "number") {
                return;
            }
            if (hours < 0 || hours > 23) {
                return;
            }
            hours = Math.floor(hours);

            if (this.ampm_input) {
                var is_pm = hours > 12;
                this.ampm_input.selectedIndex = is_pm ? 1 : 0;
            }

            this.hours_input.value = this._format_hours(hours);
        },
        set_minutes: function(minutes) {
            if (typeof minutes !== "number") {
                return;
            }
            if (minutes < 0 || minutes > 59) {
                return;
            }
            minutes = Math.floor(minutes);

            this.minutes_input.value = this._format_minutes(minutes);
        },
        getSelectedDates: function() {
            var dates = Calendar_With_Time.superclass.getSelectedDates.apply(this, arguments);
            this.time_is_valid = false;

            var hours = parseInt(this.hours_input.value.trim());
            if (isNaN(hours)) {
                return dates;
            }
            var minutes = parseInt(this.minutes_input.value.trim());
            if (isNaN(minutes)) {
                return dates;
            }

            if (minutes < 0 || minutes > 59) {
                return [];
            }

            if (hours <= 12 && this.ampm_input) {
                if (hours < 1) {
                    return dates;
                }
                var selected = this.ampm_input.selectedIndex;
                switch (selected) {
                    case 0: // AM
                        if (hours === 12) {
                            hours = 0;
                        }
                        break;
                    case 1: // PM
                        if (hours !== 12) {
                            hours += 12;
                        }
                }
            } else {
                if (hours < 0) {
                    return dates;
                }
            }

            if (hours > 23) {
                return dates;
            }

            var cur_date;
            for (var d = 0; cur_date = dates[d]; d++) {
                cur_date.setHours(hours);
                cur_date.setMinutes(minutes);
            }

            this.time_is_valid = true;

            return dates;
        }
    });

    CPANEL.widgets.Calendar_With_Time = Calendar_With_Time;

})();
