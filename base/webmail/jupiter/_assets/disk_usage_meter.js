/*
# cpanel - base/webmail/jupiter/_assets/disk_usage_meter.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global CPANEL: false */

/* jshint -W064 */

/*
 * Both of the following classes expose the same methods:
 *
 * @class Disk_Usage_Meter_Cpuser
 *
 *     //The parameter is a DOM element that will contain the disk usage.
 *     var du_meter = new Disk_Usage_Meter_Cpuser(usage_el);
 *
 *     //Sets the disk usage immediately.
 *     du_meter.set( usage_in_bytes );
 *
 *     //Fires off an AJAX request to fetch the disk usage;
 *     //sets the disk usage once the API call returns.
 *     du_meter.refresh();
 *
 * @class Disk_Usage_Meter_Mailuser
 *
 *     //For a mail user that has no quota.
 *     var du_meter = new Disk_Usage_Meter_Mailuser(usage_el);
 *
 *     //or …
 *
 *     //For a mail user with a quota.
 *     //
 *     //“link_el” is a DOM element that will
 *     //receive the disk usage percentage as a two-character integer in the
 *     //“data-quotausage” attribute. (i.e., 0-9 will have a leading “0”)
 *     //
 *     //It is assumed that the user’s quota will not change over the lifetime
 *     //of this object; adding an interface to change that would be trivial.
 *     //
 *     var du_meter = new Disk_Usage_Meter_Mailuser(usage_el, link_el, quota_in_bytes);
 *
 */
(function(window) {
    "use strict";

    function Disk_Usage_Meter_Base(el) {
        this._el = el;
    }

    $.extend(
        Disk_Usage_Meter_Base.prototype,
        {
            _get_refresher: function _get_refresher() {
                var dum_obj = this;

                // TODO: Update this to whatever new, post-CJT1 hotness we
                // concoct for API access without AngularJS.
                return CPANEL.api( {
                    version: 3,
                    module: this.MODULE,
                    func: this.FUNC,
                    callback: {
                        success: function(o) {
                            delete dum_obj._refreshing;

                            var usage = parseInt( dum_obj._get_usage(o.cpanel_data), 10 );
                            dum_obj.set(usage);

                        },
                        failure: function(o) {
                            delete dum_obj._refreshing;
                            console.error(o);
                        },
                    },
                } );
            },

            refresh: function refresh() {
                if (this._refreshing) {
                    return false;
                }

                this._refreshing = this._get_refresher();

                return true;
            },

            set: function set(usage) {
                this._el.textContent = LOCALE.format_bytes(usage);

                if (this._after_set) {
                    this._after_set(usage);
                }
            },
        }
    );

    function Disk_Usage_Meter_Cpuser(el) {
        Disk_Usage_Meter_Base.call(this, el);
    }
    Disk_Usage_Meter_Cpuser.prototype = Object.create(
        Disk_Usage_Meter_Base.prototype
    );
    $.extend(
        Disk_Usage_Meter_Cpuser.prototype,
        {
            MODULE: "Email",
            FUNC: "get_main_account_disk_usage_bytes",
            _get_usage: String,
        }
    );

    function Disk_Usage_Meter_Mailuser(el, usage_data_el, quota) {
        Disk_Usage_Meter_Base.call(this, el);
        this._usage_data_el = usage_data_el;
        this._quota = quota;
    }
    Disk_Usage_Meter_Mailuser.prototype = Object.create(
        Disk_Usage_Meter_Base.prototype
    );
    $.extend(
        Disk_Usage_Meter_Mailuser.prototype,
        {
            MODULE: "Email",
            FUNC: "list_pops_with_disk",
            _get_usage: function(cpanel_data) {
                return cpanel_data[0]._diskused;
            },

            _after_set: function(usage) {
                if (this._quota) {
                    var usage_pct = Math.min( 99, Math.floor(100 * usage / this._quota) );

                    if (String(usage_pct).length === 1) {
                        usage_pct = "0" + usage_pct;
                    }

                    this._usage_data_el.setAttribute("data-quotausage", usage_pct);
                }
            },
        }
    );

    window.Disk_Usage_Meter_Cpuser = Disk_Usage_Meter_Cpuser;
    window.Disk_Usage_Meter_Mailuser = Disk_Usage_Meter_Mailuser;
})(window);
