//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/email_deliverability/directives/edDomainListerViewDirective.js
// Generated: /usr/local/cpanel/base/sharedjs/email_deliverability/directives/edDomainListerViewDirective-ar.js
// Module:    legacy_shared/email_deliverability/directives/edDomainListerViewDirective-ar
// Locale:    ar
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Automatic repair is currently unavailable for this domain. You must wait until “[_1]”’s operation completes because these two domains share the same DNS zone.":"Automatic repair is currently unavailable for this domain. You must wait until “[_1]”’s operation completes because these two domains share the same DNS zone.","Automatic repair is not available for this domain because this system is not authoritative for this domain.":"Automatic repair is not available for this domain because this system is not authoritative for this domain.","Loading …":"جارٍ التحميل …","Reverse [asis,DNS]":"Reverse [asis,DNS]","This domain’s DKIM and SPF configurations are valid.":"This domain’s DKIM and SPF configurations are valid.","This system does not control [asis,DNS] for the “[_1]” domain, and the system did not find any authoritative nameservers for this domain. Contact your domain registrar to verify this domain’s registration.":"This system does not control [asis,DNS] for the “[_1]” domain, and the system did not find any authoritative nameservers for this domain. Contact your domain registrar to verify this domain’s registration.","This system does not control [asis,DNS] for the “[_1]” domain. Contact the person responsible for the [list_and_quoted,_3] [numerate,_2,nameserver,nameservers] and request that they update the records.":"This system does not control [asis,DNS] for the “[_1]” domain. Contact the person responsible for the [list_and_quoted,_3] [numerate,_2,nameserver,nameservers] and request that they update the records.","You cannot modify this domain while a domain on the “[_1]” zone is updating.":"You cannot modify this domain while a domain on the “[_1]” zone is updating."};

    if (!this.LEXICON) {
        this.LEXICON = {};
    }

    for(var item in newLex) {
        if(newLex.hasOwnProperty(item)) {
            var value = newLex[item];
            if (typeof(value) === "string" && value !== "") {
                // Only add it if there is a value.
                this.LEXICON[item] = value;
            }
        }
    }
})();
//~~END-GENERATED~~
