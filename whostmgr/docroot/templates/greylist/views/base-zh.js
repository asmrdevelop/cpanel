//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/whostmgr/docroot/templates/greylist/views/base.js
// Generated: /usr/local/cpanel/whostmgr/docroot/templates/greylist/views/base-zh.js
// Module:    /templates/greylist/views/base-zh
// Locale:    zh
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Add to Trusted Hosts":"添加到“受信任主机”","Some Host [asis,IP] addresses were not added to the Trusted Hosts list.":"一些主机 [asis,IP] 地址未添加到“受信任主机”列表中。","The status for [asis,Greylisting] has changed, possibly in another browser session.":"[asis,Greylisting] 的状态已更改，可能在另一个浏览器会话中。","You have successfully added [quant,_1,record,records] to the Trusted Hosts list.":"您已成功将 [quant,_1,条记录,条记录]添加到“受信任主机”列表。","You have successfully added “[_1]” to the Trusted Hosts list.":"您已成功将“[_1]”添加到“受信任主机”列表。","You have successfully updated the comment for “[_1]”.":"已成功更新“[_1]”的注释。","Your neighboring [asis,IP] addresses are not in the Trusted Hosts list.":"您的相邻 [asis,IP] 地址不在“受信任主机”列表中。","[asis,Exim] is disabled on the server which makes [asis,Greylisting] ineffective. Use the [output,url,_1,Service Manager page,_2] to enable [asis,Exim].":"服务器上禁用了 [asis,Exim]，这导致了 [asis,Greylisting] 无效。 请使用[output,url,_1,服务管理器页,_2]启用 [asis,Exim]。","[asis,Greylisting] is now disabled.":"[asis,Greylisting]  当前已禁用。","[asis,Greylisting] is now enabled.":"[asis,Greylisting] 目前已启用。"};

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
