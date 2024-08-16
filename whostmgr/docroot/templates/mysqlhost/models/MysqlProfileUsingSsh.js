/*
# templates/mysqlhost/models/MysqlProfileUsingSsh.js  Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    ["lodash"],
    function(_) {
        function MysqlProfileUsingSsh(defaults) {
            if (!_.isObject(defaults)) {
                defaults = {};
            }
            this.type = "ssh";
            this.active = false;
            this.name = defaults.name || "";
            this.host = defaults.host || "";
            this.port = defaults.port || 22;
            this.account = defaults.account || "";
            this.password = defaults.password || "";
            this.ssh_key = defaults.ssh_key || "";
            this.ssh_passphrase = defaults.ssh_passphrase || "";
            this.escalation_type = defaults.escalation_type || "";
            this.escalation_password = defaults.escalation_password || "";
            this.comment = defaults.comment || "";
            this.is_local = defaults.is_local || void 0;
            this.is_supported = defaults.is_supported || void 0;
        }
        MysqlProfileUsingSsh.prototype.activate = function() {
            this.active = true;
        };
        MysqlProfileUsingSsh.prototype.deactivate = function() {
            this.active = false;
        };
        MysqlProfileUsingSsh.prototype.convertToProfileObject = function(ConvertToThis) {
            return new ConvertToThis({
                active: this.active,
                name: this.name,
                host: this.host,
                account: this.account,
                comment: this.comment,
                is_local: this.is_local,
                is_supported: this.is_supported
            });
        };

        return MysqlProfileUsingSsh;
    }
);
