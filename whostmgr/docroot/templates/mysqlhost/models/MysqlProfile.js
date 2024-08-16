/*
# templates/mysqlhost/models/MysqlProfile.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    ["lodash"],
    function(_) {

        function MysqlProfile(defaults) {
            if (!_.isObject(defaults)) {
                defaults = {};
            }
            this.type = "mysql";
            this.active = false;
            this.name = defaults.name || "";
            this.host = defaults.host || "";
            this.port = defaults.port || 3306;
            this.account = defaults.account || "";
            this.password = defaults.password || "";
            this.comment = defaults.comment || "";
            this.is_local = defaults.is_local || void 0;
            this.is_supported = defaults.is_supported || void 0;
        }
        MysqlProfile.prototype.activate = function() {
            this.active = true;
        };
        MysqlProfile.prototype.deactivate = function() {
            this.active = false;
        };
        MysqlProfile.prototype.convertToProfileObject = function(ConvertToThis) {
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

        return MysqlProfile;
    }
);
