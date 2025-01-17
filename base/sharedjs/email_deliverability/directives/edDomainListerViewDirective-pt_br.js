//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/email_deliverability/directives/edDomainListerViewDirective.js
// Generated: /usr/local/cpanel/base/sharedjs/email_deliverability/directives/edDomainListerViewDirective-pt_br.js
// Module:    legacy_shared/email_deliverability/directives/edDomainListerViewDirective-pt_br
// Locale:    pt_br
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Automatic repair is currently unavailable for this domain. You must wait until “[_1]”’s operation completes because these two domains share the same DNS zone.":"O reparo automático está indisponível no momento para esse domínio. Você deve aguardar até que a operação de “[_1]”’s seja concluída, porque esses dois domínios compartilham a mesma zona DNS.","Automatic repair is not available for this domain because this system is not authoritative for this domain.":"O reparo automático não está disponível para esse domínio porque esse sistema não tem autoridade para este domínio.","Loading …":"Carregando …","Reverse [asis,DNS]":"Reverter [asis,DNS]","This domain’s DKIM and SPF configurations are valid.":"As configurações DKIM e SPF deste domínio são válidas.","This system does not control [asis,DNS] for the “[_1]” domain, and the system did not find any authoritative nameservers for this domain. Contact your domain registrar to verify this domain’s registration.":"This system does not control [asis,DNS] for the “[_1]” domain, and the system did not find any authoritative nameservers for this domain. Contact your domain registrar to verify this domain’s registration.","This system does not control [asis,DNS] for the “[_1]” domain. Contact the person responsible for the [list_and_quoted,_3] [numerate,_2,nameserver,nameservers] and request that they update the records.":"This system does not control [asis,DNS] for the “[_1]” domain. Contact the person responsible for the [list_and_quoted,_3] [numerate,_2,nameserver,nameservers] and request that they update the records.","You cannot modify this domain while a domain on the “[_1]” zone is updating.":"Você não pode modificar este domínio enquanto um domínio na zona “[_1]” estiver sendo atualizado."};

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
