if (!window.CPANEL) {
    window.CPANEL = {};
}

(function() {

    var TWO_EXP_32 = Math.pow(2, 32);

    CPANEL.net = {

        // No validation
        ipv4_to_number: function(str) {
            return str.split(".").reduce(function(a, b) {
                return a * 256 + Number(b);
            }, 0);
        },

        // No validation
        number_to_ipv4: function(num) {
            return num.toString(2).lpad(32, "0").match(/.{8}/g).map(function(s) {
                return parseInt(s, 2);
            }).join(".");
        },

        cidr_netmask_to_number: function(bits) {
            return TWO_EXP_32 - Math.pow(2, 32 - bits);
        },

        cidr_netmask_is_valid: function(bits) {
            return /^[1-9]\d?$/.test(bits) && (bits < 33);
        },

        ipv4_netmask_is_valid: function(ipv4) {
            var valid_netmasks = {};
            for (var n = 1; n < 33; n++) {
                valid_netmasks[CPANEL.net.number_to_ipv4(CPANEL.net.cidr_netmask_to_number(n))] = true;
            }

            CPANEL.net.ipv4_netmask_is_valid = function(ipv4) {
                return (ipv4.replace(/0+(\d)/g, "$1") in valid_netmasks);
            };
            return CPANEL.net.ipv4_netmask_is_valid(ipv4);
        },

        // Three formats: IP/IPmask, IP/bits, IP-IP
        // Returns undefined if anything doesn't work.
        ipv4_range_to_min_max: function(str) {
            var low, high;

            if (/\//.test(str)) {
                var match = /^([^\/]+)\/(.*)$/.exec(str);
                if (!match) {
                    return;
                }

                low = match[1];
                if (!CPANEL.validate.ip(low)) {
                    return;
                }

                var netmask = match[2];
                var netmask_length;
                if (/\./.test(netmask)) {
                    if (!CPANEL.net.ipv4_netmask_is_valid(netmask)) {
                        return;
                    }
                    netmask = CPANEL.net.ipv4_to_number(netmask);
                    netmask_length = netmask.toString(2).match(/^1+/)[0].length;
                } else {
                    if (!CPANEL.net.cidr_netmask_is_valid(netmask)) {
                        return;
                    }
                    netmask_length = netmask;
                    netmask = CPANEL.net.cidr_netmask_to_number(netmask);
                }

                low = CPANEL.net.ipv4_to_number(low);

                // Sanity check: Something like 192.168.0.3/24, while it's
                // parseable, almost certainly stems from an error at some point.
                // So, ensure that the IP given is the actual network IP by
                // checking that all of the IP's non-masked bits are zero.
                if (/[^0]/.test(low.toString(2).lpad(32).substr(netmask_length))) {
                    return;
                }

                high = low + TWO_EXP_32 - netmask - 1;
            } else if (/-/.test(str)) {
                var match = /^([^-]+)-(.+)$/.exec(str);
                if (!match) {
                    return;
                }

                low = match[1];
                if (!CPANEL.validate.ip(low)) {
                    return;
                }

                var high = match[2];
                var high_split = high.split(".");
                var digits_lacking = 4 - high_split.length;

                if (digits_lacking > 0) {
                    high_split.unshift.apply(high_split, low.split(".").slice(0, digits_lacking));
                    high = high_split.join(".");
                } else if (digits_lacking < 0) {
                    return;
                }

                low = CPANEL.net.ipv4_to_number(low);
                high = CPANEL.net.ipv4_to_number(high);

                if (low > high) {
                    return;
                }
            } else {
                return;
            }

            return [low, high];
        }
    };

})();
