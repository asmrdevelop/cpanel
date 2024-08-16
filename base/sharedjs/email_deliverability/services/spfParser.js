/*
 * email_deliverability/services/spfParser.js         Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */


define(
    ["lodash"],
    function(_) {

        "use strict";

        var MechanismError = function MechanismError(message, type) {
            this.name = "MechanismError";
            this.message = message;
            this.type = type || "warning";
            this.stack = new Error().stack;
        };

        function domainPrefixCheck(name, pattern, term) {
            var parts = term.match(pattern);
            var value = parts[1];

            if (!value) {
                return null;
            }

            if (value === ":" || value === "/") {
                throw new MechanismError("Blank argument for the " + name + " mechanism", "error");
            }

            // Value starts with ":" so it"s a domain
            if (/^:/.test(value)) {
                value = value.replace(/^:/, "");
            }

            return value;
        }

        function domainCheckNullable(name, pattern, term) {
            return domainCheck(name, pattern, term, true);
        }

        function domainCheck(name, pattern, term, nullable) {
            var value = term.match(pattern)[1];

            if (!nullable && !value) {
                throw new MechanismError("Missing mandatory argument for the " + name + " mechanism", "error");
            }

            if (value === ":" || value === "=") {
                throw new MechanismError("Blank argument for the " + name + " mechanism", "error");
            }

            if (/^(:|=)/.test(value)) {
                value = value.replace(/^(:|=)/, "");
            }

            return value;
        }

        MechanismError.prototype = Object.create(Error.prototype);
        MechanismError.prototype.constructor = MechanismError;

        var MECHANISMS = {
            version: {
                description: "The SPF record version",
                pattern: /^v=(.+)$/i,
                validate: function validate(r) {
                    var version = r.match(this.pattern)[1]; // NOTE: This test can never work since we force match it to spf1 in index.js
                    // if (version !== 'spf1') {
                    // 	throw new MechanismError(`Invalid version '${version}', must be 'spf1'`);
                    // }

                    return version;
                }
            },
            all: {
                description: "Always matches. It goes at the end of your record",
                pattern: /^all$/i
            },
            ip4: {

            // ip4:<ip4-address>
            // ip4:<ip4-network>/<prefix-length>
                description: "Match if IP is in the given range",
                pattern: /^ip4:(([\d.]*)(\/\d+)?)$/i,
                validate: function validate(r) {
                    var parts = r.match(this.pattern);
                    var value = parts[1];

                    if (!value) {
                        throw new MechanismError("Missing or blank mandatory network specification for the 'ip4' mechanism.", "error");
                    }

                    return value;
                }
            },
            ip6: {

            // ip6:<ip6-address>
            // ip6:<ip6-network>/<prefix-length>
                description: "Match if IPv6 is in the given range",
                pattern: /^ip6:((.*?)(\/\d+)?)$/i,
                validate: function validate(r) {
                    var parts = r.match(this.pattern);
                    var value = parts[1];

                    if (!value) {
                        throw new MechanismError("Missing or blank mandatory network specification for the 'ip6' mechanism.", "error");
                    }

                    return value;
                }
            },
            a: {

            // a
            // a/<prefix-length>
            // a:<domain>
            // a:<domain>/<prefix-length>
                description: "Match if IP has a DNS 'A' record in given domain",
                pattern: /a((:.*?)?(\/\d*)?)?$/i,
                validate: function validate(r) {
                    return domainPrefixCheck("a", this.pattern, r);
                }
            },
            mx: {

            // mx
            // mx/<prefix-length>
            // mx:<domain>
            // mx:<domain>/<prefix-length>
                description: "",
                pattern: /mx((:.*?)?(\/\d*)?)?$/i,
                validate: function validate(r) {
                    return domainPrefixCheck("mx", this.pattern, r);
                }
            },
            ptr: {

            // ptr
            // ptr:<domain>
                description: "Match if IP has a DNS 'PTR' record within given domain",
                pattern: /^ptr(:.*?)?$/i,
                validate: function validate(r) {
                    return domainCheckNullable("ptr", this.pattern, r);
                }
            },
            exists: {
                pattern: /^exists(:.*?)?$/i,
                validate: function validate(r) {
                    return domainCheck("exists", this.pattern, r);
                }
            },
            include: {
                description: "The specified domain is searched for an 'allow'",
                pattern: /^include(:.*?)?$/i,
                validate: function validate(r) {
                    return domainCheck("include", this.pattern, r);
                }
            },
            redirect: {
                description: "The SPF record for the value replaces the current record",
                pattern: /redirect(=.*?)?$/i,
                validate: function validate(r) {
                    return domainCheck("redirect", this.pattern, r);
                }
            },
            exp: {
                description: "Explanation message to send with rejection",
                pattern: /exp(=.*?)?$/i,
                validate: function validate(r) {
                    return domainCheck("exp", this.pattern, r);
                }
            }
        };

        var PREFIXES = {
            "+": "Pass",
            "-": "Fail",
            "~": "SoftFail",
            "?": "Neutral"
        };

        var versionRegex = /^v=spf1/i;
        var mechanismRegex = /(\+|-|~|\?)?(.+)/i; // * Values that will be set for every mechanism:
        // Prefix
        // Type
        // Value
        // PrefixDesc
        // Description

        function parseTerm(term, messages) {

        // Match up the prospective mechanism against the mechanism regex
            var parts = term.match(mechanismRegex);
            var record = {}; // It matched! Let's try to see which specific mechanism type it matches

            if (parts !== null) {

            // Break up the parts into their pieces
                var prefix = parts[1];
                var mechanism = parts[2]; // Check qualifier

                if (prefix) {
                    record.prefix = prefix;
                    record.prefixdesc = PREFIXES[prefix];
                } else if (versionRegex.test(mechanism)) {
                    record.prefix = "v";
                } else {

                    // Default to "pass" qualifier
                    record.prefix = "+";
                    record.prefixdesc = PREFIXES["+"];
                }

                var found = false;

                for (var name in MECHANISMS) {
                    if (Object.prototype.hasOwnProperty.call(MECHANISMS, name)) {
                        var settings = MECHANISMS[name]; // Matches mechanism spec

                        if (settings.pattern.test(mechanism)) {
                            found = true;
                            record.type = name;
                            record.description = settings.description;

                            if (settings.validate) {
                                try {
                                    var value = settings.validate.call(settings, mechanism);

                                    if (typeof value !== "undefined" && value !== null) {
                                        record.value = value;
                                    }
                                } catch (err) {
                                    if (err instanceof MechanismError) {

                                        // Error validating mechanism
                                        messages.push({
                                            message: err.message,
                                            type: err.type
                                        });
                                        break;
                                    } // else {
                                    // 	throw err;
                                    // }

                                }
                            }

                            break;
                        }
                    }
                }

                if (!found) {
                    messages.push({
                        message: "Unknown standalone term '".concat(mechanism, "'"),
                        type: "error"
                    });
                }
            }


            return record;
        }

        function parse(record) {

        // Remove whitespace
            record = record.trim();
            var records = {
                mechanisms: [],
                messages: [],

                // Valid flag will be changed at end of function
                valid: false
            };

            if (!versionRegex.test(record)) {

            // throw new Error();
                records.messages.push({
                    message: "No valid version found, record must start with 'v=spf1'",
                    type: "error"
                });
                return records;
            }

            var terms = record.split(/\s+/); // Give an error for duplicate Modifiers

            var duplicateMods = terms.filter(function(x) {
                return new RegExp("=").test(x);
            }).map(function(x) {
                return x.match(/^(.*?)=/)[1];
            }).filter(function(x, i, arr) {
                return _.includes(arr, x, i + 1);
            });

            if (duplicateMods && duplicateMods.length > 0) {
                records.messages.push({
                    type: "error",
                    message: "Modifiers like \"".concat(duplicateMods[0], "\" may appear only once in an SPF string")
                });
                return records;
            } // Give warning for duplicate mechanisms


            var duplicateMechs = terms.map(function(x) {
                return x.replace(/^(\+|-|~|\?)/, "");
            }).filter(function(x, i, arr) {
                return _.includes(arr, x, i + 1);
            });

            if (duplicateMechs && duplicateMechs.length > 0) {
                records.messages.push({
                    type: "warning",
                    message: "One or more duplicate mechanisms were found in the policy"
                });
            }


            try {
                for (var i = 0; i < terms.length; i++) {
                    var term = terms[i];
                    var mechanism = parseTerm(term, records.messages);

                    if (mechanism) {
                        records.mechanisms.push(mechanism);
                    }
                } // See if there's an "all" or "redirect" at the end of the policy
            } catch (err) {
            // eslint-disable-next-line no-console
                console.error(err);
            }

            if (records.mechanisms.length > 0) {

            // More than one modifier like redirect or exp is invalid
            // if (records.mechanisms.filter(x => x.type === 'redirect').length > 1 || records.mechanisms.filter(x => x.type === 'exp').length > 1) {
            // 	records.messages.push({
            // 		type: 'error',
            // 		message: 'Modifiers like "redirect" and "exp" can only appear once in an SPF string'
            // 	});
            // 	return records;
            // }
            // let lastMech = records.mechanisms[records.mechanisms.length - 1];
                var redirectMech = _.find(records.mechanisms, function(x) {
                    return x.type === "redirect";
                });
                var allMech = _.find(records.mechanisms, function(x) {
                    return x.type === "all";
                }); // if (lastMech.type !== "all" && lastMech !== "redirect") {

                if (!allMech && !redirectMech) {
                    records.messages.push({
                        type: "warning",
                        message: 'SPF strings should always either use an "all" mechanism or a "redirect" modifier to explicitly terminate processing.'
                    });
                } // Give a warning if "all" is not last mechanism in policy


                var allIdx = -1;

                records.mechanisms.forEach(function(x, index) {
                    if (x.type === "all" && allIdx === -1) {
                        allIdx = index;
                    }
                });

                if (allIdx > -1) {
                    if (allIdx < records.mechanisms.length - 1) {
                        records.messages.push({
                            type: "warning",
                            message: "One or more mechanisms were found after the \"all\" mechanism. These mechanisms will be ignored"
                        });
                    }
                } // Give a warning if there"s a redirect modifier AND an "all" mechanism


                if (redirectMech && allMech) {
                    records.messages.push({
                        type: "warning",
                        message: 'The "redirect" modifier will not be used, because the SPF string contains an "all" mechanism. A "redirect" modifier is only used after all mechanisms fail to match, but "all" will always match'
                    });
                }
            } // If there are no messages, delete the key from "records"


            if (!Object.keys(records.messages).length > 0) {
                delete records.messages;
            }

            records.valid = true;
            return records;
        }

        return {
            parse: parse,
            parseTerm: parseTerm,
            mechanisms: MECHANISMS,
            prefixes: PREFIXES
        };
    }
);
